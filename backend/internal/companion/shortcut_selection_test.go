package companion

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"reflect"
	"testing"
)

// 四个收藏只显示前三个时，左右切换遵循可见顺序并首尾循环，栏外前台从两端进入，空栏和单图标也有确定结果。
func TestVisibleShortcutSelection(t *testing.T) {
	t.Setenv("JUNIMO_INSTANCE_ID", "selection-test")
	store := &shortcutStore{directory: t.TempDir()}
	items := []appShortcut{{"com.test.a", "A"}, {"com.test.b", "B"}, {"com.test.c", "C"}, {"com.test.d", "D"}}
	if err := store.save(appShortcuts{Items: items}); err != nil {
		t.Fatal(err)
	}
	before, _ := store.load()
	handler := newHandler(nil, nil, store)
	for _, tc := range []struct {
		count, direction int
		active, want     string
	}{
		{3, 1, "com.test.a", "com.test.b"}, {3, -1, "com.test.b", "com.test.a"},
		{3, 1, "com.test.c", "com.test.a"}, {3, -1, "com.test.a", "com.test.c"},
		{3, 1, "com.test.d", "com.test.a"}, {3, -1, "com.other.app", "com.test.c"},
		{0, 1, "com.test.a", ""}, {1, -1, "com.test.a", "com.test.a"},
	} {
		body := fmt.Sprintf(`{"revision":1,"visibleCount":%d,"direction":%d,"activeId":%q}`, tc.count, tc.direction, tc.active)
		r := httptest.NewRequest("POST", "/app-shortcuts/selection", bytes.NewBufferString(body))
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("X-Junimo-Instance-ID", "selection-test")
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		var result shortcutSelectionResponse
		if w.Code != 200 || json.Unmarshal(w.Body.Bytes(), &result) != nil {
			t.Fatalf("%+v: %s", tc, w.Body.String())
		}
		got := ""
		if result.Item != nil {
			got = result.Item.BundleID
		}
		if got != tc.want {
			t.Fatalf("%+v: got %s", tc, got)
		}
	}
	after, _ := store.load()
	if !reflect.DeepEqual(before, after) {
		t.Fatal("selection changed saved favorites")
	}
}

// 过时收藏、越界可见数量、无效方向、尾随数据及不可信来源都不能生成切换目标。
func TestShortcutSelectionRejectsInvalidContext(t *testing.T) {
	t.Setenv("JUNIMO_INSTANCE_ID", "selection-test")
	handler := newHandler(nil, nil, &shortcutStore{directory: t.TempDir()})
	valid := `{"revision":1,"visibleCount":1,"direction":1,"activeId":""}`
	for _, tc := range []struct {
		body, instance, origin, contentType string
		status                              int
	}{
		{`{"revision":0,"visibleCount":1,"direction":1}`, "selection-test", "", "application/json", 409},
		{`{"revision":1,"visibleCount":2,"direction":1}`, "selection-test", "", "application/json", 400},
		{`{"revision":1,"visibleCount":-1,"direction":1}`, "selection-test", "", "application/json", 400},
		{`{"revision":1,"visibleCount":1,"direction":0}`, "selection-test", "", "application/json", 400},
		{valid + `{}`, "selection-test", "", "application/json", 400},
		{valid, "wrong", "", "application/json", 403},
		{valid, "selection-test", "https://example.com", "application/json", 403},
		{valid, "selection-test", "", "text/plain", 415},
	} {
		r := httptest.NewRequest("POST", "/app-shortcuts/selection", bytes.NewBufferString(tc.body))
		r.Header.Set("Content-Type", tc.contentType)
		r.Header.Set("X-Junimo-Instance-ID", tc.instance)
		r.Header.Set("Origin", tc.origin)
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, r)
		if w.Code != tc.status {
			t.Fatalf("%+v: got %d", tc, w.Code)
		}
	}
}
