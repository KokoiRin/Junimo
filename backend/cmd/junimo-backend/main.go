package main

import (
	"context"
	"log"

	"junimo/backend/internal/companion"
)

func main() {
	if err := companion.Run(context.Background()); err != nil {
		log.Fatal(err)
	}
}
