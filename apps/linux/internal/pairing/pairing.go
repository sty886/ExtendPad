// Package pairing implements pairing protocol v13 (PROTOCOL.md 2.3).
//
// It is a byte-exact port of packages/shared/Pairing.swift and the Android
// mirror. The ceremony runs over plain TCP on port 9002: a commit-then-reveal
// hello, ephemeral P-256 ECDH, HKDF/HMAC confirmation keys, and a six-digit
// SAS both people compare. Trust is written only after the peer's
// authenticated confirmation and the initiator's commit is acknowledged.
package pairing

import (
	"bytes"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/raiseCatError/ExtendPad/apps/linux/internal/trust"
)

const (
	Version       = 13
	maxFrameBytes = 64 * 1024

	roleInitiator = 1
	roleResponder = 2

	stepCommit    = 0x10
	stepCommitAck = 0x11
	stepAbort     = 0x12
)

var uuidPattern = regexp.MustCompile(
	`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// Error is a pairing failure whose message is safe to show the user.
type Error struct{ Message string }

func (e *Error) Error() string { return e.Message }

func fail(format string, args ...any) error {
	return &Error{Message: fmt.Sprintf(format, args...)}
}

// ---------------------------------------------------------------- entities

type Hello struct {
	Version            int    `json:"version"`
	DeviceID           string `json:"deviceID"`
	DisplayName        string `json:"displayName"`
	IdentitySPKI       []byte `json:"identitySPKI"`
	EphemeralPublicKey []byte `json:"ephemeralPublicKey"`
	Nonce              []byte `json:"nonce"`
}

type Confirmation struct {
	Accepted      bool   `json:"accepted"`
	Authenticator []byte `json:"authenticator"`
}

type Envelope struct {
	Kind            string        `json:"kind"`
	Hello           *Hello        `json:"hello,omitempty"`
	Confirmation    *Confirmation `json:"confirmation,omitempty"`
	Authenticator   []byte        `json:"authenticator,omitempty"`
	HelloCommitment []byte        `json:"helloCommitment,omitempty"`
}

const (
	kindHelloCommit = "helloCommit"
	kindHello       = "hello"
	kindHelloReveal = "helloReveal"
	kindConfirm     = "confirmation"
	kindCommit      = "commit"
	kindCommitAck   = "commitAck"
	kindAbort       = "abort"
)

type Pending struct {
	PeerID   string
	PeerName string
	PeerSPKI []byte
	SAS      string
}

// ------------------------------------------------------------- validation

func isUUID(value string) bool { return uuidPattern.MatchString(value) }

func isCanonicalP256SPKI(spki []byte) bool {
	public, err := x509.ParsePKIXPublicKey(spki)
	if err != nil {
		return false
	}
	key, ok := public.(*ecdsa.PublicKey)
	if !ok || key.Curve != elliptic.P256() {
		return false
	}
	encoded, err := x509.MarshalPKIXPublicKey(key)
	return err == nil && bytes.Equal(encoded, spki)
}

func (h *Hello) Validate() error {
	if h.Version != Version {
		return fail("This device must be updated before pairing")
	}
	if !isUUID(h.DeviceID) ||
		strings.TrimSpace(h.DisplayName) == "" ||
		len([]byte(h.DisplayName)) > 128 ||
		len(h.IdentitySPKI) > 512 ||
		!isCanonicalP256SPKI(h.IdentitySPKI) ||
		len(h.EphemeralPublicKey) != 65 ||
		len(h.Nonce) != 32 {
		return fail("Invalid pairing message")
	}
	if _, err := ecdh.P256().NewPublicKey(h.EphemeralPublicKey); err != nil {
		return fail("Invalid pairing message")
	}
	return nil
}

// --------------------------------------------------------------- encoding

func writeLP(buffer *bytes.Buffer, data []byte) {
	_ = binary.Write(buffer, binary.BigEndian, uint32(len(data)))
	buffer.Write(data)
}

func (h *Hello) canonical(role byte) []byte {
	var buffer bytes.Buffer
	buffer.WriteByte(role)
	_ = binary.Write(&buffer, binary.BigEndian, uint32(h.Version))
	writeLP(&buffer, []byte(h.DeviceID))
	writeLP(&buffer, []byte(h.DisplayName))
	writeLP(&buffer, h.IdentitySPKI)
	writeLP(&buffer, h.EphemeralPublicKey)
	writeLP(&buffer, h.Nonce)
	return buffer.Bytes()
}

// HelloCommitment is SHA256(lp(domain) || canonical(initiator hello)).
func HelloCommitment(hello *Hello) []byte {
	preimage := appendLP(nil, []byte("MeowDisplay-Pairing-HelloCommit-v13"))
	preimage = append(preimage, hello.canonical(roleInitiator)...)
	digest := sha256.Sum256(preimage)
	return digest[:]
}

func appendLP(dst, data []byte) []byte {
	var length [4]byte
	binary.BigEndian.PutUint32(length[:], uint32(len(data)))
	return append(append(dst, length[:]...), data...)
}

func hmacSHA256(key, message []byte) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write(message)
	return mac.Sum(nil)
}

// hkdf is HKDF-SHA256 (RFC 5869); Go 1.22 has no standard package for it.
func hkdf(secret, salt, info []byte, length int) []byte {
	if len(salt) == 0 {
		salt = make([]byte, sha256.Size)
	}
	prk := hmacSHA256(salt, secret)
	output := make([]byte, 0, length)
	var block []byte
	for counter := byte(1); len(output) < length; counter++ {
		block = hmacSHA256(prk, append(append(append([]byte{}, block...), info...), counter))
		output = append(output, block...)
	}
	return output[:length]
}

// --------------------------------------------------------------- handshake

type Result struct {
	Pending    Pending
	localKey   []byte
	peerKey    []byte
	transcript []byte
}

func (r *Result) Confirmation(accepted bool) Confirmation {
	body := append(append([]byte{}, r.transcript...), 0)
	if accepted {
		body[len(body)-1] = 1
	}
	return Confirmation{Accepted: accepted, Authenticator: hmacSHA256(r.localKey, body)}
}

func (r *Result) StepAuthenticator(step byte) []byte {
	return hmacSHA256(r.localKey, append(append([]byte{}, r.transcript...), step))
}

func (r *Result) Verify(confirmation Confirmation) error {
	body := append(append([]byte{}, r.transcript...), 0)
	if confirmation.Accepted {
		body[len(body)-1] = 1
	}
	expected := hmacSHA256(r.peerKey, body)
	if !hmac.Equal(expected, confirmation.Authenticator) {
		return fail("Pairing could not be verified")
	}
	if !confirmation.Accepted {
		return fail("Pairing was cancelled")
	}
	return nil
}

func (r *Result) VerifyStep(step byte, authenticator []byte) error {
	expected := hmacSHA256(r.peerKey, append(append([]byte{}, r.transcript...), step))
	if !hmac.Equal(expected, authenticator) {
		return fail("Pairing could not be verified")
	}
	return nil
}

type handshake struct {
	role      byte
	ephemeral *ecdh.PrivateKey
	local     *Hello
}

func newHandshake(role byte, deviceID, displayName string, identitySPKI []byte) (*handshake, error) {
	ephemeral, err := ecdh.P256().GenerateKey(rand.Reader)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, 32)
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	return handshakeWith(role, deviceID, displayName, identitySPKI, ephemeral, nonce), nil
}

func handshakeWith(role byte, deviceID, displayName string, identitySPKI []byte,
	ephemeral *ecdh.PrivateKey, nonce []byte) *handshake {
	return &handshake{
		role:      role,
		ephemeral: ephemeral,
		local: &Hello{
			Version:            Version,
			DeviceID:           deviceID,
			DisplayName:        displayName,
			IdentitySPKI:       identitySPKI,
			EphemeralPublicKey: ephemeral.PublicKey().Bytes(),
			Nonce:              nonce,
		},
	}
}

func (h *handshake) result(peer *Hello) (*Result, error) {
	if err := h.local.Validate(); err != nil {
		return nil, err
	}
	if err := peer.Validate(); err != nil {
		return nil, err
	}
	if peer.DeviceID == h.local.DeviceID || bytes.Equal(peer.IdentitySPKI, h.local.IdentitySPKI) {
		return nil, fail("Invalid pairing message")
	}
	peerKey, err := ecdh.P256().NewPublicKey(peer.EphemeralPublicKey)
	if err != nil {
		return nil, fail("Pairing could not be verified")
	}
	shared, err := h.ephemeral.ECDH(peerKey)
	if err != nil {
		return nil, fail("Pairing could not be verified")
	}

	initiator, responder := peer, h.local
	if h.role == roleInitiator {
		initiator, responder = h.local, peer
	}
	transcript := appendLP(nil, []byte("OpenDisplay-Pairing-Transcript-v13"))
	transcript = append(transcript, initiator.canonical(roleInitiator)...)
	transcript = append(transcript, responder.canonical(roleResponder)...)
	transcriptHash := sha256.Sum256(transcript)

	root := hkdf(shared, transcriptHash[:], []byte("OpenDisplay pairing v13"), 32)
	sasBytes := hkdf(root, []byte("sas"), transcriptHash[:], 4)
	number := binary.BigEndian.Uint32(sasBytes) % 1_000_000

	peerRole := byte(roleResponder)
	if h.role == roleResponder {
		peerRole = roleInitiator
	}
	return &Result{
		Pending: Pending{
			PeerID:   peer.DeviceID,
			PeerName: displayName(peer.DisplayName),
			PeerSPKI: peer.IdentitySPKI,
			SAS:      fmt.Sprintf("%03d %03d", number/1000, number%1000),
		},
		localKey:   hkdf(root, []byte("confirmation"), []byte{h.role}, 32),
		peerKey:    hkdf(root, []byte("confirmation"), []byte{peerRole}, 32),
		transcript: transcriptHash[:],
	}, nil
}

var dangerousRunes = func() map[rune]bool {
	set := map[rune]bool{0x061C: true, 0x200B: true, 0x200E: true, 0x200F: true,
		0x2028: true, 0x2029: true, 0x2060: true, 0xFEFF: true}
	for r := rune(0x202A); r <= 0x202E; r++ {
		set[r] = true
	}
	for r := rune(0x2066); r <= 0x2069; r++ {
		set[r] = true
	}
	return set
}()

func displayName(raw string) string {
	var kept []rune
	for _, r := range raw {
		if unicode.IsControl(r) || dangerousRunes[r] {
			continue
		}
		kept = append(kept, r)
	}
	name := strings.TrimSpace(string(kept))
	if len([]rune(name)) > 40 {
		name = strings.TrimSpace(string([]rune(name)[:40]))
	}
	if name == "" {
		return "Device"
	}
	return name
}

// ----------------------------------------------------------------- framing

func writeEnvelope(w io.Writer, envelope Envelope) error {
	body, err := json.Marshal(envelope)
	if err != nil {
		return err
	}
	if len(body) == 0 || len(body) > maxFrameBytes {
		return fail("Invalid pairing message")
	}
	var header [4]byte
	binary.BigEndian.PutUint32(header[:], uint32(len(body)))
	if _, err := w.Write(header[:]); err != nil {
		return err
	}
	_, err = w.Write(body)
	return err
}

func readEnvelope(r io.Reader) (Envelope, error) {
	var header [4]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		return Envelope{}, fail("Invalid pairing message")
	}
	length := binary.BigEndian.Uint32(header[:])
	if length == 0 || length > maxFrameBytes {
		return Envelope{}, fail("Invalid pairing message")
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(r, body); err != nil {
		return Envelope{}, fail("Invalid pairing message")
	}
	var envelope Envelope
	if err := json.Unmarshal(body, &envelope); err != nil {
		return Envelope{}, fail("Invalid pairing message")
	}
	switch envelope.Kind {
	case kindHelloCommit, kindHello, kindHelloReveal, kindConfirm, kindCommit, kindCommitAck, kindAbort:
		return envelope, nil
	default:
		return Envelope{}, fail("Invalid pairing message")
	}
}

// -------------------------------------------------------------------- pump

type pumpItem struct {
	envelope Envelope
	err      error
}

type framePump struct {
	items     chan pumpItem
	peerAbort bool
	mutex     sync.Mutex
}

func startPump(conn io.Reader, result *Result) *framePump {
	pump := &framePump{items: make(chan pumpItem, 8)}
	go func() {
		for {
			envelope, err := readEnvelope(conn)
			if err != nil {
				pump.items <- pumpItem{err: err}
				return
			}
			if envelope.Kind == kindAbort {
				if envelope.Authenticator != nil && result.VerifyStep(stepAbort, envelope.Authenticator) == nil {
					pump.mutex.Lock()
					pump.peerAbort = true
					pump.mutex.Unlock()
					pump.items <- pumpItem{err: fail("Pairing was cancelled on the other device")}
				} else {
					pump.items <- pumpItem{err: fail("Invalid pairing message")}
				}
				return
			}
			pump.items <- pumpItem{envelope: envelope}
		}
	}()
	return pump
}

func (p *framePump) next() (Envelope, error) {
	item := <-p.items
	return item.envelope, item.err
}

func (p *framePump) aborted() bool {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	return p.peerAbort
}

// ------------------------------------------------------------------ flow

type Options struct {
	LocalID        string
	LocalName      string
	IdentitySPKI   []byte
	Store          *trust.Store
	ExpectedPeerID string
	Decide         func(Pending) bool
	Log            func(string)
}

func classify(pending Pending, existing []byte) (Pending, string) {
	switch {
	case existing == nil:
		return pending, "new"
	case bytes.Equal(existing, pending.PeerSPKI):
		return pending, "same-key"
	default:
		return pending, "identity-changed"
	}
}

// RunInitiator dials a receiver's pairing port and runs the initiator side.
func RunInitiator(conn io.ReadWriteCloser, options Options) (Pending, error) {
	handshake, err := newHandshake(roleInitiator, options.LocalID, options.LocalName, options.IdentitySPKI)
	if err != nil {
		return Pending{}, err
	}
	if err := writeEnvelope(conn, Envelope{Kind: kindHelloCommit, HelloCommitment: HelloCommitment(handshake.local)}); err != nil {
		return Pending{}, err
	}

	response, err := readEnvelope(conn)
	if err != nil {
		return Pending{}, err
	}
	if response.Kind != kindHello || response.Hello == nil {
		return Pending{}, fail("Invalid pairing message")
	}
	if options.ExpectedPeerID != "" && response.Hello.DeviceID != options.ExpectedPeerID {
		return Pending{}, fail("Device identity changed")
	}

	if err := writeEnvelope(conn, Envelope{Kind: kindHelloReveal, Hello: handshake.local}); err != nil {
		return Pending{}, err
	}
	result, err := handshake.result(response.Hello)
	if err != nil {
		return Pending{}, err
	}
	pending, classification := classify(result.Pending, options.Store.Pin(result.Pending.PeerID))
	if classification == "identity-changed" {
		return Pending{}, fail("Device identity changed")
	}

	pump := startPump(conn, result)
	accepted := options.Decide(pending)
	if pump.aborted() {
		return Pending{}, fail("Pairing was cancelled on the other device")
	}
	if err := writeEnvelope(conn, Envelope{Kind: kindConfirm, Confirmation: ptr(result.Confirmation(accepted))}); err != nil {
		return Pending{}, err
	}
	if !accepted {
		return Pending{}, fail("Pairing was cancelled")
	}

	reply, err := pump.next()
	if err != nil {
		return Pending{}, err
	}
	if reply.Kind != kindConfirm || reply.Confirmation == nil {
		return Pending{}, fail("Invalid pairing message")
	}
	if err := result.Verify(*reply.Confirmation); err != nil {
		return Pending{}, err
	}

	if err := writeEnvelope(conn, Envelope{Kind: kindCommit, Authenticator: result.StepAuthenticator(stepCommit)}); err != nil {
		return Pending{}, err
	}
	ack, err := pump.next()
	if err != nil {
		return Pending{}, err
	}
	if ack.Kind != kindCommitAck || ack.Authenticator == nil {
		return Pending{}, fail("Invalid pairing message")
	}
	if err := result.VerifyStep(stepCommitAck, ack.Authenticator); err != nil {
		return Pending{}, err
	}

	if err := finalizeTrust(options.Store, pending, classification, result, *reply.Confirmation); err != nil {
		return Pending{}, err
	}
	return pending, nil
}

// finalizeTrust is the only place trust is written after a handshake:
// strictly after the peer's authenticated confirmation verified.
func finalizeTrust(store *trust.Store, pending Pending, classification string,
	result *Result, peerConfirmation Confirmation) error {
	if err := result.Verify(peerConfirmation); err != nil {
		return err
	}
	// A same-key re-pair whose pin vanished since the SAS was shown would
	// silently recreate trust from a stale classification.
	if classification == "same-key" && !bytes.Equal(store.Pin(pending.PeerID), pending.PeerSPKI) {
		return fail("Trust changed during pairing. Try again")
	}
	if store.HeldByAnother(pending.PeerID, pending.PeerSPKI) {
		return fail("Device identity changed")
	}
	stored, err := store.SetPin(pending.PeerID, pending.PeerSPKI, pending.PeerName)
	if err != nil {
		return err
	}
	if !stored {
		return fail("Device identity changed")
	}
	return nil
}

func ptr[T any](value T) *T { return &value }

// Deadline is the overall pairing attempt budget, matching the Android side.
const Deadline = 70 * time.Second

// Fingerprint is the human-comparable grouped digits shown for a pin.
func Fingerprint(spki []byte) string {
	derived := hkdf(spki, []byte("OpenDisplay-TLS-Pairing-v1"), []byte("fingerprint"), 10)
	parts := make([]string, 0, 5)
	for index := 0; index < 10; index += 2 {
		value := (uint32(derived[index])<<8 | uint32(derived[index+1])) % 10000
		parts = append(parts, fmt.Sprintf("%04d", value))
	}
	return strings.Join(parts, " ")
}
