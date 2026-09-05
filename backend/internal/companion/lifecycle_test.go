package companion

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

// 外壳父进程仍在时后端继续运行，父进程退出并被重新托管后应取消后端运行上下文。
func TestBackendFollowsParentLifetime(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var parent atomic.Int32
	parent.Store(42)
	go cancelWhenParentExits(ctx, cancel, 42, func() int { return int(parent.Load()) })
	select {
	case <-ctx.Done():
		t.Fatal("backend stopped while its parent was alive")
	case <-time.After(150 * time.Millisecond):
	}
	parent.Store(1)
	select {
	case <-ctx.Done():
	case <-time.After(time.Second):
		t.Fatal("backend did not stop after losing its parent")
	}
}

// 托管后端尚未开始运行就已经失去父进程时，应立即取消，不能把 PID 1 当作外壳长期等待。
func TestAlreadyOrphanedBackendStops(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	cancelWhenParentExits(ctx, cancel, 1, func() int { return 1 })
	if ctx.Err() == nil {
		t.Fatal("orphaned backend should stop immediately")
	}
}
