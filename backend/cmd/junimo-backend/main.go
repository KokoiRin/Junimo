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
)

const backendProtocolVersion = 3

type healthResponse struct {
	Status          string `json:"status"`
	ProtocolVersion int    `json:"protocolVersion"`
}

type stateResponse struct {
	Revision uint64              `json:"revision"`
	Pomodoro pomodoro.Snapshot   `json:"pomodoro"`
	Codex    codexusage.Snapshot `json:"codex"`
}

// backendState 串行生成组合快照，保证快照内容与单调 revision 表达同一时序。
type backendState struct {
	mu            sync.Mutex
	timer         *pomodoro.Timer
	usageSnapshot func() codexusage.Snapshot
	revision      uint64
}

// newBackendState 创建 Go 产品状态的唯一组合入口。
func newBackendState(timer *pomodoro.Timer, usageSnapshot func() codexusage.Snapshot) *backendState {
	return &backendState{timer: timer, usageSnapshot: usageSnapshot}
}

// snapshot 返回一份比之前所有组合快照都更新的状态。
func (state *backendState) snapshot() stateResponse {
	state.mu.Lock()
	defer state.mu.Unlock()
	return state.response(state.timer.Snapshot())
}

// apply 在组合状态锁内执行已校验意图，避免变更和快照序号交叉。
func (state *backendState) apply(intent pomodoroIntent) stateResponse {
	state.mu.Lock()
	defer state.mu.Unlock()

	var snapshot pomodoro.Snapshot
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
	}
	return state.response(snapshot)
}

// response 仅在持有组合状态锁时调用，为当前事实分配下一个 revision。
func (state *backendState) response(pomodoroSnapshot pomodoro.Snapshot) stateResponse {
	state.revision++
	return stateResponse{
		Revision: state.revision,
		Pomodoro: pomodoroSnapshot,
		Codex:    state.usageSnapshot(),
	}
}

type intentRequest struct {
	Type            string `json:"type"`
	DurationSeconds *int64 `json:"durationSeconds,omitempty"`
}

// pomodoroIntentKind 枚举 Go 组合状态可执行的番茄钟动作。
type pomodoroIntentKind uint8

const (
	intentStartFocus pomodoroIntentKind = iota
	intentPause
	intentResume
	intentReset
	intentStartBreak
	intentSkipBreak
)

// pomodoroIntent 表示 HTTP adapter 已校验的番茄钟意图，不允许非法的类型与参数组合进入产品状态。
type pomodoroIntent struct {
	kind            pomodoroIntentKind
	durationSeconds int64
}

// decodePomodoroIntent 严格解码 wire request，并把字符串协议收敛在 HTTP 接缝。
func decodePomodoroIntent(body io.Reader) (pomodoroIntent, error) {
	var request intentRequest
	decoder := json.NewDecoder(body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		return pomodoroIntent{}, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		if err == nil {
			return pomodoroIntent{}, errors.New("intent request must contain one JSON object")
		}
		return pomodoroIntent{}, err
	}

	switch request.Type {
	case "pomodoro.start", "pomodoro.startFocus":
		if request.DurationSeconds == nil || *request.DurationSeconds <= 0 {
			return pomodoroIntent{}, errors.New("startFocus requires a positive durationSeconds")
		}
		return pomodoroIntent{kind: intentStartFocus, durationSeconds: *request.DurationSeconds}, nil
	case "pomodoro.pause":
		return durationFreeIntent(intentPause, request.DurationSeconds)
	case "pomodoro.resume":
		return durationFreeIntent(intentResume, request.DurationSeconds)
	case "pomodoro.reset":
		return durationFreeIntent(intentReset, request.DurationSeconds)
	case "pomodoro.startBreak":
		return durationFreeIntent(intentStartBreak, request.DurationSeconds)
	case "pomodoro.skipBreak":
		return durationFreeIntent(intentSkipBreak, request.DurationSeconds)
	default:
		return pomodoroIntent{}, errors.New("unknown intent")
	}
}

// durationFreeIntent 拒绝无时长动作夹带 durationSeconds，使每种意图只有一种合法形状。
func durationFreeIntent(kind pomodoroIntentKind, durationSeconds *int64) (pomodoroIntent, error) {
	if durationSeconds != nil {
		return pomodoroIntent{}, errors.New("intent does not accept durationSeconds")
	}
	return pomodoroIntent{kind: kind}, nil
}

func main() {
	timer := pomodoro.NewTimer(time.Now)
	usageMonitor := codexusage.NewMonitor(codexusage.NewClient(codexusage.ResolveExecutable()))
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	usageMonitor.Start(ctx, 30*time.Second, 40*time.Second)
	mux := newHandler(timer, usageMonitor.Snapshot)

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
	usageSnapshot := func() codexusage.Snapshot {
		return codexusage.Snapshot{Status: codexusage.StatusLoading}
	}
	if len(usageProviders) > 0 && usageProviders[0] != nil {
		usageSnapshot = usageProviders[0]
	}
	backend := newBackendState(timer, usageSnapshot)

	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, healthResponse{Status: "ok", ProtocolVersion: backendProtocolVersion})
	})
	mux.HandleFunc("GET /state", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, backend.snapshot())
	})
	mux.HandleFunc("POST /intent", func(writer http.ResponseWriter, request *http.Request) {
		intent, err := decodePomodoroIntent(request.Body)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(writer, backend.apply(intent))
	})

	return mux
}

func writeJSON(writer http.ResponseWriter, value any) {
	writer.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(writer).Encode(value); err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
	}
}
