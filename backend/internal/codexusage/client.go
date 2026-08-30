package codexusage

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"time"
)

type Client struct {
	executable string
}

func NewClient(executable string) *Client {
	return &Client{executable: executable}
}

func (client *Client) Query(ctx context.Context) (Snapshot, error) {
	if client.executable == "" {
		return Snapshot{}, errors.New("codex executable not found")
	}

	command := exec.CommandContext(ctx, client.executable, "app-server", "--stdio")
	stdin, err := command.StdinPipe()
	if err != nil {
		return Snapshot{}, err
	}
	stdout, err := command.StdoutPipe()
	if err != nil {
		return Snapshot{}, err
	}
	command.Stderr = io.Discard
	if err := command.Start(); err != nil {
		return Snapshot{}, err
	}
	defer func() {
		_ = stdin.Close()
		if command.Process != nil {
			_ = command.Process.Kill()
		}
		_ = command.Wait()
	}()

	encoder := json.NewEncoder(stdin)
	if err := encoder.Encode(map[string]any{
		"id":     0,
		"method": "initialize",
		"params": map[string]any{
			"clientInfo": map[string]any{
				"name":    "junimo",
				"title":   "Junimo",
				"version": "0.2.0",
			},
			"capabilities": map[string]any{"experimentalApi": true},
		},
	}); err != nil {
		return Snapshot{}, err
	}

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 4*1024), 1024*1024)
	if _, err := readResponse(scanner, 0); err != nil {
		return Snapshot{}, err
	}
	if err := encoder.Encode(map[string]any{"method": "initialized", "params": map[string]any{}}); err != nil {
		return Snapshot{}, err
	}
	if err := encoder.Encode(map[string]any{"id": 1, "method": "account/rateLimits/read", "params": nil}); err != nil {
		return Snapshot{}, err
	}

	response, err := readResponse(scanner, 1)
	if err != nil {
		return Snapshot{}, err
	}
	snapshot, err := ParseRateLimits(response)
	if err != nil {
		return Snapshot{}, err
	}
	snapshot.RefreshedAt = time.Now().UTC().Format(time.RFC3339)
	return snapshot, nil
}

func readResponse(scanner *bufio.Scanner, responseID int) ([]byte, error) {
	for scanner.Scan() {
		line := append([]byte(nil), scanner.Bytes()...)
		var envelope struct {
			ID    *int            `json:"id"`
			Error json.RawMessage `json:"error"`
		}
		if err := json.Unmarshal(line, &envelope); err != nil || envelope.ID == nil || *envelope.ID != responseID {
			continue
		}
		if len(envelope.Error) > 0 && string(envelope.Error) != "null" {
			return nil, fmt.Errorf("codex app-server response %d: %s", responseID, envelope.Error)
		}
		return line, nil
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return nil, fmt.Errorf("codex app-server closed before response %d", responseID)
}
