// Package codexactivity 把 Codex 会话历史转换为 Junimo 可消费的任务完成事实。
package codexactivity

import (
	"context"
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
	Turns     []Turn
}

// CompletionEvent 表示一个可稳定去重的 Codex 任务完成事实。
type CompletionEvent struct {
	ID          string `json:"id"`
	ThreadID    string `json:"threadId"`
	Title       string `json:"title"`
	CompletedAt int64  `json:"completedAt"`
}

// Snapshot 是后端组合状态公开的 Codex 活动快照。
type Snapshot struct {
	Status          Status           `json:"status"`
	CompletionEvent *CompletionEvent `json:"completionEvent,omitempty"`
	Message         string           `json:"message,omitempty"`
}

type scanner interface {
	Scan(context.Context) ([]Thread, error)
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
	threads, err := monitor.scanner.Scan(ctx)
	now := monitor.now().Unix()
	monitor.mu.Lock()
	defer monitor.mu.Unlock()
	if err != nil {
		monitor.snapshot.Status = StatusUnavailable
		monitor.snapshot.Message = err.Error()
		return
	}

	completed := completedEvents(threads)
	if !monitor.initialized {
		for _, event := range completed {
			monitor.seen[event.ID] = struct{}{}
		}
		monitor.initialized = true
		monitor.lastSuccessfulScanAt = now
		monitor.snapshot = Snapshot{Status: StatusAvailable}
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
	monitor.pending = publishablePendingEvents(monitor.pending, threads, now)
	monitor.snapshot.Status = StatusAvailable
	monitor.snapshot.Message = ""
	if len(monitor.pending) > 0 {
		event := monitor.pending[0]
		monitor.pending = monitor.pending[1:]
		monitor.snapshot.CompletionEvent = &event
	}
}

// publishablePendingEvents 在真正发布前再次检查队列，防止等待期间已继续运行的会话收到迟到提醒。
func publishablePendingEvents(events []CompletionEvent, threads []Thread, now int64) []CompletionEvent {
	runningThreads := make(map[string]struct{})
	for _, thread := range threads {
		for _, turn := range thread.Turns {
			if turn.Status == TurnStatusInProgress {
				runningThreads[thread.ID] = struct{}{}
				break
			}
		}
	}

	publishable := events[:0]
	for _, event := range events {
		if _, running := runningThreads[event.ThreadID]; running {
			continue
		}
		if !isFreshCompletion(event, 0, now) {
			continue
		}
		publishable = append(publishable, event)
	}
	return publishable
}

// latestIdleCompletionEvents 每个空闲会话只保留最新完成，避免历史 turn 补发和继续对话后的迟到提醒。
func latestIdleCompletionEvents(threads []Thread) []CompletionEvent {
	events := make([]CompletionEvent, 0, len(threads))
	for _, thread := range threads {
		var latest *Turn
		running := false
		for index := range thread.Turns {
			turn := &thread.Turns[index]
			if turn.Status == TurnStatusInProgress {
				running = true
			}
			if turn.Status != TurnStatusCompleted || turn.ID == "" {
				continue
			}
			if latest == nil || turn.CompletedAt > latest.CompletedAt ||
				(turn.CompletedAt == latest.CompletedAt && turn.ID > latest.ID) {
				latest = turn
			}
		}
		if running || latest == nil {
			continue
		}
		events = append(events, CompletionEvent{
			ID:          latest.ID,
			ThreadID:    thread.ID,
			Title:       threadTitle(thread),
			CompletedAt: latest.CompletedAt,
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

// Start 立即刷新并按固定间隔重试；超时只结束当次扫描，不终止后续恢复机会。
func (monitor *Monitor) Start(ctx context.Context, refreshInterval time.Duration, queryTimeout time.Duration) {
	go func() {
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
					<-timer.C
				}
				return
			case <-timer.C:
			}
		}
	}()
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
