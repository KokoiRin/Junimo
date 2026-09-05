package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"junimo/backend/internal/companion"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := companion.Run(ctx); err != nil {
		log.Fatal(err)
	}
}
