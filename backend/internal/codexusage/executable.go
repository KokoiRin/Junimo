package codexusage

import (
	"os"
	"os/exec"
	"path/filepath"
)

func ResolveExecutable() string {
	if configured := os.Getenv("JUNIMO_CODEX_EXECUTABLE"); configured != "" {
		return configured
	}
	if executable, err := exec.LookPath("codex"); err == nil {
		return executable
	}

	var candidates []string
	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates,
			filepath.Join(home, ".local", "bin", "codex"),
			filepath.Join(home, ".cargo", "bin", "codex"),
			filepath.Join(home, ".npm-global", "bin", "codex"),
		)
	}
	candidates = append(candidates,
		"/opt/homebrew/bin/codex",
		"/usr/local/bin/codex",
	)
	for _, candidate := range candidates {
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
			return candidate
		}
	}
	return ""
}
