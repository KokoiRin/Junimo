// Package todo owns Junimo's ordered local Todo list and its persistence rules.
package todo

import (
	"errors"
	"strings"
	"sync"
	"unicode/utf8"
)

// Status 表示一条 Todo 已生效的完成状态。
type Status string

const (
	StatusOpen      Status = "open"
	StatusCompleted Status = "completed"
)

// Availability 表示 Todo 持久化事实源当前是否可用。
type Availability string

const (
	AvailabilityAvailable   Availability = "available"
	AvailabilityUnavailable Availability = "unavailable"
)

var (
	ErrUnavailable  = errors.New("todo storage unavailable")
	ErrInvalidTitle = errors.New("todo title must contain 1 to 120 characters")
	ErrNotFound     = errors.New("todo not found")
)

// Item 表示 Todo 列表中具有稳定身份的一条正式任务。
type Item struct {
	ID     string `json:"id"`
	Title  string `json:"title"`
	Status Status `json:"status"`
}

// Snapshot 表示调用方可观察的完整 Todo 列表与可用状态。
type Snapshot struct {
	Status Availability `json:"status"`
	Items  []Item       `json:"items"`
}

// Store 隔离 Todo 领域与具体文件系统持久化方式。
type Store interface {
	Load() ([]Item, error)
	Save([]Item) error
}

// List 是 Todo 正式状态的唯一内存所有者，候选状态保存成功后才会生效。
type List struct {
	mu        sync.Mutex
	store     Store
	newID     func() string
	items     []Item
	available bool
}

// NewList 从 Store 恢复 Todo；读取失败时只将 Todo 标为不可用，不向调用方泄露半初始化状态。
func NewList(store Store, newID func() string) *List {
	items, err := store.Load()
	if newID == nil {
		newID = func() string { return "" }
	}
	return &List{
		store:     store,
		newID:     newID,
		items:     cloneItems(items),
		available: err == nil,
	}
}

// Snapshot 返回当前正式 Todo 状态的防御性副本。
func (list *List) Snapshot() Snapshot {
	list.mu.Lock()
	defer list.mu.Unlock()
	return list.snapshotLocked()
}

// Create 校验标题并把新任务置于列表首位，保存成功后才发布新状态。
func (list *List) Create(title string) (Snapshot, error) {
	list.mu.Lock()
	defer list.mu.Unlock()
	if !list.available {
		return list.snapshotLocked(), ErrUnavailable
	}
	normalized, err := normalizeTitle(title)
	if err != nil {
		return list.snapshotLocked(), err
	}
	candidate := append([]Item{{ID: list.newID(), Title: normalized, Status: StatusOpen}}, list.items...)
	if err := list.commitLocked(candidate); err != nil {
		return list.snapshotLocked(), err
	}
	return list.snapshotLocked(), nil
}

// Rename 只修改已存在任务的标题，并在保存失败时保留原任务集合。
func (list *List) Rename(id string, title string) (Snapshot, error) {
	list.mu.Lock()
	defer list.mu.Unlock()
	if !list.available {
		return list.snapshotLocked(), ErrUnavailable
	}
	normalized, err := normalizeTitle(title)
	if err != nil {
		return list.snapshotLocked(), err
	}
	candidate := cloneItems(list.items)
	for index := range candidate {
		if candidate[index].ID == id {
			candidate[index].Title = normalized
			if err := list.commitLocked(candidate); err != nil {
				return list.snapshotLocked(), err
			}
			return list.snapshotLocked(), nil
		}
	}
	return list.snapshotLocked(), ErrNotFound
}

// SetCompletion 把任务设置为明确目标状态，重复请求保持幂等而不会反向切换。
func (list *List) SetCompletion(id string, completed bool) (Snapshot, error) {
	list.mu.Lock()
	defer list.mu.Unlock()
	if !list.available {
		return list.snapshotLocked(), ErrUnavailable
	}
	target := StatusOpen
	if completed {
		target = StatusCompleted
	}
	candidate := cloneItems(list.items)
	for index := range candidate {
		if candidate[index].ID != id {
			continue
		}
		if candidate[index].Status == target {
			return list.snapshotLocked(), nil
		}
		candidate[index].Status = target
		if err := list.commitLocked(candidate); err != nil {
			return list.snapshotLocked(), err
		}
		return list.snapshotLocked(), nil
	}
	return list.snapshotLocked(), ErrNotFound
}

// Delete 删除已存在任务；目标已不存在时视为幂等成功。
func (list *List) Delete(id string) (Snapshot, error) {
	list.mu.Lock()
	defer list.mu.Unlock()
	if !list.available {
		return list.snapshotLocked(), ErrUnavailable
	}
	candidate := make([]Item, 0, len(list.items))
	found := false
	for _, item := range list.items {
		if item.ID == id {
			found = true
			continue
		}
		candidate = append(candidate, item)
	}
	if !found {
		return list.snapshotLocked(), nil
	}
	if err := list.commitLocked(candidate); err != nil {
		return list.snapshotLocked(), err
	}
	return list.snapshotLocked(), nil
}

// commitLocked 仅在持有列表锁时保存并发布一份完整候选集合。
func (list *List) commitLocked(candidate []Item) error {
	if err := list.store.Save(candidate); err != nil {
		return err
	}
	list.items = cloneItems(candidate)
	return nil
}

// snapshotLocked 仅在持有列表锁时构造当前快照。
func (list *List) snapshotLocked() Snapshot {
	status := AvailabilityUnavailable
	if list.available {
		status = AvailabilityAvailable
	}
	return Snapshot{Status: status, Items: cloneItems(list.items)}
}

// normalizeTitle 把用户输入收敛为领域允许的单一标题形态。
func normalizeTitle(title string) (string, error) {
	normalized := strings.TrimSpace(title)
	if normalized == "" || utf8.RuneCountInString(normalized) > 120 {
		return "", ErrInvalidTitle
	}
	return normalized, nil
}

// cloneItems 防止 Store 或调用方通过共享 slice 绕过 List 的状态所有权。
func cloneItems(items []Item) []Item {
	if len(items) == 0 {
		return []Item{}
	}
	return append([]Item(nil), items...)
}
