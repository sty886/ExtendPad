// Command extendpad shows this Linux desktop on an ExtendPad receiver.
//
// Pair once with a six-digit code, then run (or let the systemd service run)
// while the receiver is reachable. Wi-Fi and USB differ only in how a TCP
// connection to the receiver's pinned TLS listener is obtained.
package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/raiseCatError/ExtendPad/apps/linux/internal/config"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/discovery"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/display"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/identity"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/knock"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/pairing"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/pairingserver"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/session"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/trust"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/usb"
)

var version = "0.1.0"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "pair":
		err = commandPair(os.Args[2:])
	case "serve":
		err = commandServe(os.Args[2:])
	case "confirm":
		err = commandConfirm(os.Args[2:])
	case "reject":
		err = commandReject(os.Args[2:])
	case "run":
		err = commandRun(os.Args[2:])
	case "devices":
		err = commandDevices(os.Args[2:])
	case "forget":
		err = commandForget(os.Args[2:])
	case "doctor":
		err = commandDoctor(os.Args[2:])
	case "status":
		err = commandStatus(os.Args[2:])
	case "version", "--version", "-v":
		fmt.Println(version)
	case "help", "--help", "-h":
		usage()
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		logf("%v", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `usage: extendpad <command> [flags]

  pair      pair with a receiver (six-digit code on both screens)
  serve     advertise for pairing (receiver-initiated)
  confirm   accept a waiting pairing request: confirm <code>
  reject    decline a waiting pairing request
  run       stream and reconnect
  devices   list paired receivers
  forget    forget a paired receiver
  doctor    check ffmpeg, X, identity and pins
  status    show saved settings
  version   print the version`)
}

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[%s] %s\n", time.Now().Format("15:04:05"), fmt.Sprintf(format, args...))
}

func loadIdentity() (*identity.Identity, error) {
	return identity.LoadOrCreate(config.IdentityDir())
}

func loadTrust() (*trust.Store, error) {
	return trust.Load(config.PinsPath())
}

// ---------------------------------------------------------------- pair

