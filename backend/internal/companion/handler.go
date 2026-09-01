// Package companion 组合 Junimo 后端公开的产品状态并运行本地 HTTP 接口。
package companion

import (
	"encoding/json"
	"net/http"
	"sync"

	"junimo/backend/internal/codexactivity"
	"junimo/backend/internal/codexusage"
)

const protocolVersion = 5

type healthResponse struct {
	Status          string `json:"status"`
	ProtocolVersion int    `json:"protocolVersion"`
}

// state 只组合轻量产品仍需公开的两类 Codex 事实。
type state struct {
	mu               sync.Mutex
	usageSnapshot    func() codexusage.Snapshot
	activitySnapshot func() codexactivity.Snapshot
	revision         uint64
}

type stateResponse struct {
	Revision uint64                 `json:"revision"`
	Codex    codexusage.Snapshot    `json:"codex"`
	Activity codexactivity.Snapshot `json:"activity"`
}

// snapshot 为一次组合读取分配严格递增的时序号。
func (state *state) snapshot() stateResponse {
	state.mu.Lock()
	defer state.mu.Unlock()
	state.revision++
	return stateResponse{
		Revision: state.revision,
		Codex:    state.usageSnapshot(),
		Activity: state.activitySnapshot(),
	}
}

// newHandler 创建协议 v5 的只读 HTTP 接口。
func newHandler(
	usageProvider func() codexusage.Snapshot,
	activityProvider func() codexactivity.Snapshot,
) http.Handler {
	if usageProvider == nil {
		usageProvider = func() codexusage.Snapshot {
			return codexusage.Snapshot{Status: codexusage.StatusLoading}
		}
	}
	if activityProvider == nil {
		activityProvider = func() codexactivity.Snapshot {
			return codexactivity.Snapshot{Status: codexactivity.StatusLoading}
		}
	}
	current := &state{usageSnapshot: usageProvider, activitySnapshot: activityProvider}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, healthResponse{Status: "ok", ProtocolVersion: protocolVersion})
	})
	mux.HandleFunc("GET /state", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, current.snapshot())
	})
	return mux
}

func writeJSON(writer http.ResponseWriter, value any) {
	writer.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(writer).Encode(value); err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
	}
}
