package pairing

import (
	"net"
	"path/filepath"
	"testing"
	"time"

	"github.com/raiseCatError/ExtendPad/apps/linux/internal/identity"
	"github.com/raiseCatError/ExtendPad/apps/linux/internal/trust"
)

// TestResponderInitiatorRoundTrip runs both halves of the ceremony over an
// in-memory connection: the receiver-initiated path used by "Pair" on an
// Android device.
func TestResponderInitiatorRoundTrip(t *testing.T) {
	initiatorIdentity, err := identity.LoadOrCreate(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	responderIdentity, err := identity.LoadOrCreate(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	initiatorStore, err := trust.Load(filepath.Join(t.TempDir(), "pins.json"))
	if err != nil {
		t.Fatal(err)
	}
	responderStore, err := trust.Load(filepath.Join(t.TempDir(), "pins.json"))
	if err != nil {
		t.Fatal(err)
	}

	initiatorConn, responderConn := tcpPair(t)
	defer initiatorConn.Close()
	defer responderConn.Close()
	_ = initiatorConn.SetDeadline(time.Now().Add(20 * time.Second))
	_ = responderConn.SetDeadline(time.Now().Add(20 * time.Second))

	type outcome struct {
		pending Pending
		err     error
	}
	initiatorDone := make(chan outcome, 1)
	responderDone := make(chan outcome, 1)

	go func() {
		pending, err := RunInitiator(initiatorConn, Options{
			LocalID:      initiatorIdentity.InstallID,
			LocalName:    "initiator",
			IdentitySPKI: initiatorIdentity.SPKI(),
			Store:        initiatorStore,
			Decide:       func(Pending) bool { return true },
		})
		initiatorDone <- outcome{pending, err}
	}()
	go func() {
		pending, err := RunResponder(responderConn, Options{
			LocalID:      responderIdentity.InstallID,
			LocalName:    "responder",
			IdentitySPKI: responderIdentity.SPKI(),
			Store:        responderStore,
			Decide:       func(Pending) bool { return true },
		})
		responderDone <- outcome{pending, err}
	}()

	first := <-initiatorDone
	second := <-responderDone
	if first.err != nil {
		t.Fatalf("initiator: %v", first.err)
	}
	if second.err != nil {
		t.Fatalf("responder: %v", second.err)
	}
	if first.pending.PeerID != responderIdentity.InstallID {
		t.Errorf("initiator saw %s", first.pending.PeerID)
	}
	if second.pending.PeerID != initiatorIdentity.InstallID {
		t.Errorf("responder saw %s", second.pending.PeerID)
	}
	if first.pending.SAS != second.pending.SAS {
		t.Errorf("SAS mismatch: %q vs %q", first.pending.SAS, second.pending.SAS)
	}
	if initiatorStore.Pin(responderIdentity.InstallID) == nil {
		t.Error("initiator did not store the responder pin")
	}
	if responderStore.Pin(initiatorIdentity.InstallID) == nil {
		t.Error("responder did not store the initiator pin")
	}
}

func TestResponderRejectsBadCommitment(t *testing.T) {
	responderIdentity, err := identity.LoadOrCreate(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	store, err := trust.Load(filepath.Join(t.TempDir(), "pins.json"))
	if err != nil {
		t.Fatal(err)
	}
	client, server := tcpPair(t)
	defer client.Close()
	defer server.Close()
	_ = server.SetDeadline(time.Now().Add(5 * time.Second))

	done := make(chan error, 1)
	go func() {
		_, err := RunResponder(server, Options{
			LocalID:      responderIdentity.InstallID,
			LocalName:    "responder",
			IdentitySPKI: responderIdentity.SPKI(),
			Store:        store,
			Decide:       func(Pending) bool { return true },
		})
		done <- err
	}()

	// A well-formed commitment of the wrong bytes must not reveal a hello.
	_ = writeEnvelope(client, Envelope{Kind: kindHelloCommit, HelloCommitment: make([]byte, 32)})
	handshake, _ := newHandshake(roleInitiator, initiatorUUID(t), "initiator", responderIdentity.SPKI())
	_ = writeEnvelope(client, Envelope{Kind: kindHelloReveal, Hello: handshake.local})

	select {
	case err := <-done:
		if err == nil {
			t.Fatal("responder accepted a mismatched commitment")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("responder did not fail")
	}
}

func tcpPair(t *testing.T) (net.Conn, net.Conn) {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	client, err := net.Dial("tcp", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	server, err := listener.Accept()
	if err != nil {
		t.Fatal(err)
	}
	return client, server
}

func initiatorUUID(t *testing.T) string {
	t.Helper()
	value, err := identity.LoadOrCreate(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return value.InstallID
}
