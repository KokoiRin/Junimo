package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"junimo/backend/internal/codexusage"
	"junimo/backend/internal/pomodoro"
)

// 向 handler 注入主窗口剩余 94% 的 Codex 快照后请求 /state，响应应原样包含这份用量，证明 HTTP 组合层不会丢失后端数据。
func TestStateIncludesCodexUsageSnapshot(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer, func() codexusage.Snapshot {
		return codexusage.Snapshot{
			Status: codexusage.StatusAvailable,
			Primary: &codexusage.Window{
				RemainingPercent:      94,
				WindowDurationMinutes: 300,
			},
		}
	})
	request := httptest.NewRequest(http.MethodGet, "/state", nil)
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)

	var response stateResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.Codex.Primary == nil || response.Codex.Primary.RemainingPercent != 94 {
		t.Fatalf("codex usage = %#v, want 94%% remaining", response.Codex)
	}
}

// 向 /intent 发送兼容类型 pomodoro.start 和 120 秒正时长时，接口应返回 200，并启动剩余 120 秒的 running 专注。
func TestIntentStartsPomodoro(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer)
	body := bytes.NewBufferString(`{"type":"pomodoro.start","durationSeconds":120}`)
	request := httptest.NewRequest(http.MethodPost, "/intent", body)
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", recorder.Code, recorder.Body.String())
	}

	var response stateResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.Pomodoro.Status != pomodoro.StatusRunning {
		t.Fatalf("status = %s, want running", response.Pomodoro.Status)
	}
	if response.Pomodoro.RemainingSeconds != 120 {
		t.Fatalf("remaining = %d, want 120", response.Pomodoro.RemainingSeconds)
	}
}

// 使用固定时钟创建后端后请求 /health，接口应返回 200 和当前协议版本，供 Swift 在连接前判断兼容性。
func TestHealthReportsProtocolVersion(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer)
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", recorder.Code, recorder.Body.String())
	}

	var response healthResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.ProtocolVersion != backendProtocolVersion {
		t.Fatalf("protocolVersion = %d, want %d", response.ProtocolVersion, backendProtocolVersion)
	}
}

// 120 秒专注运行 30 秒后经 HTTP 暂停、静置 60 秒再恢复并运行 45 秒时，应先冻结在 90 秒，最终只消耗恢复后的 45 秒并剩余 45 秒。
func TestIntentCanPauseAndResumePomodoro(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := pomodoro.NewTimer(func() time.Time { return now })
	handler := newHandler(timer)

	postIntent(t, handler, `{"type":"pomodoro.startFocus","durationSeconds":120}`)
	now = now.Add(30 * time.Second)
	paused := postIntent(t, handler, `{"type":"pomodoro.pause"}`)
	if paused.Pomodoro.Status != pomodoro.StatusPaused {
		t.Fatalf("status = %s, want paused", paused.Pomodoro.Status)
	}
	if paused.Pomodoro.RemainingSeconds != 90 {
		t.Fatalf("remaining = %d, want 90", paused.Pomodoro.RemainingSeconds)
	}

	now = now.Add(60 * time.Second)
	resumed := postIntent(t, handler, `{"type":"pomodoro.resume"}`)
	if resumed.Pomodoro.Status != pomodoro.StatusRunning {
		t.Fatalf("status = %s, want running", resumed.Pomodoro.Status)
	}

	now = now.Add(45 * time.Second)
	request := httptest.NewRequest(http.MethodGet, "/state", nil)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)

	var response stateResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.Pomodoro.RemainingSeconds != 45 {
		t.Fatalf("remaining = %d, want 45", response.Pomodoro.RemainingSeconds)
	}
}

// 未配置 Codex 用量提供方时请求 /state，接口应返回 HTTP 200 的 JSON，并把用量状态标记为 loading，供 Swift 稳定展示加载态。
func TestStateDefaultsCodexUsageToLoadingAndJSON(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer)
	request := httptest.NewRequest(http.MethodGet, "/state", nil)
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", recorder.Code)
	}
	if contentType := recorder.Header().Get("Content-Type"); contentType != "application/json" {
		t.Fatalf("content type = %q, want application/json", contentType)
	}

	var response stateResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.Codex.Status != codexusage.StatusLoading {
		t.Fatalf("codex status = %q, want loading", response.Codex.Status)
	}
}

// 向 /intent 分别发送截断 JSON 和未注册的动作类型时，两个无效请求都应返回 400，且不能被当作合法番茄钟操作执行。
func TestIntentRejectsMalformedAndUnknownRequests(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer)

	tests := []struct {
		name string
		body string
	}{
		{name: "malformed JSON", body: `{"type":`},
		{name: "unknown intent", body: `{"type":"pomodoro.unknown"}`},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, "/intent", bytes.NewBufferString(test.body))
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, request)
			if recorder.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400: %s", recorder.Code, recorder.Body.String())
			}
		})
	}
}

