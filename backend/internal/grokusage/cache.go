// Package grokusage reads the desktop app's account-scoped weekly quota cache.
// It never reads credentials or changes Grok Bot's files.
package grokusage

import (
	"context"
	"crypto/sha256"
	"encoding/base32"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"junimo/backend/internal/codexusage"
)

type Client struct {
	settingsPath, cacheDir string
	now                    func() time.Time
}

func NewClient() *Client {
	home, _ := os.UserHomeDir()
	return &Client{filepath.Join(home, ".grokbot", "settings.json"), filepath.Join(home, "Library", "Application Support", "Grok Bot", "sand-client-persistence"), time.Now}
}

type settings struct {
	ActiveAccountScope string `json:"activeAccountScope"`
	SelectedTeam       *struct {
		TeamID       int64  `json:"teamId"`
		AccountScope string `json:"accountScope"`
	} `json:"selectedTeam"`
}

type cache struct {
	SchemaVersion int `json:"schemaVersion"`
	Value         struct {
		Kind           string `json:"kind"`
		SelectedTeamID *int64 `json:"selectedTeamId"`
		Reading        struct {
			Usage *struct {
				PercentUsed             *float64 `json:"percentUsed"`
				NextResetMs             *int64   `json:"nextResetMs"`
				HasNonZeroIncludedLimit bool     `json:"hasNonZeroIncludedLimit"`
			} `json:"usage"`
			ReadAtMs int64 `json:"readAtMs"`
		} `json:"reading"`
		ExpiresAtMs int64 `json:"expiresAtMs"`
	} `json:"value"`
}

func (c *Client) Query(ctx context.Context) (codexusage.Snapshot, error) {
	var config settings
	data, err := os.ReadFile(c.settingsPath)
	if err != nil || json.Unmarshal(data, &config) != nil || config.ActiveAccountScope == "" {
		return codexusage.Snapshot{}, errors.New("请打开并登录 Grok Bot，等待用量刷新")
	}
	entries, err := os.ReadDir(c.cacheDir)
	if err != nil {
		return codexusage.Snapshot{}, errors.New("尚未找到 Grok Bot 用量缓存，请打开 Usage & Billing")
	}
	for _, entry := range entries {
		if err := ctx.Err(); err != nil {
			return codexusage.Snapshot{}, err
		}
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".blob") {
			continue
		}
		decoded, err := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(strings.ToUpper(strings.TrimSuffix(entry.Name(), ".blob")))
		key := string(decoded)
		const prefix, suffix = "sand.client.slice.account.", ".weekly-usage.cache"
		if err != nil || !strings.HasPrefix(key, prefix) || !strings.HasSuffix(key, suffix) {
			continue
		}
		account, err := url.PathUnescape(strings.TrimSuffix(strings.TrimPrefix(key, prefix), suffix))
		if err != nil {
			continue
		}
		hash := sha256.Sum256([]byte(account))
		if hex.EncodeToString(hash[:]) != config.ActiveAccountScope {
			continue
		}
		data, err := os.ReadFile(filepath.Join(c.cacheDir, entry.Name()))
		if err != nil {
			return codexusage.Snapshot{}, errors.New("无法读取 Grok Bot 用量缓存")
		}
		snapshot, err := parse(data, config, c.now())
		if err != nil {
			return codexusage.Snapshot{}, err
		}
		// Recheck the selected account/team so an in-flight switch cannot show another account's quota.
		latest, err := os.ReadFile(c.settingsPath)
		var current settings
		if err != nil || json.Unmarshal(latest, &current) != nil || current.ActiveAccountScope != config.ActiveAccountScope || teamID(current) != teamID(config) {
			return codexusage.Snapshot{}, errors.New("Grok Bot 账户正在切换，等待用量刷新")
		}
		return snapshot, nil
	}
	return codexusage.Snapshot{}, errors.New("当前 Grok Bot 账户尚无用量缓存，请打开 Usage & Billing")
}

func teamID(s settings) int64 {
	if s.SelectedTeam != nil && s.SelectedTeam.AccountScope == s.ActiveAccountScope {
		return s.SelectedTeam.TeamID
	}
	return 0
}

func parse(data []byte, config settings, now time.Time) (codexusage.Snapshot, error) {
	var cached cache
	if json.Unmarshal(data, &cached) != nil || cached.SchemaVersion != 2 || cached.Value.Kind != "present" {
		return codexusage.Snapshot{}, errors.New("Grok Bot 用量缓存格式暂不支持")
	}
	v := cached.Value
	var selected int64
	if v.SelectedTeamID != nil {
		selected = *v.SelectedTeamID
	}
	if selected != teamID(config) {
		return codexusage.Snapshot{}, errors.New("Grok Bot 团队已切换，等待用量刷新")
	}
	u := v.Reading.Usage
	if u == nil || u.PercentUsed == nil || math.IsNaN(*u.PercentUsed) || math.IsInf(*u.PercentUsed, 0) || !u.HasNonZeroIncludedLimit {
		return codexusage.Snapshot{}, errors.New("Grok Bot 未提供可用的个人额度")
	}
	at := time.UnixMilli(v.Reading.ReadAtMs)
	if v.Reading.ReadAtMs <= 0 || at.After(now.Add(time.Minute)) || now.Sub(at) >= 24*time.Hour || v.ExpiresAtMs <= now.UnixMilli() || u.NextResetMs == nil || *u.NextResetMs <= now.UnixMilli() {
		return codexusage.Snapshot{}, errors.New("Grok Bot 用量缓存已过期，请打开 Usage & Billing 刷新")
	}
	remaining := int(math.Round(100 - math.Min(100, math.Max(0, *u.PercentUsed))))
	return codexusage.Snapshot{Status: codexusage.StatusAvailable, Primary: &codexusage.Window{RemainingPercent: remaining, WindowDurationMinutes: 7 * 24 * 60, ResetsAt: *u.NextResetMs / 1000}, RefreshedAt: at.UTC().Format(time.RFC3339), Message: "来自 Grok Bot 本机用量缓存，随原应用刷新"}, nil
}
