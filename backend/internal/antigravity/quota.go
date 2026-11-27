package antigravity

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"junimo/backend/internal/quota"
)

const quotaMethod = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"

type desktopHub struct {
	PID     int    `json:"pid"`
	Port    int    `json:"httpPort"`
	Session string `json:"csrfToken"`
}

// Read the desktop's own registration. A stale port must never receive a
// session header after it has been reassigned to a different local process.
func readHub(ctx context.Context, path string) (desktopHub, bool) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() > 8192 {
		return desktopHub{}, false
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || int(stat.Uid) != os.Getuid() {
		return desktopHub{}, false
	}
	data, err := os.ReadFile(path)
	var hub desktopHub
	if err != nil || json.Unmarshal(data, &hub) != nil || hub.PID <= 0 || hub.Port < 1 || hub.Port > 65535 || hub.Session == "" {
		return desktopHub{}, false
	}
	pid := strconv.Itoa(hub.PID)
	exe, err := exec.CommandContext(ctx, "/bin/ps", "-p", pid, "-o", "comm=").Output()
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(exe)), "/Antigravity.app/Contents/Resources/bin/language_server") {
		return desktopHub{}, false
	}
	return hub, true
}

// Bind the session header to the verified peer of this particular connection.
func (hub desktopHub) dial(ctx context.Context, network, address string) (net.Conn, error) {
	conn, err := (&net.Dialer{Timeout: 2 * time.Second}).DialContext(ctx, network, address)
	if err != nil {
		return nil, err
	}
	checkCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	peers, err := exec.CommandContext(checkCtx, "/usr/sbin/lsof", "-nP", "-a", "-p", strconv.Itoa(hub.PID), "-iTCP:"+strconv.Itoa(hub.Port), "-sTCP:ESTABLISHED", "-Fn").Output()
	want := "n" + conn.RemoteAddr().String() + "->" + conn.LocalAddr().String()
	for _, peer := range strings.Split(string(peers), "\n") {
		if err == nil && peer == want {
			return conn, nil
		}
	}
	conn.Close()
	return nil, errors.New("无法确认 Antigravity 本机连接")
}

type WeeklyQuota struct{ DaemonDir string }

func (q WeeklyQuota) Query(ctx context.Context) (quota.Snapshot, error) {
	paths, _ := filepath.Glob(filepath.Join(q.DaemonDir, "hub_*.json"))
	var active *desktopHub
	for _, path := range paths {
		hub, ok := readHub(ctx, path)
		if !ok {
			continue
		}
		if active != nil {
			return quota.Snapshot{}, errors.New("有多个 Antigravity 服务，暂时无法确认当前额度")
		}
		active = &hub
	}
	if active == nil {
		return quota.Snapshot{}, errors.New("等待 Antigravity 桌面服务")
	}
	address := net.JoinHostPort("127.0.0.1", strconv.Itoa(active.Port))
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "http://"+address+quotaMethod, strings.NewReader("{}"))
	if err != nil {
		return quota.Snapshot{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Connect-Protocol-Version", "1")
	req.Header.Set("X-Codeium-Csrf-Token", active.Session)
	client := http.Client{
		Transport:     &http.Transport{DialContext: active.dial, DisableKeepAlives: true},
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	res, err := client.Do(req)
	if err != nil {
		return quota.Snapshot{}, errors.New("未能读取 Antigravity 额度")
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return quota.Snapshot{}, errors.New("Antigravity 暂未提供额度")
	}
	return geminiWeekly(io.LimitReader(res.Body, 1<<20), time.Now())
}

func geminiWeekly(input io.Reader, now time.Time) (quota.Snapshot, error) {
	var payload struct {
		Response struct {
			Groups []struct {
				DisplayName string
				Buckets     []struct {
					BucketID          string
					Window            string
					RemainingFraction *float64
					ResetTime         time.Time
				}
			}
		}
	}
	if err := json.NewDecoder(input).Decode(&payload); err != nil {
		return quota.Snapshot{}, errors.New("无法读取 Antigravity 额度格式")
	}
	for _, group := range payload.Response.Groups {
		if !strings.EqualFold(group.DisplayName, "Gemini Models") {
			continue
		}
		for _, b := range group.Buckets {
			if b.BucketID != "gemini-weekly" || b.Window != "weekly" || b.RemainingFraction == nil || *b.RemainingFraction < 0 || *b.RemainingFraction > 1 || !b.ResetTime.After(now) {
				continue
			}
			return quota.Snapshot{
				Status:      quota.StatusAvailable,
				Primary:     &quota.Window{RemainingPercent: int(math.Round(*b.RemainingFraction * 100)), WindowDurationMinutes: 7 * 24 * 60, ResetsAt: b.ResetTime.Unix()},
				RefreshedAt: now.UTC().Format(time.RFC3339),
			}, nil
		}
	}
	return quota.Snapshot{}, errors.New("未找到当前 Gemini 每周额度")
}
