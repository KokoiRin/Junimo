package codexactivity

import (
	"bytes"
	"context"
	"encoding/binary"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"syscall"
	"time"
)

var writerLockName = regexp.MustCompile(`^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}\.lock$`)

type workingFileStamp struct {
	size     int64
	modified time.Time
}

type workingDBStamp struct {
	db            workingFileStamp
	wal           workingFileStamp
	changeCounter uint32
}

type workingCache struct {
	dbPath   string
	stamp    workingDBStamp
	locksKey string
	result   bool
	valid    bool
}

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
		client.invalidateWorkingCache()
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
		client.invalidateWorkingCache()
		return false
	}
	sort.Strings(ids)
	locksKey := strings.Join(ids, ",")
	db := filepath.Join(home, "thread_history_1.sqlite")
	stamp, ok := readWorkingDBStamp(db)
	if !ok {
		client.invalidateWorkingCache()
		return false
	}

	client.workingMu.Lock()
	if client.workingCache.valid &&
		client.workingCache.dbPath == db &&
		client.workingCache.locksKey == locksKey &&
		client.workingCache.stamp == stamp {
		cached := client.workingCache.result
		client.workingMu.Unlock()
		return cached
	}
	client.workingMu.Unlock()

	query := "WITH live(id) AS (VALUES " + locksKey + `) SELECT EXISTS (
		SELECT 1 FROM live WHERE (
			SELECT status FROM thread_turns WHERE thread_id = live.id
			ORDER BY rollout_ordinal DESC LIMIT 1
		) = 'inProgress')`
	result, err := exec.CommandContext(ctx, "/usr/bin/sqlite3", "-init", "/dev/null", "-batch", "-readonly", "-cmd", ".timeout 250", db, query).Output()
	if err != nil {
		client.invalidateWorkingCache()
		return false
	}
	working := bytes.Equal(bytes.TrimSpace(result), []byte("1"))
	client.workingMu.Lock()
	client.workingCache = workingCache{
		dbPath:   db,
		stamp:    stamp,
		locksKey: locksKey,
		result:   working,
		valid:    true,
	}
	client.workingMu.Unlock()
	return working
}

func (client *Client) invalidateWorkingCache() {
	client.workingMu.Lock()
	client.workingCache = workingCache{}
	client.workingMu.Unlock()
}

// readWorkingDBStamp 读取数据库文件元信息、WAL 变化以及 SQLite 文件头变更计数器，避免无变化时重复派生 sqlite3。
func readWorkingDBStamp(dbPath string) (workingDBStamp, bool) {
	info, err := os.Stat(dbPath)
	if err != nil {
		return workingDBStamp{}, false
	}
	stamp := workingDBStamp{
		db: workingFileStamp{size: info.Size(), modified: info.ModTime()},
	}
	if walInfo, err := os.Stat(dbPath + "-wal"); err == nil {
		stamp.wal = workingFileStamp{size: walInfo.Size(), modified: walInfo.ModTime()}
	}
	if file, err := os.Open(dbPath); err == nil {
		var header [4]byte
		if _, err := file.ReadAt(header[:], 24); err == nil {
			stamp.changeCounter = binary.BigEndian.Uint32(header[:])
		}
		_ = file.Close()
	}
	return stamp, true
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
