package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"junimo/backend/internal/codexusage"
	"junimo/backend/internal/pomodoro"
	"junimo/backend/internal/todo"
)

// failingTodoStore 模拟无法读取或保存的 Todo 持久化边界。
type failingTodoStore struct{}

// Load 返回固定损坏错误，使 Todo 初始化为 unavailable。
func (failingTodoStore) Load() ([]todo.Item, error) {
	return nil, errors.New("corrupt todo store")
}

// Save 保持同一不可用结果，避免测试意外绕过初始化状态。
func (failingTodoStore) Save([]todo.Item) error {
	return errors.New("corrupt todo store")
}

// 已运行的番茄钟收到 todo.create 后，响应应包含持久化新任务且保持 Pomodoro running，证明两个领域只在组合快照中并列。
func TestTodoCreateAppearsInStateWithoutChangingPomodoro(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := pomodoro.NewTimer(func() time.Time { return now })
	todos := todo.NewList(
		todo.NewFileStore(filepath.Join(t.TempDir(), "todos.json")),
		func() string { return "todo-1" },
	)
	handler := newHandlerWithTodo(timer, todos)

	postIntent(t, handler, `{"type":"pomodoro.startFocus","durationSeconds":120}`)
	created := postIntent(t, handler, `{"type":"todo.create","title":"  完成 HTTP 合约  "}`)
	if created.Pomodoro.Status != pomodoro.StatusRunning || created.Pomodoro.RemainingSeconds != 120 {
		t.Fatalf("pomodoro = %#v, want unchanged running 120s", created.Pomodoro)
	}
	if created.Todo.Status != todo.AvailabilityAvailable || len(created.Todo.Items) != 1 {
		t.Fatalf("todo snapshot = %#v, want one available item", created.Todo)
	}
	if item := created.Todo.Items[0]; item.ID != "todo-1" || item.Title != "完成 HTTP 合约" || item.Status != todo.StatusOpen {
		t.Fatalf("created todo = %#v", item)
	}
}

// 同一 Todo 经 HTTP 创建、改名、重复完成、恢复和删除时，快照应逐步反映明确目标状态，重复完成不得翻转且删除后列表为空。
func TestTodoIntentLifecycleUsesExplicitCompletionState(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	todos := todo.NewList(
		todo.NewFileStore(filepath.Join(t.TempDir(), "todos.json")),
		func() string { return "todo-1" },
	)
	handler := newHandlerWithTodo(timer, todos)

	postIntent(t, handler, `{"type":"todo.create","title":"初始标题"}`)
	renamed := postIntent(t, handler, `{"type":"todo.rename","id":"todo-1","title":"更新标题"}`)
	if renamed.Todo.Items[0].Title != "更新标题" {
		t.Fatalf("renamed todo = %#v", renamed.Todo.Items[0])
	}
	postIntent(t, handler, `{"type":"todo.setCompletion","id":"todo-1","completed":true}`)
	repeated := postIntent(t, handler, `{"type":"todo.setCompletion","id":"todo-1","completed":true}`)
	if repeated.Todo.Items[0].Status != todo.StatusCompleted {
		t.Fatalf("repeated completion status = %q, want completed", repeated.Todo.Items[0].Status)
	}
	restored := postIntent(t, handler, `{"type":"todo.setCompletion","id":"todo-1","completed":false}`)
	if restored.Todo.Items[0].Status != todo.StatusOpen {
		t.Fatalf("restored status = %q, want open", restored.Todo.Items[0].Status)
	}
	deleted := postIntent(t, handler, `{"type":"todo.delete","id":"todo-1"}`)
	if len(deleted.Todo.Items) != 0 {
		t.Fatalf("deleted items = %#v, want empty", deleted.Todo.Items)
	}
}

// Todo 意图缺少必填字段、夹带其他动作字段或使用空标题时，HTTP 接缝应返回 400 且不创建任何正式任务。
func TestTodoIntentsRejectInvalidShapesAndTitles(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer)

	tests := []struct {
		name string
		body string
	}{
		{name: "create without title", body: `{"type":"todo.create"}`},
		{name: "create with blank title", body: `{"type":"todo.create","title":"   "}`},
		{name: "rename without id", body: `{"type":"todo.rename","title":"new"}`},
		{name: "rename with completion", body: `{"type":"todo.rename","id":"1","title":"new","completed":true}`},
		{name: "completion without target", body: `{"type":"todo.setCompletion","id":"1"}`},
		{name: "completion with title", body: `{"type":"todo.setCompletion","id":"1","completed":true,"title":"extra"}`},
		{name: "delete with duration", body: `{"type":"todo.delete","id":"1","durationSeconds":10}`},
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
	if snapshot := getState(t, handler); len(snapshot.Todo.Items) != 0 {
		t.Fatalf("todo items = %#v, want empty after rejected intents", snapshot.Todo.Items)
	}
}

// Todo Store 损坏时，健康检查、组合快照、Codex 和 Pomodoro 仍应工作，只有 Todo 写入返回 500 并保持 unavailable。
func TestUnavailableTodoDoesNotDisableOtherBackendDomains(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := pomodoro.NewTimer(func() time.Time { return now })
	todos := todo.NewList(failingTodoStore{}, func() string { return "unused" })
	handler := newHandlerWithTodo(timer, todos, func() codexusage.Snapshot {
		return codexusage.Snapshot{Status: codexusage.StatusAvailable}
	})

	healthRequest := httptest.NewRequest(http.MethodGet, "/health", nil)
	healthRecorder := httptest.NewRecorder()
	handler.ServeHTTP(healthRecorder, healthRequest)
	if healthRecorder.Code != http.StatusOK {
		t.Fatalf("health status = %d, want 200", healthRecorder.Code)
	}

	initial := getState(t, handler)
	if initial.Todo.Status != todo.AvailabilityUnavailable || initial.Codex.Status != codexusage.StatusAvailable {
		t.Fatalf("combined state = %#v, want unavailable Todo and available Codex", initial)
	}
	running := postIntent(t, handler, `{"type":"pomodoro.startFocus","durationSeconds":60}`)
	if running.Pomodoro.Status != pomodoro.StatusRunning {
		t.Fatalf("pomodoro status = %q, want running", running.Pomodoro.Status)
	}

	request := httptest.NewRequest(http.MethodPost, "/intent", bytes.NewBufferString(`{"type":"todo.create","title":"不可保存"}`))
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusInternalServerError {
		t.Fatalf("todo create status = %d, want 500: %s", recorder.Code, recorder.Body.String())
	}
}

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
