package companion

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// 初次使用时只导入旧配置中的应用并按原顺序去重，网页保留原文件且之后不再重复导入。
func TestShortcutImportOnce(t *testing.T) {
	directory := t.TempDir()
	legacy := []byte(`{"items":[{"type":"application","target":"com.test.one","title":"一"},{"type":"url","target":"https://example.com","title":"网页"},{"type":"application","target":"com.test.one","title":"重复"},{"type":"application","target":"com.test.two","title":"二"}]}`)
	path := filepath.Join(directory, "quick-launch.json")
	if err := os.WriteFile(path, legacy, 0600); err != nil {
		t.Fatal(err)
	}
	store := &shortcutStore{directory: directory}
	value, err := store.load()
	if err != nil || len(value.Items) != 2 || value.Items[0].BundleID != "com.test.one" {
		t.Fatalf("%+v %v", value, err)
	}
	if err := store.save(appShortcuts{Items: []appShortcut{}}); err != nil {
		t.Fatal(err)
	}
	restarted := &shortcutStore{directory: directory}
	empty, err := restarted.load()
	if err != nil || len(empty.Items) != 0 {
		t.Fatalf("empty collection was reimported: %+v %v", empty, err)
	}
	unchanged, _ := os.ReadFile(path)
	if !bytes.Equal(legacy, unchanged) {
		t.Fatal("legacy configuration changed")
	}
}

// 收藏增删和调序经过保存后应按用户顺序恢复，重复应用、超量和无效标识均不能覆盖已有列表。
func TestShortcutValidationAndOrdering(t *testing.T) {
	store := &shortcutStore{directory: t.TempDir()}
	one := appShortcut{"com.test.one", "一"}
	two := appShortcut{"com.test.two", "二"}
	for _, items := range [][]appShortcut{{one}, {one, two}, {two, one}, {two}} {
		if err := store.save(appShortcuts{Items: items}); err != nil {
			t.Fatal(err)
		}
		restarted := &shortcutStore{directory: store.directory}
		value, err := restarted.load()
		if err != nil || !reflect.DeepEqual(value.Items, items) {
			t.Fatalf("%+v %v", value, err)
		}
	}
	oversized := []appShortcut{}
	for i := 0; i < 13; i++ {
		oversized = append(oversized, appShortcut{BundleID: "com.test." + string(rune('a'+i)), Name: "应用"})
	}
	for _, invalid := range [][]appShortcut{{one, one}, oversized, {{"invalid", "名称"}}, nil} {
		if err := store.save(appShortcuts{Items: invalid}); err == nil {
			t.Fatal("invalid collection accepted")
		}
		value, _ := store.load()
		if !reflect.DeepEqual(value.Items, []appShortcut{two}) {
			t.Fatal("invalid save replaced collection")
		}
	}
}

// 保存过程中目标目录不可写时应报告失败并保留内存和磁盘上已确认的旧收藏。
func TestShortcutSaveFailureKeepsOldValue(t *testing.T) {
	directory := t.TempDir()
	store := &shortcutStore{directory: directory}
	old := appShortcuts{Items: []appShortcut{{"com.test.one", "一"}}}
	if err := store.save(old); err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(filepath.Join(directory, "app-shortcuts.json"))
	blocker := filepath.Join(directory, "blocker")
	if err := os.WriteFile(blocker, []byte("not a directory"), 0600); err != nil {
		t.Fatal(err)
	}
	store.directory = blocker
	if err := store.save(appShortcuts{Items: []appShortcut{}}); err == nil {
		t.Fatal("save should fail")
	}
	value, err := store.load()
	if err != nil || !reflect.DeepEqual(value.Items, old.Items) {
		t.Fatal("last good collection lost")
	}
	after, _ := os.ReadFile(filepath.Join(directory, "app-shortcuts.json"))
	if !bytes.Equal(before, after) {
		t.Fatal("old file changed")
	}
}

// 已保存的收藏文件损坏时应返回读取错误，不得自动重置为 Codex 或覆盖用户文件。
func TestShortcutCorruptFileIsPreserved(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "app-shortcuts.json")
	if err := os.WriteFile(path, []byte("broken"), 0600); err != nil {
		t.Fatal(err)
	}
	store := &shortcutStore{directory: directory}
	if _, err := store.load(); err == nil {
		t.Fatal("corrupt file accepted")
	}
	data, _ := os.ReadFile(path)
	if string(data) != "broken" {
		t.Fatal("corrupt file overwritten")
	}
}

