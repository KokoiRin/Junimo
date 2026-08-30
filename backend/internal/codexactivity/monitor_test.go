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
	scanner := &fakeScanner{threads: []Thread{completedThread("thread-1", "turn-1", "实现轻量提醒", 10)}}
	monitor := NewMonitor(scanner)
	monitor.Refresh(context.Background())

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
			scanner := &fakeScanner{}
			monitor := NewMonitor(scanner)
			monitor.Refresh(context.Background())
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
	scanner := &fakeScanner{threads: []Thread{}}
	monitor := NewMonitor(scanner)
	monitor.Refresh(context.Background())

	scanner.threads = []Thread{completedThread("thread-1", "turn-1", "只提醒一次", 10)}
	monitor.Refresh(context.Background())
	first := monitor.Snapshot().CompletionEvent
	scanner.threads = append(scanner.threads, completedThread("thread-2", "turn-2", "后续任务", 20))
	monitor.Refresh(context.Background())
	second := monitor.Snapshot().CompletionEvent

	if first == nil || second == nil || first.ID != "turn-1" || second.ID != "turn-2" {
		t.Fatalf("events = %#v then %#v, want duplicate skipped before next completion", first, second)
	}
}

// 两个会话在同一扫描间隔内完成时，监控器应逐次发布两条稳定事件而不是只保留最后一条。
func TestMonitorPublishesEveryCompletionAcrossRefreshes(t *testing.T) {
	scanner := &fakeScanner{threads: []Thread{}}
	monitor := NewMonitor(scanner)
	monitor.Refresh(context.Background())

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
	scanner.set([]Thread{completedThread("thread-1", "turn-1", "后台完成", 20)}, nil)

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
