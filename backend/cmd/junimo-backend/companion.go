package main

import (
	"net/http"
	"sync"

	"junimo/backend/internal/codexactivity"
	"junimo/backend/internal/codexusage"
)

const companionProtocolVersion = 5

// companionState 只组合轻量产品仍需公开的两类 Codex 事实。
type companionState struct {
	mu               sync.Mutex
	usageSnapshot    func() codexusage.Snapshot
	activitySnapshot func() codexactivity.Snapshot
	revision         uint64
}

type companionStateResponse struct {
	Revision uint64                 `json:"revision"`
	Codex    codexusage.Snapshot    `json:"codex"`
	Activity codexactivity.Snapshot `json:"activity"`
}

// snapshot 为一次组合读取分配严格递增的时序号。
func (state *companionState) snapshot() companionStateResponse {
	state.mu.Lock()
	defer state.mu.Unlock()
	state.revision++
	return companionStateResponse{
		Revision: state.revision,
		Codex:    state.usageSnapshot(),
		Activity: state.activitySnapshot(),
	}
}

// newCompanionHandler 创建协议 v5 的只读 HTTP 边界。
func newCompanionHandler(
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
	state := &companionState{usageSnapshot: usageProvider, activitySnapshot: activityProvider}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, healthResponse{Status: "ok", ProtocolVersion: companionProtocolVersion})
	})
	mux.HandleFunc("GET /state", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, state.snapshot())
	})
	return mux
}
