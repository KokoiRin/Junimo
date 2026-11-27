package companion

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

// 应用未运行时 gate 不应启动后台任务；切换为运行后应立刻启动，退出时取消并释放资源，再次启动前必须等上一轮清理完毕。
func TestAgentGateStartsPausesAndSerializesRestarts(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var starts atomic.Int32
	var closes atomic.Int32
	var activeWorkers atomic.Int32
	var pausedCalls atomic.Int32
	started := make(chan struct{}, 4)
	closed := make(chan struct{}, 4)

	gate := newAgentGate(ctx, func(runCtx context.Context) {
		if activeWorkers.Add(1) != 1 {
			t.Error("overlapping workers ran concurrently")
		}
		starts.Add(1)
		started <- struct{}{}
		<-runCtx.Done()
		time.Sleep(15 * time.Millisecond)
		activeWorkers.Add(-1)
		closes.Add(1)
		closed <- struct{}{}
	}, func() {
		pausedCalls.Add(1)
	})

	gate.SetActive(false)
	if starts.Load() != 0 {
		t.Fatal("inactive gate must not start worker")
	}

	gate.SetActive(true)
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("gate did not start worker immediately")
	}

	gate.SetActive(false)
	if pausedCalls.Load() != 1 {
		t.Fatalf("pausedCalls = %d, want 1", pausedCalls.Load())
	}

	// 在上一轮尚未完全结束时立刻重新激活，必须等旧 worker 释放完毕后再启动新 worker。
	gate.SetActive(true)
	select {
	case <-closed:
	case <-time.After(time.Second):
		t.Fatal("previous worker did not close")
	}
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("re-activated worker did not start")
	}

	gate.Stop()
	if starts.Load() != 2 || closes.Load() != 2 {
		t.Fatalf("starts=%d closes=%d, want 2 and 2", starts.Load(), closes.Load())
	}
}
