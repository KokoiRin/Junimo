package codexactivity

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
)

var writerLockName = regexp.MustCompile(`^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\.lock$`)

// 独立 app-server 会把其他进程正在执行的 turn 投影为 interrupted。
// 只对有活跃写入者的会话查询最新一轮，避免崩溃遗留的 inProgress 记录点亮圆环。
func (client *Client) IsWorking(ctx context.Context) bool {
	home := os.Getenv("CODEX_HOME")
	if home == "" {
		userHome, err := os.UserHomeDir()
		if err != nil {
			return false
		}
		home = filepath.Join(userHome, ".codex")
	}
	dir := filepath.Join(home, "thread-writer-locks")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false
	}
	var ids []string
	for _, entry := range entries {
		name := entry.Name()
		if entry.Type().IsRegular() && writerLockName.MatchString(name) && hasWriter(filepath.Join(dir, name)) {
			ids = append(ids, "('"+strings.TrimSuffix(name, ".lock")+"')")
		}
	}
	if len(ids) == 0 {
		return false
	}
	query := "WITH live(id) AS (VALUES " + strings.Join(ids, ",") + `) SELECT EXISTS (
		SELECT 1 FROM live WHERE (
			SELECT status FROM thread_turns WHERE thread_id = live.id
			ORDER BY rollout_ordinal DESC LIMIT 1
		) = 'inProgress')`
	db := filepath.Join(home, "thread_history_1.sqlite")
	result, err := exec.CommandContext(ctx, "/usr/bin/sqlite3", "-init", "/dev/null", "-batch", "-readonly", "-cmd", ".timeout 250", db, query).Output()
	return err == nil && bytes.Equal(bytes.TrimSpace(result), []byte("1"))
}

func hasWriter(path string) bool {
	file, err := os.Open(path)
	if err != nil {
		return false
	}
	defer file.Close()
	// F_GETLK 只查询冲突的独占锁，不会获取或释放 Codex 自己的锁。
	lock := syscall.Flock_t{Type: syscall.F_RDLCK}
	return syscall.FcntlFlock(file.Fd(), syscall.F_GETLK, &lock) == nil && lock.Type == syscall.F_WRLCK
}
