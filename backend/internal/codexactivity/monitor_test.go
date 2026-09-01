package codexactivity

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

type fakeScanner struct {
	mu      sync.Mutex
	threads []Thread
	err     error
}

func (scanner *fakeScanner) Scan(context.Context) ([]Thread, error) {
	scanner.mu.Lock()
	defer scanner.mu.Unlock()
	return scanner.threads, scanner.err
}

func (scanner *fakeScanner) set(threads []Thread, err error) {
	scanner.mu.Lock()
	defer scanner.mu.Unlock()
	scanner.threads = threads
	scanner.err = err
}

func completedThread(threadID string, turnID string, title string, completedAt int64) Thread {
	return Thread{
		ID:        threadID,
		Name:      title,
		UpdatedAt: completedAt,
		Turns: []Turn{{
			ID:          turnID,
			Status:      TurnStatusCompleted,
			CompletedAt: completedAt,
		}},
	}
}

func testMonitorAt(source scanner, current *int64) *Monitor {
	monitor := NewMonitor(source)
	monitor.now = func() time.Time { return time.Unix(*current, 0) }
	return monitor
}

// 已有历史完成任务只用于建立启动基线，首次刷新不得制造过期提醒。
func TestMonitorBaselinesHistoricalCompletions(t *testing.T) {
	scanner := &fakeScanner{threads: []Thread{completedThread("thread-old", "turn-old", "旧任务", 10)}}
	monitor := NewMonitor(scanner)

	monitor.Refresh(context.Background())
	snapshot := monitor.Snapshot()
	if snapshot.Status != StatusAvailable {
		t.Fatalf("status = %q, want available", snapshot.Status)
	}
	if snapshot.CompletionEvent != nil {
		t.Fatalf("completion event = %#v, want nil baseline", snapshot.CompletionEvent)
	}
}

// 基线完成后出现的新 completed turn 应发布包含稳定身份和任务标题的一次事件。
func TestMonitorPublishesNewCompletedTurn(t *testing.T) {
	current := int64(10)
	scanner := &fakeScanner{threads: []Thread{completedThread("thread-1", "turn-1", "实现轻量提醒", 10)}}
	monitor := testMonitorAt(scanner, &current)
	monitor.Refresh(context.Background())

	current = 20
	scanner.threads = append(scanner.threads, completedThread("thread-2", "turn-2", "整理快捷入口", 20))
	monitor.Refresh(context.Background())

	event := monitor.Snapshot().CompletionEvent
	if event == nil {
		t.Fatal("completion event = nil, want new completed turn")
	}
	if event.ID != "turn-2" || event.ThreadID != "thread-2" || event.Title != "整理快捷入口" || event.CompletedAt != 20 {
		t.Fatalf("completion event = %#v", event)
	}
}

// 会话没有名称时完成提醒应依次使用预览文本和通用标题，避免通知出现空白内容。
func TestMonitorUsesReadableFallbackTitles(t *testing.T) {
	tests := []struct {
		name     string
		thread   Thread
		expected string
	}{
		{
			name: "preview fallback",
			thread: Thread{ID: "thread-preview", Preview: "整理测试", Turns: []Turn{{
				ID: "turn-preview", Status: TurnStatusCompleted, CompletedAt: 10,
			}}},
			expected: "整理测试",
		},
		{
			name: "generic fallback",
			thread: Thread{ID: "thread-empty", Turns: []Turn{{
				ID: "turn-empty", Status: TurnStatusCompleted, CompletedAt: 10,
			}}},
			expected: "Codex 任务",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			current := int64(9)
			scanner := &fakeScanner{}
			monitor := testMonitorAt(scanner, &current)
			monitor.Refresh(context.Background())
			current = 10
			scanner.set([]Thread{test.thread}, nil)
			monitor.Refresh(context.Background())

			event := monitor.Snapshot().CompletionEvent
			if event == nil || event.Title != test.expected {
				t.Fatalf("event = %#v, want title %q", event, test.expected)
			}
		})
	}
}

// 已发布 turn 再次出现时不能挡住后续新 turn，下一次公开事件应直接前进到新完成任务。
func TestMonitorDuplicateDoesNotDelayNextCompletion(t *testing.T) {
	current := int64(9)
	scanner := &fakeScanner{threads: []Thread{}}
	monitor := testMonitorAt(scanner, &current)
	monitor.Refresh(context.Background())

	current = 10
	scanner.threads = []Thread{completedThread("thread-1", "turn-1", "只提醒一次", 10)}
	monitor.Refresh(context.Background())
	first := monitor.Snapshot().CompletionEvent
	current = 20
	scanner.threads = append(scanner.threads, completedThread("thread-2", "turn-2", "后续任务", 20))
	monitor.Refresh(context.Background())
	second := monitor.Snapshot().CompletionEvent

	if first == nil || second == nil || first.ID != "turn-1" || second.ID != "turn-2" {
		t.Fatalf("events = %#v then %#v, want duplicate skipped before next completion", first, second)
	}
}

