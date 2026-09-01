package companion

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"junimo/backend/internal/codexactivity"
	"junimo/backend/internal/codexusage"
)

// 轻量后端收到健康检查时必须声明协议 v5，让旧 Swift 客户端拒绝不兼容快照。
func TestHealthReportsProtocolFive(t *testing.T) {
	handler := newHandler(
		func() codexusage.Snapshot { return codexusage.Snapshot{Status: codexusage.StatusLoading} },
		func() codexactivity.Snapshot { return codexactivity.Snapshot{Status: codexactivity.StatusLoading} },
	)
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	var health healthResponse
	if err := json.Unmarshal(response.Body.Bytes(), &health); err != nil {
		t.Fatal(err)
	}
	if response.Code != http.StatusOK || health.ProtocolVersion != 5 {
		t.Fatalf("status = %d health = %#v", response.Code, health)
	}
}

// v5 状态读取只公开 revision、Codex 用量和 activity，避免未使用字段扩大跨进程契约。
func TestStateContainsOnlyUsageAndActivity(t *testing.T) {
	handler := newHandler(
		func() codexusage.Snapshot {
			return codexusage.Snapshot{
				Status:  codexusage.StatusAvailable,
				Primary: &codexusage.Window{RemainingPercent: 73, WindowDurationMinutes: 300},
			}
		},
		func() codexactivity.Snapshot {
			return codexactivity.Snapshot{
				Status: codexactivity.StatusAvailable,
				CompletionEvent: &codexactivity.CompletionEvent{
					ID: "turn-1", ThreadID: "thread-1", Title: "轻量 Junimo", CompletedAt: 20,
				},
			}
		},
	)

	request := httptest.NewRequest(http.MethodGet, "/state", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	var current map[string]json.RawMessage
	if err := json.Unmarshal(response.Body.Bytes(), &current); err != nil {
		t.Fatal(err)
	}
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", response.Code, response.Body.String())
	}
	for _, key := range []string{"revision", "codex", "activity"} {
		if _, exists := current[key]; !exists {
			t.Fatalf("state missing %q: %s", key, response.Body.String())
		}
	}
	if len(current) != 3 {
		t.Fatalf("state fields = %v, want exactly revision, codex, activity", current)
	}
}
