package pomodoro

import (
	"testing"
	"time"
)

// 从固定时刻启动 10 秒专注并让时钟越过截止点后，快照应从 running 进入 completed、剩余时间归零，并保留准确的结束时间。
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

// 10 秒专注首次到期应生成稳定的 id 1 focus 事件，重复读取不变；后续休息完成应生成递增的 id 2 break 事件。
func TestTimerCompletionPublishesOneStableEventPerCycle(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(10)

	now = now.Add(10 * time.Second)
	completed := timer.Snapshot()
	if completed.CompletionEvent == nil {
		t.Fatal("completed focus should publish a completion event")
	}
	if completed.CompletionEvent.ID != 1 || completed.CompletionEvent.Mode != ModeFocus {
		t.Fatalf("completion event = %#v, want id 1 for focus", completed.CompletionEvent)
	}

	repeated := timer.Snapshot()
	if repeated.CompletionEvent == nil || repeated.CompletionEvent.ID != completed.CompletionEvent.ID {
		t.Fatalf("repeated completion event = %#v, want stable id %d", repeated.CompletionEvent, completed.CompletionEvent.ID)
	}

	timer.StartBreak()
	now = now.Add(5 * time.Minute)
	breakCompleted := timer.Snapshot()
	if breakCompleted.CompletionEvent == nil || breakCompleted.CompletionEvent.ID != 2 || breakCompleted.CompletionEvent.Mode != ModeBreak {
		t.Fatalf("break completion event = %#v, want id 2 for break", breakCompleted.CompletionEvent)
	}
}

// 运行中的 60 秒专注收到重置请求时，应回到 idle 并恢复完整的 60 秒，而不是保留已经消耗的时间。
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

// 60 秒专注运行 10 秒后暂停并静置 20 秒时，剩余时间应冻结在 50 秒；恢复再运行 25 秒后应只剩 25 秒。
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

// 已有 60 秒专注正在运行且剩余 50 秒时，再请求启动 120 秒专注应被忽略，当前周期的总时长和剩余时间都不能被覆盖。
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

// 10 秒专注完成后启动休息时，应进入 300 秒 break/running；再让时钟越过休息截止点后，应进入 break/completed。
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

// 使用 10 秒专注完成后进入休息，再执行跳过休息时，应回到 focus/idle，并恢复最近配置的 10 秒专注时长。
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

// 10 秒专注的当前时间恰好等于结束时间时，应立即进入 completed 且剩余 0 秒，不能多显示一秒 running。
func TestTimerCompletesExactlyAtDeadline(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(10)

	now = now.Add(10 * time.Second)
	snapshot := timer.Snapshot()
	if snapshot.Status != StatusCompleted || snapshot.RemainingSeconds != 0 {
		t.Fatalf("snapshot = %s/%d, want completed/0", snapshot.Status, snapshot.RemainingSeconds)
	}
}

// 用户上一轮配置过 45 秒专注并完成、重置后，再用 0 作为非正时长启动时，应沿用 45 秒而不是退回默认 25 分钟。
func TestTimerNonPositiveStartUsesCurrentFocusDuration(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(45)
	now = now.Add(45 * time.Second)
	timer.Snapshot()
	timer.Reset()

	snapshot := timer.StartFocus(0)
	if snapshot.DurationSeconds != 45 || snapshot.RemainingSeconds != 45 {
		t.Fatalf("duration/remaining = %d/%d, want 45/45", snapshot.DurationSeconds, snapshot.RemainingSeconds)
	}
}

// 在 focus/idle 或仍剩 50 秒的 focus/running 状态请求开始休息时，都应保持原专注状态，只有 focus/completed 才能进入 break。
func TestTimerBreakCannotStartBeforeFocusCompletes(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })

	idle := timer.StartBreak()
	if idle.Mode != ModeFocus || idle.Status != StatusIdle {
		t.Fatalf("idle break request = %s/%s, want focus/idle", idle.Mode, idle.Status)
	}

	timer.StartFocus(60)
	now = now.Add(10 * time.Second)
	running := timer.StartBreak()
	if running.Mode != ModeFocus || running.Status != StatusRunning || running.RemainingSeconds != 50 {
		t.Fatalf("running break request = %s/%s/%d, want focus/running/50", running.Mode, running.Status, running.RemainingSeconds)
	}
}

// 10 秒专注恰好到达截止时刻时再发送暂停请求，计时应保持 completed/0，不能被回退成 paused。
func TestTimerPauseAtDeadlineKeepsCompletedState(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(10)

	now = now.Add(10 * time.Second)
	snapshot := timer.Pause()
	if snapshot.Status != StatusCompleted || snapshot.RemainingSeconds != 0 {
		t.Fatalf("snapshot = %s/%d, want completed/0", snapshot.Status, snapshot.RemainingSeconds)
	}
}

// 45 秒专注完成并进入休息后执行重置时，应回到 focus/idle，并把总时长和剩余时间都恢复为最近配置的 45 秒。
func TestTimerResetDuringBreakRestoresConfiguredFocus(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(45)
	now = now.Add(45 * time.Second)
	timer.StartBreak()

	snapshot := timer.Reset()
	if snapshot.Mode != ModeFocus || snapshot.Status != StatusIdle {
		t.Fatalf("snapshot = %s/%s, want focus/idle", snapshot.Mode, snapshot.Status)
	}
	if snapshot.DurationSeconds != 45 || snapshot.RemainingSeconds != 45 {
		t.Fatalf("duration/remaining = %d/%d, want 45/45", snapshot.DurationSeconds, snapshot.RemainingSeconds)
	}
}

// 60 秒专注仍在运行且剩余 50 秒时误发跳过休息请求，应保持 focus/running/50，不得改变当前专注周期。
func TestTimerSkipBreakIsNoOpDuringFocus(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(60)
	now = now.Add(10 * time.Second)

	snapshot := timer.SkipBreak()
	if snapshot.Mode != ModeFocus || snapshot.Status != StatusRunning || snapshot.RemainingSeconds != 50 {
		t.Fatalf("snapshot = %s/%s/%d, want focus/running/50", snapshot.Mode, snapshot.Status, snapshot.RemainingSeconds)
	}
}

// 10 秒专注完成后用 90 秒显式启动下一轮时，应进入新的 focus/running，并同时采用 90 秒总时长和剩余时间。
func TestTimerCompletedFocusCanStartAgainWithNewDuration(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := NewTimer(func() time.Time { return now })
	timer.StartFocus(10)
	now = now.Add(10 * time.Second)
	timer.Snapshot()

	snapshot := timer.StartFocus(90)
	if snapshot.Mode != ModeFocus || snapshot.Status != StatusRunning {
		t.Fatalf("snapshot = %s/%s, want focus/running", snapshot.Mode, snapshot.Status)
	}
	if snapshot.DurationSeconds != 90 || snapshot.RemainingSeconds != 90 {
		t.Fatalf("duration/remaining = %d/%d, want 90/90", snapshot.DurationSeconds, snapshot.RemainingSeconds)
	}
}