// 两个会话在同一扫描间隔内完成时，监控器应逐次发布两条稳定事件而不是只保留最后一条。
func TestMonitorPublishesEveryCompletionAcrossRefreshes(t *testing.T) {
	current := int64(9)
	scanner := &fakeScanner{threads: []Thread{}}
	monitor := testMonitorAt(scanner, &current)
	monitor.Refresh(context.Background())

	current = 20
	scanner.threads = []Thread{
		completedThread("thread-1", "turn-1", "第一个任务", 10),
		completedThread("thread-2", "turn-2", "第二个任务", 20),
	}
	monitor.Refresh(context.Background())
	first := monitor.Snapshot().CompletionEvent
	monitor.Refresh(context.Background())
	second := monitor.Snapshot().CompletionEvent

	if first == nil || second == nil || first.ID != "turn-1" || second.ID != "turn-2" {
		t.Fatalf("events = %#v then %#v, want both completions in order", first, second)
	}
}

// 多个任务同时完成而排队发布时，尚未轮到的会话若已开始下一轮，其旧完成事件应从队列中移除。
func TestMonitorDropsQueuedCompletionWhenThreadStartsRunningAgain(t *testing.T) {
	current := int64(100)
	scanner := &fakeScanner{}
	monitor := testMonitorAt(scanner, &current)
	monitor.Refresh(context.Background())

	current = 103
	scanner.set([]Thread{
		completedThread("thread-first", "turn-first", "先完成", 101),
		completedThread("thread-queued", "turn-queued", "排队等待", 102),
	}, nil)
	monitor.Refresh(context.Background())
	first := monitor.Snapshot().CompletionEvent
	if first == nil || first.ID != "turn-first" {
		t.Fatalf("completion event = %#v, want first turn", first)
	}

	current = 104
	scanner.set([]Thread{
		completedThread("thread-first", "turn-first", "先完成", 101),
		{
			ID:   "thread-queued",
			Name: "排队等待",
			Turns: []Turn{
				{ID: "turn-queued", Status: TurnStatusCompleted, CompletedAt: 102},
				{ID: "turn-running", Status: TurnStatusInProgress},
			},
		},
	}, nil)
	monitor.Refresh(context.Background())

	current = 105
	scanner.set([]Thread{
		completedThread("thread-first", "turn-first", "先完成", 101),
		completedThread("thread-queued", "turn-queued", "排队等待", 102),
	}, nil)
	monitor.Refresh(context.Background())
	if event := monitor.Snapshot().CompletionEvent; event == nil || event.ID != "turn-first" {
		t.Fatalf("completion event = %#v, want queued turn to stay suppressed", event)
	}
}

// 一个会话重新进入最近列表时，即使携带此前从未扫描过的历史完成记录，也不能补发过期提醒。
func TestMonitorDoesNotReplayHistoricalCompletionFromReturningThread(t *testing.T) {
	current := int64(100)
	scanner := &fakeScanner{}
	monitor := testMonitorAt(scanner, &current)
	monitor.Refresh(context.Background())

	current = 103
	scanner.set([]Thread{completedThread("thread-returned", "turn-old", "重新出现的旧任务", 80)}, nil)
	monitor.Refresh(context.Background())
	if event := monitor.Snapshot().CompletionEvent; event != nil {
		t.Fatalf("completion event = %#v, want nil for historical turn", event)
	}
}

// 同一会话的上一轮刚完成但下一轮已经开始时，用户已继续交互，不应再弹出上一轮的迟到提醒。
func TestMonitorSuppressesCompletionWhenThreadIsAlreadyRunningAgain(t *testing.T) {
	current := int64(100)
	scanner := &fakeScanner{}
	monitor := testMonitorAt(scanner, &current)
	monitor.Refresh(context.Background())

	current = 103
	scanner.set([]Thread{{
		ID:   "thread-active",
		Name: "继续对话",
		Turns: []Turn{
			{ID: "turn-completed", Status: TurnStatusCompleted, CompletedAt: 102},
			{ID: "turn-running", Status: TurnStatusInProgress},
		},
	}}, nil)
	monitor.Refresh(context.Background())
	if event := monitor.Snapshot().CompletionEvent; event != nil {
		t.Fatalf("completion event = %#v, want nil while next turn is running", event)
	}

	current = 104
	scanner.set([]Thread{completedThread("thread-active", "turn-completed", "继续对话", 102)}, nil)
	monitor.Refresh(context.Background())
	if event := monitor.Snapshot().CompletionEvent; event != nil {
		t.Fatalf("completion event = %#v, want suppressed turn to stay consumed", event)
	}
}

