package codexactivity

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

const recentThreadLimit = 12

// Client 通过一个长生命周期 Codex app-server 读取最近会话的持久化 turn 状态。
type Client struct {
	mu         sync.Mutex
	executable string
	command    *exec.Cmd
	stdin      io.WriteCloser
	scanner    *bufio.Scanner
	nextID     int
	cache      map[string]Thread
}

// NewClient 创建延迟启动的活动读取客户端。
func NewClient(executable string) *Client {
	return &Client{executable: executable, cache: make(map[string]Thread)}
}

// Scan 返回最近线程及其在本次更新时间对应的 turn 投影。
func (client *Client) Scan(ctx context.Context) ([]Thread, error) {
	client.mu.Lock()
	defer client.mu.Unlock()
	if client.executable == "" {
		return nil, errors.New("codex executable not found")
	}
	if err := client.ensureStartedLocked(ctx); err != nil {
		client.terminateLocked()
		return nil, err
	}

	var listed struct {
		Data []threadPayload `json:"data"`
	}
	if err := client.callLocked(ctx, "thread/list", map[string]any{
		"limit":         recentThreadLimit,
		"sortKey":       "updated_at",
		"sortDirection": "desc",
	}, &listed); err != nil {
		client.terminateLocked()
		return nil, err
	}

	threads := make([]Thread, 0, len(listed.Data))
	current := make(map[string]struct{}, len(listed.Data))
	for _, summary := range listed.Data {
		current[summary.ID] = struct{}{}
		if cached, exists := client.cache[summary.ID]; exists && cached.UpdatedAt == summary.UpdatedAt {
			threads = append(threads, cached)
			continue
		}
		var turns struct {
			Data []turnPayload `json:"data"`
		}
		if err := client.callLocked(ctx, "thread/turns/list", map[string]any{
			"threadId":      summary.ID,
			"limit":         20,
			"itemsView":     "notLoaded",
			"sortDirection": "desc",
		}, &turns); err != nil {
			client.terminateLocked()
			return nil, err
		}
		summary.Turns = turns.Data
		thread := summary.project()
		client.cache[thread.ID] = thread
		threads = append(threads, thread)
	}
	for id := range client.cache {
		if _, exists := current[id]; !exists {
			delete(client.cache, id)
		}
	}
	return threads, nil
}

// Close 停止客户端拥有的 app-server 子进程。
func (client *Client) Close() {
	client.mu.Lock()
	defer client.mu.Unlock()
	client.terminateLocked()
}

type threadPayload struct {
	ID        string        `json:"id"`
	Name      *string       `json:"name"`
	Preview   string        `json:"preview"`
	UpdatedAt int64         `json:"updatedAt"`
	Turns     []turnPayload `json:"turns"`
}

type turnPayload struct {
	ID          string     `json:"id"`
	Status      TurnStatus `json:"status"`
	CompletedAt *int64     `json:"completedAt"`
}

// project 将 app-server wire payload 收敛为完成检测所需的最小领域投影。
func (payload threadPayload) project() Thread {
	name := ""
	if payload.Name != nil {
		name = *payload.Name
	}
	thread := Thread{
		ID:        payload.ID,
		Name:      name,
		Preview:   payload.Preview,
		UpdatedAt: payload.UpdatedAt,
		Turns:     make([]Turn, 0, len(payload.Turns)),
	}
	for _, payload := range payload.Turns {
		completedAt := int64(0)
		if payload.CompletedAt != nil {
			completedAt = *payload.CompletedAt
		}
		thread.Turns = append(thread.Turns, Turn{
			ID:          payload.ID,
			Status:      payload.Status,
			CompletedAt: completedAt,
		})
	}
	return thread
}

// ensureStartedLocked 建立并初始化独立 app-server；调用方必须持有客户端锁。
func (client *Client) ensureStartedLocked(ctx context.Context) error {
	if client.command != nil {
		return nil
	}
	command := exec.Command(client.executable, "app-server", "--stdio")
	stdin, err := command.StdinPipe()
	if err != nil {
		return err
	}
	stdout, err := command.StdoutPipe()
	if err != nil {
		stdin.Close()
		return err
	}
	command.Stderr = io.Discard
	if err := command.Start(); err != nil {
		stdin.Close()
		return err
	}
	client.command = command
	client.stdin = stdin
	client.scanner = bufio.NewScanner(stdout)
	client.scanner.Buffer(make([]byte, 64*1024), 32*1024*1024)
	client.nextID = 0

	var initialized json.RawMessage
	if err := client.callLocked(ctx, "initialize", map[string]any{
		"clientInfo": map[string]any{
			"name":    "junimo",
			"title":   "Junimo",
			"version": "0.2.0",
		},
		"capabilities": map[string]any{"experimentalApi": true},
	}, &initialized); err != nil {
		return err
	}
	return json.NewEncoder(client.stdin).Encode(map[string]any{
		"method": "initialized",
		"params": map[string]any{},
	})
}

// callLocked 发送一个顺序 JSON-RPC 请求并跳过期间出现的通知。
func (client *Client) callLocked(ctx context.Context, method string, params any, result any) error {
	id := client.nextID
	client.nextID++
	if err := json.NewEncoder(client.stdin).Encode(map[string]any{
		"id":     id,
		"method": method,
		"params": params,
	}); err != nil {
		return err
	}
	response, err := client.readResponseLocked(ctx, id)
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

// readResponseLocked 支持调用超时；取消时会终止当前进程并由下一次扫描重连。
func (client *Client) readResponseLocked(ctx context.Context, responseID int) ([]byte, error) {
	result := make(chan scanResult, 1)
	scanner := client.scanner
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
		client.terminateLocked()
		return nil, ctx.Err()
	case response := <-result:
		return response.data, response.err
	}
}

// terminateLocked 清理失败或关闭后的进程句柄；调用方必须持有客户端锁。
func (client *Client) terminateLocked() {
	if client.stdin != nil {
		_ = client.stdin.Close()
	}
	if client.command != nil && client.command.Process != nil {
		_ = client.command.Process.Kill()
		_ = client.command.Wait()
	}
	client.command = nil
	client.stdin = nil
	client.scanner = nil
	client.nextID = 0
}
