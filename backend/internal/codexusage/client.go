package codexusage

import (
	"context"
	"time"

	"junimo/backend/internal/codexappserver"
)

type Client struct {
	executable string
}

func NewClient(executable string) *Client {
	return &Client{executable: executable}
}

func (client *Client) Query(ctx context.Context) (Snapshot, error) {
	session := codexappserver.NewSession(client.executable)
	defer session.Close()
	var result rateLimitsResult
	if err := session.Call(ctx, "account/rateLimits/read", nil, &result); err != nil {
		return Snapshot{}, err
	}
	snapshot, err := snapshotFromRateLimits(result)
	if err != nil {
		return Snapshot{}, err
	}
	snapshot.RefreshedAt = time.Now().UTC().Format(time.RFC3339)
	return snapshot, nil
}
