// Package wire implements the media framing and the control messages a
// sender sends (PROTOCOL.md 3, 4, 6).
//
// Every frame is [u32 big-endian length][payload]. A payload is a control
// message when it is under 32768 bytes, starts with '{', and has no NUL byte;
// everything else is a video access unit.
package wire

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
)

const (
	ProtocolVersion          = 22
	MinSupportedPeer         = 1
	SessionInvitationVersion = 21
	MaxControlBytes          = 32768
	MaxIncomingBytes         = 32 << 20
)

var ErrBadFrame = errors.New("bad frame")

func WriteFrame(w io.Writer, payload []byte) error {
	if len(payload) == 0 || len(payload) >= MaxIncomingBytes {
		return fmt.Errorf("%w: %d bytes", ErrBadFrame, len(payload))
	}
	var header [4]byte
	binary.BigEndian.PutUint32(header[:], uint32(len(payload)))
	if _, err := w.Write(header[:]); err != nil {
		return err
	}
	if _, err := w.Write(payload); err != nil {
		return err
	}
	return nil
}

// ReadFrame reads exactly one frame. A clean EOF on the first header byte is
// reported as io.EOF.
func ReadFrame(r io.Reader) ([]byte, error) {
	var header [4]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		return nil, err
	}
	length := binary.BigEndian.Uint32(header[:])
	if length == 0 || length >= MaxIncomingBytes {
		return nil, fmt.Errorf("%w: length %d", ErrBadFrame, length)
	}
	payload := make([]byte, length)
	if _, err := io.ReadFull(r, payload); err != nil {
		return nil, err
	}
	return payload, nil
}

// IsControl applies the receiver's demux heuristic.
func IsControl(payload []byte) bool {
	return len(payload) > 0 &&
		len(payload) < MaxControlBytes &&
		payload[0] == '{' &&
		bytes.IndexByte(payload, 0) < 0
}

func DecodeControl(payload []byte) (map[string]any, error) {
	var message map[string]any
	if err := json.Unmarshal(payload, &message); err != nil {
		return nil, err
	}
	return message, nil
}

// Control encodes one control message, enforcing the demux limits.
func Control(message map[string]any) ([]byte, error) {
	payload, err := json.Marshal(message)
	if err != nil {
		return nil, err
	}
	if len(payload) >= MaxControlBytes {
		return nil, fmt.Errorf("control message too large: %d bytes", len(payload))
	}
	return payload, nil
}

// Hello is the receiver's first message.
type Hello struct {
	Type          string   `json:"type"`
	PixelsWide    int      `json:"pixelsWide"`
	PixelsHigh    int      `json:"pixelsHigh"`
	Scale         float64  `json:"scale"`
	Device        string   `json:"device"`
	ID            string   `json:"id"`
	PV            int      `json:"pv"`
	PP            int      `json:"pp"`
	RequestedMode string   `json:"requestedMode"`
	MaxEncodeWide int      `json:"maxEncodeWide"`
	MaxEncodeHigh int      `json:"maxEncodeHigh"`
	MaxFPS        int      `json:"maxFPS"`
	Codecs        []string `json:"codecs"`
	Transports    []string `json:"transports"`
}

func ParseHello(payload []byte) (Hello, error) {
	var hello Hello
	if err := json.Unmarshal(payload, &hello); err != nil {
		return Hello{}, err
	}
	if hello.Type != "hello" || hello.ID == "" {
		return Hello{}, errors.New("not a hello")
	}
	return hello, nil
}

// ------------------------------------------------------- sender messages

func Welcome() map[string]any {
	return map[string]any{
		"type":       "welcome",
		"pv":         ProtocolVersion,
		"min":        MinSupportedPeer,
		"features":   []string{},
		"transports": []string{"tcp"},
	}
}

func SessionInvite(id, intent, mode string) map[string]any {
	return map[string]any{
		"type":           "sessionInvite",
		"id":             id,
		"initiator":      "sender",
		"intent":         intent,
		"mode":           mode,
		"awaitingSender": false,
	}
}

func Pong(receiverT any, monotonicMS int64) map[string]any {
	return map[string]any{"type": "pong", "t": receiverT, "mt": monotonicMS}
}

func Ping() map[string]any { return map[string]any{"type": "ping"} }

func AllowInputState(allowed bool) map[string]any {
	state := "off"
	if allowed {
		state = "allowed"
	}
	return AllowInputStateAs(allowed, state)
}

// AllowInputStateAs reports an explicit pv 18 consent `state`
// (off/requesting/allowed/notAllowed/requestsDisabled). `allowed` stays the
// effective on/off summary every peer understands.
func AllowInputStateAs(allowed bool, state string) map[string]any {
	return map[string]any{"type": "allowInputState", "allowed": allowed, "state": state}
}

func VideoState(enabled bool, width, height int) map[string]any {
	message := map[string]any{"type": "videoState", "enabled": enabled}
	if width > 0 && height > 0 {
		message["width"] = width
		message["height"] = height
	}
	return message
}

func DisplayModeState(mode string) map[string]any {
	return map[string]any{"type": "displayModeState", "mode": mode}
}

func StreamCodecState(codec, reason string) map[string]any {
	return map[string]any{"type": "streamCodecState", "codec": codec, "reason": reason}
}

func AudioState(enabled bool) map[string]any {
	return map[string]any{"type": "audioState", "enabled": enabled}
}

func SmartTouchProbeResult(id any, scrollable bool) map[string]any {
	return map[string]any{"type": "smartTouchProbeResult", "id": id, "scrollable": scrollable}
}
