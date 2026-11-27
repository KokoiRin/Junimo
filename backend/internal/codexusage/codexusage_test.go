package codexusage

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"junimo/backend/internal/quota"
)

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
	if snapshot.Status != quota.StatusAvailable {
		t.Fatalf("status = %q, want %q", snapshot.Status, quota.StatusAvailable)
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

// 连续两次查询额度时应复用同一个 app-server 进程并映射出剩余 94% 与合法 RFC3339 时间，而不是每次查询都重新拉起子进程。
func TestClientReusesPersistentSessionAcrossQueries(t *testing.T) {
	dir := t.TempDir()
	startsFile := filepath.Join(dir, "starts.log")
	executable := filepath.Join(dir, "fake-codex")
	script := `#!/bin/sh
echo "$$" >> "` + startsFile + `"
while IFS= read -r line; do
	case "$line" in
	  *'"id":0'*)
	      printf '%s\n' '{"id":0,"result":{"userAgent":"fake"}}'
	      ;;
	  *'"id":1'*'account/rateLimits/read'*)
	      printf '%s\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":6,"windowDurationMins":300,"resetsAt":1783655023},"secondary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1784241823}}}}'
	      ;;
	  *'"id":2'*'account/rateLimits/read'*)
	      printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1783655023}}}}'
	      ;;
	esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}

	client := NewClient(executable)
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	first, err := client.Query(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if first.Primary == nil || first.Primary.RemainingPercent != 94 {
		t.Fatalf("first primary = %#v, want 94%% remaining", first.Primary)
	}
	if _, err := time.Parse(time.RFC3339, first.RefreshedAt); err != nil {
		t.Fatalf("refreshedAt = %q, want RFC3339 timestamp: %v", first.RefreshedAt, err)
	}

	second, err := client.Query(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if second.Primary == nil || second.Primary.RemainingPercent != 88 {
		t.Fatalf("second primary = %#v, want 88%% remaining", second.Primary)
	}

	startsData, err := os.ReadFile(startsFile)
	if err != nil {
		t.Fatal(err)
	}
	starts := strings.Split(strings.TrimSpace(string(startsData)), "\n")
	if len(starts) != 1 {
		t.Fatalf("app-server started %d times (%v), want 1 persistent process", len(starts), starts)
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
