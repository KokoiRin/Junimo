// Package codexactivity 把 Codex 会话历史转换为 Junimo 可消费的任务完成事实。
package codexactivity

import (
	"context"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"
)

// Status 表示 Codex 活动事实源当前是否可读取。
type Status string

const (
	StatusLoading     Status = "loading"
	StatusAvailable   Status = "available"
	StatusUnavailable Status = "unavailable"
)

// TurnStatus 是 app-server 持久化 turn 的终态或运行态。
type TurnStatus string

const (
	TurnStatusInProgress  TurnStatus = "inProgress"
	TurnStatusCompleted   TurnStatus = "completed"
	TurnStatusFailed      TurnStatus = "failed"
	TurnStatusInterrupted TurnStatus = "interrupted"
)

const completionFreshnessWindow = 15 * time.Second

// Turn 是完成检测所需的最小 Codex turn 投影。
type Turn struct {
	ID          string
	Status      TurnStatus
	CompletedAt int64
}

// Thread 是完成检测所需的最小 Codex thread 投影。
type Thread struct {
	ID        string
	Name      string
	Preview   string
	UpdatedAt int64
	Turns     []Turn // thread/turns/list 按轮次从新到旧返回。
}

// CompletionEvent 表示一个可稳定去重的 Codex 任务完成事实。
type CompletionEvent struct {
	ID          string `json:"id"`
	ThreadID    string `json:"threadId"`
	Title       string `json:"title"`
	CompletedAt int64  `json:"completedAt"`
	NotifyUntil int64  `json:"notifyUntil,omitempty"`
}

// Snapshot 是后端组合状态公开的 Codex 活动快照。
type Snapshot struct {
	IsWorking       bool             `json:"isWorking"`
	Status          Status           `json:"status"`
	CompletionEvent *CompletionEvent `json:"completionEvent,omitempty"`
	Message         string           `json:"message,omitempty"`
}

type scanner interface {
	Scan(context.Context) ([]Thread, error)
	IsWorking(context.Context) bool
}

// Monitor 负责启动基线、完成去重与适配器错误隔离。
type Monitor struct {
	mu                   sync.RWMutex
	scanner              scanner
	now                  func() time.Time
	initialized          bool
	lastSuccessfulScanAt int64
	seen                 map[string]struct{}
	pending              []CompletionEvent
	snapshot             Snapshot
	onChange             func()
}

// NewMonitor 创建尚未完成首次基线扫描的活动监控器。
func NewMonitor(source scanner) *Monitor {
	return &Monitor{
		scanner:  source,
		now:      time.Now,
		seen:     make(map[string]struct{}),
		snapshot: Snapshot{Status: StatusLoading},
	}
}

// SetOnChange 注册活动快照变化时的回调。
func (monitor *Monitor) SetOnChange(fn func()) {
	monitor.mu.Lock()
	monitor.onChange = fn
	monitor.mu.Unlock()
}

// SetIdle 在目标应用退出并暂停轮询时清除残留的运行态标记。
func (monitor *Monitor) SetIdle() {
	monitor.mu.Lock()
	changed := monitor.snapshot.IsWorking
	monitor.snapshot.IsWorking = false
	onChange := monitor.onChange
	monitor.mu.Unlock()
	if changed && onChange != nil {
		onChange()
	}
}

// Snapshot 返回当前活动事实的防御性副本。
func (monitor *Monitor) Snapshot() Snapshot {
	monitor.mu.RLock()
	defer monitor.mu.RUnlock()
	snapshot := monitor.snapshot
	if snapshot.CompletionEvent != nil {
		event := *snapshot.CompletionEvent
		snapshot.CompletionEvent = &event
	}
	return snapshot
}

// Refresh 扫描新完成 turn；首次成功只建立基线，避免启动时重放历史通知。
func (monitor *Monitor) Refresh(ctx context.Context) {
	working := monitor.scanner.IsWorking(ctx)
	threads, err := monitor.scanner.Scan(ctx)
	if err != nil && ctx.Err() != nil {
		return
	}
	now := monitor.now().Unix()
	monitor.mu.Lock()
	previous := monitor.snapshot
	if previous.CompletionEvent != nil {
		ev := *previous.CompletionEvent
		previous.CompletionEvent = &ev
	}
	onChange := monitor.onChange

	monitor.snapshot.IsWorking = working
	if err != nil {
		monitor.snapshot.Status = StatusUnavailable
		monitor.snapshot.Message = err.Error()
		changed := !activitySnapshotsEqual(previous, monitor.snapshot)
		monitor.mu.Unlock()
		if changed && onChange != nil {
			onChange()
		}
		return
	}

	completed := completedEvents(threads)
	if !monitor.initialized {
		for _, event := range completed {
			monitor.seen[event.ID] = struct{}{}
		}
		monitor.initialized = true
		monitor.lastSuccessfulScanAt = now
		monitor.snapshot.Status = StatusAvailable
		monitor.snapshot.Message = ""
		changed := !activitySnapshotsEqual(previous, monitor.snapshot)
		monitor.mu.Unlock()
		if changed && onChange != nil {
			onChange()
		}
		return
	}

	candidates := latestIdleCompletionEvents(threads)
	for index := range candidates {
		event := candidates[index]
		if _, exists := monitor.seen[event.ID]; exists {
			continue
		}
		if !isFreshCompletion(event, monitor.lastSuccessfulScanAt, now) {
			continue
		}
		monitor.pending = append(monitor.pending, event)
	}
	for _, event := range completed {
		monitor.seen[event.ID] = struct{}{}
	}
	monitor.lastSuccessfulScanAt = now
	monitor.pending = publishablePendingEvents(monitor.pending, candidates, now)
	monitor.snapshot.Status = StatusAvailable
	monitor.snapshot.Message = ""
	if len(monitor.pending) > 0 {
		event := monitor.pending[0]
		monitor.pending = monitor.pending[1:]
		event.NotifyUntil = event.CompletedAt + int64(completionFreshnessWindow/time.Second)
		monitor.snapshot.CompletionEvent = &event
	}
	changed := !activitySnapshotsEqual(previous, monitor.snapshot)
	monitor.mu.Unlock()
	if changed && onChange != nil {
		onChange()
	}
}

