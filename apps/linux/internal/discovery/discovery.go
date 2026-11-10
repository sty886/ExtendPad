// Package discovery finds ExtendPad receivers over Bonjour.
//
// Discovery is only a hint: it says where a receiver claims to be. Identity
// still comes solely from the pinned TLS certificate; the TXT id is checked
// against the hello only after that.
package discovery

import (
	"context"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/grandcat/zeroconf"
)

const MediaService = "_opensidecar._tcp"

type Receiver struct {
	Name         string
	Host         string
	Port         int
	InstallID    string
	PV           int
	PP           int
	ConnectToken string
	// ConnectTarget is the install id of the one sender the receiver's user
	// asked for (TXT `crt`). Empty on receivers that predate targeting: such a
	// request names nobody, so every paired sender may answer it.
	ConnectTarget string
}

// AskedFor reports whether this Connect request is addressed to senderID. A
// receiver that predates `crt` publishes no target: its request names nobody,
// so every paired sender answers it, exactly as before.
func (r Receiver) AskedFor(senderID string) bool {
	return r.ConnectTarget == "" || r.ConnectTarget == senderID
}

func (r Receiver) Label() string {
	label := r.Name + "  " + r.Host
	if r.PV > 0 {
		label += "  pv " + strconv.Itoa(r.PV)
	}
	return label
}

// Browse looks for media services for at most timeout.
func Browse(ctx context.Context, timeout time.Duration) ([]Receiver, error) {
	resolver, err := zeroconf.NewResolver(nil)
	if err != nil {
		return nil, err
	}
	entries := make(chan *zeroconf.ServiceEntry)

	var mutex sync.Mutex
	found := map[string]Receiver{}

	collected := make(chan struct{})
	go func() {
		defer close(collected)
		for entry := range entries {
			receiver, ok := convert(entry)
			if !ok {
				continue
			}
			key := receiver.InstallID
			if key == "" {
				key = receiver.Host
			}
			mutex.Lock()
			found[key] = receiver
			mutex.Unlock()
		}
	}()

	browseContext, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	if err := resolver.Browse(browseContext, MediaService, "local.", entries); err != nil {
		return nil, err
	}
	select {
	case <-collected:
	case <-time.After(500 * time.Millisecond):
	}

	mutex.Lock()
	defer mutex.Unlock()
	result := make([]Receiver, 0, len(found))
	for _, receiver := range found {
		result = append(result, receiver)
	}
	return result, nil
}

// Watch polls receivers' advertisements and calls onRequest when a paired
// receiver publishes a new Connect token (its TXT `cr`). The receiver writes
// the token when its user taps Connect, and waits for the sender to dial;
// each fresh browse is needed because a TXT update is not re-delivered by the
// mDNS client.
func Watch(ctx context.Context, onRequest func(Receiver)) error {
	seen := map[string]string{}
	for {
		if ctx.Err() != nil {
			return nil
		}
		receivers, err := snapshot(ctx, 1500*time.Millisecond)
		if err == nil {
			for _, receiver := range receivers {
				if receiver.InstallID == "" || receiver.ConnectToken == "" {
					continue
				}
				if seen[receiver.InstallID] == receiver.ConnectToken {
					continue
				}
				seen[receiver.InstallID] = receiver.ConnectToken
				onRequest(receiver)
			}
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(1 * time.Second):
		}
	}
}

// snapshot browses for the whole timeout, unlike Browse's early return.
func snapshot(ctx context.Context, timeout time.Duration) ([]Receiver, error) {
	resolver, err := zeroconf.NewResolver(nil)
	if err != nil {
		return nil, err
	}
	entries := make(chan *zeroconf.ServiceEntry)
	var mutex sync.Mutex
	found := map[string]Receiver{}
	collected := make(chan struct{})
	go func() {
		defer close(collected)
		for entry := range entries {
			receiver, ok := convert(entry)
			if !ok {
				continue
			}
			key := receiver.InstallID
			if key == "" {
				key = receiver.Host
			}
			mutex.Lock()
			found[key] = receiver
			mutex.Unlock()
		}
	}()

	browseContext, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	if err := resolver.Browse(browseContext, MediaService, "local.", entries); err != nil {
		return nil, err
	}
	select {
	case <-collected:
	case <-time.After(timeout + 500*time.Millisecond):
	}
	mutex.Lock()
	defer mutex.Unlock()
	result := make([]Receiver, 0, len(found))
	for _, receiver := range found {
		result = append(result, receiver)
	}
	return result, nil
}

func convert(entry *zeroconf.ServiceEntry) (Receiver, bool) {
	host := ""
	if len(entry.AddrIPv4) > 0 {
		host = entry.AddrIPv4[0].String()
	} else if len(entry.AddrIPv6) > 0 {
		host = entry.AddrIPv6[0].String()
	}
	if host == "" || entry.Port == 0 {
		return Receiver{}, false
	}
	receiver := Receiver{Name: entry.Instance, Host: host, Port: entry.Port}
	for _, item := range entry.Text {
		key, value, ok := strings.Cut(item, "=")
		if !ok {
			continue
		}
		switch key {
		case "id":
			receiver.InstallID = value
		case "pv":
			receiver.PV, _ = strconv.Atoi(value)
		case "pp":
			receiver.PP, _ = strconv.Atoi(value)
		case "cr":
			receiver.ConnectToken = value
		case "crt":
			receiver.ConnectTarget = value
		}
	}
	return receiver, true
}
