package companion

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"junimo/backend/internal/codexactivity"
	"junimo/backend/internal/quota"
)

// 轻量后端收到健康检查时必须声明协议 v7，让旧 Swift 客户端拒绝不兼容快照。
func TestHealthReportsProtocolSeven(t *testing.T) {
	handler := newHandler(
		func() quota.Snapshot { return quota.Snapshot{Status: quota.StatusLoading} },
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
		func() quota.Snapshot {
			return quota.Snapshot{
				Status:  quota.StatusAvailable,
				Primary: &quota.Window{RemainingPercent: 73, WindowDurationMinutes: 300},
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
	for _, key := range []string{"revision", "codex", "grok", "activity", "antigravity"} {
		if _, exists := current[key]; !exists {
			t.Fatalf("state missing %q: %s", key, response.Body.String())
		}
	}
	if len(current) != 5 {
		t.Fatalf("state fields = %v, want exactly revision, codex, grok, activity, antigravity", current)
	}
}

// Codex 不可用而 Grok 仍有周额度时，状态接口必须保留 Grok 的独立百分比、来源与时间，不把失败扩散到另一个来源。
func TestGrokUsageIsIndependent(t *testing.T) {
	handler := newSurfaceHandler(
		func() quota.Snapshot { return quota.Snapshot{Status: quota.StatusUnavailable} }, nil,
		func() quota.Snapshot {
			return quota.Snapshot{Status: quota.StatusAvailable, Primary: &quota.Window{RemainingPercent: 15, WindowDurationMinutes: 10080}, Message: "本机缓存", RefreshedAt: "2026-11-06T15:59:00Z"}
		}, nil,
	)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/state", nil))
	var current stateResponse
	if err := json.Unmarshal(response.Body.Bytes(), &current); err != nil {
		t.Fatal(err)
	}
	if current.Codex.Status != quota.StatusUnavailable || current.Grok.Status != quota.StatusAvailable || current.Grok.Primary == nil || current.Grok.Primary.RemainingPercent != 15 || current.Grok.Message != "本机缓存" || current.Grok.RefreshedAt != "2026-11-06T15:59:00Z" {
		t.Fatalf("independent state = %+v", current)
	}
}

// 状态长轮询在无变化超时后返回 304，变更发生时应立即返回 200 和最新状态版本；常用应用长轮询在 PUT 保存后也应立即唤醒。
func TestLongPollingForStateAndShortcuts(t *testing.T) {
	t.Setenv("JUNIMO_INSTANCE_ID", "lp-instance")
	notifier := newChangeNotifier()
	store := &shortcutStore{directory: t.TempDir()}
	shutdown := make(chan struct{})
	defer close(shutdown)
	handler := newSurfaceHandlerWithLifecycle(nil, nil, nil, nil, notifier, shutdown, store)

	initial := httptest.NewRecorder()
	handler.ServeHTTP(initial, httptest.NewRequest(http.MethodGet, "/state", nil))
	version := initial.Header().Get(stateVersionHeaderKey)
	if version != "1" {
		t.Fatalf("initial version header = %q, want 1", version)
	}

	// 无变更且短超时时应返回 304 Not Modified 且不携带响应体。
	unchanged := httptest.NewRecorder()
	handler.ServeHTTP(unchanged, httptest.NewRequest(http.MethodGet, "/state?after=1&wait=20", nil))
	if unchanged.Code != http.StatusNotModified || unchanged.Body.Len() != 0 {
		t.Fatalf("unchanged status=%d body=%q", unchanged.Code, unchanged.Body.String())
	}

	// 状态变更时等待中的 /state 长轮询应立即返回 200 与新版本号。
	woke := make(chan *httptest.ResponseRecorder, 1)
	go func() {
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/state?after=1&wait=2000", nil))
		woke <- rec
	}()
	time.Sleep(15 * time.Millisecond)
	notifier.Notify()
	select {
	case rec := <-woke:
		if rec.Code != http.StatusOK || rec.Header().Get(stateVersionHeaderKey) != "2" {
			t.Fatalf("woke status=%d version=%q", rec.Code, rec.Header().Get(stateVersionHeaderKey))
		}
	case <-time.After(time.Second):
		t.Fatal("state long poll did not wake on Notify")
	}

	// 常用应用长轮询在 PUT 写入新收藏后应立即返回新版本。
	initialShortcuts := httptest.NewRecorder()
	handler.ServeHTTP(initialShortcuts, httptest.NewRequest(http.MethodGet, "/app-shortcuts", nil))
	if initialShortcuts.Code != http.StatusOK {
		t.Fatalf("initial shortcuts status=%d", initialShortcuts.Code)
	}
	shortcutWoke := make(chan *httptest.ResponseRecorder, 1)
	go func() {
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/app-shortcuts?after=1&wait=2000", nil))
		shortcutWoke <- rec
	}()
	time.Sleep(15 * time.Millisecond)
	putReq := httptest.NewRequest(http.MethodPut, "/app-shortcuts", bytes.NewBufferString(`{"revision":1,"items":[{"bundleId":"com.apple.finder","name":"Finder"}]}`))
	putReq.Header.Set("Content-Type", "application/json")
	putReq.Header.Set("X-Junimo-Instance-ID", "lp-instance")
	putRec := httptest.NewRecorder()
	handler.ServeHTTP(putRec, putReq)
	if putRec.Code != http.StatusOK {
		t.Fatalf("PUT shortcuts failed: %d %s", putRec.Code, putRec.Body.String())
	}
	select {
	case rec := <-shortcutWoke:
		var updated appShortcuts
		if rec.Code != http.StatusOK || json.Unmarshal(rec.Body.Bytes(), &updated) != nil || updated.Revision != 2 {
			t.Fatalf("shortcuts long poll = %d %s", rec.Code, rec.Body.String())
		}
	case <-time.After(time.Second):
		t.Fatal("app-shortcuts long poll did not wake on PUT")
	}
}