// 正确实例可读写收藏，网页来源、其他实例、非 JSON、重复应用和尾随数据必须被拒绝且旧列表不变。
func TestShortcutHTTPContract(t *testing.T) {
	t.Setenv("JUNIMO_INSTANCE_ID", "test-instance")
	store := &shortcutStore{directory: t.TempDir()}
	handler := newHandler(nil, nil, store)
	request := func(method, body, instance, contentType, origin string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/app-shortcuts", bytes.NewBufferString(body))
		r.Header.Set("X-Junimo-Instance-ID", instance)
		r.Header.Set("Content-Type", contentType)
		if origin != "" {
			r.Header.Set("Origin", origin)
		}
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		return w
	}
	body := `{"revision":1,"items":[{"bundleId":"com.test.one","name":"一"}]}`
	if w := request("PUT", body, "test-instance", "application/json", ""); w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	for _, input := range []struct {
		body, instance, contentType, origin string
		status                              int
	}{
		{body, "wrong", "application/json", "", 403},
		{body, "test-instance", "application/json", "", 409},
		{`{"items":[]}`, "test-instance", "application/json", "", 428},
		{body, "test-instance", "application/json", "https://example.com", 403},
		{body, "test-instance", "text/plain", "", 415},
		{body + ` {}`, "test-instance", "application/json", "", 400},
		{`{"items":[{"bundleId":"com.test.one","name":"一"},{"bundleId":"com.test.one","name":"一"}]}`, "test-instance", "application/json", "", 400},
	} {
		if w := request("PUT", input.body, input.instance, input.contentType, input.origin); w.Code != input.status {
			t.Fatalf("status %d expected %d", w.Code, input.status)
		}
	}
	w := request(http.MethodGet, "", "", "", "")
	var value appShortcuts
	if err := json.Unmarshal(w.Body.Bytes(), &value); err != nil {
		t.Fatal(err)
	}
	if w.Code != 200 || len(value.Items) != 1 || value.Items[0].BundleID != "com.test.one" || w.Header().Get("X-Junimo-Instance-ID") != "test-instance" {
		t.Fatalf("%+v", w)
	}
}

// 旧快捷配置中应用标识和名称的首尾空白应像旧 Swift 解析器一样去除，规范化后重复的应用只导入一次。
func TestShortcutImportNormalizesLegacyFields(t *testing.T) {
	directory := t.TempDir()
	legacy := `{"version":1,"items":[{"type":"application","target":" com.openai.codex \n","title":" Codex "},{"type":"application","target":"com.openai.codex","title":"第二个名称"}]}`
	if err := os.WriteFile(filepath.Join(directory, "quick-launch.json"), []byte(legacy), 0600); err != nil {
		t.Fatal(err)
	}
	value, err := (&shortcutStore{directory: directory}).load()
	if err != nil || !reflect.DeepEqual(value.Items, []appShortcut{{"com.openai.codex", "Codex"}}) {
		t.Fatalf("%+v %v", value, err)
	}
}

// 两个客户端读取同一版本后，先保存的修改必须保留，后保存的旧列表应被拒绝，重启后版本和收藏仍一致。
func TestShortcutCompareAndSaveRejectsLostUpdates(t *testing.T) {
	store := &shortcutStore{directory: t.TempDir()}
	original, err := store.load()
	if err != nil {
		t.Fatal(err)
	}
	added := appShortcut{"com.google.Chrome", "Chrome"}
	current, err := store.compareAndSave(appShortcuts{Items: append(original.Items, added), Revision: original.Revision})
	if err != nil || current.Revision <= original.Revision {
		t.Fatalf("%+v %v", current, err)
	}
	_, err = store.compareAndSave(appShortcuts{Items: []appShortcut{}, Revision: original.Revision})
	if err != errShortcutConflict {
		t.Fatalf("expected conflict, got %v", err)
	}
	restarted, err := (&shortcutStore{directory: store.directory}).load()
	if err != nil || !reflect.DeepEqual(current, restarted) {
		t.Fatalf("saved version was not preserved: %+v %v", restarted, err)
	}
}

// 现有未带版本的收藏文件首次读取时应保留内容并赋予初始版本，第一次带版本保存后可从磁盘恢复新版本。
func TestShortcutMigratesUnversionedCollection(t *testing.T) {
	directory := t.TempDir()
	if err := os.WriteFile(filepath.Join(directory, "app-shortcuts.json"), []byte(`{"items":[{"bundleId":"com.google.Chrome","name":"Chrome"}]}`), 0600); err != nil {
		t.Fatal(err)
	}
	store := &shortcutStore{directory: directory}
	value, err := store.load()
	if err != nil || value.Revision != 1 || value.Items[0].BundleID != "com.google.Chrome" {
		t.Fatalf("%+v %v", value, err)
	}
	saved, err := store.compareAndSave(value)
	if err != nil || saved.Revision != 2 {
		t.Fatalf("%+v %v", saved, err)
	}
	restored, err := (&shortcutStore{directory: directory}).load()
	if err != nil || !reflect.DeepEqual(saved, restored) {
		t.Fatalf("%+v %v", restored, err)
	}
}
