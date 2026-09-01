package codexusage

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// failingQuerier 模拟 Codex 查询边界失败，供监控器降级测试使用。
type failingQuerier struct{}

// Query 始终返回不可用错误，不生成任何伪造的用量快照。
func (failingQuerier) Query(context.Context) (Snapshot, error) {
	return Snapshot{}, errors.New("codex is unavailable")
}

// fixedQuerier 为监控器测试提供确定快照，并可通过 channel 暴露查询已经发生。
type fixedQuerier struct {
	snapshot Snapshot
	calls    chan struct{}
}

// Query 返回配置好的快照，并在存在 calls channel 时非阻塞地报告本次查询。
func (querier fixedQuerier) Query(context.Context) (Snapshot, error) {
	if querier.calls != nil {
		select {
		case querier.calls <- struct{}{}:
		default:
		}
	}
	return querier.snapshot, nil
}

// app-server 返回主窗口已用 6%、次窗口已用 1% 时，解析结果应为 available，并分别给出 5 小时剩余 94% 和 7 天剩余 99%。
func TestParseRateLimitsReturnsRemainingUsageWindows(t *testing.T) {
	response := []byte(`{
		"id": 1,
		"result": {
			"rateLimits": {
				"primary": {"usedPercent": 6, "windowDurationMins": 300, "resetsAt": 1783655023},
				"secondary": {"usedPercent": 1, "windowDurationMins": 10080, "resetsAt": 1784241823}
			}
		}
	}`)

	snapshot, err := ParseRateLimits(response)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Status != StatusAvailable {
		t.Fatalf("status = %q, want %q", snapshot.Status, StatusAvailable)
	}
	if snapshot.Primary == nil || snapshot.Primary.RemainingPercent != 94 {
		t.Fatalf("primary = %#v, want 94%% remaining", snapshot.Primary)
	}
	if snapshot.Primary.WindowDurationMinutes != 300 {
		t.Fatalf("primary duration = %d, want 300", snapshot.Primary.WindowDurationMinutes)
	}
	if snapshot.Secondary == nil || snapshot.Secondary.RemainingPercent != 99 {
		t.Fatalf("secondary = %#v, want 99%% remaining", snapshot.Secondary)
	}
}

// app-server 返回主窗口已用 6% 时，客户端应映射出剩余 94%，并写入合法 RFC3339 刷新时间。
func TestClientMapsRateLimitsIntoUsageSnapshot(t *testing.T) {
	executable := filepath.Join(t.TempDir(), "fake-codex")
	script := `#!/bin/sh
while IFS= read -r line; do
	case "$line" in
	  *'"id":0'*)
	      printf '%s\n' '{"id":0,"result":{"userAgent":"fake"}}'
	      ;;
	    *'account/rateLimits/read'*)
	      printf '%s\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":6,"windowDurationMins":300,"resetsAt":1783655023},"secondary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1784241823}}}}'
      exit 0
      ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	snapshot, err := NewClient(executable).Query(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Primary == nil || snapshot.Primary.RemainingPercent != 94 {
		t.Fatalf("primary = %#v, want 94%% remaining", snapshot.Primary)
	}
	if _, err := time.Parse(time.RFC3339, snapshot.RefreshedAt); err != nil {
		t.Fatalf("refreshedAt = %q, want RFC3339 timestamp: %v", snapshot.RefreshedAt, err)
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

// app-server 异常返回已用 105% 和 -5% 时，剩余量应分别限制为 0% 和 100%，避免越界数字进入 Swift UI。
func TestParseRateLimitsClampsUnexpectedPercentages(t *testing.T) {
	response := []byte(`{
		"id": 1,
		"result": {"rateLimits": {
			"primary": {"usedPercent": 105, "windowDurationMins": 300},
			"secondary": {"usedPercent": -5, "windowDurationMins": 10080}
		}}
	}`)

	snapshot, err := ParseRateLimits(response)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Primary.RemainingPercent != 0 {
		t.Fatalf("primary remaining = %d, want 0", snapshot.Primary.RemainingPercent)
	}
	if snapshot.Secondary.RemainingPercent != 100 {
		t.Fatalf("secondary remaining = %d, want 100", snapshot.Secondary.RemainingPercent)
	}
}

// 输入分别为截断 JSON 和只有次窗口的响应时，解析都应返回错误，不能把缺失主窗口的数据标记为 available。
func TestParseRateLimitsRejectsMalformedOrIncompleteResponses(t *testing.T) {
	tests := []struct {
		name     string
		response string
	}{
		{name: "malformed JSON", response: `{"result":`},
		{name: "missing primary window", response: `{"result":{"rateLimits":{"secondary":{"usedPercent":1}}}}`},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := ParseRateLimits([]byte(test.response)); err == nil {
				t.Fatal("ParseRateLimits should reject an unusable response")
			}
		})
	}
}

// 响应只包含已用 25% 的主窗口且带重置时间时，应得到剩余 75%、保留 resetsAt，并允许 secondary 为 nil。
func TestParseRateLimitsAllowsMissingSecondaryAndPreservesResetTime(t *testing.T) {
	response := []byte(`{
		"result": {"rateLimits": {
			"primary": {"usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1783655023}
		}}
	}`)

	snapshot, err := ParseRateLimits(response)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Primary == nil || snapshot.Primary.RemainingPercent != 75 {
		t.Fatalf("primary = %#v, want 75%% remaining", snapshot.Primary)
	}
	if snapshot.Primary.ResetsAt != 1783655023 {
		t.Fatalf("resetsAt = %d, want 1783655023", snapshot.Primary.ResetsAt)
	}
	if snapshot.Secondary != nil {
		t.Fatalf("secondary = %#v, want nil", snapshot.Secondary)
	}
}

// 客户端收到空可执行文件路径时，应在启动进程前立即返回错误，不能生成 loading 或 available 的伪快照。
func TestClientRequiresAnExecutable(t *testing.T) {
	if _, err := NewClient("").Query(context.Background()); err == nil {
		t.Fatal("query should fail when no Codex executable is available")
	}
}

// 监控器从初始 loading 状态执行一次返回主窗口 88% 的成功刷新后，公开快照应切换为 available 并携带 88%。
func TestMonitorPublishesSuccessfulRefresh(t *testing.T) {
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
}

// 使用 1 小时刷新间隔启动监控器时，首次查询仍应在 1 秒内发生并发布 available，不能等到第一个周期结束。
func TestMonitorStartRefreshesImmediately(t *testing.T) {
	calls := make(chan struct{}, 1)
	monitor := NewMonitor(fixedQuerier{
		snapshot: Snapshot{Status: StatusAvailable},
		calls:    calls,
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
	cancel()
	if status := monitor.Snapshot().Status; status != StatusAvailable {
		t.Fatalf("status = %q, want available", status)
	}
}
