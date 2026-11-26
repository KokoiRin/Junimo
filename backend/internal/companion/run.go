package companion

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"junimo/backend/internal/antigravity"
	"junimo/backend/internal/codexactivity"
	"junimo/backend/internal/codexappserver"
	"junimo/backend/internal/codexusage"
	"junimo/backend/internal/grokusage"
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
	usageMonitor := codexusage.NewMonitor(codexusage.NewClient(executable))
	grokMonitor := codexusage.NewMonitor(grokusage.NewClient())
	activityMonitor := codexactivity.NewMonitor(codexactivity.NewClient(executable))
	monitorContext, stopMonitors := context.WithCancel(ctx)
	defer stopMonitors()
	usageMonitor.Start(monitorContext, usageRefreshInterval, usageQueryTimeout)
	grokMonitor.Start(monitorContext, usageRefreshInterval, usageQueryTimeout)
	activityMonitor.Start(monitorContext, activityRefreshInterval, activityQueryTimeout)

	var gravitySnapshot func() antigravity.Snapshot
	if home, err := os.UserHomeDir(); err == nil {
		gravity := antigravity.NewMonitor(antigravity.DesktopSource(home))
		quota := codexusage.NewMonitor(antigravity.WeeklyQuota{DaemonDir: filepath.Join(home, ".gemini", "antigravity", "daemon")})
		quota.Start(monitorContext, time.Minute, 8*time.Second)
		gravitySnapshot = func() antigravity.Snapshot {
			snapshot := gravity.Snapshot()
			weekly := quota.Snapshot()
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
		Handler: newSurfaceHandler(usageMonitor.Snapshot, activityMonitor.Snapshot, grokMonitor.Snapshot, gravitySnapshot),
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
