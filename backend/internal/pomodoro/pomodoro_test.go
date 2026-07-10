package pomodoro

import (
	"testing"
	"time"
)

func TestTimerStartAndComplete(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })

	started := timer.Start(10)
	if started.Status != StatusRunning {
		t.Fatalf("status = %s, want running", started.Status)
	}
	if started.RemainingSeconds != 10 {
		t.Fatalf("remaining = %d, want 10", started.RemainingSeconds)
	}

	now = now.Add(11 * time.Second)
	completed := timer.Snapshot()
	if completed.Status != StatusCompleted {
		t.Fatalf("status = %s, want completed", completed.Status)
	}
	if completed.RemainingSeconds != 0 {
		t.Fatalf("remaining = %d, want 0", completed.RemainingSeconds)
	}
	if completed.EndsAt == nil || *completed.EndsAt != "2026-07-07T10:00:10Z" {
		t.Fatalf("endsAt = %v, want 2026-07-07T10:00:10Z", completed.EndsAt)
	}
}

func TestTimerResetReturnsIdle(t *testing.T) {
	timer := NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	timer.Start(60)

	reset := timer.Reset()
	if reset.Status != StatusIdle {
		t.Fatalf("status = %s, want idle", reset.Status)
	}
	if reset.RemainingSeconds != 60 {
		t.Fatalf("remaining = %d, want 60", reset.RemainingSeconds)
	}
}

func TestTimerPauseAndResumeKeepsRemainingTime(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(60)

	now = now.Add(10 * time.Second)
	paused := timer.Pause()
	if paused.Status != StatusPaused {
		t.Fatalf("status = %s, want paused", paused.Status)
	}
	if paused.RemainingSeconds != 50 {
		t.Fatalf("remaining = %d, want 50", paused.RemainingSeconds)
	}

	now = now.Add(20 * time.Second)
	stillPaused := timer.Snapshot()
	if stillPaused.RemainingSeconds != 50 {
		t.Fatalf("remaining while paused = %d, want 50", stillPaused.RemainingSeconds)
	}

	resumed := timer.Resume()
	if resumed.Status != StatusRunning {
		t.Fatalf("status = %s, want running", resumed.Status)
	}

	now = now.Add(25 * time.Second)
	running := timer.Snapshot()
	if running.RemainingSeconds != 25 {
		t.Fatalf("remaining after resume = %d, want 25", running.RemainingSeconds)
	}
}

func TestTimerStartFocusIsNoOpWhileFocusIsActive(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(60)

	now = now.Add(10 * time.Second)
	snapshot := timer.StartFocus(120)
	if snapshot.DurationSeconds != 60 {
		t.Fatalf("duration = %d, want 60", snapshot.DurationSeconds)
	}
	if snapshot.RemainingSeconds != 50 {
		t.Fatalf("remaining = %d, want 50", snapshot.RemainingSeconds)
	}
}

func TestTimerBreakStartsAfterFocusCompletes(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(10)

	now = now.Add(11 * time.Second)
	completed := timer.Snapshot()
	if completed.Mode != ModeFocus || completed.Status != StatusCompleted {
		t.Fatalf("snapshot = %s/%s, want focus/completed", completed.Mode, completed.Status)
	}

	breakSnapshot := timer.StartBreak()
	if breakSnapshot.Mode != ModeBreak || breakSnapshot.Status != StatusRunning {
		t.Fatalf("snapshot = %s/%s, want break/running", breakSnapshot.Mode, breakSnapshot.Status)
	}
	if breakSnapshot.RemainingSeconds != 300 {
		t.Fatalf("break remaining = %d, want 300", breakSnapshot.RemainingSeconds)
	}

	now = now.Add(301 * time.Second)
	breakCompleted := timer.Snapshot()
	if breakCompleted.Mode != ModeBreak || breakCompleted.Status != StatusCompleted {
		t.Fatalf("snapshot = %s/%s, want break/completed", breakCompleted.Mode, breakCompleted.Status)
	}
}

func TestTimerSkipBreakReturnsToIdleFocus(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(10)
	now = now.Add(11 * time.Second)
	timer.StartBreak()

	snapshot := timer.SkipBreak()
	if snapshot.Mode != ModeFocus || snapshot.Status != StatusIdle {
		t.Fatalf("snapshot = %s/%s, want focus/idle", snapshot.Mode, snapshot.Status)
	}
	if snapshot.RemainingSeconds != 10 {
		t.Fatalf("remaining = %d, want 10", snapshot.RemainingSeconds)
	}
}
