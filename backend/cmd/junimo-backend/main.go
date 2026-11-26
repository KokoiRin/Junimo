package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"junimo/backend/internal/antigravity"
	"junimo/backend/internal/companion"
)

func main() {
	if len(os.Args) > 1 {
		if len(os.Args) != 2 || os.Args[1] != "antigravity-stop" {
			os.Exit(2)
		}

		if home, err := os.UserHomeDir(); err == nil {
			_ = antigravity.DesktopSource(home).RecordStop(os.Stdin)
		}
		fmt.Println(`{"decision":"allow"}`)
		return
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := companion.Run(ctx); err != nil {
		log.Fatal(err)
	}
}
