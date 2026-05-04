package main

import (
	"log"
	"net/http"
)

func main() {
	cfg := loadConfig()
	app, err := newApp(cfg)
	if err != nil {
		log.Fatal(err)
	}

	log.Printf("silverpear backend listening on %s", cfg.Addr)
	if err := http.ListenAndServe(cfg.Addr, app.routes()); err != nil {
		log.Fatal(err)
	}
}
