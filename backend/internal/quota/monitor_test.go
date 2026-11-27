package quota

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"
)

type failingQuerier struct{}

func (failingQuerier) Query(context.Context) (Snapshot, error) {
	return Snapshot{}, errors.New("quota source is unavailable")
}

type fixedQuerier struct {
	snapshot Snapshot
	calls    chan struct{}
	closed   *atomic.Bool
}

func (querier fixedQuerier) Query(context.Context) (Snapshot, error) {
	if querier.calls != nil {
		select {
		case querier.calls <- struct{}{}:
		default:
		}
	}
	return querier.snapshot, nil
}

func (querier fixedQuerier) Close() {
	if querier.closed != nil {
		querier.closed.Store(true)
	}
}

// 新监控器初始为 loading，外部查询返回错误后应切换为 unavailable，并保留非空失败原因供 UI 降级诊断。
func TestMonitorReportsUnavailableWhenRefreshFails(t *testing.T) {
	monitor := NewMonitor(failingQuerier{})
	if monitor.Snapshot().Status != StatusLoading {
		t.Fatalf("initial status = %q, want %q", monitor.Snapshot().Status, StatusLoading)
	}

	monitor.Refresh(context.Background())
	snapshot := monitor.Snapshot()
	if snapshot.Status != StatusUnavailable {
		t.Fatalf("status = %q, want %q", snapshot.Status, StatusUnavailable)
	}
	if snapshot.Message == "" {
		t.Fatal("unavailable snapshot should explain the failure")
	}
}

// 监控器从初始 loading 状态执行一次返回主窗口 88% 的成功刷新后，公开快照应切换为 available 并携带 88%，且修改返回值不会污染内部状态。
func TestMonitorPublishesDefensiveCopyOnSuccessfulRefresh(t *testing.T) {
	monitor := NewMonitor(fixedQuerier{snapshot: Snapshot{
		Status: StatusAvailable,
		Primary: &Window{
			RemainingPercent:      88,
			WindowDurationMinutes: 300,
		},
	}})

	monitor.Refresh(context.Background())
	snapshot := monitor.Snapshot()
	if snapshot.Status != StatusAvailable || snapshot.Primary == nil || snapshot.Primary.RemainingPercent != 88 {
		t.Fatalf("snapshot = %#v, want available primary at 88%%", snapshot)
	}
	snapshot.Primary.RemainingPercent = 1
	if monitor.Snapshot().Primary.RemainingPercent != 88 {
		t.Fatal("mutating returned snapshot must not alter monitor state")
	}
}

// 使用 1 小时刷新间隔启动监控器时，首次查询应在 1 秒内发生并发布 available；取消上下文后应自动关闭支持 Close 的查询器。
func TestMonitorStartRefreshesImmediatelyAndClosesOnCancel(t *testing.T) {
	calls := make(chan struct{}, 1)
	var closed atomic.Bool
	monitor := NewMonitor(fixedQuerier{
		snapshot: Snapshot{Status: StatusAvailable},
		calls:    calls,
		closed:   &closed,
	})
	ctx, cancel := context.WithCancel(context.Background())
	monitor.Start(ctx, time.Hour, time.Second)

	select {
	case <-calls:
	case <-time.After(time.Second):
		cancel()
		t.Fatal("monitor did not refresh immediately")
	}
	deadline := time.Now().Add(time.Second)
	for monitor.Snapshot().Status != StatusAvailable && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if status := monitor.Snapshot().Status; status != StatusAvailable {
		cancel()
		t.Fatalf("status = %q, want available", status)
	}
	cancel()
	deadline = time.Now().Add(time.Second)
	for !closed.Load() && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if !closed.Load() {
		t.Fatal("monitor should close its querier when stopped")
	}
}
