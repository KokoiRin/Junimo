package processwatch

import (
	"context"
	"testing"
	"time"
)

// 进程存活期间应复用缓存 PID 并跳过重复 pgrep；进程退出后应立即重新探测并在停机冷却期内复用未运行结论，强制探测时应立刻生效。
func TestWatcherCachesLivePIDAndRespectsStoppedCooldown(t *testing.T) {
	probes := 0
	live := true
	probeRunning := true
	w := &Watcher{
		name:              "Grok Bot",
		runningRevalidate: 30 * time.Second,
		stoppedProbe:      4 * time.Second,
		probe: func(context.Context, string) (int, *bool) {
			probes++
			if probeRunning {
				return 4242, new(true)
			}
			return 0, new(false)
		},
		alive: func(pid int) bool {
			return pid == 4242 && live
		},
	}

	t0 := time.Unix(1000, 0)
	if got := w.IsRunning(context.Background(), t0, false); got == nil || !*got || probes != 1 {
		t.Fatalf("first probe = %v probes=%d, want true and 1 probe", got, probes)
	}
	if got := w.IsRunning(context.Background(), t0.Add(2*time.Second), false); got == nil || !*got || probes != 1 {
		t.Fatalf("cached alive check = %v probes=%d, want true and 1 probe", got, probes)
	}

	live = false
	probeRunning = false
	if got := w.IsRunning(context.Background(), t0.Add(4*time.Second), false); got == nil || *got || probes != 2 {
		t.Fatalf("after exit = %v probes=%d, want false and 2 probes", got, probes)
	}
	if got := w.IsRunning(context.Background(), t0.Add(6*time.Second), false); got == nil || *got || probes != 2 {
		t.Fatalf("within cooldown = %v probes=%d, want false and 2 probes", got, probes)
	}

	probeRunning = true
	live = true
	if got := w.IsRunning(context.Background(), t0.Add(7*time.Second), true); got == nil || !*got || probes != 3 {
		t.Fatalf("forced probe = %v probes=%d, want true and 3 probes", got, probes)
	}
}
