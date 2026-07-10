package codexusage

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type failingQuerier struct{}

func (failingQuerier) Query(context.Context) (Snapshot, error) {
	return Snapshot{}, errors.New("codex is unavailable")
}

func TestParseRateLimitsReturnsRemainingUsageWindows(t *testing.T) {
	response := []byte(`{
		"id": 1,
		"result": {
			"rateLimits": {
				"primary": {"usedPercent": 6, "windowDurationMins": 300, "resetsAt": 1783655023},
				"secondary": {"usedPercent": 1, "windowDurationMins": 10080, "resetsAt": 1784241823}
			}
		}
	}`)

	snapshot, err := ParseRateLimits(response)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Status != StatusAvailable {
		t.Fatalf("status = %q, want %q", snapshot.Status, StatusAvailable)
	}
	if snapshot.Primary == nil || snapshot.Primary.RemainingPercent != 94 {
		t.Fatalf("primary = %#v, want 94%% remaining", snapshot.Primary)
	}
	if snapshot.Primary.WindowDurationMinutes != 300 {
		t.Fatalf("primary duration = %d, want 300", snapshot.Primary.WindowDurationMinutes)
	}
	if snapshot.Secondary == nil || snapshot.Secondary.RemainingPercent != 99 {
		t.Fatalf("secondary = %#v, want 99%% remaining", snapshot.Secondary)
	}
}

func TestClientQueriesCodexAppServerWithoutBlockingStateReaders(t *testing.T) {
	executable := filepath.Join(t.TempDir(), "fake-codex")
	script := `#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    *'"id":0'*) printf '%s\n' '{"id":0,"result":{"userAgent":"fake"}}' ;;
    *'account/rateLimits/read'*)
      printf '%s\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":6,"windowDurationMins":300,"resetsAt":1783655023},"secondary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1784241823}}}}'
      exit 0
      ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	snapshot, err := NewClient(executable).Query(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Primary == nil || snapshot.Primary.RemainingPercent != 94 {
		t.Fatalf("primary = %#v, want 94%% remaining", snapshot.Primary)
	}
}

func TestMonitorReportsUnavailableWhenRefreshFails(t *testing.T) {
	monitor := NewMonitor(failingQuerier{})
	if monitor.Snapshot().Status != StatusLoading {
		t.Fatalf("initial status = %q, want %q", monitor.Snapshot().Status, StatusLoading)
	}

	monitor.Refresh(context.Background())
	snapshot := monitor.Snapshot()
	if snapshot.Status != StatusUnavailable {
		t.Fatalf("status = %q, want %q", snapshot.Status, StatusUnavailable)
	}
	if snapshot.Message == "" {
		t.Fatal("unavailable snapshot should explain the failure")
	}
}

func TestResolveExecutableHonorsConfiguredCodexPath(t *testing.T) {
	t.Setenv("JUNIMO_CODEX_EXECUTABLE", "/tmp/custom-codex")
	if executable := ResolveExecutable(); executable != "/tmp/custom-codex" {
		t.Fatalf("executable = %q, want configured path", executable)
	}
}

func TestParseRateLimitsClampsUnexpectedPercentages(t *testing.T) {
	response := []byte(`{
		"id": 1,
		"result": {"rateLimits": {
			"primary": {"usedPercent": 105, "windowDurationMins": 300},
			"secondary": {"usedPercent": -5, "windowDurationMins": 10080}
		}}
	}`)

	snapshot, err := ParseRateLimits(response)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.Primary.RemainingPercent != 0 {
		t.Fatalf("primary remaining = %d, want 0", snapshot.Primary.RemainingPercent)
	}
	if snapshot.Secondary.RemainingPercent != 100 {
		t.Fatalf("secondary remaining = %d, want 100", snapshot.Secondary.RemainingPercent)
	}
}

func TestClientStopsPromptlyWhenRateLimitQueryTimesOut(t *testing.T) {
	executable := filepath.Join(t.TempDir(), "slow-codex")
	script := `#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    *'"id":0'*) printf '%s\n' '{"id":0,"result":{"userAgent":"fake"}}' ;;
    *'account/rateLimits/read'*) sleep 5 ;;
  esac
done
`
	if err := os.WriteFile(executable, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	startedAt := time.Now()
	_, err := NewClient(executable).Query(ctx)
	if err == nil {
		t.Fatal("query should fail when app-server times out")
	}
	if elapsed := time.Since(startedAt); elapsed > time.Second {
		t.Fatalf("timed out query returned after %s, want under 1s", elapsed)
	}
}
