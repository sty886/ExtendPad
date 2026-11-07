// Package session runs one media session.
//
// The receiver is the TLS listener and speaks first with hello. This sender
// answers welcome, asks for the session with sessionInvite, and sends no video
// until that invitation is accepted on this connection (PROTOCOL.md 6.9). It
// then captures the X screen with ffmpeg, splits the encoded stream into
// access units, and answers ping/kf/input messages.
package session

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/raiseCatError/ExtendPad/apps/linux/internal/annexb"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/capture"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/config"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/display"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/identity"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/input"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/tlsclient"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/trust"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/wire"
)

const (
	pingInterval     = 2 * time.Second
	livenessTimeout  = 5 * time.Second
	handshakeTimeout = 10 * time.Second
	admissionTimeout = 90 * time.Second
	readPollInterval = time.Second
)

type Config struct {
	Host         string
	Port         int
	PeerID       string
	Identity     *identity.Identity
	Trust        *trust.Store
	Settings     config.Settings
	InvitationID string
	// Intent is "manual" for a user-initiated connect (the tablet's Connect
	// button) and "automatic" for startup and background reconnects. The
	// receiver only lets a manual invitation replace a live session.
	Intent string
	Log    func(string)
}

type Result struct {
	Reason    string
	Reconnect bool
}

type Session struct {
	config Config

	conn    *tls.Conn
	writeMu sync.Mutex

	ctx    context.Context
	cancel context.CancelFunc

	running      atomic.Bool
	lastReceived atomic.Int64
	keyframe     atomic.Bool
	videoEnabled atomic.Bool
	admitted     atomic.Bool
	inputGranted atomic.Bool

	inviteID string
	intent   string
	hello    wire.Hello

	display  *display.Display
	region   display.Region
	encodedW int
	encodedH int
	monitor  *display.ExtendedMonitor
	encoder  *capture.Encoder
	injector *input.Injector

	stateMu   sync.Mutex
	reason    string
	reconnect bool
}

// Run dials, handshakes, streams, and returns when the session ends.
func Run(ctx context.Context, cfg Config) Result {
	inviteID := cfg.InvitationID
	if inviteID == "" {
		inviteID = randomID()
	}
	intent := cfg.Intent
	if intent != "manual" {
		intent = "automatic"
	}
	session := &Session{config: cfg, inviteID: inviteID, intent: intent}
	session.videoEnabled.Store(true)
	session.ctx, session.cancel = context.WithCancel(ctx)
	session.logf("connecting to %s:%d …", cfg.Host, cfg.Port)

	if err := session.connect(); err != nil {
		session.logf("%v", err)
		return Result{Reason: err.Error(), Reconnect: true}
	}
	defer session.shutdown()

	if err := session.handshake(); err != nil {
		session.logf("%v", err)
		session.stop(err.Error(), !errors.Is(err, ErrDeclined))
		return session.result()
	}
	if err := session.startCapture(); err != nil {
		session.stop(err.Error(), true)
		session.logf("%v", err)
		return session.result()
	}

	var workers sync.WaitGroup
	workers.Add(2)
	go func() { defer workers.Done(); session.videoLoop() }()
	go func() { defer workers.Done(); session.pingLoop() }()

	session.controlLoop()
	session.cancel()
	session.closeConn()
	if session.encoder != nil {
		// Unblocks a video goroutine parked in Read.
		session.encoder.Stop()
	}
	workers.Wait()

	result := session.result()
	session.logf("session ended: %s", result.Reason)
	return result
}

func (s *Session) logf(format string, args ...any) {
	if s.config.Log != nil {
		s.config.Log(fmt.Sprintf(format, args...))
	}
}

func (s *Session) connect() error {
	pin := s.config.Trust.Pin(s.config.PeerID)
	if pin == nil {
		return fmt.Errorf("%s is not paired", s.config.PeerID)
	}
	conn, err := tlsclient.Dial(
		s.config.Host, s.config.Port,
		tlsclient.Certificate(s.config.Identity), pin, handshakeTimeout,
	)
	if err != nil {
		return err
	}
	s.conn = conn
	s.running.Store(true)
	s.lastReceived.Store(time.Now().UnixNano())
	return nil
}

// ------------------------------------------------------------- handshake

