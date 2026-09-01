package codexappserver

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// 同一会话连续执行两次调用时应只启动和初始化一个 app-server，并忽略夹在响应前的通知。
func TestSessionReusesOneInitializedProcess(t *testing.T) {
	directory := t.TempDir()
	marker := filepath.Join(directory, "starts.log")
	executable := filepath.Join(directory, "codex")
	script := `#!/bin/sh
printf 'start\n' >> "$JUNIMO_TEST_MARKER"
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"method":"initialize"'*) printf '{"id":%s,"result":{}}\n' "$id" ;;
    *'"method":"first"'*)
      printf '{"method":"noise","params":{}}\n'
      printf '{"id":%s,"result":{"value":"one"}}\n' "$id"
      ;;
    *'"method":"second"'*) printf '{"id":%s,"result":{"value":"two"}}\n' "$id" ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("JUNIMO_TEST_MARKER", marker)

	session := NewSession(executable)
	t.Cleanup(session.Close)
	var first, second struct {
		Value string `json:"value"`
	}
	if err := session.Call(context.Background(), "first", nil, &first); err != nil {
		t.Fatal(err)
	}
	if err := session.Call(context.Background(), "second", nil, &second); err != nil {
		t.Fatal(err)
	}
	if first.Value != "one" || second.Value != "two" {
		t.Fatalf("first = %q second = %q", first.Value, second.Value)
	}
	starts, err := os.ReadFile(marker)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Count(string(starts), "start\n") != 1 {
		t.Fatalf("starts = %q, want one process", starts)
	}
}

// app-server 第一次返回错误后，同一会话的下一次调用应启动新进程并成功返回，避免把坏连接永久留给调用方。
func TestSessionReconnectsAfterAppServerError(t *testing.T) {
	directory := t.TempDir()
	marker := filepath.Join(directory, "failed-once")
	executable := filepath.Join(directory, "codex")
	script := `#!/bin/sh
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"method":"initialize"'*) printf '{"id":%s,"result":{}}\n' "$id" ;;
    *'"method":"read"'*)
      if [ ! -f "$JUNIMO_TEST_MARKER" ]; then
        touch "$JUNIMO_TEST_MARKER"
        printf '{"id":%s,"error":{"message":"temporary failure"}}\n' "$id"
      else
        printf '{"id":%s,"result":{"ok":true}}\n' "$id"
      fi
      ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("JUNIMO_TEST_MARKER", marker)

	session := NewSession(executable)
	t.Cleanup(session.Close)
	var result struct {
		OK bool `json:"ok"`
	}
	if err := session.Call(context.Background(), "read", nil, &result); err == nil || !strings.Contains(err.Error(), "temporary failure") {
		t.Fatalf("first error = %v, want temporary failure", err)
	}
	if err := session.Call(context.Background(), "read", nil, &result); err != nil {
		t.Fatal(err)
	}
	if !result.OK {
		t.Fatal("second call should succeed after reconnect")
	}
}

// app-server 在调用期间持续阻塞而上下文只允许 100 毫秒时，会话应在 1 秒内失败并清理进程。
func TestSessionStopsPromptlyWhenCallTimesOut(t *testing.T) {
	executable := filepath.Join(t.TempDir(), "codex")
	script := `#!/bin/sh
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"method":"initialize"'*) printf '{"id":%s,"result":{}}\n' "$id" ;;
    *'"method":"slow"'*) sleep 5 ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}

	session := NewSession(executable)
	t.Cleanup(session.Close)
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	startedAt := time.Now()
	var result struct{}
	err := session.Call(ctx, "slow", nil, &result)
	if err == nil {
		t.Fatal("call should fail when app-server times out")
	}
	if elapsed := time.Since(startedAt); elapsed > time.Second {
		t.Fatalf("timed out call returned after %s, want under 1s", elapsed)
	}
}

// app-server 在握手响应前发送 128KB 通知时，会话应跳过大消息并继续返回目标调用结果。
func TestSessionAcceptsLargeNotifications(t *testing.T) {
	executable := filepath.Join(t.TempDir(), "codex")
	script := `#!/bin/sh
while IFS= read -r line; do
  id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
  case "$line" in
    *'"method":"initialize"'*)
      payload=$(dd if=/dev/zero bs=1024 count=128 2>/dev/null | tr '\000' x)
      printf '{"method":"noise","params":{"payload":"%s"}}\n' "$payload"
      printf '{"id":%s,"result":{}}\n' "$id"
      ;;
    *'"method":"read"'*) printf '{"id":%s,"result":{"ok":true}}\n' "$id" ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}

	session := NewSession(executable)
	t.Cleanup(session.Close)
	var result struct {
		OK bool `json:"ok"`
	}
	if err := session.Call(context.Background(), "read", nil, &result); err != nil {
		t.Fatal(err)
	}
	if !result.OK {
		t.Fatal("call should complete after the large notification")
	}
}
