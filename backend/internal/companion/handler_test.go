package companion

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"junimo/backend/internal/codexactivity"
	"junimo/backend/internal/codexusage"
)

// 轻量后端收到健康检查时必须声明协议 v7，让旧 Swift 客户端拒绝不兼容快照。
func TestHealthReportsProtocolSeven(t *testing.T) {
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
	if response.Code != http.StatusOK || health.ProtocolVersion != 7 {
		t.Fatalf("status = %d health = %#v", response.Code, health)
	}
}

// 前端指定启动实例标识后，健康接口和状态响应都必须携带同一标识，以便拒绝其他后端的响应。
func TestResponsesIdentifyTheirInstance(t *testing.T) {
	t.Setenv("JUNIMO_INSTANCE_ID", "owned-instance")
	handler := newHandler(nil, nil)
	for _, path := range []string{"/health", "/state"} {
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, path, nil))
		if response.Header().Get("X-Junimo-Instance-ID") != "owned-instance" {
			t.Fatalf("%s did not identify the serving instance", path)
		}
		if path == "/health" {
			var health healthResponse
			if err := json.Unmarshal(response.Body.Bytes(), &health); err != nil {
				t.Fatal(err)
			}
			if health.InstanceID != "owned-instance" {
				t.Fatalf("health instance = %q", health.InstanceID)
			}
		}
	}
}

// v7 状态读取分别公开 Codex、Grok 用量和任务活动，让任一用量源失败不影响另一来源。
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
	for _, key := range []string{"revision", "codex", "grok", "activity"} {
		if _, exists := current[key]; !exists {
			t.Fatalf("state missing %q: %s", key, response.Body.String())
		}
	}
	if len(current) != 4 {
		t.Fatalf("state fields = %v, want exactly revision, codex, grok, activity", current)
	}
}

// Codex 不可用而 Grok 仍有周额度时，状态接口必须保留 Grok 的独立百分比、来源与时间，不把失败扩散到另一个来源。
func TestGrokUsageIsIndependent(t *testing.T) {
	handler := newHandlerWithGrok(
		func() codexusage.Snapshot { return codexusage.Snapshot{Status: codexusage.StatusUnavailable} }, nil,
		func() codexusage.Snapshot {
			return codexusage.Snapshot{Status: codexusage.StatusAvailable, Primary: &codexusage.Window{RemainingPercent: 15, WindowDurationMinutes: 10080}, Message: "本机缓存", RefreshedAt: "2026-11-06T15:59:00Z"}
		},
	)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/state", nil))
	var current stateResponse
	if err := json.Unmarshal(response.Body.Bytes(), &current); err != nil {
		t.Fatal(err)
	}
	if current.Codex.Status != codexusage.StatusUnavailable || current.Grok.Status != codexusage.StatusAvailable || current.Grok.Primary == nil || current.Grok.Primary.RemainingPercent != 15 || current.Grok.Message != "本机缓存" || current.Grok.RefreshedAt != "2026-11-06T15:59:00Z" {
		t.Fatalf("independent state = %+v", current)
	}
}