func (s *Session) handshake() error {
	hello, _, err := s.waitForHello(handshakeTimeout)
	if err != nil {
		return err
	}
	if err := s.acceptHello(hello); err != nil {
		return err
	}
	if err := s.sendMessage(wire.Welcome()); err != nil {
		return err
	}
	if err := s.sendMessage(wire.SessionInvite(s.inviteID, s.intent, s.config.Settings.Mode)); err != nil {
		return err
	}
	s.logf("waiting for the receiver to accept the session …")

	deadline := time.Now().Add(admissionTimeout)
	for time.Now().Before(deadline) {
		if s.ctx.Err() != nil {
			return s.ctx.Err()
		}
		message, _, err := s.nextControl(readPollInterval)
		if err != nil {
			if errors.Is(err, errTimeout) {
				continue
			}
			return err
		}
		kind, _ := message["type"].(string)
		switch kind {
		case "sessionInviteResponse":
			if id, _ := message["id"].(string); id != s.inviteID {
				continue
			}
			result, _ := message["result"].(string)
			switch result {
			case "accepted":
				s.admitted.Store(true)
				s.logf("session accepted")
				return nil
			case "pending":
				continue
			case "declined", "blocked", "cancelled":
				return fmt.Errorf("%w: %s", ErrDeclined, result)
			default:
				return fmt.Errorf("receiver answered %s", result)
			}
		default:
			s.handleBeforeAdmission(message)
		}
	}
	return errors.New("timed out waiting for session acceptance")
}

func (s *Session) waitForHello(timeout time.Duration) (wire.Hello, []byte, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if s.ctx.Err() != nil {
			return wire.Hello{}, nil, s.ctx.Err()
		}
		message, payload, err := s.nextControl(readPollInterval)
		if err != nil {
			if errors.Is(err, errTimeout) {
				continue
			}
			return wire.Hello{}, nil, err
		}
		if kind, _ := message["type"].(string); kind == "hello" {
			hello, err := wire.ParseHello(payload)
			if err != nil {
				return wire.Hello{}, nil, err
			}
			return hello, payload, nil
		}
		s.handleBeforeAdmission(message)
	}
	return wire.Hello{}, nil, errors.New("receiver did not send hello")
}

func (s *Session) acceptHello(hello wire.Hello) error {
	if hello.ID != s.config.PeerID {
		return fmt.Errorf("receiver identity changed: hello says %s, pinned as %s", hello.ID, s.config.PeerID)
	}
	s.hello = hello
	s.logf("receiver: %s %d×%d pv %d", hello.Device, hello.PixelsWide, hello.PixelsHigh, hello.PV)
	return nil
}

func (s *Session) handleBeforeAdmission(message map[string]any) {
	kind, _ := message["type"].(string)
	switch kind {
	case "ping":
		_ = s.sendMessage(wire.Pong(message["t"], time.Now().UnixMilli()))
	case "closing":
		s.stop("receiver closed the app", false)
	case "sleeping":
		s.stop("receiver is asleep", true)
	case "sessionInviteResponse":
		return
	default:
		s.logf("ignored before admission: %s", kind)
	}
}

// --------------------------------------------------------------- capture

