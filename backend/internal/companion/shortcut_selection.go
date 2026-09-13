package companion

import (
	"encoding/json"
	"io"
	"net/http"
)

// 外壳只上报可见数量和前台应用；循环顺序与越界规则由后端根据已保存收藏决定。
type shortcutSelectionRequest struct {
	Revision     uint64 `json:"revision"`
	VisibleCount int    `json:"visibleCount"`
	ActiveID     string `json:"activeId"`
	Direction    int    `json:"direction"`
}

type shortcutSelectionResponse struct {
	Item *appShortcut `json:"item"`
}

func adjacentShortcut(items []appShortcut, activeID string, direction int) *appShortcut {
	if len(items) == 0 {
		return nil
	}
	for index, item := range items {
		if item.BundleID == activeID {
			return &items[(index+direction+len(items))%len(items)]
		}
	}
	if direction < 0 {
		return &items[len(items)-1]
	}
	return &items[0]
}

func registerShortcutSelection(mux *http.ServeMux, store *shortcutStore, instanceID string) {
	mux.HandleFunc("POST /app-shortcuts/selection", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Origin") != "" || (instanceID != "" && r.Header.Get("X-Junimo-Instance-ID") != instanceID) {
			http.Error(w, "实例身份不匹配", http.StatusForbidden)
			return
		}
		if r.Header.Get("Content-Type") != "application/json" {
			http.Error(w, "需要 JSON 内容", http.StatusUnsupportedMediaType)
			return
		}
		decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
		decoder.DisallowUnknownFields()
		var request shortcutSelectionRequest
		if err := decoder.Decode(&request); err != nil {
			http.Error(w, "切换参数无效", http.StatusBadRequest)
			return
		}
		if err := decoder.Decode(new(any)); err != io.EOF || (request.Direction != -1 && request.Direction != 1) {
			http.Error(w, "切换参数无效", http.StatusBadRequest)
			return
		}
		value, err := store.load()
		if err != nil {
			http.Error(w, "读取常用应用失败", http.StatusInternalServerError)
			return
		}
		if request.Revision != value.Revision {
			http.Error(w, errShortcutConflict.Error(), http.StatusConflict)
			return
		}
		if request.VisibleCount < 0 || request.VisibleCount > len(value.Items) {
			http.Error(w, "可见数量无效", http.StatusBadRequest)
			return
		}
		writeJSON(w, shortcutSelectionResponse{Item: adjacentShortcut(value.Items[:request.VisibleCount], request.ActiveID, request.Direction)})
	})
}
