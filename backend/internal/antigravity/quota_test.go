package antigravity

import (
	"strings"
	"testing"
	"time"
)

// 即使 Claude 周额度和 Gemini 五小时额度排在前面，也只取 Gemini 的周剩余比例，保留重置时间并四舍五入。
func TestGeminiWeeklyUsesNamedBucket(t *testing.T) {
	const payload = `{"response":{"groups":[
        {"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","window":"weekly","remainingFraction":0.41,"resetTime":"2026-12-01T07:01:38Z"}]},
        {"displayName":"Gemini Models","buckets":[
            {"bucketId":"gemini-5h","window":"5h","remainingFraction":0.89,"resetTime":"2026-11-25T13:00:00Z"},
            {"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0.9229138,"resetTime":"2026-12-01T07:01:38Z"}]}]}}`
	now := time.Date(2026, 11, 25, 12, 0, 0, 0, time.UTC)
	got, err := geminiWeekly(strings.NewReader(payload), now)
	reset := time.Date(2026, 12, 1, 7, 1, 38, 0, time.UTC)
	if err != nil || got.Primary == nil || got.Primary.RemainingPercent != 92 || got.Primary.WindowDurationMinutes != 10080 || got.Primary.ResetsAt != reset.Unix() {
		t.Fatalf("snapshot=%+v error=%v", got, err)
	}
}

// 零和满额都是有效读数，缺少比例、错误窗口、越界数值、过期结果和尚未返回的 Gemini 模型组都显示未知。
func TestGeminiWeeklyUnknownAndLimits(t *testing.T) {
	const base = `{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0,"resetTime":"2030-01-01T00:00:00Z"}]}]}}`
	now := time.Unix(1700000000, 0)
	for _, tc := range []struct {
		from, to string
		want     int
	}{
		{"", "", 0}, {":0,", ":1,", 100},
		{"remainingFraction", "otherField", -1}, {"gemini-weekly", "gemini-5h", -1}, {"Gemini Models", "Claude and GPT models", -1},
		{":0,", ":1.1,", -1}, {"2030-", "2000-", -1},
	} {
		payload := base
		if tc.from != "" {
			payload = strings.ReplaceAll(base, tc.from, tc.to)
		}
		got, err := geminiWeekly(strings.NewReader(payload), now)
		if tc.want < 0 {
			if err == nil || got.Primary != nil {
				t.Fatal("expected unknown", got)
			}
			continue
		}
		if err != nil || got.Primary == nil || got.Primary.RemainingPercent != tc.want {
			t.Fatal("unexpected percentage", got, err)
		}
	}
}
