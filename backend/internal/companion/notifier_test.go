package companion

import (
	"context"
	"testing"
	"time"
)

// 版本已领先于客户端时 Wait 应立即返回；版本一致时应阻塞到 Notify 唤醒、超时返回未变化或服务关闭时立刻退出。
func TestChangeNotifierWakesOnNotifyTimeoutAndShutdown(t *testing.T) {
	notifier := newChangeNotifier()
	shutdown := make(chan struct{})

	if v, changed := notifier.Wait(context.Background(), shutdown, 0, time.Second); !changed || v != 1 {
		t.Fatalf("stale client wait = (%d, %v), want (1, true)", v, changed)
	}

	if v, changed := notifier.Wait(context.Background(), shutdown, 1, 20*time.Millisecond); changed || v != 1 {
		t.Fatalf("timeout wait = (%d, %v), want (1, false)", v, changed)
	}

	done := make(chan struct{})
	go func() {
		if v, changed := notifier.Wait(context.Background(), shutdown, 1, time.Second); !changed || v != 2 {
			t.Errorf("notified wait = (%d, %v), want (2, true)", v, changed)
		}
		close(done)
	}()
	time.Sleep(15 * time.Millisecond)
	notifier.Notify()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("Wait did not wake up after Notify")
	}

	shutdownDone := make(chan struct{})
	go func() {
		if _, changed := notifier.Wait(context.Background(), shutdown, 2, time.Second); changed {
			t.Error("shutdown should exit without reporting change")
		}
		close(shutdownDone)
	}()
	time.Sleep(15 * time.Millisecond)
	close(shutdown)
	select {
	case <-shutdownDone:
	case <-time.After(time.Second):
		t.Fatal("Wait did not exit immediately on server shutdown")
	}
}