func (s *Session) startCapture() error {
	screen, err := display.Wait(s.ctx, 30*time.Second, s.config.Settings.Display)
	if err != nil {
		return errors.New("no X display found")
	}
	s.display = screen

	maxWidth := s.hello.MaxEncodeWide
	maxHeight := s.hello.MaxEncodeHigh
	if maxWidth <= 0 {
		maxWidth = 1920
	}
	if maxHeight <= 0 {
		maxHeight = 1200
	}

	var region display.Region
	var encodedWidth, encodedHeight int

	if s.config.Settings.Mode == "extend" {
		width, height := even(s.hello.PixelsWide), even(s.hello.PixelsHigh)
		if width <= 0 || height <= 0 {
			width, height = 1280, 800
		}
		width, height = fit(width, height, maxWidth, maxHeight)
		monitor := display.NewExtended(screen, width, height)
		region, err = monitor.Create()
		if err != nil {
			s.logf("extend unavailable (%v); mirroring instead", err)
		} else {
			s.monitor = monitor
			s.logf("extended monitor %d×%d at +%d+%d", width, height, region.X, region.Y)
		}
	}
	if region.Width == 0 {
		width, height := screen.ScreenSize()
		region = display.Region{X: 0, Y: 0, Width: width, Height: height}
		encodedWidth, encodedHeight = fit(width, height, maxWidth, maxHeight)
		s.logf("mirroring %s %d×%d", screen.Name, width, height)
	}
	s.region = region
	if encodedWidth == 0 {
		encodedWidth, encodedHeight = region.Width, region.Height
	}
	s.encodedW, s.encodedH = encodedWidth, encodedHeight

	s.encoder = capture.New(capture.Config{
		Display:      screen,
		Region:       region,
		FPS:          s.config.Settings.FPS,
		Bitrate:      s.config.Settings.Bitrate,
		Preset:       s.config.Settings.Preset,
		OutputWidth:  encodedWidth,
		OutputHeight: encodedHeight,
	})
	if err := s.encoder.Start(); err != nil {
		return err
	}
	s.logf("capture started (%d×%d)", encodedWidth, encodedHeight)

	if s.config.Settings.AllowInput {
		injector, err := input.New(screen, region)
		if err != nil {
			s.logf("input disabled: %v", err)
		} else {
			s.injector = injector
		}
	}

	if err := s.sendMessage(wire.AllowInputState(s.injector != nil)); err != nil {
		return err
	}
	s.inputGranted.Store(s.injector != nil)
	if err := s.sendMessage(wire.DisplayModeState(s.config.Settings.Mode)); err != nil {
		return err
	}
	if err := s.sendMessage(wire.StreamCodecState("h264", "")); err != nil {
		return err
	}
	return s.sendMessage(wire.VideoState(true, encodedWidth, encodedHeight))
}

// ---------------------------------------------------------------- loops

func (s *Session) videoLoop() {
	splitter := &annexb.Splitter{}
	buffer := make([]byte, 256*1024)
	for s.ctx.Err() == nil && s.running.Load() {
		if !s.videoEnabled.Load() {
			time.Sleep(100 * time.Millisecond)
			continue
		}
		count, err := s.encoder.Read(buffer)
		if count > 0 {
			for _, unit := range splitter.Feed(buffer[:count]) {
				if err := s.sendVideo(unit); err != nil {
					s.stop("connection lost", true)
					return
				}
			}
		}
		if err != nil {
			if s.ctx.Err() != nil || !s.running.Load() {
				return
			}
			time.Sleep(100 * time.Millisecond)
			if !s.encoder.Running() && s.videoEnabled.Load() {
				if restartErr := s.encoder.Restart(); restartErr == nil {
					splitter = &annexb.Splitter{}
				} else {
					time.Sleep(500 * time.Millisecond)
				}
			}
			continue
		}
		if s.keyframe.CompareAndSwap(true, false) {
			if err := s.encoder.Restart(); err == nil {
				splitter = &annexb.Splitter{}
			}
		}
	}
}

func (s *Session) pingLoop() {
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-s.ctx.Done():
			return
		case <-ticker.C:
			if time.Since(time.Unix(0, s.lastReceived.Load())) > livenessTimeout {
				s.stop("receiver stopped responding", true)
				return
			}
			if err := s.sendMessage(wire.Ping()); err != nil {
				return
			}
		}
	}
}

func (s *Session) controlLoop() {
	for s.ctx.Err() == nil {
		message, _, err := s.nextControl(readPollInterval)
		if err != nil {
			if errors.Is(err, errTimeout) {
				if time.Since(time.Unix(0, s.lastReceived.Load())) > livenessTimeout {
					s.stop("receiver stopped responding", true)
					return
				}
				continue
			}
			s.stop("connection lost", true)
			return
		}
		s.handle(message)
		if s.ctx.Err() != nil {
			return
		}
	}
}

// --------------------------------------------------------------- control

