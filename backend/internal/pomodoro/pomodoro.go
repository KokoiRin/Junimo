package pomodoro

import (
	"sync"
	"time"
)

type Status string

const (
	StatusIdle      Status = "idle"
	StatusRunning   Status = "running"
	StatusPaused    Status = "paused"
	StatusCompleted Status = "completed"
)

type Mode string

const (
	ModeFocus Mode = "focus"
	ModeBreak Mode = "break"
)

type Snapshot struct {
	Mode                 Mode    `json:"mode"`
	Status               Status  `json:"status"`
	DurationSeconds      int64   `json:"durationSeconds"`
	RemainingSeconds     int64   `json:"remainingSeconds"`
	FocusDurationSeconds int64   `json:"focusDurationSeconds"`
	BreakDurationSeconds int64   `json:"breakDurationSeconds"`
	StartedAt            *string `json:"startedAt,omitempty"`
	EndsAt               *string `json:"endsAt,omitempty"`
}

type Clock func() time.Time

type Timer struct {
	mu        sync.Mutex
	clock     Clock
	mode      Mode
	duration  time.Duration
	remaining time.Duration
	focus     time.Duration
	breakTime time.Duration
	startedAt time.Time
	status    Status
}

func NewTimer(clock Clock) *Timer {
	if clock == nil {
		clock = time.Now
	}
	focus := 25 * time.Minute
	return &Timer{
		clock:     clock,
		mode:      ModeFocus,
		duration:  focus,
		remaining: focus,
		focus:     focus,
		breakTime: 5 * time.Minute,
		status:    StatusIdle,
	}
}

func (timer *Timer) Snapshot() Snapshot {
	timer.mu.Lock()
	defer timer.mu.Unlock()

	return timer.snapshotLocked(timer.clock())
}

func (timer *Timer) Start(durationSeconds int64) Snapshot {
	return timer.StartFocus(durationSeconds)
}

func (timer *Timer) StartFocus(durationSeconds int64) Snapshot {
	timer.mu.Lock()
	defer timer.mu.Unlock()

	now := timer.clock()
	if timer.mode == ModeFocus && (timer.status == StatusRunning || timer.status == StatusPaused) {
		return timer.snapshotLocked(now)
	}
	if durationSeconds <= 0 {
		durationSeconds = int64(timer.focus.Seconds())
	}
	timer.mode = ModeFocus
	timer.duration = time.Duration(durationSeconds) * time.Second
	timer.focus = timer.duration
	timer.remaining = timer.duration
	timer.startedAt = now
	timer.status = StatusRunning
	return timer.snapshotLocked(now)
}

func (timer *Timer) StartBreak() Snapshot {
	timer.mu.Lock()
	defer timer.mu.Unlock()

	now := timer.clock()
	snapshot := timer.snapshotLocked(now)
	if timer.mode != ModeFocus || timer.status != StatusCompleted {
		return snapshot
	}
	timer.mode = ModeBreak
	timer.duration = timer.breakTime
	timer.remaining = timer.breakTime
	timer.startedAt = now
	timer.status = StatusRunning
	return timer.snapshotLocked(now)
}

func (timer *Timer) SkipBreak() Snapshot {
	timer.mu.Lock()
	defer timer.mu.Unlock()

	if timer.mode == ModeBreak {
		timer.mode = ModeFocus
		timer.duration = timer.focus
		timer.remaining = timer.focus
		timer.startedAt = time.Time{}
		timer.status = StatusIdle
	}
	return timer.snapshotLocked(timer.clock())
}

func (timer *Timer) Pause() Snapshot {
	timer.mu.Lock()
	defer timer.mu.Unlock()

	now := timer.clock()
	snapshot := timer.snapshotLocked(now)
	if timer.status != StatusRunning {
		return snapshot
	}
	timer.remaining = time.Duration(snapshot.RemainingSeconds) * time.Second
	timer.startedAt = time.Time{}
	timer.status = StatusPaused
	return timer.snapshotLocked(now)
}

func (timer *Timer) Resume() Snapshot {
	timer.mu.Lock()
	defer timer.mu.Unlock()

	now := timer.clock()
	if timer.status == StatusPaused {
		timer.startedAt = now
		timer.status = StatusRunning
	}
	return timer.snapshotLocked(now)
}

func (timer *Timer) Reset() Snapshot {
	timer.mu.Lock()
	defer timer.mu.Unlock()

	if timer.mode != ModeFocus {
		timer.duration = timer.focus
	}
	timer.mode = ModeFocus
	timer.remaining = timer.duration
	timer.status = StatusIdle
	timer.startedAt = time.Time{}
	return timer.snapshotLocked(timer.clock())
}

func (timer *Timer) snapshotLocked(now time.Time) Snapshot {
	remainingDuration := timer.remaining
	if timer.status == StatusIdle {
		remainingDuration = timer.duration
	}
	var startedAt *string
	var endsAt *string

	if timer.status == StatusRunning {
		end := timer.startedAt.Add(timer.remaining)
		if !now.Before(end) {
			timer.status = StatusCompleted
			remainingDuration = 0
		} else {
			remainingDuration = end.Sub(now)
		}

		start := timer.startedAt.UTC().Format(time.RFC3339)
		endText := end.UTC().Format(time.RFC3339)
		startedAt = &start
		endsAt = &endText
	}

	if timer.status == StatusCompleted {
		remainingDuration = 0
		if !timer.startedAt.IsZero() {
			end := timer.startedAt.Add(timer.remaining)
			start := timer.startedAt.UTC().Format(time.RFC3339)
			endText := end.UTC().Format(time.RFC3339)
			startedAt = &start
			endsAt = &endText
		}
	}

	return Snapshot{
		Mode:                 timer.mode,
		Status:               timer.status,
		DurationSeconds:      int64(timer.duration.Seconds()),
		RemainingSeconds:     int64(remainingDuration.Seconds()),
		FocusDurationSeconds: int64(timer.focus.Seconds()),
		BreakDurationSeconds: int64(timer.breakTime.Seconds()),
		StartedAt:            startedAt,
		EndsAt:               endsAt,
	}
}
