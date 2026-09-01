package codexactivity

import (
	"context"
	"sync"

	"junimo/backend/internal/codexappserver"
)

const recentThreadLimit = 12

// Client 通过一个长生命周期 Codex app-server 读取最近会话的持久化 turn 状态。
type Client struct {
	mu      sync.Mutex
	session *codexappserver.Session
	cache   map[string]Thread
}

// NewClient 创建延迟启动的活动读取客户端。
func NewClient(executable string) *Client {
	return &Client{
		session: codexappserver.NewSession(executable),
		cache:   make(map[string]Thread),
	}
}

// Scan 返回最近线程及其在本次更新时间对应的 turn 投影。
func (client *Client) Scan(ctx context.Context) ([]Thread, error) {
	client.mu.Lock()
	defer client.mu.Unlock()
	var listed struct {
		Data []threadPayload `json:"data"`
	}
	if err := client.session.Call(ctx, "thread/list", map[string]any{
		"limit":         recentThreadLimit,
		"sortKey":       "updated_at",
		"sortDirection": "desc",
	}, &listed); err != nil {
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
		if err := client.session.Call(ctx, "thread/turns/list", map[string]any{
			"threadId":      summary.ID,
			"limit":         20,
			"itemsView":     "notLoaded",
			"sortDirection": "desc",
		}, &turns); err != nil {
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
	client.session.Close()
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
