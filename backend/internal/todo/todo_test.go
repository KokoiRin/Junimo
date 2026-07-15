package todo

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// memoryStore 模拟 Todo 的持久化边界，让领域测试观察已生效的保存结果。
type memoryStore struct {
	loaded  []Item
	saved   []Item
	loadErr error
	saveErr error
}

// Load 返回测试预置的持久化任务集合。
func (store *memoryStore) Load() ([]Item, error) {
	return append([]Item(nil), store.loaded...), store.loadErr
}

// Save 记录领域决定持久化的完整任务集合。
func (store *memoryStore) Save(items []Item) error {
	if store.saveErr != nil {
		return store.saveErr
	}
	store.saved = append([]Item(nil), items...)
	return nil
}

// 空白标题和超过 120 个字符的标题分别用于创建或重命名时，都应返回标题错误且保持原列表不变。
func TestListRejectsInvalidTitlesWithoutChangingState(t *testing.T) {
	store := &memoryStore{loaded: []Item{{ID: "todo-1", Title: "原任务", Status: StatusOpen}}}
	list := NewList(store, func() string { return "todo-2" })

	for _, operation := range []func() error{
		func() error { _, err := list.Create("   "); return err },
		func() error { _, err := list.Rename("todo-1", strings.Repeat("界", 121)); return err },
	} {
		if err := operation(); !errors.Is(err, ErrInvalidTitle) {
			t.Fatalf("invalid title error = %v, want ErrInvalidTitle", err)
		}
	}
	want := []Item{{ID: "todo-1", Title: "原任务", Status: StatusOpen}}
	if got := list.Snapshot().Items; !reflect.DeepEqual(got, want) {
		t.Fatalf("items after invalid titles = %#v, want %#v", got, want)
	}
}

// 空列表收到带首尾空格的有效标题后，应创建稳定 ID 的未完成任务、把规范化标题置于列表首位并保存同一结果。
func TestListCreatesOpenTodoAtFront(t *testing.T) {
	store := &memoryStore{}
	list := NewList(store, func() string { return "todo-1" })

	snapshot, err := list.Create("  完成 Todo 设计  ")
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	want := []Item{{ID: "todo-1", Title: "完成 Todo 设计", Status: StatusOpen}}
	if !reflect.DeepEqual(snapshot.Items, want) {
		t.Fatalf("snapshot items = %#v, want %#v", snapshot.Items, want)
	}
	if !reflect.DeepEqual(store.saved, want) {
		t.Fatalf("saved items = %#v, want %#v", store.saved, want)
	}
}

// 已有两条任务时重命名第二条，应只替换其规范化标题，并保留两个任务的 ID、状态和相对顺序。
func TestListRenamesTodoWithoutChangingIdentityOrOrder(t *testing.T) {
	store := &memoryStore{loaded: []Item{
		{ID: "todo-2", Title: "第二条", Status: StatusCompleted},
		{ID: "todo-1", Title: "第一条", Status: StatusOpen},
	}}
	list := NewList(store, func() string { return "unused" })

	snapshot, err := list.Rename("todo-1", "  更新后的第一条  ")
	if err != nil {
		t.Fatalf("Rename() error = %v", err)
	}
	want := []Item{
		{ID: "todo-2", Title: "第二条", Status: StatusCompleted},
		{ID: "todo-1", Title: "更新后的第一条", Status: StatusOpen},
	}
	if !reflect.DeepEqual(snapshot.Items, want) {
		t.Fatalf("snapshot items = %#v, want %#v", snapshot.Items, want)
	}
}

// 未完成任务连续两次设置为已完成时，两次结果都应保持 completed，显式目标状态不能像 toggle 一样翻回未完成。
func TestListSetsCompletionIdempotently(t *testing.T) {
	store := &memoryStore{loaded: []Item{{ID: "todo-1", Title: "任务", Status: StatusOpen}}}
	list := NewList(store, func() string { return "unused" })

	first, err := list.SetCompletion("todo-1", true)
	if err != nil {
		t.Fatalf("first SetCompletion() error = %v", err)
	}
	second, err := list.SetCompletion("todo-1", true)
	if err != nil {
		t.Fatalf("second SetCompletion() error = %v", err)
	}
	if first.Items[0].Status != StatusCompleted || second.Items[0].Status != StatusCompleted {
		t.Fatalf("completion statuses = %q/%q, want completed/completed", first.Items[0].Status, second.Items[0].Status)
	}
}

