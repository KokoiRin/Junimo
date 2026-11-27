package codexusage

import "testing"

// Codex 进程匹配应识别 Bundle ID 为 com.openai.codex 的桌面端和交互式 CLI，同时排除普通 ChatGPT 与 Junimo 自启动的 app-server 子进程。
func TestMatchCodexProcessFiltersDesktopCLIAndAppServer(t *testing.T) {
	bundles := map[string]string{
		"/Applications/ChatGPT.app":        "com.openai.codex",
		"/Applications/OtherChatGPT.app":   "com.openai.chat",
		"/Applications/Codex.app":          "com.openai.codex",
	}
	readBundle := func(path string) string { return bundles[path] }

	for _, tc := range []struct {
		name    string
		ps      string
		wantPID int
		wantRun bool
	}{
		{
			name:    "only junimo app-server child",
			ps:      "100 1 /Applications/Junimo.app/Contents/MacOS/junimo-backend\n101 100 /opt/homebrew/bin/codex app-server --stdio\n102 1 /usr/local/bin/codex app-server --stdio\n",
			wantPID: 0, wantRun: false,
		},
		{
			name:    "non-codex ChatGPT app ignored",
			ps:      "200 1 /Applications/OtherChatGPT.app/Contents/MacOS/ChatGPT\n",
			wantPID: 0, wantRun: false,
		},
		{
			name:    "ChatGPT bundle with com.openai.codex matched even when pid contains ppid digits",
			ps:      "1300 1 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT\n",
			wantPID: 1300, wantRun: true,
		},
		{
			name:    "Codex.app matched",
			ps:      "301 1 /Applications/Codex.app/Contents/MacOS/Codex\n",
			wantPID: 301, wantRun: true,
		},
		{
			name:    "interactive codex CLI matched",
			ps:      "400 50 /opt/homebrew/bin/codex --model gpt-5\n",
			wantPID: 400, wantRun: true,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			pid, running := matchCodexProcess(tc.ps, 100, readBundle)
			if running == nil || *running != tc.wantRun || pid != tc.wantPID {
				t.Fatalf("got pid=%d running=%v, want pid=%d running=%v", pid, running, tc.wantPID, tc.wantRun)
			}
		})
	}
}
