// Package pairingserver advertises this sender to receivers and answers a
// pairing attempt the receiver starts.
//
// The Android app lists "available hosts" from `_opendisplay-mac-pair._tcp`;
// advertising is what puts Linux in that list. The service record carries only
// a routing hint and an install ID. Trust still comes from the v13 ceremony:
// the code appears on the tablet, and this side accepts only after the user
// runs `extendpad confirm <code>` (or answers an interactive prompt).
package pairingserver

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/grandcat/zeroconf"

	"github.com/raiseCatError/ExtendPad/apps/linux/internal/config"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/identity"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/pairing"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/trust"
)

const ServiceType = "_opendisplay-mac-pair._tcp"

type Config struct {
	Identity *identity.Identity
	Trust    *trust.Store
	Name     string
	Log      func(string)
}

// Serve advertises and listens until the context ends.
func Serve(ctx context.Context, cfg Config) error {
	listener, err := net.Listen("tcp", ":0")
	if err != nil {
		return err
	}
	port := listener.Addr().(*net.TCPAddr).Port
	text := []string{
		"id=" + cfg.Identity.InstallID,
		"pv=22",
		"pp=" + strconv.Itoa(pairing.Version),
		"os=linux",
	}
	server, err := zeroconf.Register(cfg.Name, ServiceType, "local.", port, text, nil)
	if err != nil {
		_ = listener.Close()
		return err
	}
	defer server.Shutdown()
	defer listener.Close()

	cfg.Log(fmt.Sprintf("advertising %q for pairing on port %d", cfg.Name, port))
	go func() {
		<-ctx.Done()
		_ = listener.Close()
	}()

	limiter := &throttle{}
	semaphore := make(chan struct{}, 1) // one ceremony at a time
	var workers sync.WaitGroup
	for {
		conn, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil {
				workers.Wait()
				return nil
			}
			continue
		}
		if !limiter.admitted() {
			_ = conn.Close()
			continue
		}
		select {
		case semaphore <- struct{}{}:
		default:
			_ = conn.Close()
			continue
		}
		workers.Add(1)
		go func(c net.Conn) {
			defer workers.Done()
			defer func() { <-semaphore }()
			defer c.Close()
			_ = c.SetDeadline(time.Now().Add(pairing.Deadline))

			pending, err := pairing.RunResponder(c, pairing.Options{
				LocalID:      cfg.Identity.InstallID,
				LocalName:    cfg.Name,
				IdentitySPKI: cfg.Identity.SPKI(),
				Store:        cfg.Trust,
				Decide:       func(request pairing.Pending) bool { return confirm(request, cfg.Log) },
			})
			if err != nil {
				limiter.failed()
				cfg.Log("pairing failed: " + err.Error())
				return
			}
			limiter.succeeded()
			cfg.Log("paired with " + pending.PeerName)
		}(conn)
	}
}

// ------------------------------------------------------------ confirmation

func confirm(pending pairing.Pending, log func(string)) bool {
	if isTerminal() {
		return prompt(pending)
	}
	request := PendingRequest{
		Code:      pending.SAS,
		PeerName:  pending.PeerName,
		PeerID:    pending.PeerID,
		ExpiresAt: time.Now().Add(60 * time.Second).Unix(),
	}
	if err := writePending(request); err != nil {
		log("cannot record the pairing request: " + err.Error())
		return false
	}
	defer clearPending()
	log(fmt.Sprintf(
		"pairing request from %s: code %s — run \"extendpad confirm %s\" within 60 s",
		pending.PeerName, pending.SAS, NormalizeCode(pending.SAS),
	))

	deadline := time.Now().Add(60 * time.Second)
	for time.Now().Before(deadline) {
		decision, ok := readDecision()
		if ok {
			if !decision.Accept {
				return false
			}
			return NormalizeCode(decision.Code) == NormalizeCode(pending.SAS)
		}
		time.Sleep(200 * time.Millisecond)
	}
	log("pairing request timed out")
	return false
}

func prompt(pending pairing.Pending) bool {
	fmt.Println()
	fmt.Println("  +----------------------------------+")
	fmt.Printf("  |        code:  %s         |\n", pending.SAS)
	fmt.Println("  +----------------------------------+")
	fmt.Printf("  Pairing with %s.\n", pending.PeerName)
	fmt.Println("  Confirm the same code on the tablet, then answer here.")
	fmt.Print("  Do the codes match? [y/N] ")
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	answer := strings.ToLower(strings.TrimSpace(line))
	return answer == "y" || answer == "yes"
}

func isTerminal() bool {
	info, err := os.Stdin.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}

// ---------------------------------------------------------------- files

type PendingRequest struct {
	Code      string `json:"code"`
	PeerName  string `json:"peer_name"`
	PeerID    string `json:"peer_id"`
	ExpiresAt int64  `json:"expires_at"`
}

type Decision struct {
	Accept bool   `json:"accept"`
	Code   string `json:"code,omitempty"`
}

func directory() string { return filepath.Join(config.StateDir(), "pairing") }
func pendingPath() string { return filepath.Join(directory(), "pending.json") }
func decisionPath() string { return filepath.Join(directory(), "decision.json") }

func writePending(request PendingRequest) error {
	if err := os.MkdirAll(directory(), 0o700); err != nil {
		return err
	}
	return writeAtomic(pendingPath(), request)
}

func writeAtomic(path string, value any) error {
	raw, err := json.MarshalIndent(value, "", " ")
	if err != nil {
		return err
	}
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, raw, 0o600); err != nil {
		return err
	}
	return os.Rename(temporary, path)
}

func readPending() (PendingRequest, error) {
	var request PendingRequest
	raw, err := os.ReadFile(pendingPath())
	if err != nil {
		return request, err
	}
	err = json.Unmarshal(raw, &request)
	return request, err
}

func readDecision() (Decision, bool) {
	var decision Decision
	raw, err := os.ReadFile(decisionPath())
	if err != nil {
		return decision, false
	}
	if err := json.Unmarshal(raw, &decision); err != nil {
		return decision, false
	}
	return decision, true
}

// ReadPending returns the request waiting for local confirmation.
func ReadPending() (PendingRequest, error) { return readPending() }

// WriteDecision records the local answer for the waiting ceremony.
func WriteDecision(decision Decision) error {
	if err := os.MkdirAll(directory(), 0o700); err != nil {
		return err
	}
	return writeAtomic(decisionPath(), decision)
}

func clearPending() {
	_ = os.Remove(pendingPath())
	_ = os.Remove(decisionPath())
}

// NormalizeCode keeps only digits, so "123 456" and "123456" compare equal.
func NormalizeCode(code string) string {
	var digits strings.Builder
	for _, character := range code {
		if character >= '0' && character <= '9' {
			digits.WriteRune(character)
		}
	}
	return digits.String()
}

// --------------------------------------------------------------- throttle

type throttle struct {
	mutex     sync.Mutex
	failures  int
	cooldown  time.Time
}

func (t *throttle) admitted() bool {
	t.mutex.Lock()
	defer t.mutex.Unlock()
	return time.Now().After(t.cooldown)
}

func (t *throttle) failed() {
	t.mutex.Lock()
	defer t.mutex.Unlock()
	t.failures++
	if t.failures >= 3 {
		t.cooldown = time.Now().Add(30 * time.Second)
		t.failures = 0
	}
}

func (t *throttle) succeeded() {
	t.mutex.Lock()
	defer t.mutex.Unlock()
	t.failures = 0
}
