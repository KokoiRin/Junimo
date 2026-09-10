package companion

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
)

type appShortcut struct {
	BundleID string `json:"bundleId"`
	Name     string `json:"name"`
}
type appShortcuts struct {
	Items    []appShortcut `json:"items"`
	Revision uint64        `json:"revision"`
}

var errShortcutConflict = errors.New("收藏已在其他地方更新，请按最新列表重新操作")

type shortcutStore struct {
	mu        sync.Mutex
	directory string
	current   *appShortcuts
}

var bundleIDPattern = regexp.MustCompile(`^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$`)

func newShortcutStore() *shortcutStore {
	directory := os.Getenv("JUNIMO_DATA_DIR")
	if directory == "" {
		home, _ := os.UserHomeDir()
		directory = filepath.Join(home, "Library", "Application Support", "Junimo")
	}
	return &shortcutStore{directory: directory}
}

func validateShortcuts(value appShortcuts) error {
	if value.Items == nil {
		return errors.New("应用列表必须是数组")
	}
	if len(value.Items) > 12 {
		return errors.New("最多收藏 12 个应用")
	}
	seen := map[string]bool{}
	for _, item := range value.Items {
		if !bundleIDPattern.MatchString(item.BundleID) || len(item.BundleID) > 255 || item.Name == "" || len(item.Name) > 512 {
			return errors.New("应用标识或名称无效")
		}
		if seen[item.BundleID] {
			return errors.New("该应用已在收藏中")
		}
		seen[item.BundleID] = true
	}
	return nil
}

func (s *shortcutStore) load() (appShortcuts, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.loadLocked()
}

func (s *shortcutStore) loadLocked() (appShortcuts, error) {
	if s.current != nil {
		return *s.current, nil
	}
	data, err := os.ReadFile(filepath.Join(s.directory, "app-shortcuts.json"))
	if err == nil {
		var value appShortcuts
		if err = json.Unmarshal(data, &value); err != nil {
			return appShortcuts{}, err
		}
		if err = validateShortcuts(value); err != nil {
			return appShortcuts{}, err
		}
		// 已有的 v6 收藏文件没有 revision，首次读取时赋予稳定初始版本。
		if value.Revision == 0 {
			value.Revision = 1
		}
		s.current = &value
		return value, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return appShortcuts{}, err
	}
	// 仅在尚未保存收藏列表时导入旧入口，空收藏也属于用户明确保存的状态。
	value := appShortcuts{Items: []appShortcut{}}
	legacy, err := os.ReadFile(filepath.Join(s.directory, "quick-launch.json"))
	if errors.Is(err, os.ErrNotExist) {
		value.Items = append(value.Items, appShortcut{"com.openai.codex", "Codex"})
	} else if err != nil {
		return value, err
	} else {
		var old struct {
			Items []struct{ Type, Target, Title string } `json:"items"`
		}
		if err := json.Unmarshal(legacy, &old); err != nil {
			return value, fmt.Errorf("无法导入旧快捷入口：%w", err)
		}
		seen := map[string]bool{}
		for _, item := range old.Items {
			target := strings.TrimSpace(item.Target)
			title := strings.TrimSpace(item.Title)
			if item.Type == "application" && !seen[target] {
				value.Items = append(value.Items, appShortcut{target, title})
				seen[target] = true
			}
		}
	}
	if err := s.persist(value); err != nil {
		return value, err
	}
	return *s.current, nil
}

// 在同一把锁内比较版本并保存，拒绝过期界面覆盖其他客户端刚写入的收藏。
func (s *shortcutStore) compareAndSave(value appShortcuts) (appShortcuts, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	current, err := s.loadLocked()
	if err != nil {
		return appShortcuts{}, err
	}
	if value.Revision != current.Revision {
		return current, errShortcutConflict
	}
	if err := s.persist(value); err != nil {
		return current, err
	}
	return *s.current, nil
}

func (s *shortcutStore) save(value appShortcuts) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.persist(value)
}
func (s *shortcutStore) persist(value appShortcuts) error {
	if err := validateShortcuts(value); err != nil {
		return err
	}
	value.Revision = 1
	if s.current != nil {
		value.Revision = s.current.Revision + 1
	}
	if err := os.MkdirAll(s.directory, 0700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	file, err := os.CreateTemp(s.directory, ".app-shortcuts-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err = file.Write(data); err != nil {
		file.Close()
		return err
	}
	if err = file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	if err = os.Rename(file.Name(), filepath.Join(s.directory, "app-shortcuts.json")); err != nil {
		return err
	}
	s.current = &value
	return nil
}

func registerShortcuts(mux *http.ServeMux, store *shortcutStore, instanceID string) {
	mux.HandleFunc("GET /app-shortcuts", func(w http.ResponseWriter, r *http.Request) {
		value, err := store.load()
		if err != nil {
			http.Error(w, "读取常用应用失败："+err.Error(), 500)
			return
		}
		writeJSON(w, value)
	})
	mux.HandleFunc("PUT /app-shortcuts", func(w http.ResponseWriter, r *http.Request) {
		// 只接受本机外壳的 JSON 写入；网页来源和其他启动实例不能修改收藏。
		if r.Header.Get("Origin") != "" || (instanceID != "" && r.Header.Get("X-Junimo-Instance-ID") != instanceID) {
			http.Error(w, "实例身份不匹配", 403)
			return
		}
		if r.Header.Get("Content-Type") != "application/json" {
			http.Error(w, "需要 JSON 内容", 415)
			return
		}
		decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16384))
		decoder.DisallowUnknownFields()
		var value appShortcuts
		if err := decoder.Decode(&value); err != nil {
			http.Error(w, "收藏格式无效", 400)
			return
		}
		if err := decoder.Decode(new(any)); err != io.EOF {
			http.Error(w, "收藏格式无效", 400)
			return
		}
		if err := validateShortcuts(value); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if value.Revision == 0 {
			http.Error(w, "请先读取最新收藏并携带 revision 保存", http.StatusPreconditionRequired)
			return
		}
		saved, err := store.compareAndSave(value)
		if errors.Is(err, errShortcutConflict) {
			http.Error(w, err.Error(), http.StatusConflict)
			return
		}
		if err != nil {
			http.Error(w, "保存失败，原收藏未更改："+err.Error(), 500)
			return
		}
		writeJSON(w, saved)
	})
}
