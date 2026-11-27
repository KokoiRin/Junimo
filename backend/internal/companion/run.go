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

	stateNotifier := newChangeNotifier()
	usageMonitor.SetOnChange(stateNotifier.Notify)
	grokMonitor.SetOnChange(stateNotifier.Notify)
	activityMonitor.SetOnChange(stateNotifier.Notify)

	codexUsageGate := newAgentGate(monitorContext, func(runCtx context.Context) {
		usageMonitor.Run(runCtx, usageRefreshInterval, usageQueryTimeout)
	}, nil)
	codexActivityGate := newAgentGate(monitorContext, func(runCtx context.Context) {
		activityMonitor.Run(runCtx, activityRefreshInterval, activityQueryTimeout)
	}, activityMonitor.SetIdle)
	grokGate := newAgentGate(monitorContext, func(runCtx context.Context) {
		grokMonitor.Run(runCtx, usageRefreshInterval, usageQueryTimeout)
	}, nil)
	defer func() {
		codexUsageGate.Stop()
		codexActivityGate.Stop()
		grokGate.Stop()
	}()

	var codexRunning atomic.Pointer[bool]
	var grokRunning atomic.Pointer[bool]
	codexWatcher := codexusage.NewProcessWatcher()
	grokWatcher := processwatch.New("Grok Bot")

	updatePresence := func(probeCtx context.Context) {
		now := time.Now()
		prevCodex := codexRunning.Load()
		nextCodex := codexWatcher.IsRunning(probeCtx, now, false)
		codexRunning.Store(nextCodex)
		codexActive := nextCodex != nil && *nextCodex
		codexUsageGate.SetActive(codexActive)
		codexActivityGate.SetActive(codexActive)

		prevGrok := grokRunning.Load()
		nextGrok := grokWatcher.IsRunning(probeCtx, now, false)
		grokRunning.Store(nextGrok)
		grokGate.SetActive(nextGrok != nil && *nextGrok)

		if !boolPtrEqual(prevCodex, nextCodex) || !boolPtrEqual(prevGrok, nextGrok) {
			stateNotifier.Notify()
		}
	}
	go func() {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for {
			probeCtx, cancel := context.WithTimeout(monitorContext, 1500*time.Millisecond)
			updatePresence(probeCtx)
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
	var gravityQuotaGate *agentGate
	if home, err := os.UserHomeDir(); err == nil {
		gravity := antigravity.NewMonitor(antigravity.DesktopSource(home))
		weeklyQuota := quota.NewMonitor(antigravity.WeeklyQuota{DaemonDir: filepath.Join(home, ".gemini", "antigravity", "daemon")})
		gravity.SetOnChange(stateNotifier.Notify)
		weeklyQuota.SetOnChange(stateNotifier.Notify)
		gravityQuotaGate = newAgentGate(monitorContext, func(runCtx context.Context) {
			weeklyQuota.Run(runCtx, time.Minute, 8*time.Second)
		}, nil)
		defer gravityQuotaGate.Stop()
		gravity.SetOnRunningChange(gravityQuotaGate.SetActive)
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
		Handler: newSurfaceHandlerWithLifecycle(codexSnapshot, activityMonitor.Snapshot, grokSnapshot, gravitySnapshot, stateNotifier, ctx.Done()),
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

func boolPtrEqual(a, b *bool) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}