func (s *Session) handle(message map[string]any) {
	kind, _ := message["type"].(string)
	switch kind {
	case "hello":
		// Rotation, resize, or a receiver preference change: re-answer.
		payload, err := json.Marshal(message)
		if err == nil {
			if hello, parseErr := wire.ParseHello(payload); parseErr == nil {
				if err := s.acceptHello(hello); err != nil {
					s.stop(err.Error(), true)
					return
				}
			}
		}
		_ = s.sendMessage(wire.Welcome())
		_ = s.sendMessage(wire.SessionInvite(s.inviteID, s.intent, s.config.Settings.Mode))
		_ = s.sendMessage(wire.VideoState(true, s.encodedW, s.encodedH))
	case "ping":
		_ = s.sendMessage(wire.Pong(message["t"], time.Now().UnixMilli()))
	case "kf":
		s.keyframe.Store(true)
	case "closing":
		s.stop("receiver closed the app", false)
	case "sleeping":
		s.stop("receiver is asleep", true)
	case "allowInputRequest":
		wanted := boolean(message["allowed"]) && s.injector != nil
		s.inputGranted.Store(wanted)
		if !wanted && s.injector != nil {
			s.injector.ReleaseAll()
		}
		_ = s.sendMessage(wire.AllowInputState(wanted))
	case "videoRequest":
		enabled := boolean(message["enabled"])
		if enabled && !s.videoEnabled.Load() {
			s.videoEnabled.Store(true)
			_ = s.encoder.Start()
			_ = s.sendMessage(wire.VideoState(true, s.encodedW, s.encodedH))
		} else if !enabled && s.videoEnabled.Load() {
			s.videoEnabled.Store(false)
			s.encoder.Stop()
			_ = s.sendMessage(wire.VideoState(false, 0, 0))
		}
	case "audioRequest":
		_ = s.sendMessage(wire.AudioState(false))
	case "smartTouchProbe":
		_ = s.sendMessage(wire.SmartTouchProbeResult(message["id"], false))
	case "displayModeRequest":
		if mode, _ := message["mode"].(string); mode == s.config.Settings.Mode {
			_ = s.sendMessage(wire.DisplayModeState(s.config.Settings.Mode))
		}
	default:
		if !s.inputGranted.Load() || s.injector == nil || !s.admitted.Load() {
			return
		}
		s.inject(message)
	}
}

func (s *Session) inject(message map[string]any) {
	injector := s.injector
	if injector == nil {
		return
	}
	switch message["type"] {
	case "touch":
		phase, _ := message["phase"].(string)
		x, okX := number(message["x"])
		y, okY := number(message["y"])
		if okX && okY {
			injector.Touch(phase, x, y)
		}
	case "pointer":
		action, _ := message["action"].(string)
		switch action {
		case "move":
			x, okX := number(message["x"])
			y, okY := number(message["y"])
			if okX && okY {
				injector.MoveTo(x, y)
			}
		case "moveRelative":
			dx, okX := number(message["dx"])
			dy, okY := number(message["dy"])
			if okX && okY {
				injector.MoveRelative(dx, dy)
			}
		case "down", "up":
			button, _ := message["button"].(string)
			if button != "left" && button != "right" {
				return
			}
			if action == "down" {
				injector.ButtonDown(button)
			} else {
				injector.ButtonUp(button)
			}
		}
	case "scroll":
		dx, okX := number(message["dx"])
		dy, okY := number(message["dy"])
		if okX && okY {
			injector.Scroll(dx, dy)
		}
	case "keyboard":
		s.injectKeyboard(message, injector)
	}
}

func (s *Session) injectKeyboard(message map[string]any, injector *input.Injector) {
	action, _ := message["action"].(string)
	modifiers := stringList(message["modifiers"])
	switch action {
	case "text":
		text, _ := message["text"].(string)
		if text != "" {
			if runes := []rune(text); len(runes) > 4096 {
				text = string(runes[:4096])
			}
			injector.TypeText(text)
		}
	case "press", "down", "up":
		usageValue, ok := number(message["usage"])
		if !ok {
			return
		}
		usage := uint32(usageValue)
		switch action {
		case "press":
			injector.KeyPress(usage, modifiers)
		case "down":
			if !boolean(message["repeat"]) {
				injector.KeyDown(usage, modifiers)
			}
		case "up":
			injector.KeyUp(usage, modifiers)
		}
	case "modifierDown":
		if name, ok := message["modifier"].(string); ok {
			injector.ModifierDown(name)
		}
	case "modifierUp":
		if name, ok := message["modifier"].(string); ok {
			injector.ModifierUp(name)
		}
	case "cancel":
		injector.ReleaseAll()
	}
}

// --------------------------------------------------------------- plumbing

var errTimeout = errors.New("read timeout")

// ErrDeclined means the receiver refused this invitation (background attempts
// from another host are declined while its session is live). Retrying
// immediately would start a takeover fight, so the sender waits to be woken.
var ErrDeclined = errors.New("receiver declined the session")

