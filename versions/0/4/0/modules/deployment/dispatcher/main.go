// bnox-deploy-dispatcher (D-013, D-018): the sole subscriber to host.deploy.>.
// "changed" starts <thing>-sync.service, "synced" starts <thing>-build.service.
// Go instead of the 0/3 nats-py script: nats-py could not do nkey auth (pypi
// nkeys broken on python 3.13). Origin: bnox-bg agenthub deploy-bridge.
package main

import (
	"log"
	"os"
	"os/exec"
	"context"
	"strings"
	"time"

	"github.com/nats-io/nats.go"
)

var eventSuffix = map[string]string{
	"changed": "-sync.service",
	"synced":  "-build.service",
}

func handle(m *nats.Msg) {
	parts := strings.Split(m.Subject, ".")
	if len(parts) != 4 || parts[0] != "host" || parts[1] != "deploy" {
		log.Printf("ignoring malformed subject %s", m.Subject)
		return
	}
	thing, event := parts[2], parts[3]
	if strings.Contains(thing, "_bnox_validate_") {
		return // bnox-validate permission probe, not a deploy
	}
	if !validName(thing) {
		log.Printf("rejecting bad thing name in %s", m.Subject)
		return
	}
	suffix, ok := eventSuffix[event]
	if !ok {
		return
	}
	target := thing + suffix
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	if out, err := exec.CommandContext(ctx, "systemctl", "start", target).CombinedOutput(); err != nil {
		log.Printf("systemctl start %s failed: %s", target, strings.TrimSpace(string(out)))
	}
}

func validName(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
		default:
			return false
		}
	}
	return true
}

func main() {
	url := getenv("NATS_URL", "nats://127.0.0.1:4222")
	seedFile := os.Getenv("NATS_NKEY")
	if seedFile == "" {
		log.Fatal("NATS_NKEY (seed file path) is required")
	}
	nkeyOpt, err := nats.NkeyOptionFromSeed(seedFile)
	if err != nil {
		log.Fatalf("seed: %v", err)
	}

	log.SetFlags(log.LstdFlags | log.Lmsgprefix)
	log.SetPrefix("dispatcher: ")

	nc, err := nats.Connect(url,
		nats.Name("bnox-deploy-dispatcher"),
		nkeyOpt,
		nats.MaxReconnects(-1),
	)
	if err != nil {
		log.Fatalf("connect: %v", err)
	}
	defer nc.Drain()

	if _, err := nc.Subscribe("host.deploy.>", handle); err != nil {
		log.Fatalf("subscribe: %v", err)
	}
	if err := nc.Flush(); err != nil {
		log.Fatalf("flush: %v", err)
	}
	log.Printf("connected to %s, watching host.deploy.>", url)

	select {} // until systemd stops us (SIGTERM default disposition)
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