func activitySnapshotsEqual(a, b Snapshot) bool {
	if a.IsWorking != b.IsWorking || a.Status != b.Status || a.Message != b.Message {
		return false
	}
	if a.CompletionEvent == nil || b.CompletionEvent == nil {
		return a.CompletionEvent == b.CompletionEvent
	}
	return *a.CompletionEvent == *b.CompletionEvent
}

// publishablePendingEvents 在真正发布前再次检查队列，防止等待期间已继续运行的会话收到迟到提醒。
func publishablePendingEvents(events, candidates []CompletionEvent, now int64) []CompletionEvent {
	latest := make(map[string]string, len(candidates))
	for _, candidate := range candidates {
		latest[candidate.ThreadID] = candidate.ID
	}
	publishable := events[:0]
	for _, event := range events {
		if latest[event.ThreadID] == event.ID && isFreshCompletion(event, 0, now) {
			publishable = append(publishable, event)
		}
	}
	return publishable
}

// 每个会话只有最新轮次可以触发提醒，后续失败或中断同样使前一轮的成功提醒失效。
func latestIdleCompletionEvents(threads []Thread) []CompletionEvent {
	var events []CompletionEvent
	for _, thread := range threads {
		if len(thread.Turns) == 0 {
			continue
		}
		latest := thread.Turns[0]
		if latest.Status != TurnStatusCompleted || latest.ID == "" {
			continue
		}
		if slices.ContainsFunc(thread.Turns[1:], func(turn Turn) bool { return turn.Status == TurnStatusInProgress }) {
			continue
		}
		events = append(events, CompletionEvent{
			ID: latest.ID, ThreadID: thread.ID, Title: threadTitle(thread), CompletedAt: latest.CompletedAt,
		})
	}
	sortCompletionEvents(events)
	return events
}

// isFreshCompletion 只接受上次成功扫描之后刚落盘的完成事实，错误恢复时也不补发过期提醒。
func isFreshCompletion(event CompletionEvent, lastSuccessfulScanAt int64, now int64) bool {
	if event.CompletedAt <= 0 || event.CompletedAt < lastSuccessfulScanAt || event.CompletedAt > now {
		return false
	}
	return time.Duration(now-event.CompletedAt)*time.Second <= completionFreshnessWindow
}

// Run 同步执行活动监控并在 ctx 取消时关闭底层扫描器。
func (monitor *Monitor) Run(ctx context.Context, refreshInterval time.Duration, queryTimeout time.Duration) {
	defer func() {
		if closer, ok := monitor.scanner.(interface{ Close() }); ok {
			closer.Close()
		}
	}()
	for {
		queryContext, cancel := context.WithTimeout(ctx, queryTimeout)
		monitor.Refresh(queryContext)
		cancel()

		timer := time.NewTimer(refreshInterval)
		select {
		case <-ctx.Done():
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
			return
		case <-timer.C:
		}
	}
}

// Start 立即刷新并按固定间隔重试；超时只结束当次扫描，不终止后续恢复机会。
func (monitor *Monitor) Start(ctx context.Context, refreshInterval time.Duration, queryTimeout time.Duration) {
	go monitor.Run(ctx, refreshInterval, queryTimeout)
}

// completedEvents 按完成时间排序，使同一扫描内最新事件成为当前公开事实。
func completedEvents(threads []Thread) []CompletionEvent {
	var events []CompletionEvent
	for _, thread := range threads {
		for _, turn := range thread.Turns {
			if turn.Status != TurnStatusCompleted || turn.ID == "" {
				continue
			}
			events = append(events, CompletionEvent{
				ID:          turn.ID,
				ThreadID:    thread.ID,
				Title:       threadTitle(thread),
				CompletedAt: turn.CompletedAt,
			})
		}
	}
	sortCompletionEvents(events)
	return events
}

func sortCompletionEvents(events []CompletionEvent) {
	sort.Slice(events, func(left int, right int) bool {
		if events[left].CompletedAt == events[right].CompletedAt {
			return events[left].ID < events[right].ID
		}
		return events[left].CompletedAt < events[right].CompletedAt
	})
}

// threadTitle 统一完成通知可见标题的降级顺序。
func threadTitle(thread Thread) string {
	if title := strings.TrimSpace(thread.Name); title != "" {
		return title
	}
	if preview := strings.TrimSpace(thread.Preview); preview != "" {
		return preview
	}
	return "Codex 任务"
}
