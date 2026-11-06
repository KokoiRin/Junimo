package grokusage

import (
	"context"
	"crypto/sha256"
	"encoding/base32"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

var testNow = time.Unix(1800000000, 0)

func fixture(t *testing.T, change func(map[string]any)) []byte {
	t.Helper()
	data := map[string]any{"schemaVersion": 2, "value": map[string]any{"kind": "present", "selectedTeamId": nil, "reading": map[string]any{"usage": map[string]any{"percentUsed": 84.5287, "nextResetMs": testNow.Add(time.Hour).UnixMilli(), "hasNonZeroIncludedLimit": true}, "readAtMs": testNow.Add(-time.Minute).UnixMilli()}, "expiresAtMs": testNow.Add(time.Hour).UnixMilli()}}
	if change != nil {
		change(data)
	}
	encoded, err := json.Marshal(data)
	if err != nil {
		t.Fatal(err)
	}
	return encoded
}

// 当前账户缓存记录已用 84.5287% 时，应按周额度显示剩余 15%，并保留原应用的采样时间。
func TestParseWeeklyRemaining(t *testing.T) {
	s, err := parse(fixture(t, nil), settings{}, testNow)
	if err != nil || s.Primary == nil || s.Primary.RemainingPercent != 15 || s.Primary.WindowDurationMinutes != 10080 || s.RefreshedAt != testNow.Add(-time.Minute).UTC().Format(time.RFC3339) {
		t.Fatalf("snapshot=%+v err=%v", s, err)
	}
}

// 缓存过期、跨过重置时间、采样时间异常、格式改变、缺少额度或团队不匹配时，都不能继续显示旧百分比。
func TestRejectUnusableCache(t *testing.T) {
	for _, name := range []string{"expired", "reset", "old", "future", "version", "absent", "null-percent", "no-limit", "team", "broken"} {
		t.Run(name, func(t *testing.T) {
			data := fixture(t, func(d map[string]any) {
				v := d["value"].(map[string]any)
				r := v["reading"].(map[string]any)
				u := r["usage"].(map[string]any)
				switch name {
				case "expired":
					v["expiresAtMs"] = testNow.UnixMilli()
				case "reset":
					u["nextResetMs"] = testNow.UnixMilli()
				case "old":
					r["readAtMs"] = testNow.Add(-24 * time.Hour).UnixMilli()
				case "future":
					r["readAtMs"] = testNow.Add(time.Hour).UnixMilli()
				case "version":
					d["schemaVersion"] = 3
				case "absent":
					v["kind"] = "absent"
				case "null-percent":
					delete(u, "percentUsed")
				case "no-limit":
					u["hasNonZeroIncludedLimit"] = false
				case "team":
					v["selectedTeamId"] = 4
				}
			})
			if name == "broken" {
				data = []byte("{")
			}
			if _, err := parse(data, settings{}, testNow); err == nil {
				t.Fatal("invalid cache accepted")
			}
		})
	}
}

// 已用比例为零、超过上限或略低于零时，剩余额度分别保持 100%、0% 和 100%，不会越界。
func TestClampPercent(t *testing.T) {
	for _, tc := range []struct {
		used float64
		want int
	}{{0, 100}, {150, 0}, {-1, 100}} {
		data := fixture(t, func(d map[string]any) {
			d["value"].(map[string]any)["reading"].(map[string]any)["usage"].(map[string]any)["percentUsed"] = tc.used
		})
		s, err := parse(data, settings{}, testNow)
		if err != nil || s.Primary.RemainingPercent != tc.want {
			t.Fatalf("used=%v snapshot=%+v err=%v", tc.used, s, err)
		}
	}
}

// 多个账户各有缓存时，只读取当前已选账户；账户退出或切换到没有缓存的账户后，不沿用其他人的额度。
func TestQueryMatchesActiveAccount(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, "settings.json")
	scope := "grok|user_test"
	hash := sha256.Sum256([]byte(scope))
	active := hex.EncodeToString(hash[:])
	c := &Client{configPath, dir, func() time.Time { return testNow }}
	key := "sand.client.slice.account.grok%7Cuser_test.weekly-usage.cache"
	file := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString([]byte(key)) + ".blob"
	if err := os.WriteFile(filepath.Join(dir, file), fixture(t, nil), 0600); err != nil {
		t.Fatal(err)
	}
	for _, account := range []string{active, "another-account", ""} {
		data, _ := json.Marshal(settings{ActiveAccountScope: account})
		if err := os.WriteFile(configPath, data, 0600); err != nil {
			t.Fatal(err)
		}
		snapshot, err := c.Query(context.Background())
		if account == active {
			if err != nil || snapshot.Primary.RemainingPercent != 15 {
				t.Fatalf("snapshot=%+v err=%v", snapshot, err)
			}
		} else if err == nil {
			t.Fatal("another account's quota was accepted")
		}
	}
}
