package pairing

import (
	"crypto/ecdh"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"testing"
)

// The fixtures are the same vectors the Swift and Kotlin implementations use.
type fixture struct {
	Name                          string            `json:"name"`
	SAS                           string            `json:"sas"`
	HelloCommitment               string            `json:"helloCommitment"`
	Initiator                     fixtureSide       `json:"initiator"`
	Responder                     fixtureSide       `json:"responder"`
	InitiatorConfirmationAccepted string            `json:"initiatorConfirmationAccepted"`
	InitiatorConfirmationRejected string            `json:"initiatorConfirmationRejected"`
	ResponderConfirmationAccepted string            `json:"responderConfirmationAccepted"`
	ResponderConfirmationRejected string            `json:"responderConfirmationRejected"`
	InitiatorSteps                map[string]string `json:"initiatorSteps"`
	ResponderSteps                map[string]string `json:"responderSteps"`
}

type fixtureSide struct {
	DeviceID            string `json:"deviceID"`
	DisplayName         string `json:"displayName"`
	EphemeralPrivateKey string `json:"ephemeralPrivateKey"`
	EphemeralPublicKey  string `json:"ephemeralPublicKey"`
	IdentitySPKI        string `json:"identitySPKI"`
	Nonce               string `json:"nonce"`
}

func mustB64(t *testing.T, text string) []byte {
	t.Helper()
	value, err := base64.StdEncoding.DecodeString(text)
	if err != nil {
		t.Fatalf("base64: %v", err)
	}
	return value
}

func sideHandshake(t *testing.T, side fixtureSide, role byte) *handshake {
	t.Helper()
	private, err := hex.DecodeString(side.EphemeralPrivateKey)
	if err != nil {
		t.Fatal(err)
	}
	ephemeral, err := ecdh.P256().NewPrivateKey(private)
	if err != nil {
		t.Fatal(err)
	}
	return handshakeWith(role, side.DeviceID, side.DisplayName,
		mustB64(t, side.IdentitySPKI), ephemeral, mustB64(t, side.Nonce))
}

func TestPairingVectors(t *testing.T) {
	raw, err := os.ReadFile("../../../../fixtures/receiver-protocol/swift-vectors.json")
	if err != nil {
		t.Skip("shared fixtures are not checked out")
	}
	var document struct {
		PairingVersion int       `json:"pairingVersion"`
		Pairing        []fixture `json:"pairing"`
	}
	if err := json.Unmarshal(raw, &document); err != nil {
		t.Fatal(err)
	}
	if document.PairingVersion != Version {
		t.Fatalf("pairing version: got %d, want %d", Version, document.PairingVersion)
	}
	for _, vector := range document.Pairing {
		t.Run(vector.Name, func(t *testing.T) {
			initiator := sideHandshake(t, vector.Initiator, roleInitiator)
			responder := sideHandshake(t, vector.Responder, roleResponder)

			if got := base64.StdEncoding.EncodeToString(HelloCommitment(initiator.local)); got != vector.HelloCommitment {
				t.Errorf("commitment: got %s want %s", got, vector.HelloCommitment)
			}

			initiatorResult, err := initiator.result(responder.local)
			if err != nil {
				t.Fatal(err)
			}
			responderResult, err := responder.result(initiator.local)
			if err != nil {
				t.Fatal(err)
			}

			if initiatorResult.Pending.SAS != vector.SAS {
				t.Errorf("SAS: got %q want %q", initiatorResult.Pending.SAS, vector.SAS)
			}
			if initiatorResult.Pending.PeerID != vector.Responder.DeviceID {
				t.Errorf("peer id: got %s", initiatorResult.Pending.PeerID)
			}
			if responderResult.Pending.PeerID != vector.Initiator.DeviceID {
				t.Errorf("peer id: got %s", responderResult.Pending.PeerID)
			}

			checks := []struct {
				name  string
				value []byte
				want  string
			}{
				{"initiator accepted", initiatorResult.Confirmation(true).Authenticator, vector.InitiatorConfirmationAccepted},
				{"initiator rejected", initiatorResult.Confirmation(false).Authenticator, vector.InitiatorConfirmationRejected},
				{"responder accepted", responderResult.Confirmation(true).Authenticator, vector.ResponderConfirmationAccepted},
				{"responder rejected", responderResult.Confirmation(false).Authenticator, vector.ResponderConfirmationRejected},
				{"initiator commit", initiatorResult.StepAuthenticator(stepCommit), vector.InitiatorSteps["commit"]},
				{"initiator commitAck", initiatorResult.StepAuthenticator(stepCommitAck), vector.InitiatorSteps["commitAck"]},
				{"initiator abort", initiatorResult.StepAuthenticator(stepAbort), vector.InitiatorSteps["abort"]},
				{"responder commit", responderResult.StepAuthenticator(stepCommit), vector.ResponderSteps["commit"]},
				{"responder commitAck", responderResult.StepAuthenticator(stepCommitAck), vector.ResponderSteps["commitAck"]},
				{"responder abort", responderResult.StepAuthenticator(stepAbort), vector.ResponderSteps["abort"]},
			}
			for _, check := range checks {
				if got := base64.StdEncoding.EncodeToString(check.value); got != check.want {
					t.Errorf("%s: got %s want %s", check.name, got, check.want)
				}
			}

			if err := initiatorResult.Verify(responderResult.Confirmation(true)); err != nil {
				t.Errorf("verify: %v", err)
			}
			if err := responderResult.Verify(initiatorResult.Confirmation(true)); err != nil {
				t.Errorf("verify: %v", err)
			}
		})
	}
}

func TestRejectsNonCanonicalSPKI(t *testing.T) {
	if isCanonicalP256SPKI([]byte{0x30, 0x00}) {
		t.Fatal("accepted garbage as a pin")
	}
}
