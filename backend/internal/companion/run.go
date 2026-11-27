package companion

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync/atomic"
	"time"

	"junimo/backend/internal/antigravity"
	"junimo/backend/internal/codexactivity"
	"junimo/backend/internal/codexappserver"
	"junimo/backend/internal/codexusage"
	"junimo/backend/internal/grokusage"
	"junimo/backend/internal/processwatch"
	"junimo/backend/internal/quota"
)

const (
	defaultPort             = "44832"
	usageRefreshInterval    = 30 * time.Second
	usageQueryTimeout       = 40 * time.Second
	activityRefreshInterval = 3 * time.Second
	activityQueryTimeout    = 20 * time.Second
	shutdownTimeout         = 5 * time.Second
)

// Run 装配并运行完整后端；调用方只负责提供进程生命周期。
func Run(ctx context.Context) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	if os.Getenv("JUNIMO_INSTANCE_ID") != "" {
		go cancelWhenParentExits(ctx, cancel, os.Getppid(), os.Getppid)
	}
	executable := codexappserver.ResolveExecutable()
	usageMonitor := quota.NewMonitor(codexusage.NewClient(executable))
	grokMonitor := quota.NewMonitor(grokusage.NewClient())
	activityMonitor := codexactivity.NewMonitor(codexactivity.NewClient(executable))
	monitorContext, stopMonitors := context.WithCancel(ctx)
	defer stopMonitors()
	usageMonitor.Start(monitorContext, usageRefreshInterval, usageQueryTimeout)
	grokMonitor.Start(monitorContext, usageRefreshInterval, usageQueryTimeout)
	activityMonitor.Start(monitorContext, activityRefreshInterval, activityQueryTimeout)

	var codexRunning atomic.Pointer[bool]
	var grokRunning atomic.Pointer[bool]
	codexWatcher := codexusage.NewProcessWatcher()
	grokWatcher := processwatch.New("Grok Bot")
	go func() {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for {
			probeCtx, cancel := context.WithTimeout(monitorContext, 1500*time.Millisecond)
			now := time.Now()
			codexRunning.Store(codexWatcher.IsRunning(probeCtx, now, false))
			grokRunning.Store(grokWatcher.IsRunning(probeCtx, now, false))
			cancel()
			select {
			case <-monitorContext.Done():
				return
			case <-ticker.C:
			}
		}
	}()
	codexSnapshot := func() quota.Snapshot {
		snapshot := usageMonitor.Snapshot()
		if running := codexRunning.Load(); running != nil {
			value := *running
			snapshot.IsAppRunning = &value
		}
		return snapshot
	}
	grokSnapshot := func() quota.Snapshot {
		snapshot := grokMonitor.Snapshot()
		if running := grokRunning.Load(); running != nil {
			value := *running
			snapshot.IsAppRunning = &value
		}
		return snapshot
	}

	var gravitySnapshot func() antigravity.Snapshot
	if home, err := os.UserHomeDir(); err == nil {
		gravity := antigravity.NewMonitor(antigravity.DesktopSource(home))
		weeklyQuota := quota.NewMonitor(antigravity.WeeklyQuota{DaemonDir: filepath.Join(home, ".gemini", "antigravity", "daemon")})
		weeklyQuota.Start(monitorContext, time.Minute, 8*time.Second)
		gravitySnapshot = func() antigravity.Snapshot {
			snapshot := gravity.Snapshot()
			weekly := weeklyQuota.Snapshot()
			snapshot.WeeklyQuota = &weekly
			return snapshot
		}
		go gravity.Run(monitorContext)
	}
	port := os.Getenv("JUNIMO_BACKEND_PORT")
	if port == "" {
		port = defaultPort
	}
	address := "127.0.0.1:" + port
	server := &http.Server{
		Addr:    address,
		Handler: newSurfaceHandler(codexSnapshot, activityMonitor.Snapshot, grokSnapshot, gravitySnapshot),
	}
	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("junimo backend listening on http://%s", address)
		serverErrors <- server.ListenAndServe()
	}()

	select {
	case err := <-serverErrors:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		shutdownContext, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		if err := server.Shutdown(shutdownContext); err != nil {
			return err
		}
		return nil
	}
}