func commandPair(arguments []string) error {
	flags := flag.NewFlagSet("pair", flag.ContinueOnError)
	host := flags.String("host", "", "receiver address")
	peerID := flags.String("id", "", "receiver install id")
	overUSB := flags.Bool("usb", false, "pair over adb")
	serial := flags.String("serial", "", "adb device serial")
	name := flags.String("name", "", "the name shown on the tablet")
	if err := flags.Parse(arguments); err != nil {
		return err
	}

	id, err := loadIdentity()
	if err != nil {
		return err
	}
	pins, err := loadTrust()
	if err != nil {
		return err
	}

	var forward *usb.Forward
	targetHost := *host
	targetPort := 9002
	expected := *peerID
	if *overUSB {
		forward, err = usb.Open(9002, *serial)
		if err != nil {
			return fmt.Errorf("USB: %w", err)
		}
		defer forward.Close()
		targetHost = "127.0.0.1"
		targetPort = forward.LocalPort
	} else {
		targetHost, expected, err = chooseReceiver(targetHost, expected, 4*time.Second)
		if err != nil {
			return err
		}
	}

	logf("pairing with %s:%d", targetHost, targetPort)
	logf("both screens must show the same six-digit code")

	conn, err := net.DialTimeout("tcp", net.JoinHostPort(targetHost, strconv.Itoa(targetPort)), 10*time.Second)
	if err != nil {
		return fmt.Errorf("pairing failed: %w", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(pairing.Deadline))

	localName := *name
	if localName == "" {
		localName = localNameForHost()
	}
	pending, err := pairing.RunInitiator(conn, pairing.Options{
		LocalID:        id.InstallID,
		LocalName:      localName,
		IdentitySPKI:   id.SPKI(),
		Store:          pins,
		ExpectedPeerID: expected,
		Decide:         confirmSAS,
	})
	if err != nil {
		return fmt.Errorf("pairing failed: %w", err)
	}

	logf("paired with %s", pending.PeerName)
	settings := config.Load()
	settings.PeerID = pending.PeerID
	if *overUSB {
		settings.USB = true
		settings.Host = ""
		logf("saved USB as the default transport")
	} else {
		settings.USB = false
		settings.Host = targetHost
		logf("saved default receiver %s", targetHost)
	}
	return settings.Save()
}

func confirmSAS(pending pairing.Pending) bool {
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

func localNameForHost() string {
	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		hostname = "Linux"
	}
	name := "Ubuntu (" + hostname + ")"
	if len([]rune(name)) > 128 {
		name = string([]rune(name)[:128])
	}
	return name
}

// --------------------------------------------------------------- serve

func commandServe(arguments []string) error {
	flags := flag.NewFlagSet("serve", flag.ContinueOnError)
	name := flags.String("name", "", "the name shown on receivers")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	id, err := loadIdentity()
	if err != nil {
		return err
	}
	pins, err := loadTrust()
	if err != nil {
		return err
	}
	instance := *name
	if instance == "" {
		instance = localNameForHost()
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return pairingserver.Serve(ctx, pairingserver.Config{
		Identity: id,
		Trust:    pins,
		Name:     instance,
		Log:      func(message string) { logf("%s", message) },
	})
}

func commandConfirm(arguments []string) error {
	flags := flag.NewFlagSet("confirm", flag.ContinueOnError)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if flags.NArg() != 1 {
		return errors.New("usage: extendpad confirm <code>")
	}
	request, err := pairingserver.ReadPending()
	if err != nil {
		return errors.New("no pairing request is waiting")
	}
	if time.Now().Unix() > request.ExpiresAt {
		return errors.New("the pairing request has expired")
	}
	if pairingserver.NormalizeCode(flags.Arg(0)) != pairingserver.NormalizeCode(request.Code) {
		return errors.New("the code does not match; run `extendpad reject` to decline")
	}
	if err := pairingserver.WriteDecision(pairingserver.Decision{Accept: true, Code: request.Code}); err != nil {
		return err
	}
	fmt.Println("confirmed")
	return nil
}

func commandReject(arguments []string) error {
	if err := flag.NewFlagSet("reject", flag.ContinueOnError).Parse(arguments); err != nil {
		return err
	}
	if err := pairingserver.WriteDecision(pairingserver.Decision{Accept: false}); err != nil {
		return err
	}
	fmt.Println("rejected")
	return nil
}

func chooseReceiver(host, peerID string, timeout time.Duration) (string, string, error) {
	if host != "" {
		return host, peerID, nil
	}
	receivers, err := discovery.Browse(context.Background(), timeout)
	if err != nil {
		return "", "", fmt.Errorf("discovery: %w", err)
	}
	if len(receivers) == 0 {
		return "", "", errors.New("no receiver found on this network; pass --host, or connect the tablet over USB")
	}
	if peerID != "" {
		for _, receiver := range receivers {
			if receiver.InstallID == peerID {
				return receiver.Host, peerID, nil
			}
		}
		return "", "", fmt.Errorf("%s is not advertised on this network", peerID)
	}
	if len(receivers) > 1 {
		for _, receiver := range receivers {
			fmt.Fprintln(os.Stderr, "  "+receiver.Label())
		}
		return "", "", errors.New("more than one receiver found; pass --host or --id")
	}
	return receivers[0].Host, receivers[0].InstallID, nil
}

// ----------------------------------------------------------------- run

func commandRun(arguments []string) error {
	flags := flag.NewFlagSet("run", flag.ContinueOnError)
	host := flags.String("host", "", "receiver address (overrides saved)")
	peerID := flags.String("peer-id", "", "paired receiver id")
	overUSB := flags.Bool("usb", false, "use adb forward")
	serial := flags.String("serial", "", "adb device serial")
	mode := flags.String("mode", "", "mirror or extend")
	fps := flags.Int("fps", 0, "frames per second")
	bitrate := flags.String("bitrate", "", "e.g. 6M")
	preset := flags.String("preset", "", "ultrafast, superfast, veryfast or faster")
	displayName := flags.String("display", "", "X display, e.g. :2")
	noInput := flags.Bool("no-input", false, "view only")
	allowInput := flags.Bool("allow-input", false, "grant input")
	once := flags.Bool("once", false, "exit when the session ends")
	if err := flags.Parse(arguments); err != nil {
		return err
	}

	settings := config.Load()
	if *host != "" {
		settings.Host = *host
		settings.USB = false
	}
	if *overUSB {
		settings.USB = true
	}
	if *mode != "" {
		if *mode != "mirror" && *mode != "extend" {
			return errors.New("--mode must be mirror or extend")
		}
		settings.Mode = *mode
	}
	if *fps != 0 {
		settings.FPS = *fps
	}
	if *bitrate != "" {
		settings.Bitrate = *bitrate
	}
	if *preset != "" {
		settings.Preset = *preset
	}
	if *displayName != "" {
		settings.Display = *displayName
	}
	if *noInput {
		settings.AllowInput = false
	}
	if *allowInput {
		settings.AllowInput = true
	}
	if *once {
		settings.Autostart = false
	}

	id, err := loadIdentity()
	if err != nil {
		return err
	}
	pins, err := loadTrust()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Advertising, receiver-initiated pairing and the wake listener live with
	// the sender: the tablet can always find this host and wake it even when no
	// session is running.
	wake := make(chan knock.Request, 1)
	go func() {
		err := pairingserver.Serve(ctx, pairingserver.Config{
			Identity: id,
			Trust:    pins,
			Name:     localNameForHost(),
			Log:      func(message string) { logf("%s", message) },
		})
		if err != nil && ctx.Err() == nil {
			logf("pairing service: %v", err)
		}
	}()
	go func() {
		err := knock.Listen(ctx, knock.Config{
			Identity: id,
			Trust:    pins,
			Log:      func(message string) { logf("%s", message) },
		}, wake)
		if err != nil && ctx.Err() == nil {
			logf("wake service: %v", err)
		}
	}()
	go func() {
		err := discovery.Watch(ctx, func(receiver discovery.Receiver) {
			if pins.Pin(receiver.InstallID) == nil {
				return
			}
			// The receiver's Connect names the sender its user asked for. This
			// host must not dial just because another paired sender (say, the
			// Mac) was requested; it would replace the session the user wanted.
			if !receiver.AskedFor(id.InstallID) {
				logf("connect request from %s is for another sender; ignoring", receiver.Name)
				return
			}
			logf("connect request from %s", receiver.Name)
			select {
			case wake <- knock.Request{PeerID: receiver.InstallID, RemoteIP: receiver.Host, Intent: "manual"}:
			default:
			}
		})
		if err != nil && ctx.Err() == nil {
			logf("discovery service: %v", err)
		}
	}()

	var forward *usb.Forward
	targetHost := settings.Host
	targetPort := 9001
	if settings.USB {
		forward, err = usb.Open(9001, *serial)
		if err != nil {
			return fmt.Errorf("USB: %w", err)
		}
		defer forward.Close()
		targetHost = "127.0.0.1"
		targetPort = forward.LocalPort
	}

	requestedPeer := firstNonEmpty(*peerID, settings.PeerID)
	targetPeer, err := optionalPeer(pins, requestedPeer)
	if err != nil {
		return err
	}
	if targetPeer != "" && !settings.USB && targetHost == "" {
		if found, _, discoverErr := chooseReceiver("", targetPeer, 4*time.Second); discoverErr == nil {
			targetHost = found
		} else {
			logf("%v", discoverErr)
		}
	}

	logf("sender ready as %s", id.InstallID)
	backoff := time.Second
	invitationID := session.NewInvitationID()
	intent := "automatic"
	applyWake := func(request knock.Request) {
		targetPeer, targetHost = wakeTarget(request, targetHost, !settings.USB)
		intent = "manual"
		backoff = time.Second
	}
	for {
		if targetPeer == "" {
			peer, peerErr := optionalPeer(pins, requestedPeer)
			if peerErr != nil {
				return peerErr
			}
			targetPeer = peer
		}
		ready := targetPeer != "" && (settings.USB || targetHost != "")

		if ready {
			result := session.Run(ctx, session.Config{
				Host:         targetHost,
				Port:         targetPort,
				PeerID:       targetPeer,
				Identity:     id,
				Trust:        pins,
				Settings:     settings,
				InvitationID: invitationID,
				Intent:       intent,
				Log:          func(message string) { logf("%s", message) },
			})
			// Only a wake starts a manual invitation; every later retry is a
			// background attempt that must not replace another live session.
			intent = "automatic"
			if ctx.Err() != nil {
				return nil
			}
			if result.Reconnect && settings.Autostart {
				select {
				case <-ctx.Done():
					return nil
				case request := <-wake:
					applyWake(request)
				case <-time.After(backoff):
				}
				if backoff < 10*time.Second {
					backoff *= 2
				}
				continue
			}
			if !settings.Autostart {
				return nil
			}
			// The receiver ended the session on purpose. Stay discoverable and
			// wait to be woken instead of immediately taking the tablet over.
			logf("idle; the tablet can wake this sender from Connect")
			select {
			case <-ctx.Done():
				return nil
			case request := <-wake:
				applyWake(request)
				logf("wake request from %s; connecting", request.PeerID)
			}
			continue
		}

		logf("advertising; waiting for a tablet to pair or connect")
		select {
		case <-ctx.Done():
			return nil
		case request := <-wake:
			applyWake(request)
			logf("wake request from %s; connecting", request.PeerID)
		case <-time.After(15 * time.Second):
			if peer, peerErr := optionalPeer(pins, requestedPeer); peerErr == nil && peer != "" {
				targetPeer = peer
				logf("paired with %s", peer)
				if !settings.USB && targetHost == "" {
					if found, _, discoverErr := chooseReceiver("", peer, 4*time.Second); discoverErr == nil {
						targetHost = found
					}
				}
			}
		}
	}
}

// optionalPeer resolves the peer without failing when nothing is paired yet.
func optionalPeer(pins *trust.Store, requested string) (string, error) {
	if requested != "" {
		if pins.Pin(requested) == nil {
			return "", fmt.Errorf("%s is not paired; run `extendpad pair` first", requested)
		}
		return requested, nil
	}
	pinned := pins.Pinned()
	switch len(pinned) {
	case 0:
		return "", nil
	case 1:
		for peer := range pinned {
			return peer, nil
		}
	}
	names := make([]string, 0, len(pinned))
	for peer := range pinned {
		names = append(names, peer+" ("+pins.Name(peer)+")")
	}
	return "", fmt.Errorf("more than one paired receiver; pass --peer-id: %s", strings.Join(names, ", "))
}

// wakeTarget prefers the address that knocked; over USB the forwarded port
// only exists on loopback, so the saved target is kept.
func wakeTarget(request knock.Request, currentHost string, useRemoteIP bool) (string, string) {
	host := currentHost
	if useRemoteIP && request.RemoteIP != "" {
		host = request.RemoteIP
	}
	return request.PeerID, host
}

func resolvePeer(pins *trust.Store, requested string) (string, error) {
	if requested != "" {
		if pins.Pin(requested) == nil {
			return "", fmt.Errorf("%s is not paired; run `extendpad pair` first", requested)
		}
		return requested, nil
	}
	pinned := pins.Pinned()
	if len(pinned) == 0 {
		return "", errors.New("no paired receiver; run `extendpad pair` first")
	}
	if len(pinned) == 1 {
		for peerID := range pinned {
			return peerID, nil
		}
	}
	names := make([]string, 0, len(pinned))
	for peerID := range pinned {
		names = append(names, peerID+" ("+pins.Name(peerID)+")")
	}
	return "", fmt.Errorf("more than one paired receiver; pass --peer-id: %s", strings.Join(names, ", "))
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

// -------------------------------------------------------------- inspect

func commandDevices(arguments []string) error {
	if err := flag.NewFlagSet("devices", flag.ContinueOnError).Parse(arguments); err != nil {
		return err
	}
	pins, err := loadTrust()
	if err != nil {
		return err
	}
	pinned := pins.Pinned()
	if len(pinned) == 0 {
		fmt.Println("no paired receivers")
		return nil
	}
	for peerID, spki := range pinned {
		fmt.Printf("%s  %s  %s\n", peerID, pins.Name(peerID), pairing.Fingerprint(spki))
	}
	return nil
}

func commandForget(arguments []string) error {
	flags := flag.NewFlagSet("forget", flag.ContinueOnError)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if flags.NArg() != 1 {
		return errors.New("usage: extendpad forget <peer-id>")
	}
	peerID := flags.Arg(0)
	pins, err := loadTrust()
	if err != nil {
		return err
	}
	if pins.Pin(peerID) == nil {
		return fmt.Errorf("%s is not paired", peerID)
	}
	if err := pins.Forget(peerID); err != nil {
		return err
	}
	fmt.Printf("forgot %s\n", peerID)
	return nil
}

func commandDoctor(arguments []string) error {
	flags := flag.NewFlagSet("doctor", flag.ContinueOnError)
	displayName := flags.String("display", "", "X display, e.g. :2")
	if err := flags.Parse(arguments); err != nil {
		return err
	}

	problems := 0
	if path, err := exec.LookPath("ffmpeg"); err == nil {
		fmt.Printf("ffmpeg: ok (%s)\n", path)
	} else {
		fmt.Println("ffmpeg: MISSING (apt install ffmpeg)")
		problems++
	}
	if screen, err := display.Detect(*displayName); err == nil {
		fmt.Printf("display: %s %d×%d\n", screen.Name, screen.Width, screen.Height)
	} else {
		fmt.Println("display: not found (is the desktop/VNC session running?)")
		problems++
	}
	if id, err := loadIdentity(); err == nil {
		fmt.Printf("identity: %s\n", id.InstallID)
	} else {
		fmt.Printf("identity: broken (%v)\n", err)
		problems++
	}
	if pins, err := loadTrust(); err == nil {
		pinned := pins.Pinned()
		fmt.Printf("paired receivers: %d\n", len(pinned))
		for peerID := range pinned {
			fmt.Printf("  %s  %s\n", peerID, pins.Name(peerID))
		}
	} else {
		fmt.Printf("pins: broken (%v)\n", err)
		problems++
	}
	if _, err := exec.LookPath("adb"); err == nil {
		fmt.Println("adb: present (USB available)")
	} else {
		fmt.Println("adb: not installed (USB unavailable)")
	}
	if problems > 0 {
		return errors.New("doctor found problems")
	}
	return nil
}

func commandStatus(arguments []string) error {
	if err := flag.NewFlagSet("status", flag.ContinueOnError).Parse(arguments); err != nil {
		return err
	}
	settings := config.Load()
	transport := settings.Host
	if settings.USB {
		transport = "usb"
	}
	if transport == "" {
		transport = "discover"
	}
	input := "disabled"
	if settings.AllowInput {
		input = "allowed"
	}
	fmt.Printf("mode: %s\n", settings.Mode)
	fmt.Printf("transport: %s\n", transport)
	fmt.Printf("peer: %s\n", firstNonEmpty(settings.PeerID, "-"))
	fmt.Printf("input: %s\n", input)
	fmt.Printf("fps: %d  bitrate: %s  preset: %s\n", settings.FPS, settings.Bitrate, settings.Preset)
	fmt.Printf("state: %s\n", config.StateDir())
	return nil
}
