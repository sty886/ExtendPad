package discovery

import (
	"net"
	"testing"

	"github.com/grandcat/zeroconf"
)

func TestAskedFor(t *testing.T) {
	cases := []struct {
		name   string
		target string
		sender string
		want   bool
	}{
		{"a request for this sender", "sender-a", "sender-a", true},
		{"a request for another sender", "sender-b", "sender-a", false},
		// Receivers before `crt` publish no target. Their Connect names nobody,
		// so every paired sender must keep answering it.
		{"an untargeted request from an older receiver", "", "sender-a", true},
	}
	for _, tc := range cases {
		if got := (Receiver{ConnectTarget: tc.target}).AskedFor(tc.sender); got != tc.want {
			t.Errorf("%s: AskedFor(%q) = %v, want %v", tc.name, tc.sender, got, tc.want)
		}
	}
}

func TestConvertReadsTheConnectTarget(t *testing.T) {
	entry := &zeroconf.ServiceEntry{
		ServiceRecord: zeroconf.ServiceRecord{Instance: "Tablet", Service: MediaService, Domain: "local."},
		HostName:      "tablet.local.",
		Port:          9001,
		Text:          []string{"id=receiver-1", "pv=22", "cr=abc123", "crt=sender-a"},
		AddrIPv4:      []net.IP{net.ParseIP("192.0.2.10")},
	}
	receiver, ok := convert(entry)
	if !ok {
		t.Fatal("convert rejected a complete entry")
	}
	if receiver.ConnectToken != "abc123" {
		t.Errorf("ConnectToken = %q, want abc123", receiver.ConnectToken)
	}
	if receiver.ConnectTarget != "sender-a" {
		t.Errorf("ConnectTarget = %q, want sender-a", receiver.ConnectTarget)
	}
	if !receiver.AskedFor("sender-a") || receiver.AskedFor("sender-b") {
		t.Errorf("target not applied: AskedFor(sender-a)=%v AskedFor(sender-b)=%v",
			receiver.AskedFor("sender-a"), receiver.AskedFor("sender-b"))
	}
}
