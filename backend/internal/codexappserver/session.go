// Package codexappserver 隐藏 Codex app-server 子进程和 JSON-RPC 通信细节。
package codexappserver

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"sync"
)

const maxMessageSize = 32 * 1024 * 1024

// Session 是可复用、串行调用的 Codex app-server 会话。
// 首次 Call 时延迟启动进程；调用失败后会丢弃进程，下一次 Call 自动重连。
type Session struct {
	mu         sync.Mutex
	executable string
	command    *exec.Cmd
	stdin      io.WriteCloser
	scanner    *bufio.Scanner
	nextID     int
}

// NewSession 创建一个尚未启动子进程的会话。
func NewSession(executable string) *Session {
	return &Session{executable: executable}
}

// Call 确保 app-server 已初始化，再执行一次顺序 JSON-RPC 调用。
func (session *Session) Call(ctx context.Context, method string, params any, result any) error {
	session.mu.Lock()
	defer session.mu.Unlock()

	if session.executable == "" {
		return errors.New("codex executable not found")
	}
	if err := session.ensureStartedLocked(ctx); err != nil {
		session.terminateLocked()
		return err
	}
	if err := session.requestLocked(ctx, method, params, result); err != nil {
		session.terminateLocked()
		return err
	}
	return nil
}

// Close 停止会话拥有的 app-server 子进程。
func (session *Session) Close() {
	session.mu.Lock()
	defer session.mu.Unlock()
	session.terminateLocked()
}

func (session *Session) ensureStartedLocked(ctx context.Context) error {
	if session.command != nil {
		return nil
	}
	command := exec.Command(session.executable, "app-server", "--stdio")
	stdin, err := command.StdinPipe()
	if err != nil {
		return err
	}
	stdout, err := command.StdoutPipe()
	if err != nil {
		_ = stdin.Close()
		return err
	}
	command.Stderr = io.Discard
	if err := command.Start(); err != nil {
		_ = stdin.Close()
		return err
	}

	session.command = command
	session.stdin = stdin
	session.scanner = bufio.NewScanner(stdout)
	session.scanner.Buffer(make([]byte, 64*1024), maxMessageSize)
	session.nextID = 0

	var initialized json.RawMessage
	if err := session.requestLocked(ctx, "initialize", map[string]any{
		"clientInfo": map[string]any{
			"name":    "junimo",
			"title":   "Junimo",
			"version": "0.2.0",
		},
		"capabilities": map[string]any{"experimentalApi": true},
	}, &initialized); err != nil {
		return err
	}
	return json.NewEncoder(session.stdin).Encode(map[string]any{
		"method": "initialized",
		"params": map[string]any{},
	})
}

func (session *Session) requestLocked(ctx context.Context, method string, params any, result any) error {
	id := session.nextID
	session.nextID++
	if err := json.NewEncoder(session.stdin).Encode(map[string]any{
		"id":     id,
		"method": method,
		"params": params,
	}); err != nil {
		return err
	}

	response, err := session.readResponseLocked(ctx, id)
	if err != nil {
		return err
	}
	var envelope struct {
		Result json.RawMessage `json:"result"`
		Error  json.RawMessage `json:"error"`
	}
	if err := json.Unmarshal(response, &envelope); err != nil {
		return err
	}
	if len(envelope.Error) > 0 && string(envelope.Error) != "null" {
		var appServerError struct {
			Message string `json:"message"`
		}
		if json.Unmarshal(envelope.Error, &appServerError) == nil && appServerError.Message != "" {
			return errors.New(appServerError.Message)
		}
		return fmt.Errorf("codex app-server error: %s", envelope.Error)
	}
	if raw, ok := result.(*json.RawMessage); ok {
		*raw = append((*raw)[:0], envelope.Result...)
		return nil
	}
	return json.Unmarshal(envelope.Result, result)
}

type scanResult struct {
	data []byte
	err  error
}

func (session *Session) readResponseLocked(ctx context.Context, responseID int) ([]byte, error) {
	result := make(chan scanResult, 1)
	scanner := session.scanner
	go func() {
		for scanner.Scan() {
			line := append([]byte(nil), scanner.Bytes()...)
			var envelope struct {
				ID *int `json:"id"`
			}
			if json.Unmarshal(line, &envelope) != nil || envelope.ID == nil || *envelope.ID != responseID {
				continue
			}
			result <- scanResult{data: line}
			return
		}
		if err := scanner.Err(); err != nil {
			result <- scanResult{err: err}
			return
		}
		result <- scanResult{err: fmt.Errorf("codex app-server closed before response %d", responseID)}
	}()

	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case response := <-result:
		return response.data, response.err
	}
}

func (session *Session) terminateLocked() {
	if session.stdin != nil {
		_ = session.stdin.Close()
	}
	if session.command != nil && session.command.Process != nil {
		_ = session.command.Process.Kill()
		_ = session.command.Wait()
	}
	session.command = nil
	session.stdin = nil
	session.scanner = nil
	session.nextID = 0
}
