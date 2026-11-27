// Package processwatch 为桌面 Agent 应用提供低开销的本机进程运行状态检测。
package processwatch

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const (
	defaultRunningRevalidate = 30 * time.Second
	defaultStoppedProbe      = 4 * time.Second
)

// Watcher 缓存目标进程 PID，存活期间使用 kill(pid, 0) 零子进程探活，仅在退出、定期复核或外部强制探测时调用 pgrep。
type Watcher struct {
	name              string
	runningRevalidate time.Duration
	stoppedProbe      time.Duration
	probe             func(context.Context, string) (int, *bool)
	alive             func(int) bool

	mu       sync.Mutex
	pid      int
	lastScan time.Time
	last     *bool
}

// New 创建按精确进程名匹配当前用户进程的 Watcher。
func New(processName string) *Watcher {
	return NewFunc(processName, pgrepExact)
}

// NewFunc 创建使用自定义进程探测函数的 Watcher，复用同一套 PID 存活缓存与冷却逻辑。
func NewFunc(name string, probe func(context.Context, string) (int, *bool)) *Watcher {
	return &Watcher{
		name:              name,
		runningRevalidate: defaultRunningRevalidate,
		stoppedProbe:      defaultStoppedProbe,
		probe:             probe,
		alive:             processAlive,
	}
}

// IsRunning 返回目标桌面应用是否正在运行；forceProbe 为 true 时忽略停机探测退避立即重新确认。
func (w *Watcher) IsRunning(ctx context.Context, now time.Time, forceProbe bool) *bool {
	w.mu.Lock()
	defer w.mu.Unlock()

	if w.pid > 0 && now.Sub(w.lastScan) < w.runningRevalidate {
		if w.alive(w.pid) {
			return new(true)
		}
		w.pid = 0
	}
	if w.pid == 0 && w.last != nil && !*w.last && !forceProbe && now.Sub(w.lastScan) < w.stoppedProbe {
		return new(false)
	}
	pid, running := w.probe(ctx, w.name)
	w.pid = pid
	w.lastScan = now
	w.last = running
	return running
}

func processAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}

func pgrepExact(ctx context.Context, name string) (int, *bool) {
	out, err := exec.CommandContext(ctx, "/usr/bin/pgrep", "-U", strconv.Itoa(os.Getuid()), "-x", name).Output()
	if err == nil {
		for _, field := range strings.Fields(string(out)) {
			if pid, convErr := strconv.Atoi(field); convErr == nil && pid > 0 {
				return pid, new(true)
			}
		}
		return 0, new(true)
	}
	var exited *exec.ExitError
	if errors.As(err, &exited) && exited.ExitCode() == 1 {
		return 0, new(false)
	}
	return 0, nil
}
