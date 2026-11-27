package codexusage

import (
	"context"
	"time"

	"junimo/backend/internal/codexappserver"
	"junimo/backend/internal/quota"
)

// Client 复用长生命周期 Codex app-server 会话查询额度，避免每次刷新重复启停子进程。
type Client struct {
	session *codexappserver.Session
}

func NewClient(executable string) *Client {
	return &Client{session: codexappserver.NewSession(executable)}
}

func (client *Client) Query(ctx context.Context) (quota.Snapshot, error) {
	var result rateLimitsResult
	if err := client.session.Call(ctx, "account/rateLimits/read", nil, &result); err != nil {
		return quota.Snapshot{}, err
	}
	snapshot, err := snapshotFromRateLimits(result)
	if err != nil {
		return quota.Snapshot{}, err
	}
	snapshot.RefreshedAt = time.Now().UTC().Format(time.RFC3339)
	return snapshot, nil
}

// Close 停止客户端持有的 app-server 子进程。
func (client *Client) Close() {
	client.session.Close()
}
