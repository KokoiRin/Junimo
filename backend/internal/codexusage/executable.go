package codexusage

import (
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

func ResolveExecutable() string {
	var candidates []string
	if configured := os.Getenv("JUNIMO_CODEX_EXECUTABLE"); configured != "" {
		candidates = append(candidates, configured)
	}
	if executable, err := exec.LookPath("codex"); err == nil {
		candidates = append(candidates, executable)
	}

	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates,
			filepath.Join(home, ".local", "bin", "codex"),
			filepath.Join(home, ".cargo", "bin", "codex"),
			filepath.Join(home, ".npm-global", "bin", "codex"),
			filepath.Join(home, "Applications", "ChatGPT.app", "Contents", "Resources", "codex"),
		)
	}
	candidates = append(candidates,
		"/Applications/ChatGPT.app/Contents/Resources/codex",
		"/opt/homebrew/bin/codex",
		"/usr/local/bin/codex",
	)
	return firstUsableExecutable(candidates, isUsableCodexExecutable)
}

func firstUsableExecutable(candidates []string, usable func(string) bool) string {
	seen := map[string]struct{}{}
	for _, candidate := range candidates {
		if candidate == "" {
			continue
		}
		if _, ok := seen[candidate]; ok {
			continue
		}
		seen[candidate] = struct{}{}
		if usable(candidate) {
			return candidate
		}
	}
	return ""
}

func isUsableCodexExecutable(candidate string) bool {
	info, err := os.Stat(candidate)
	if err != nil || info.IsDir() || info.Mode()&0o111 == 0 {
		return false
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, candidate, "--version")
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	return command.Run() == nil
}