// 同一会话在一次扫描中带回多条完成历史时，只提醒最新完成的一轮，旧轮次仅用于去重基线。
func TestMonitorPublishesOnlyLatestCompletionFromOneThread(t *testing.T) {
	current := int64(100)
	scanner := &fakeScanner{}
	monitor := testMonitorAt(scanner, &current)
	monitor.Refresh(context.Background())

	current = 103
	scanner.set([]Thread{{
		ID:   "thread-many-turns",
		Name: "连续任务",
		Turns: []Turn{
			{ID: "turn-old", Status: TurnStatusCompleted, CompletedAt: 90},
			{ID: "turn-latest", Status: TurnStatusCompleted, CompletedAt: 102},
		},
	}}, nil)
	monitor.Refresh(context.Background())
	event := monitor.Snapshot().CompletionEvent
	if event == nil || event.ID != "turn-latest" {
		t.Fatalf("completion event = %#v, want only latest turn", event)
	}
}

// 扫描故障持续超过新鲜窗口后才恢复时，故障期间很早完成的任务不应作为迟到通知补发。
func TestMonitorDropsStaleCompletionAfterRecovery(t *testing.T) {
	current := int64(100)
	scanner := &fakeScanner{}
	monitor := testMonitorAt(scanner, &current)
	monitor.Refresh(context.Background())

	current = 105
	scanner.set(nil, errors.New("temporary failure"))
	monitor.Refresh(context.Background())
	current = 130
	scanner.set([]Thread{completedThread("thread-stale", "turn-stale", "故障期间完成", 110)}, nil)
	monitor.Refresh(context.Background())
	if event := monitor.Snapshot().CompletionEvent; event != nil {
		t.Fatalf("completion event = %#v, want nil after freshness window", event)
	}
}

// 短暂扫描故障恢复时，仍在新鲜窗口内且发生于上次成功扫描后的完成任务应正常提醒。
func TestMonitorPublishesFreshCompletionAfterRecovery(t *testing.T) {
	current := int64(100)
	scanner := &fakeScanner{}
	monitor := testMonitorAt(scanner, &current)
	monitor.Refresh(context.Background())

	current = 105
	scanner.set(nil, errors.New("temporary failure"))
	monitor.Refresh(context.Background())
	current = 116
	scanner.set([]Thread{completedThread("thread-fresh", "turn-fresh", "短暂故障期间完成", 110)}, nil)
	monitor.Refresh(context.Background())
	event := monitor.Snapshot().CompletionEvent
	if event == nil || event.ID != "turn-fresh" {
		t.Fatalf("completion event = %#v, want fresh recovered turn", event)
	}
}

// failed、interrupted 与适配器错误都不能伪造成功完成事件，错误只改变 activity 可用状态。
func TestMonitorIgnoresUnsuccessfulTurnsAndIsolatesScannerFailure(t *testing.T) {
	scanner := &fakeScanner{threads: []Thread{}}
	monitor := NewMonitor(scanner)
	monitor.Refresh(context.Background())

	scanner.threads = []Thread{{
		ID: "thread-1",
		Turns: []Turn{
			{ID: "turn-failed", Status: TurnStatusFailed},
			{ID: "turn-interrupted", Status: TurnStatusInterrupted},
		},
	}}
	monitor.Refresh(context.Background())
	if event := monitor.Snapshot().CompletionEvent; event != nil {
		t.Fatalf("completion event = %#v, want nil", event)
	}

	scanner.err = errors.New("app-server unavailable")
	monitor.Refresh(context.Background())
	if snapshot := monitor.Snapshot(); snapshot.Status != StatusUnavailable || snapshot.Message == "" {
		t.Fatalf("snapshot = %#v, want unavailable with message", snapshot)
	}
}

// 后台监控应立即建立基线，并在后续间隔中从临时错误恢复后发现新完成任务。
func TestMonitorStartRefreshesImmediatelyAndRetries(t *testing.T) {
	scanner := &fakeScanner{err: errors.New("temporary failure")}
	monitor := NewMonitor(scanner)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	monitor.Start(ctx, 10*time.Millisecond, 100*time.Millisecond)

	waitForActivityStatus(t, monitor, StatusUnavailable)
	scanner.set([]Thread{}, nil)
	waitForActivityStatus(t, monitor, StatusAvailable)
	scanner.set([]Thread{completedThread("thread-1", "turn-1", "后台完成", time.Now().Unix())}, nil)

	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if event := monitor.Snapshot().CompletionEvent; event != nil && event.ID == "turn-1" {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("snapshot = %#v, want recovered completion", monitor.Snapshot())
}

func waitForActivityStatus(t *testing.T, monitor *Monitor, status Status) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if monitor.Snapshot().Status == status {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("status = %q, want %q", monitor.Snapshot().Status, status)
}
