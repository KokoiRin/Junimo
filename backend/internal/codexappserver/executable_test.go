package codexappserver

import (
	"os"
	"path/filepath"
	"testing"
)

// 环境变量显式配置自定义 Codex 路径时，解析器应直接采用该路径，不再受 PATH 或默认安装位置影响。
func TestResolveExecutableHonorsConfiguredCodexPath(t *testing.T) {
	executable := filepath.Join(t.TempDir(), "custom-codex")
	if err := os.WriteFile(executable, []byte("#!/bin/sh\nprintf 'codex-cli test\\n'\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("JUNIMO_CODEX_EXECUTABLE", executable)
	if resolved := ResolveExecutable(); resolved != executable {
		t.Fatalf("executable = %q, want configured path", resolved)
	}
}

// 候选列表首项不可用而后项可用时，解析器应跳过坏路径并返回第一个真正可执行的 Codex。
func TestResolveExecutableSkipsUnusableCandidates(t *testing.T) {
	if executable := firstUsableExecutable([]string{"bad-codex", "good-codex"}, func(candidate string) bool {
		return candidate == "good-codex"
	}); executable != "good-codex" {
		t.Fatalf("executable = %q, want first usable candidate", executable)
	}
}

// 未配置 override、PATH 中只有一个可执行的 codex 文件时，解析器应返回该绝对路径，证明普通命令行安装可以被发现。
func TestResolveExecutableFindsCodexOnPath(t *testing.T) {
	directory := t.TempDir()
	executable := filepath.Join(directory, "codex")
	if err := os.WriteFile(executable, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("JUNIMO_CODEX_EXECUTABLE", "")
	t.Setenv("PATH", directory)

	if resolved := ResolveExecutable(); resolved != executable {
		t.Fatalf("executable = %q, want %q", resolved, executable)
	}
}

// 桌面端更新后旧快捷路径成为断链且 PATH 无 Codex 时，应从用户应用目录的新 CodexCLI bundle 中找到可执行文件。
func TestResolveExecutableFindsNestedDesktopCLIWithBrokenLegacyLink(t *testing.T) {
	home := t.TempDir()
	resources := filepath.Join(home, "Applications", "ChatGPT.app", "Contents", "Resources")
	executable := filepath.Join(resources, "codex-cli", "CodexCLI.app", "Contents", "MacOS", "codex")
	if err := os.MkdirAll(filepath.Dir(executable), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(executable, []byte("#!/bin/sh\nprintf 'codex-cli test\\n'\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(home, ".local", "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(resources, "codex"), filepath.Join(bin, "codex")); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("PATH", bin)
	t.Setenv("JUNIMO_CODEX_EXECUTABLE", "")
	if resolved := ResolveExecutable(); resolved != executable {
		t.Fatalf("executable = %q, want nested desktop CLI %q", resolved, executable)
	}
}
