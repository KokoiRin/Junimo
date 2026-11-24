package codexactivity

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"syscall"
	"testing"
)

// 两个会话同时运行时，结束其中一个仍应亮灯；另一个中断、退出后留下旧记录或数据库不可读时应熄灯。
func TestWorkIndicatorTracksLatestTurnOfLiveWriters(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("Junimo reads macOS writer locks")
	}
	home := t.TempDir()
	t.Setenv("CODEX_HOME", home)
	dir := filepath.Join(home, "thread-writer-locks")
	if err := os.Mkdir(dir, 0700); err != nil {
		t.Fatal(err)
	}
	first := "aaaaaaaa-1111-2222-3333-aaaaaaaaaaaa"
	second := "bbbbbbbb-1111-2222-3333-bbbbbbbbbbbb"
	openWriter := func(id string) *os.File {
		t.Helper()
		f, err := os.Create(filepath.Join(dir, id+".lock"))
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { f.Close() })
		if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
			t.Fatal(err)
		}
		return f
	}
	openWriter(first)
	writer := openWriter(second)
	db := filepath.Join(home, "thread_history_1.sqlite")
	sql := func(query string) {
		t.Helper()
		if data, err := exec.Command("/usr/bin/sqlite3", "-init", "/dev/null", db, query).CombinedOutput(); err != nil {
			t.Fatalf("%s: %v", data, err)
		}
	}
	client := &Client{}
	check := func(want bool) {
		t.Helper()
		if got := client.IsWorking(context.Background()); got != want {
			t.Fatalf("working = %v, want %v", got, want)
		}
	}
	check(false)
	sql("CREATE TABLE thread_turns(thread_id TEXT, rollout_ordinal INTEGER, status TEXT)")
	sql("INSERT INTO thread_turns VALUES ('" + first + "',1,'inProgress'),('" + second + "',1,'inProgress')")
	check(true)
	sql("INSERT INTO thread_turns VALUES ('" + first + "',2,'completed')")
	check(true)
	sql("UPDATE thread_turns SET status='interrupted' WHERE thread_id='" + second + "'")
	check(false)
	sql("INSERT INTO thread_turns VALUES ('" + second + "',2,'inProgress')")
	check(true)
	writer.Close()
	check(false)
}