// 删除存在任务后列表和持久化结果都应只保留其他任务，再次删除同一 ID 应幂等地保持当前列表。
func TestListDeletesTodoIdempotently(t *testing.T) {
	store := &memoryStore{loaded: []Item{
		{ID: "todo-2", Title: "保留", Status: StatusOpen},
		{ID: "todo-1", Title: "删除", Status: StatusCompleted},
	}}
	list := NewList(store, func() string { return "unused" })

	first, err := list.Delete("todo-1")
	if err != nil {
		t.Fatalf("first Delete() error = %v", err)
	}
	second, err := list.Delete("todo-1")
	if err != nil {
		t.Fatalf("second Delete() error = %v", err)
	}
	want := []Item{{ID: "todo-2", Title: "保留", Status: StatusOpen}}
	if !reflect.DeepEqual(first.Items, want) || !reflect.DeepEqual(second.Items, want) {
		t.Fatalf("delete snapshots = %#v/%#v, want %#v", first.Items, second.Items, want)
	}
}

// 保存候选状态失败时，创建操作应返回原始错误，内存快照仍保持此前成功加载的任务集合。
func TestListKeepsPreviousStateWhenSaveFails(t *testing.T) {
	saveErr := errors.New("disk full")
	store := &memoryStore{
		loaded:  []Item{{ID: "todo-1", Title: "已保存", Status: StatusOpen}},
		saveErr: saveErr,
	}
	list := NewList(store, func() string { return "todo-2" })

	if _, err := list.Create("不能保存"); !errors.Is(err, saveErr) {
		t.Fatalf("Create() error = %v, want %v", err, saveErr)
	}
	want := []Item{{ID: "todo-1", Title: "已保存", Status: StatusOpen}}
	if got := list.Snapshot().Items; !reflect.DeepEqual(got, want) {
		t.Fatalf("items after failed save = %#v, want %#v", got, want)
	}
}

// 临时目录中没有 Todo 文件时，文件 Store 应把它解释为空列表，首次保存后新 List 应恢复相同任务内容和顺序。
func TestFileStoreTreatsMissingFileAsEmptyAndRestoresSavedItems(t *testing.T) {
	path := filepath.Join(t.TempDir(), "Junimo", "todos.json")
	store := NewFileStore(path)
	list := NewList(store, func() string { return "todo-1" })
	if snapshot := list.Snapshot(); snapshot.Status != AvailabilityAvailable || len(snapshot.Items) != 0 {
		t.Fatalf("initial snapshot = %#v, want available empty list", snapshot)
	}
	if _, err := list.Create("持久化任务"); err != nil {
		t.Fatalf("Create() error = %v", err)
	}

	reloaded := NewList(NewFileStore(path), func() string { return "unused" }).Snapshot()
	want := []Item{{ID: "todo-1", Title: "持久化任务", Status: StatusOpen}}
	if reloaded.Status != AvailabilityAvailable || !reflect.DeepEqual(reloaded.Items, want) {
		t.Fatalf("reloaded snapshot = %#v, want %#v", reloaded, want)
	}
}

// Todo 文件包含截断 JSON 时，新列表应标记为 unavailable 且不暴露半解析任务，供其他产品模块继续运行。
func TestFileStoreMarksMalformedDataUnavailable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "todos.json")
	if err := os.WriteFile(path, []byte(`{"version":1,"items":[`), 0o600); err != nil {
		t.Fatalf("WriteFile() error = %v", err)
	}

	snapshot := NewList(NewFileStore(path), func() string { return "unused" }).Snapshot()
	if snapshot.Status != AvailabilityUnavailable || len(snapshot.Items) != 0 {
		t.Fatalf("malformed snapshot = %#v, want unavailable empty list", snapshot)
	}
}
