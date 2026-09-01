package codexactivity

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 两次扫描复用同一 app-server，并且未变化线程直接复用缓存而不重复读取完整历史。
func TestClientScansThreadsThroughOneLongLivedAppServer(t *testing.T) {
	directory := t.TempDir()
	marker := filepath.Join(directory, "calls.log")
	executable := filepath.Join(directory, "codex")
	script := `#!/bin/sh
printf 'start\n' >> "$JUNIMO_TEST_MARKER"
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"method":"initialize"'*)
      printf '{"id":%s,"result":{"userAgent":"fake"}}\n' "$id"
      ;;
    *'"method":"thread/list"'*)
      printf 'list\n' >> "$JUNIMO_TEST_MARKER"
      printf '{"id":%s,"result":{"data":[{"id":"thread-1","name":"轻量 Junimo","preview":"fallback","updatedAt":20,"turns":[],"status":{"type":"notLoaded"}}]}}\n' "$id"
      ;;
    *'"method":"thread/turns/list"'*)
      printf 'read\n' >> "$JUNIMO_TEST_MARKER"
      printf '{"id":%s,"result":{"data":[{"id":"turn-1","status":"completed","completedAt":20,"items":[]}]}}\n' "$id"
      ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("JUNIMO_TEST_MARKER", marker)

	client := NewClient(executable)
	t.Cleanup(client.Close)
	first, err := client.Scan(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	second, err := client.Scan(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 1 || len(first[0].Turns) != 1 || first[0].Turns[0].ID != "turn-1" {
		t.Fatalf("first scan = %#v", first)
	}
	if len(second) != 1 || second[0].Name != "轻量 Junimo" {
		t.Fatalf("second scan = %#v", second)
	}

	calls, err := os.ReadFile(marker)
	if err != nil {
		t.Fatal(err)
	}
	log := string(calls)
	if strings.Count(log, "start\n") != 1 || strings.Count(log, "list\n") != 2 || strings.Count(log, "read\n") != 1 {
		t.Fatalf("call log = %q, want one process, two lists, one read", log)
	}
}

// app-server 返回错误响应时扫描应失败，以便 Monitor 隔离状态并在下一轮重连。
func TestClientReturnsAppServerErrors(t *testing.T) {
	directory := t.TempDir()
	executable := filepath.Join(directory, "codex")
	script := `#!/bin/sh
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"method":"initialize"'*) printf '{"id":%s,"result":{}}\n' "$id" ;;
    *'"method":"thread/list"'*) printf '{"id":%s,"error":{"message":"thread store unavailable"}}\n' "$id" ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}

	client := NewClient(executable)
	t.Cleanup(client.Close)
	if _, err := client.Scan(context.Background()); err == nil || !strings.Contains(err.Error(), "thread store unavailable") {
		t.Fatalf("error = %v, want app-server message", err)
	}
}