func (s *Session) nextControl(timeout time.Duration) (map[string]any, []byte, error) {
	conn := s.conn
	if conn == nil {
		return nil, nil, errors.New("no connection")
	}
	_ = conn.SetReadDeadline(time.Now().Add(timeout))
	payload, err := wire.ReadFrame(conn)
	if err != nil {
		var netError net.Error
		if errors.As(err, &netError) && netError.Timeout() {
			return nil, nil, errTimeout
		}
		if errors.Is(err, io.EOF) || errors.Is(err, net.ErrClosed) {
			return nil, nil, err
		}
		return nil, nil, err
	}
	s.lastReceived.Store(time.Now().UnixNano())
	if !wire.IsControl(payload) {
		return nil, nil, errTimeout
	}
	message, err := wire.DecodeControl(payload)
	if err != nil {
		return nil, nil, errTimeout
	}
	return message, payload, nil
}

func (s *Session) sendMessage(message map[string]any) error {
	payload, err := wire.Control(message)
	if err != nil {
		return err
	}
	return s.sendPayload(payload)
}

func (s *Session) sendVideo(unit []byte) error {
	return s.sendPayload(unit)
}

func (s *Session) sendPayload(payload []byte) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	if s.conn == nil {
		return net.ErrClosed
	}
	_ = s.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	return wire.WriteFrame(s.conn, payload)
}

func (s *Session) stop(reason string, reconnect bool) {
	s.stateMu.Lock()
	if s.reason == "" {
		s.reason = reason
		s.reconnect = reconnect
	}
	s.stateMu.Unlock()
	s.cancel()
}

func (s *Session) result() Result {
	s.stateMu.Lock()
	defer s.stateMu.Unlock()
	reason := s.reason
	if reason == "" {
		reason = "closed"
	}
	return Result{Reason: reason, Reconnect: s.reconnect}
}

func (s *Session) closeConn() {
	s.writeMu.Lock()
	conn := s.conn
	s.conn = nil
	s.writeMu.Unlock()
	if conn != nil {
		_ = conn.Close()
	}
}

func (s *Session) shutdown() {
	s.running.Store(false)
	s.cancel()
	if s.injector != nil {
		s.injector.Close()
		s.injector = nil
	}
	if s.encoder != nil {
		s.encoder.Stop()
		s.encoder = nil
	}
	if s.monitor != nil {
		s.monitor.Restore()
		s.monitor = nil
	}
	s.closeConn()
}

// ----------------------------------------------------------------- helpers

func number(value any) (float64, bool) {
	switch typed := value.(type) {
	case float64:
		if math.IsNaN(typed) || math.IsInf(typed, 0) {
			return 0, false
		}
		return typed, true
	case int:
		return float64(typed), true
	}
	return 0, false
}

func boolean(value any) bool {
	result, _ := value.(bool)
	return result
}

func stringList(value any) []string {
	items, ok := value.([]any)
	if !ok {
		return nil
	}
	result := make([]string, 0, len(items))
	for _, item := range items {
		if text, ok := item.(string); ok {
			result = append(result, text)
		}
	}
	return result
}

func even(value int) int {
	if value < 0 {
		return 0
	}
	return value - value%2
}

func fit(width, height, maxWidth, maxHeight int) (int, int) {
	if width <= 0 || height <= 0 {
		return 1280, 800
	}
	scale := math.Min(1, math.Min(float64(maxWidth)/float64(width), float64(maxHeight)/float64(height)))
	scaledWidth := even(int(math.Round(float64(width) * scale)))
	scaledHeight := even(int(math.Round(float64(height) * scale)))
	if scaledWidth < 2 {
		scaledWidth = 2
	}
	if scaledHeight < 2 {
		scaledHeight = 2
	}
	return scaledWidth, scaledHeight
}

// NewInvitationID is stable across reconnects within one run, so the receiver
// recognizes them as the same logical session (its continuation rule).
func NewInvitationID() string { return randomID() }

func randomID() string {
	// A v4 UUID for the invitation; the receiver only requires 1..64 chars.
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return fmt.Sprintf("invite-%d", time.Now().UnixNano())
	}
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", bytes[0:4], bytes[4:6], bytes[6:8], bytes[8:10], bytes[10:16])
}
