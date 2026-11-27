// Package codexusage adapts Codex app-server quota snapshots into Junimo's shared quota contract.
// It does not expose Codex process or JSON-RPC details to the Swift shell.
package codexusage

import (
	"encoding/json"
	"errors"

	"junimo/backend/internal/quota"
)

type rateLimitWindow struct {
	UsedPercent        int   `json:"usedPercent"`
	WindowDurationMins int   `json:"windowDurationMins"`
	ResetsAt           int64 `json:"resetsAt"`
}

type rateLimitsResponse struct {
	Result rateLimitsResult `json:"result"`
}

type rateLimitsResult struct {
	RateLimits struct {
		Primary   *rateLimitWindow `json:"primary"`
		Secondary *rateLimitWindow `json:"secondary"`
	} `json:"rateLimits"`
}

func ParseRateLimits(data []byte) (quota.Snapshot, error) {
	var response rateLimitsResponse
	if err := json.Unmarshal(data, &response); err != nil {
		return quota.Snapshot{}, err
	}
	return snapshotFromRateLimits(response.Result)
}

func snapshotFromRateLimits(result rateLimitsResult) (quota.Snapshot, error) {
	if result.RateLimits.Primary == nil {
		return quota.Snapshot{}, errors.New("codex rate limit response has no primary window")
	}
	return quota.Snapshot{
		Status:    quota.StatusAvailable,
		Primary:   windowSnapshot(result.RateLimits.Primary),
		Secondary: windowSnapshot(result.RateLimits.Secondary),
	}, nil
}

func windowSnapshot(window *rateLimitWindow) *quota.Window {
	if window == nil {
		return nil
	}
	remaining := 100 - window.UsedPercent
	if remaining < 0 {
		remaining = 0
	} else if remaining > 100 {
		remaining = 100
	}
	return &quota.Window{
		RemainingPercent:      remaining,
		WindowDurationMinutes: window.WindowDurationMins,
		ResetsAt:              window.ResetsAt,
	}
}
