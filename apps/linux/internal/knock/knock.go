// Package knock implements the receiver's remote wake ("knock") listener.
//
// When a paired receiver's Connect button is pressed, the receiver opens a
// pinned mutual-TLS connection to the sender's port 9003 and sends one small
// frame: `{"type":"remoteConnectRequest","intent":"manual"}`. Reading that
// frame is the acknowledgement; the sender then dials the receiver back on
// the normal media port (PROTOCOL.md 2.1, remote knock).
//
// The listener pins the client certificate exactly like the media listener
// pins the sender: the presented SPKI must be a currently paired peer.
package knock

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"time"

	"github.com/raiseCatError/ExtendPad/apps/linux/internal/identity"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/tlsclient"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/trust"
)

const (
	Port          = 9003
	maxKnockBytes = 256
	frameType     = "remoteConnectRequest"
)

type Request struct {
	PeerID   string
	RemoteIP string
	Intent   string
}

type Config struct {
	Identity *identity.Identity
	Trust    *trust.Store
	Log      func(string)
}

type knockFrame struct {
	Type   string `json:"type"`
	Intent string `json:"intent"`
}

// Listen accepts knocks until the context ends and delivers each valid one.
func Listen(ctx context.Context, cfg Config, requests chan<- Request) error {
	config := &tls.Config{
		Certificates: []tls.Certificate{tlsclient.Certificate(cfg.Identity)},
		// The certificate is checked against the pins after the handshake.
		ClientAuth: tls.RequireAnyClientCert,
		MinVersion: tls.VersionTLS13,
		MaxVersion: tls.VersionTLS13,
	}
	listener, err := tls.Listen("tcp", fmt.Sprintf(":%d", Port), config)
	if err != nil {
		return err
	}
	defer listener.Close()
	cfg.Log(fmt.Sprintf("listening for wake requests on port %d", Port))
	go func() {
		<-ctx.Done()
		_ = listener.Close()
	}()

	for {
		conn, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			time.Sleep(100 * time.Millisecond)
			continue
		}
		go handle(conn, cfg, requests)
	}
}

func handle(conn net.Conn, cfg Config, requests chan<- Request) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))

	if err := conn.(*tls.Conn).Handshake(); err != nil {
		return
	}
	state := conn.(*tls.Conn).ConnectionState()
	if len(state.PeerCertificates) == 0 {
		return
	}
	leaf := state.PeerCertificates[0]
	if leaf == nil {
		return
	}
	peerID := uniquePeer(cfg.Trust, leaf)
	if peerID == "" {
		cfg.Log("wake request from an unpinned peer; ignored")
		return
	}

	var header [4]byte
	if _, err := io.ReadFull(conn, header[:]); err != nil {
		return
	}
	length := binary.BigEndian.Uint32(header[:])
	if length == 0 || length > maxKnockBytes {
		return
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(conn, body); err != nil {
		return
	}
	var frame knockFrame
	if err := json.Unmarshal(body, &frame); err != nil || frame.Type != frameType {
		cfg.Log("ignored a malformed wake request")
		return
	}

	remoteIP := ""
	if address, ok := conn.RemoteAddr().(*net.TCPAddr); ok {
		remoteIP = address.IP.String()
	}
	request := Request{PeerID: peerID, RemoteIP: remoteIP, Intent: frame.Intent}
	select {
	case requests <- request:
	default:
		// A wake is already queued; one is enough.
	}
	cfg.Log(fmt.Sprintf("wake request from %s (%s)", peerID, frame.Intent))
}

// uniquePeer names the one paired peer holding this key; ambiguity is
// refused, exactly like the media listener's PeerDirectory.
func uniquePeer(store *trust.Store, leaf *x509.Certificate) string {
	spki := leaf.RawSubjectPublicKeyInfo
	matches := make([]string, 0, 1)
	for peerID, pin := range store.Pinned() {
		if string(pin) == string(spki) {
			matches = append(matches, peerID)
		}
	}
	if len(matches) != 1 {
		return ""
	}
	return matches[0]
}
