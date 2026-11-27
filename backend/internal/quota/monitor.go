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
}

// NewMonitor 创建初始处于 loading 状态的额度监控器。
func NewMonitor(querier Querier) *Monitor {
	return &Monitor{
		querier:  querier,
		snapshot: Snapshot{Status: StatusLoading},
	}
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
	return snapshot
}

// Refresh 立即执行一次额度查询；查询失败时切换为 unavailable 并记录原因。
func (monitor *Monitor) Refresh(ctx context.Context) {
	snapshot, err := monitor.querier.Query(ctx)
	if err != nil {
		snapshot = Snapshot{Status: StatusUnavailable, Message: err.Error()}
	}
	monitor.mu.Lock()
	monitor.snapshot = snapshot
	monitor.mu.Unlock()
}

// Start 立即执行首次查询并按固定周期刷新；上下文取消时若查询器支持 Close 则自动释放其持有的子进程或连接。
func (monitor *Monitor) Start(ctx context.Context, refreshInterval time.Duration, queryTimeout time.Duration) {
	go func() {
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
					<-timer.C
				}
				return
			case <-timer.C:
			}
		}
	}()
}
