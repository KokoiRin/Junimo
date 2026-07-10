package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"junimo/backend/internal/codexusage"
	"junimo/backend/internal/pomodoro"
)

func TestStateIncludesCodexUsageSnapshot(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer, func() codexusage.Snapshot {
		return codexusage.Snapshot{
			Status: codexusage.StatusAvailable,
			Primary: &codexusage.Window{
				RemainingPercent:      94,
				WindowDurationMinutes: 300,
			},
		}
	})
	request := httptest.NewRequest(http.MethodGet, "/state", nil)
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)

	var response stateResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.Codex.Primary == nil || response.Codex.Primary.RemainingPercent != 94 {
		t.Fatalf("codex usage = %#v, want 94%% remaining", response.Codex)
	}
}

func TestIntentStartsPomodoro(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer)
	body := bytes.NewBufferString(`{"type":"pomodoro.start","durationSeconds":120}`)
	request := httptest.NewRequest(http.MethodPost, "/intent", body)
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", recorder.Code, recorder.Body.String())
	}

	var response stateResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.Pomodoro.Status != pomodoro.StatusRunning {
		t.Fatalf("status = %s, want running", response.Pomodoro.Status)
	}
	if response.Pomodoro.RemainingSeconds != 120 {
		t.Fatalf("remaining = %d, want 120", response.Pomodoro.RemainingSeconds)
	}
}

func TestHealthReportsProtocolVersion(t *testing.T) {
	timer := pomodoro.NewTimer(func() time.Time {
		return time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	})
	handler := newHandler(timer)
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", recorder.Code, recorder.Body.String())
	}

	var response healthResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.ProtocolVersion != backendProtocolVersion {
		t.Fatalf("protocolVersion = %d, want %d", response.ProtocolVersion, backendProtocolVersion)
	}
}

func TestIntentCanPauseAndResumePomodoro(t *testing.T) {
	now := time.Date(2026, 7, 7, 10, 0, 0, 0, time.UTC)
	timer := pomodoro.NewTimer(func() time.Time { return now })
	handler := newHandler(timer)

	postIntent(t, handler, `{"type":"pomodoro.startFocus","durationSeconds":120}`)
	now = now.Add(30 * time.Second)
	paused := postIntent(t, handler, `{"type":"pomodoro.pause"}`)
	if paused.Pomodoro.Status != pomodoro.StatusPaused {
		t.Fatalf("status = %s, want paused", paused.Pomodoro.Status)
	}
	if paused.Pomodoro.RemainingSeconds != 90 {
		t.Fatalf("remaining = %d, want 90", paused.Pomodoro.RemainingSeconds)
	}

	now = now.Add(60 * time.Second)
	resumed := postIntent(t, handler, `{"type":"pomodoro.resume"}`)
	if resumed.Pomodoro.Status != pomodoro.StatusRunning {
		t.Fatalf("status = %s, want running", resumed.Pomodoro.Status)
	}

	now = now.Add(45 * time.Second)
	request := httptest.NewRequest(http.MethodGet, "/state", nil)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)

	var response stateResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if response.Pomodoro.RemainingSeconds != 45 {
		t.Fatalf("remaining = %d, want 45", response.Pomodoro.RemainingSeconds)
	}
}

func postIntent(t *testing.T, handler http.Handler, body string) stateResponse {
	t.Helper()
	request := httptest.NewRequest(http.MethodPost, "/intent", bytes.NewBufferString(body))
	recorder := httptest.NewRecorder()

	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", recorder.Code, recorder.Body.String())
	}

	var response stateResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	return response
}
