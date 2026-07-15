package todo

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

const fileFormatVersion = 1

// FileStore 把完整 Todo 集合以版本化 JSON 原子保存在用户目录中。
type FileStore struct {
	path string
}

// fileData 是 Todo 文件的稳定磁盘格式，版本字段为后续迁移保留明确接缝。
type fileData struct {
	Version int    `json:"version"`
	Items   []Item `json:"items"`
}

// NewFileStore 创建指向给定文件路径的 Todo Store。
func NewFileStore(path string) *FileStore {
	return &FileStore{path: path}
}

// DefaultFilePath 返回当前用户 Application Support 下的 Junimo Todo 文件。
func DefaultFilePath() (string, error) {
	root, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(root, "Junimo", "todos.json"), nil
}

// NewID 生成不依赖外部库的随机稳定任务标识。
func NewID() string {
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		panic(fmt.Sprintf("todo id generation failed: %v", err))
	}
	return hex.EncodeToString(bytes[:])
}

// Load 读取并校验完整 Todo 文件；文件不存在时返回可用的空列表。
func (store *FileStore) Load() ([]Item, error) {
	data, err := os.ReadFile(store.path)
	if errors.Is(err, os.ErrNotExist) {
		return []Item{}, nil
	}
	if err != nil {
		return nil, err
	}
	var file fileData
	if err := json.Unmarshal(data, &file); err != nil {
		return nil, err
	}
	if file.Version != fileFormatVersion {
		return nil, fmt.Errorf("unsupported todo file version %d", file.Version)
	}
	if err := validateItems(file.Items); err != nil {
		return nil, err
	}
	return cloneItems(file.Items), nil
}

// Save 先写同目录临时文件并同步落盘，再 rename 替换正式文件。
func (store *FileStore) Save(items []Item) error {
	if err := validateItems(items); err != nil {
		return err
	}
	directory := filepath.Dir(store.path)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(directory, ".todos-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return err
	}
	encoder := json.NewEncoder(temporary)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(fileData{Version: fileFormatVersion, Items: cloneItems(items)}); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporaryPath, store.path)
}

// validateItems 拒绝会破坏身份、标题或状态不变量的磁盘数据。
func validateItems(items []Item) error {
	seen := make(map[string]struct{}, len(items))
	for _, item := range items {
		if item.ID == "" {
			return errors.New("todo id must not be empty")
		}
		if _, exists := seen[item.ID]; exists {
			return fmt.Errorf("duplicate todo id %q", item.ID)
		}
		seen[item.ID] = struct{}{}
		if normalized, err := normalizeTitle(item.Title); err != nil || normalized != item.Title {
			return fmt.Errorf("invalid todo title for %q", item.ID)
		}
		if item.Status != StatusOpen && item.Status != StatusCompleted {
			return fmt.Errorf("invalid todo status %q", item.Status)
		}
	}
	return nil
}
