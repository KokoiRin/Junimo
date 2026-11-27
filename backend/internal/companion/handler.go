// Package companion 组合 Junimo 后端公开的产品状态并运行本地 HTTP 接口。
package companion

import (
	"encoding/json"
	"net/http"
	"os"
	"sync"

	"junimo/backend/internal/antigravity"
	"junimo/backend/internal/codexactivity"
	"junimo/backend/internal/quota"
)

const protocolVersion = 7

type healthResponse struct {
	Status          string `json:"status"`
	ProtocolVersion int    `json:"protocolVersion"`
	InstanceID      string `json:"instanceId,omitempty"`
}

// state 组合独立的 Codex、Grok 用量与 Codex 完成事实。
type state struct {
	mu                  sync.Mutex
	usageSnapshot       func() quota.Snapshot
	grokSnapshot        func() quota.Snapshot
	activitySnapshot    func() codexactivity.Snapshot
	antigravitySnapshot func() antigravity.Snapshot
	revision            uint64
}

type stateResponse struct {
	Antigravity antigravity.Snapshot   `json:"antigravity"`
	Revision    uint64                 `json:"revision"`
	Codex       quota.Snapshot         `json:"codex"`
	Grok        quota.Snapshot         `json:"grok"`
	Activity    codexactivity.Snapshot `json:"activity"`
}

// snapshot 为一次组合读取分配严格递增的时序号。
func (state *state) snapshot() stateResponse {
	state.mu.Lock()
	defer state.mu.Unlock()
	state.revision++
	return stateResponse{
		Revision:    state.revision,
		Antigravity: state.antigravitySnapshot(),
		Codex:       state.usageSnapshot(),
		Grok:        state.grokSnapshot(),
		Activity:    state.activitySnapshot(),
	}
}

// newHandler 提供协议 v7 的状态快照、收藏管理和应用切换目标接口。
func newHandler(
	usageProvider func() quota.Snapshot,
	activityProvider func() codexactivity.Snapshot,
	stores ...*shortcutStore,
) http.Handler {
	return newSurfaceHandler(usageProvider, activityProvider, nil, nil, stores...)
}

func newSurfaceHandler(usageProvider func() quota.Snapshot, activityProvider func() codexactivity.Snapshot, grokProvider func() quota.Snapshot, gravityProvider func() antigravity.Snapshot, stores ...*shortcutStore) http.Handler {
	if usageProvider == nil {
		usageProvider = func() quota.Snapshot {
			return quota.Snapshot{Status: quota.StatusLoading}
		}
	}
	if activityProvider == nil {
		activityProvider = func() codexactivity.Snapshot {
			return codexactivity.Snapshot{Status: codexactivity.StatusLoading}
		}
	}
	if grokProvider == nil {
		grokProvider = func() quota.Snapshot { return quota.Snapshot{Status: quota.StatusLoading} }
	}
	if gravityProvider == nil {
		gravityProvider = func() antigravity.Snapshot { return antigravity.Snapshot{} }
	}
	current := &state{antigravitySnapshot: gravityProvider, usageSnapshot: usageProvider, activitySnapshot: activityProvider, grokSnapshot: grokProvider}
	mux := http.NewServeMux()
	instanceID := os.Getenv("JUNIMO_INSTANCE_ID")
	store := newShortcutStore()
	if len(stores) > 0 {
		store = stores[0]
	}
	registerShortcuts(mux, store, instanceID)
	registerShortcutSelection(mux, store, instanceID)
	mux.HandleFunc("GET /health", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, healthResponse{Status: "ok", ProtocolVersion: protocolVersion, InstanceID: instanceID})
	})
	mux.HandleFunc("GET /state", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, current.snapshot())
	})
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if instanceID != "" {
			writer.Header().Set("X-Junimo-Instance-ID", instanceID)
		}
		mux.ServeHTTP(writer, request)
	})
}

func writeJSON(writer http.ResponseWriter, value any) {
	writer.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(writer).Encode(value); err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
	}
}
