// Package codexusage adapts Codex app-server quota snapshots for Junimo's Go-owned product state.
// It does not expose Codex process or JSON-RPC details to the Swift shell.
package codexusage

import (
	"encoding/json"
	"errors"
)

type Status string

const (
	StatusLoading     Status = "loading"
	StatusAvailable   Status = "available"
	StatusUnavailable Status = "unavailable"
)

type Window struct {
	RemainingPercent      int   `json:"remainingPercent"`
	WindowDurationMinutes int   `json:"windowDurationMinutes"`
	ResetsAt              int64 `json:"resetsAt"`
}

type Snapshot struct {
	Status      Status  `json:"status"`
	Primary     *Window `json:"primary,omitempty"`
	Secondary   *Window `json:"secondary,omitempty"`
	Message     string  `json:"message,omitempty"`
	RefreshedAt string  `json:"refreshedAt,omitempty"`
}

type rateLimitWindow struct {
	UsedPercent        int   `json:"usedPercent"`
	WindowDurationMins int   `json:"windowDurationMins"`
	ResetsAt           int64 `json:"resetsAt"`
}

type rateLimitsResponse struct {
	Result struct {
		RateLimits struct {
			Primary   *rateLimitWindow `json:"primary"`
			Secondary *rateLimitWindow `json:"secondary"`
		} `json:"rateLimits"`
	} `json:"result"`
}

func ParseRateLimits(data []byte) (Snapshot, error) {
	var response rateLimitsResponse
	if err := json.Unmarshal(data, &response); err != nil {
		return Snapshot{}, err
	}
	if response.Result.RateLimits.Primary == nil {
		return Snapshot{}, errors.New("codex rate limit response has no primary window")
	}
	return Snapshot{
		Status:    StatusAvailable,
		Primary:   windowSnapshot(response.Result.RateLimits.Primary),
		Secondary: windowSnapshot(response.Result.RateLimits.Secondary),
	}, nil
}

func windowSnapshot(window *rateLimitWindow) *Window {
	if window == nil {
		return nil
	}
	remaining := 100 - window.UsedPercent
	if remaining < 0 {
		remaining = 0
	} else if remaining > 100 {
		remaining = 100
	}
	return &Window{
		RemainingPercent:      remaining,
		WindowDurationMinutes: window.WindowDurationMins,
		ResetsAt:              window.ResetsAt,
	}
}
