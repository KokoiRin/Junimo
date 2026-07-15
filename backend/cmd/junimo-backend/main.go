package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"junimo/backend/internal/codexusage"
	"junimo/backend/internal/pomodoro"
	"junimo/backend/internal/todo"
)

const backendProtocolVersion = 4

type healthResponse struct {
	Status          string `json:"status"`
	ProtocolVersion int    `json:"protocolVersion"`
}

type stateResponse struct {
	Revision uint64              `json:"revision"`
	Pomodoro pomodoro.Snapshot   `json:"pomodoro"`
	Codex    codexusage.Snapshot `json:"codex"`
	Todo     todo.Snapshot       `json:"todo"`
}

// backendState 串行生成组合快照，保证快照内容与单调 revision 表达同一时序。
type backendState struct {
	mu            sync.Mutex
	timer         *pomodoro.Timer
	todos         *todo.List
	usageSnapshot func() codexusage.Snapshot
	revision      uint64
}

// newBackendState 创建 Go 产品状态的唯一组合入口。
func newBackendState(timer *pomodoro.Timer, todos *todo.List, usageSnapshot func() codexusage.Snapshot) *backendState {
	return &backendState{timer: timer, todos: todos, usageSnapshot: usageSnapshot}
}

// snapshot 返回一份比之前所有组合快照都更新的状态。
func (state *backendState) snapshot() stateResponse {
	state.mu.Lock()
	defer state.mu.Unlock()
	return state.response(state.timer.Snapshot())
}

// apply 在组合状态锁内执行已校验意图，避免变更和快照序号交叉。
func (state *backendState) apply(intent productIntent) (stateResponse, error) {
	state.mu.Lock()
	defer state.mu.Unlock()

	snapshot := state.timer.Snapshot()
	switch intent.kind {
	case intentStartFocus:
		snapshot = state.timer.StartFocus(intent.durationSeconds)
	case intentPause:
		snapshot = state.timer.Pause()
	case intentResume:
		snapshot = state.timer.Resume()
	case intentReset:
		snapshot = state.timer.Reset()
	case intentStartBreak:
		snapshot = state.timer.StartBreak()
	case intentSkipBreak:
		snapshot = state.timer.SkipBreak()
	case intentTodoCreate:
		if _, err := state.todos.Create(intent.title); err != nil {
			return state.response(snapshot), err
		}
	case intentTodoRename:
		if _, err := state.todos.Rename(intent.id, intent.title); err != nil {
			return state.response(snapshot), err
		}
	case intentTodoSetCompletion:
		if _, err := state.todos.SetCompletion(intent.id, intent.completed); err != nil {
			return state.response(snapshot), err
		}
	case intentTodoDelete:
		if _, err := state.todos.Delete(intent.id); err != nil {
			return state.response(snapshot), err
		}
	}
	return state.response(snapshot), nil
}

// response 仅在持有组合状态锁时调用，为当前事实分配下一个 revision。
func (state *backendState) response(pomodoroSnapshot pomodoro.Snapshot) stateResponse {
	state.revision++
	return stateResponse{
		Revision: state.revision,
		Pomodoro: pomodoroSnapshot,
		Codex:    state.usageSnapshot(),
		Todo:     state.todos.Snapshot(),
	}
}

type intentRequest struct {
	Type            string  `json:"type"`
	DurationSeconds *int64  `json:"durationSeconds,omitempty"`
	ID              *string `json:"id,omitempty"`
	Title           *string `json:"title,omitempty"`
	Completed       *bool   `json:"completed,omitempty"`
}

// productIntentKind 枚举 Go 组合状态可执行的产品动作。
type productIntentKind uint8

const (
	intentStartFocus productIntentKind = iota
	intentPause
	intentResume
	intentReset
	intentStartBreak
	intentSkipBreak
	intentTodoCreate
	intentTodoRename
	intentTodoSetCompletion
	intentTodoDelete
)

// productIntent 表示 HTTP adapter 已校验的产品意图，不允许非法参数组合进入领域状态。
type productIntent struct {
	kind            productIntentKind
	durationSeconds int64
	id              string
	title           string
	completed       bool
}

// decodeProductIntent 严格解码 wire request，并把字符串协议收敛在 HTTP 接缝。
func decodeProductIntent(body io.Reader) (productIntent, error) {
	var request intentRequest
	decoder := json.NewDecoder(body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		return productIntent{}, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		if err == nil {
			return productIntent{}, errors.New("intent request must contain one JSON object")
		}
		return productIntent{}, err
	}

	switch request.Type {
	case "pomodoro.start", "pomodoro.startFocus":
		if request.DurationSeconds == nil || *request.DurationSeconds <= 0 || request.ID != nil || request.Title != nil || request.Completed != nil {
			return productIntent{}, errors.New("startFocus requires only a positive durationSeconds")
		}
		return productIntent{kind: intentStartFocus, durationSeconds: *request.DurationSeconds}, nil
	case "pomodoro.pause":
		return parameterFreeIntent(intentPause, request)
	case "pomodoro.resume":
		return parameterFreeIntent(intentResume, request)
	case "pomodoro.reset":
		return parameterFreeIntent(intentReset, request)
	case "pomodoro.startBreak":
		return parameterFreeIntent(intentStartBreak, request)
	case "pomodoro.skipBreak":
		return parameterFreeIntent(intentSkipBreak, request)
	case "todo.create":
		if request.Title == nil || request.DurationSeconds != nil || request.ID != nil || request.Completed != nil {
			return productIntent{}, errors.New("todo.create requires only title")
		}
		return productIntent{kind: intentTodoCreate, title: *request.Title}, nil
	case "todo.rename":
		if request.ID == nil || request.Title == nil || request.DurationSeconds != nil || request.Completed != nil {
			return productIntent{}, errors.New("todo.rename requires only id and title")
		}
		return productIntent{kind: intentTodoRename, id: *request.ID, title: *request.Title}, nil
	case "todo.setCompletion":
		if request.ID == nil || request.Completed == nil || request.DurationSeconds != nil || request.Title != nil {
			return productIntent{}, errors.New("todo.setCompletion requires only id and completed")
		}
		return productIntent{kind: intentTodoSetCompletion, id: *request.ID, completed: *request.Completed}, nil
	case "todo.delete":
		if request.ID == nil || request.DurationSeconds != nil || request.Title != nil || request.Completed != nil {
			return productIntent{}, errors.New("todo.delete requires only id")
		}
		return productIntent{kind: intentTodoDelete, id: *request.ID}, nil
	default:
		return productIntent{}, errors.New("unknown intent")
	}
}

