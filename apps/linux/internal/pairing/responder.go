package pairing

import (
	"bytes"
	"io"
	"time"
)

// RunResponder is the advertised side of the ceremony: the receiver dials us
// after discovering `_opendisplay-mac-pair._tcp` and runs the initiator half.
//
// Nothing of ours goes out until a valid commitment arrives, and the code is
// only shown once the reveal matched it. Trust is persisted before the
// commitAck, so a lost ack cannot undo a committed pairing.
func RunResponder(conn io.ReadWriteCloser, options Options) (Pending, error) {
	setReadDeadline(conn, time.Now().Add(10*time.Second))
	request, err := readEnvelope(conn)
	if err != nil {
		return Pending{}, err
	}
	commitment := request.HelloCommitment
	if request.Kind != kindHelloCommit || commitment == nil || len(commitment) != 32 {
		return Pending{}, fail("Invalid pairing message")
	}

	handshake, err := newHandshake(roleResponder, options.LocalID, options.LocalName, options.IdentitySPKI)
	if err != nil {
		return Pending{}, err
	}
	if err := writeEnvelope(conn, Envelope{Kind: kindHello, Hello: handshake.local}); err != nil {
		return Pending{}, err
	}

	setReadDeadline(conn, time.Now().Add(5*time.Second))
	reveal, err := readEnvelope(conn)
	if err != nil {
		return Pending{}, err
	}
	if reveal.Kind != kindHelloReveal || reveal.Hello == nil {
		return Pending{}, fail("Invalid pairing message")
	}
	if !bytes.Equal(HelloCommitment(reveal.Hello), commitment) {
		return Pending{}, fail("Pairing could not be verified")
	}

	result, err := handshake.result(reveal.Hello)
	if err != nil {
		return Pending{}, err
	}
	pending, classification := classify(result.Pending, options.Store.Pin(result.Pending.PeerID))
	if classification == "identity-changed" {
		return Pending{}, fail("Device identity changed")
	}

	setReadDeadline(conn, time.Now().Add(60*time.Second))
	pump := startPump(conn, result)
	accepted := options.Decide(pending)
	if pump.aborted() {
		return Pending{}, fail("Pairing was cancelled on the other device")
	}
	if err := writeEnvelope(conn, Envelope{
		Kind:         kindConfirm,
		Confirmation: ptr(result.Confirmation(accepted)),
	}); err != nil {
		return Pending{}, err
	}
	if !accepted {
		return Pending{}, fail("Pairing was cancelled")
	}

	var peerConfirmation *Confirmation
	for {
		frame, err := pump.next()
		if err != nil {
			return Pending{}, err
		}
		switch frame.Kind {
		case kindConfirm:
			if frame.Confirmation == nil {
				return Pending{}, fail("Invalid pairing message")
			}
			if err := result.Verify(*frame.Confirmation); err != nil {
				return Pending{}, err
			}
			peerConfirmation = frame.Confirmation
		case kindCommit:
			if peerConfirmation == nil || frame.Authenticator == nil {
				return Pending{}, fail("Invalid pairing message")
			}
			if err := result.VerifyStep(stepCommit, frame.Authenticator); err != nil {
				return Pending{}, err
			}
			if err := finalizeTrust(options.Store, pending, classification, result, *peerConfirmation); err != nil {
				return Pending{}, err
			}
			// Committed and persisted: a lost ack cannot undo it.
			_ = writeEnvelope(conn, Envelope{
				Kind:          kindCommitAck,
				Authenticator: result.StepAuthenticator(stepCommitAck),
			})
			return pending, nil
		default:
			return Pending{}, fail("Invalid pairing message")
		}
	}
}

func setReadDeadline(conn io.ReadWriteCloser, deadline time.Time) {
	if setter, ok := conn.(interface{ SetReadDeadline(time.Time) error }); ok {
		_ = setter.SetReadDeadline(deadline)
	}
}
