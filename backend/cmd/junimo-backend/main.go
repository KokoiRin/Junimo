package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"junimo/backend/internal/codexactivity"
	"junimo/backend/internal/codexusage"
)

type healthResponse struct {
	Status          string `json:"status"`
	ProtocolVersion int    `json:"protocolVersion"`
}

func main() {
	executable := codexusage.ResolveExecutable()
	usageMonitor := codexusage.NewMonitor(codexusage.NewClient(executable))
	activityMonitor := codexactivity.NewMonitor(codexactivity.NewClient(executable))
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	usageMonitor.Start(ctx, 30*time.Second, 40*time.Second)
	activityMonitor.Start(ctx, 3*time.Second, 20*time.Second)

	mux := newCompanionHandler(usageMonitor.Snapshot, activityMonitor.Snapshot)
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

func writeJSON(writer http.ResponseWriter, value any) {
	writer.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(writer).Encode(value); err != nil {
		http.Error(writer, err.Error(), http.StatusInternalServerError)
	}
}
