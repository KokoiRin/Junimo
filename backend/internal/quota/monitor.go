package quota

import (
	"context"
	"sync"
	"time"
)

// Querier 封装单个 Agent 额度来源的一次拉取动作；若实现 Close()，将在监控停止时自动释放资源。
type Querier interface {
	Query(context.Context) (Snapshot, error)
}

// Monitor 定时刷新额度快照并隔离单次查询失败，始终返回线程安全的最新状态。
type Monitor struct {
	mu       sync.RWMutex
	querier  Querier
	snapshot Snapshot
	onChange func()
}

// NewMonitor 创建初始处于 loading 状态的额度监控器。
func NewMonitor(querier Querier) *Monitor {
	return &Monitor{
		querier:  querier,
		snapshot: Snapshot{Status: StatusLoading},
	}
}

// SetOnChange 注册快照内容变化时的回调函数，供上层推送变更通知。
func (monitor *Monitor) SetOnChange(fn func()) {
	monitor.mu.Lock()
	monitor.onChange = fn
	monitor.mu.Unlock()
}

// Snapshot 返回当前额度快照的防御性副本。
func (monitor *Monitor) Snapshot() Snapshot {
	monitor.mu.RLock()
	defer monitor.mu.RUnlock()
	snapshot := monitor.snapshot
	if snapshot.Primary != nil {
		primary := *snapshot.Primary
		snapshot.Primary = &primary
	}
	if snapshot.Secondary != nil {
		secondary := *snapshot.Secondary
		snapshot.Secondary = &secondary
	}
	if snapshot.IsAppRunning != nil {
		running := *snapshot.IsAppRunning
		snapshot.IsAppRunning = &running
	}
	return snapshot
}

// Refresh 立即执行一次额度查询；查询失败时切换为 unavailable 并记录原因，但主动取消上下文时不污染现有快照。
func (monitor *Monitor) Refresh(ctx context.Context) {
	snapshot, err := monitor.querier.Query(ctx)
	if err != nil {
		if ctx.Err() != nil {
			return
		}
		snapshot = Snapshot{Status: StatusUnavailable, Message: err.Error()}
	}
	monitor.mu.Lock()
	changed := !monitor.snapshot.Equal(snapshot)
	monitor.snapshot = snapshot
	onChange := monitor.onChange
	monitor.mu.Unlock()
	if changed && onChange != nil {
		onChange()
	}
}

// Run 同步执行首次查询并按固定周期刷新，直到 ctx 取消且查询器 Close() 完成后返回。
func (monitor *Monitor) Run(ctx context.Context, refreshInterval time.Duration, queryTimeout time.Duration) {
	defer func() {
		if closer, ok := monitor.querier.(interface{ Close() }); ok {
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

// Start 在后台 goroutine 中运行额度监控器。
func (monitor *Monitor) Start(ctx context.Context, refreshInterval time.Duration, queryTimeout time.Duration) {
	go monitor.Run(ctx, refreshInterval, queryTimeout)
}
