package codexusage

import (
	"context"
	"sync"
	"time"
)

type querier interface {
	Query(context.Context) (Snapshot, error)
}

type Monitor struct {
	mu       sync.RWMutex
	querier  querier
	snapshot Snapshot
}

func NewMonitor(querier querier) *Monitor {
	return &Monitor{
		querier:  querier,
		snapshot: Snapshot{Status: StatusLoading},
	}
}

func (monitor *Monitor) Snapshot() Snapshot {
	monitor.mu.RLock()
	defer monitor.mu.RUnlock()
	return monitor.snapshot
}

func (monitor *Monitor) Refresh(ctx context.Context) {
	snapshot, err := monitor.querier.Query(ctx)
	if err != nil {
		snapshot = Snapshot{Status: StatusUnavailable, Message: err.Error()}
	}
	monitor.mu.Lock()
	monitor.snapshot = snapshot
	monitor.mu.Unlock()
}

func (monitor *Monitor) Start(ctx context.Context, refreshInterval time.Duration, queryTimeout time.Duration) {
	go func() {
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
