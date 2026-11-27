package codexusage

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	"junimo/backend/internal/processwatch"
)

const codexBundleID = "com.openai.codex"

// NewProcessWatcher 监控 Codex 桌面端（com.openai.codex）或交互式 codex CLI，自动排除 Junimo 自己启动的 app-server 子进程。
func NewProcessWatcher() *processwatch.Watcher {
	var cacheMu sync.Mutex
	bundleIDCache := make(map[string]string)

	readBundleID := func(appPath string) string {
		cacheMu.Lock()
		if cached, ok := bundleIDCache[appPath]; ok {
			cacheMu.Unlock()
			return cached
		}
		cacheMu.Unlock()

		plistPath := filepath.Join(appPath, "Contents", "Info.plist")
		out, err := exec.Command("/usr/bin/plutil", "-extract", "CFBundleIdentifier", "raw", plistPath).Output()
		id := ""
		if err == nil {
			id = strings.TrimSpace(string(out))
		}
		cacheMu.Lock()
		bundleIDCache[appPath] = id
		cacheMu.Unlock()
		return id
	}

	myPID := os.Getpid()
	return processwatch.NewFunc("Codex", func(ctx context.Context, _ string) (int, *bool) {
		out, err := exec.CommandContext(ctx, "/bin/ps", "-U", strconv.Itoa(os.Getuid()), "-o", "pid=,ppid=,args=").Output()
		if err != nil {
			return 0, nil
		}
		return matchCodexProcess(string(out), myPID, readBundleID)
	})
}

func matchCodexProcess(psOutput string, myPID int, readBundleID func(appPath string) string) (int, *bool) {
	for _, rawLine := range strings.Split(psOutput, "\n") {
		line := strings.TrimSpace(rawLine)
		if line == "" {
			continue
		}
		pid, ppid, args, ok := parsePSLine(line)
		if !ok || pid == myPID || ppid == myPID {
			continue
		}
		if isCodexDesktopArgs(args, readBundleID) || isInteractiveCodexCLIArgs(args) {
			return pid, new(true)
		}
	}
	return 0, new(false)
}

func parsePSLine(line string) (pid int, ppid int, args string, ok bool) {
	pStr, rest, found := cutField(line)
	if !found {
		return 0, 0, "", false
	}
	ppStr, rest, found := cutField(rest)
	if !found {
		return 0, 0, "", false
	}
	p, err1 := strconv.Atoi(pStr)
	pp, err2 := strconv.Atoi(ppStr)
	if err1 != nil || err2 != nil || p <= 0 || rest == "" {
		return 0, 0, "", false
	}
	return p, pp, rest, true
}

func cutField(s string) (field, rest string, ok bool) {
	s = strings.TrimLeft(s, " \t")
	if s == "" {
		return "", "", false
	}
	idx := strings.IndexAny(s, " \t")
	if idx < 0 {
		return s, "", true
	}
	return s[:idx], strings.TrimLeft(s[idx:], " \t"), true
}

func isCodexDesktopArgs(args string, readBundleID func(appPath string) string) bool {
	marker := ".app/Contents/MacOS/"
	idx := strings.Index(args, marker)
	if idx < 0 {
		return false
	}
	appPath := args[:idx+len(".app")]
	rest := args[idx+len(marker):]
	execName := rest
	if sp := strings.IndexAny(rest, " \t"); sp >= 0 {
		execName = rest[:sp]
	}
	if execName != "Codex" && execName != "ChatGPT" {
		return false
	}
	return readBundleID(appPath) == codexBundleID
}

func isInteractiveCodexCLIArgs(args string) bool {
	fields := strings.Fields(args)
	if len(fields) == 0 {
		return false
	}
	if filepath.Base(fields[0]) != "codex" {
		return false
	}
	for _, arg := range fields[1:] {
		if arg == "app-server" {
			return false
		}
	}
	return true
}