// startFocus 缺少正时长、pause 夹带时长或请求出现未知字段时，HTTP 接缝应全部拒绝而不猜测用户意图。
func TestIntentRejectsInvalidTypeAndParameterCombinations(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer)

	tests := []struct {
		name string
		body string
	}{
		{name: "startFocus without duration", body: `{"type":"pomodoro.startFocus"}`},
		{name: "startFocus with zero duration", body: `{"type":"pomodoro.startFocus","durationSeconds":0}`},
		{name: "pause with duration", body: `{"type":"pomodoro.pause","durationSeconds":30}`},
		{name: "unknown field", body: `{"type":"pomodoro.pause","unexpected":true}`},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, "/intent", bytes.NewBufferString(test.body))
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, request)
			if recorder.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400: %s", recorder.Code, recorder.Body.String())
			}
		})
	}
}

// 通过 HTTP 启动 10 秒专注、让时钟到期、开始休息再跳过时，状态应依次到达 focus/completed、break/running 和 focus/idle。
func TestIntentLifecycleCompletesFocusAndReturnsFromBreak(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := pomodoro.NewTimer(func() time.Time { return now })
	handler := newHandler(timer)

	postIntent(t, handler, `{"type":"pomodoro.startFocus","durationSeconds":10}`)
	now = now.Add(10 * time.Second)
	completed := getState(t, handler)
	if completed.Pomodoro.Mode != pomodoro.ModeFocus || completed.Pomodoro.Status != pomodoro.StatusCompleted {
		t.Fatalf("focus state = %s/%s, want focus/completed", completed.Pomodoro.Mode, completed.Pomodoro.Status)
	}

	breakState := postIntent(t, handler, `{"type":"pomodoro.startBreak"}`)
	if breakState.Pomodoro.Mode != pomodoro.ModeBreak || breakState.Pomodoro.Status != pomodoro.StatusRunning {
		t.Fatalf("break state = %s/%s, want break/running", breakState.Pomodoro.Mode, breakState.Pomodoro.Status)
	}

	idle := postIntent(t, handler, `{"type":"pomodoro.skipBreak"}`)
	if idle.Pomodoro.Mode != pomodoro.ModeFocus || idle.Pomodoro.Status != pomodoro.StatusIdle {
		t.Fatalf("idle state = %s/%s, want focus/idle", idle.Pomodoro.Mode, idle.Pomodoro.Status)
	}
}

// 对只声明 GET 或 POST 的 /health、/state、/intent 发送 DELETE 时，每个端点都应返回 405，避免错误方法落入业务处理。
func TestRoutesRejectUnexpectedHTTPMethods(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer)

	for _, route := range []string{"/health", "/state", "/intent"} {
		request := httptest.NewRequest(http.MethodDelete, route, nil)
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, request)
		if recorder.Code != http.StatusMethodNotAllowed {
			t.Fatalf("DELETE %s status = %d, want 405", route, recorder.Code)
		}
	}
}

// 先读取 idle、再启动专注并再次读取状态时，三个公开快照的 revision 应严格递增，使 Swift 能拒绝晚到的旧响应。
func TestStateAndIntentResponsesHaveMonotonicRevisions(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer)

	idle := getState(t, handler)
	running := postIntent(t, handler, `{"type":"pomodoro.startFocus","durationSeconds":120}`)
	reloaded := getState(t, handler)

	if idle.Revision == 0 || running.Revision <= idle.Revision || reloaded.Revision <= running.Revision {
		t.Fatalf("revisions = %d, %d, %d; want strictly increasing positive values", idle.Revision, running.Revision, reloaded.Revision)
	}
}

// postIntent 通过公开 POST /intent 入口发送动作，并要求成功响应能够解码为组合快照。
func postIntent(t *testing.T, handler http.Handler, body string) stateResponse {
	t.Helper()
	request := httptest.NewRequest(http.MethodPost, "/intent", bytes.NewBufferString(body))
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", recorder.Code, recorder.Body.String())
	}

	var response stateResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	return response
}

// getState 通过公开 GET /state 入口读取状态，并要求成功响应能够解码为组合快照。
func getState(t *testing.T, handler http.Handler) stateResponse {
	t.Helper()
	request := httptest.NewRequest(http.MethodGet, "/state", nil)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", recorder.Code, recorder.Body.String())
	}

	var response stateResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	return response
}
