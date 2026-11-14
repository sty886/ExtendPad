package wire

import (
	"bytes"
	"encoding/binary"
	"strings"
	"testing"
	"testing/iotest"
)

func TestFramesAcrossReads(t *testing.T) {
	first := []byte(`{"type":"hello"}`)
	second := []byte{0, 0, 0, 1, 9, 'x'}
	var stream bytes.Buffer
	if err := WriteFrame(&stream, first); err != nil {
		t.Fatal(err)
	}
	if err := WriteFrame(&stream, second); err != nil {
		t.Fatal(err)
	}
	reader := iotest.OneByteReader(bytes.NewReader(stream.Bytes()))
	got, err := ReadFrame(reader)
	if err != nil || !bytes.Equal(got, first) {
		t.Fatalf("first frame: %v %q", err, got)
	}
	got, err = ReadFrame(reader)
	if err != nil || !bytes.Equal(got, second) {
		t.Fatalf("second frame: %v %q", err, got)
	}
}

func TestZeroLengthIsRejected(t *testing.T) {
	var header [4]byte
	binary.BigEndian.PutUint32(header[:], 0)
	if _, err := ReadFrame(bytes.NewReader(header[:])); err == nil {
		t.Fatal("accepted a zero-length frame")
	}
}

func TestClassify(t *testing.T) {
	if !IsControl([]byte(`{"type":"ping"}`)) {
		t.Fatal("control was not recognised")
	}
	if IsControl([]byte{0, 0, 0, 1, 9}) {
		t.Fatal("Annex B was classified as control")
	}
	if IsControl([]byte(`{"a":"` + "\x00" + `"}`)) {
		t.Fatal("JSON with a NUL was classified as control")
	}
	large := []byte(`{"pad":"` + strings.Repeat("a", MaxControlBytes) + `"}`)
	if IsControl(large) {
		t.Fatal("an oversized object was classified as control")
	}
}

func TestMessages(t *testing.T) {
	welcome := Welcome()
	if welcome["pv"] != 22 || welcome["min"] != 1 || welcome["type"] != "welcome" {
		t.Fatalf("welcome: %v", welcome)
	}
	payload, err := Control(welcome)
	if err != nil || !IsControl(payload) {
		t.Fatalf("welcome is not a valid control frame: %v", err)
	}
	invite := SessionInvite("id-1", "manual", "mirror")
	if invite["awaitingSender"] != false || invite["initiator"] != "sender" {
		t.Fatalf("invite: %v", invite)
	}
	if got := AllowInputState(true); got["allowed"] != true || got["state"] != "allowed" {
		t.Fatalf("allowInputState: %v", got)
	}
	if got := AllowInputState(false); got["allowed"] != false || got["state"] != "off" {
		t.Fatalf("allowInputState: %v", got)
	}
	// A sender that cannot inject says so once; the receiver must not keep
	// offering a request that could only be denied.
	if got := AllowInputStateAs(false, "requestsDisabled"); got["allowed"] != false || got["state"] != "requestsDisabled" {
		t.Fatalf("allowInputStateAs: %v", got)
	}
}

func TestControlHasNoNUL(t *testing.T) {
	payload, err := Control(Pong(123, 456))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.IndexByte(payload, 0) >= 0 || payload[0] != '{' || len(payload) >= MaxControlBytes {
		t.Fatalf("bad control payload: % x", payload)
	}
	if !strings.Contains(string(payload), `"mt":456`) {
		t.Fatalf("unexpected pong: %s", payload)
	}
}
