package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"time"

	"junimo/backend/internal/codexusage"
	"junimo/backend/internal/pomodoro"
)

const backendProtocolVersion = 2

type healthResponse struct {
	Status          string `json:"status"`
	ProtocolVersion int    `json:"protocolVersion"`
}

type stateResponse struct {
	Pomodoro pomodoro.Snapshot   `json:"pomodoro"`
	Codex    codexusage.Snapshot `json:"codex"`
}

type intentRequest struct {
	Type            string `json:"type"`
	DurationSeconds int64  `json:"durationSeconds,omitempty"`
}

func main() {
	timer := pomodoro.NewTimer(time.Now)
	usageMonitor := codexusage.NewMonitor(codexusage.NewClient(codexusage.ResolveExecutable()))
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	usageMonitor.Start(ctx, 30*time.Second, 40*time.Second)
	mux := newHandler(timer, usageMonitor.Snapshot)

	port := os.Getenv("JUNIMO_BACKEND_PORT")
	if port == "" {
		port = "44832"
	}
	address := "127.0.0.1:" + port
	log.Printf("junimo backend listening on http://%s", address)
	if err := http.ListenAndServe(address, mux); err != nil {
		log.Fatal(err)
	}
}

func newHandler(timer *pomodoro.Timer, usageProviders ...func() codexusage.Snapshot) http.Handler {
	usageSnapshot := func() codexusage.Snapshot {
		return codexusage.Snapshot{Status: codexusage.StatusLoading}
	}
	if len(usageProviders) > 0 && usageProviders[0] != nil {
		usageSnapshot = usageProviders[0]
	}
	state := func(pomodoroSnapshot pomodoro.Snapshot) stateResponse {
		return stateResponse{Pomodoro: pomodoroSnapshot, Codex: usageSnapshot()}
	}

	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, healthResponse{Status: "ok", ProtocolVersion: backendProtocolVersion})
	})
	mux.HandleFunc("GET /state", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, state(timer.Snapshot()))
	})
	mux.HandleFunc("POST /intent", func(writer http.ResponseWriter, request *http.Request) {
		var intent intentRequest
		if err := json.NewDecoder(request.Body).Decode(&intent); err != nil {
			http.Error(writer, err.Error(), http.StatusBadRequest)
			return
		}

		switch intent.Type {
		case "pomodoro.start", "pomodoro.startFocus":
			writeJSON(writer, state(timer.StartFocus(intent.DurationSeconds)))
		case "pomodoro.pause":
			writeJSON(writer, state(timer.Pause()))
		case "pomodoro.resume":
			writeJSON(writer, state(timer.Resume()))
		case "pomodoro.reset":
			writeJSON(writer, state(timer.Reset()))
		case "pomodoro.startBreak":
			writeJSON(writer, state(timer.StartBreak()))
		case "pomodoro.skipBreak":
			writeJSON(writer, state(timer.SkipBreak()))
		default:
			http.Error(writer, errors.New("unknown intent").Error(), http.StatusBadRequest)
		}
	})

	return mux
}

func writeJSON(writer http.ResponseWriter, value any) {
	writer.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(writer).Encode(value); err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
	}
}
