package companion

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"time"

	"junimo/backend/internal/codexactivity"
	"junimo/backend/internal/codexappserver"
	"junimo/backend/internal/codexusage"
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
	executable := codexappserver.ResolveExecutable()
	usageMonitor := codexusage.NewMonitor(codexusage.NewClient(executable))
	activityMonitor := codexactivity.NewMonitor(codexactivity.NewClient(executable))
	monitorContext, stopMonitors := context.WithCancel(ctx)
	defer stopMonitors()
	usageMonitor.Start(monitorContext, usageRefreshInterval, usageQueryTimeout)
	activityMonitor.Start(monitorContext, activityRefreshInterval, activityQueryTimeout)

	port := os.Getenv("JUNIMO_BACKEND_PORT")
	if port == "" {
		port = defaultPort
	}
	address := "127.0.0.1:" + port
	server := &http.Server{
		Addr:    address,
		Handler: newHandler(usageMonitor.Snapshot, activityMonitor.Snapshot),
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