// parameterFreeIntent 拒绝无参数动作夹带其他字段，使每种意图只有一种合法形状。
func parameterFreeIntent(kind productIntentKind, request intentRequest) (productIntent, error) {
	if request.DurationSeconds != nil || request.ID != nil || request.Title != nil || request.Completed != nil {
		return productIntent{}, errors.New("intent does not accept parameters")
	}
	return productIntent{kind: kind}, nil
}

func main() {
	timer := pomodoro.NewTimer(time.Now)
	usageMonitor := codexusage.NewMonitor(codexusage.NewClient(codexusage.ResolveExecutable()))
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	usageMonitor.Start(ctx, 30*time.Second, 40*time.Second)
	todos := newProductionTodoList()
	mux := newHandlerWithTodo(timer, todos, usageMonitor.Snapshot)

	port := os.Getenv("JUNIMO_BACKEND_PORT")
	if port == "" {
		port = "44832"
	}
	address := "127.0.0.1:" + port
	log.Printf("junimo backend listening on http://%s", address)
	if err := http.ListenAndServe(address, mux); err != nil {
		log.Fatal(err)
	}
}

func newHandler(timer *pomodoro.Timer, usageProviders ...func() codexusage.Snapshot) http.Handler {
	return newHandlerWithTodo(timer, todo.NewList(&ephemeralTodoStore{}, todo.NewID), usageProviders...)
}

// newHandlerWithTodo 组合注入的产品领域，供生产文件 Store 和测试隔离 Store 共用同一 HTTP 链路。
func newHandlerWithTodo(timer *pomodoro.Timer, todos *todo.List, usageProviders ...func() codexusage.Snapshot) http.Handler {
	usageSnapshot := func() codexusage.Snapshot {
		return codexusage.Snapshot{Status: codexusage.StatusLoading}
	}
	if len(usageProviders) > 0 && usageProviders[0] != nil {
		usageSnapshot = usageProviders[0]
	}
	backend := newBackendState(timer, todos, usageSnapshot)

	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, healthResponse{Status: "ok", ProtocolVersion: backendProtocolVersion})
	})
	mux.HandleFunc("GET /state", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, backend.snapshot())
	})
	mux.HandleFunc("POST /intent", func(writer http.ResponseWriter, request *http.Request) {
		intent, err := decodeProductIntent(request.Body)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusBadRequest)
			return
		}
		response, err := backend.apply(intent)
		if err != nil {
			status := http.StatusInternalServerError
			if errors.Is(err, todo.ErrInvalidTitle) || errors.Is(err, todo.ErrNotFound) {
				status = http.StatusBadRequest
			}
			http.Error(writer, err.Error(), status)
			return
		}
		writeJSON(writer, response)
	})

	return mux
}

// ephemeralTodoStore 为不关心文件持久化的 handler 测试提供进程内 Store。
type ephemeralTodoStore struct {
	items []todo.Item
}

// Load 返回进程内最近保存的 Todo 集合。
func (store *ephemeralTodoStore) Load() ([]todo.Item, error) {
	return append([]todo.Item(nil), store.items...), nil
}

// Save 替换进程内 Todo 集合。
func (store *ephemeralTodoStore) Save(items []todo.Item) error {
	store.items = append([]todo.Item(nil), items...)
	return nil
}

// unavailableTodoStore 在默认路径不可解析时只关闭 Todo，不阻断其他产品领域。
type unavailableTodoStore struct {
	err error
}

// Load 暴露初始化失败，使 Todo List 进入 unavailable。
func (store unavailableTodoStore) Load() ([]todo.Item, error) {
	return nil, store.err
}

// Save 保持同一初始化错误。
func (store unavailableTodoStore) Save([]todo.Item) error {
	return store.err
}

// newProductionTodoList 从用户 Application Support 恢复 Todo，路径失败时只降级该领域。
func newProductionTodoList() *todo.List {
	if override := os.Getenv("JUNIMO_TODO_STORE_PATH"); override != "" {
		return todo.NewList(todo.NewFileStore(override), todo.NewID)
	}
	path, err := todo.DefaultFilePath()
	if err != nil {
		log.Printf("todo storage unavailable: %v", err)
		return todo.NewList(unavailableTodoStore{err: err}, todo.NewID)
	}
	return todo.NewList(todo.NewFileStore(path), todo.NewID)
}

func writeJSON(writer http.ResponseWriter, value any) {
	writer.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(writer).Encode(value); err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
	}
}
