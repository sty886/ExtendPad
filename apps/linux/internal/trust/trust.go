// Package trust stores paired receivers: peer ID -> raw SPKI DER.
//
// The JSON layout is the one the earlier implementation wrote, so existing
// pairings survive the upgrade.
package trust

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type entry struct {
	SPKI     string `json:"spki"`
	Name     string `json:"name"`
	PairedAt string `json:"paired_at"`
}

type Store struct {
	path  string
	mutex sync.RWMutex
	pins  map[string]entry
}

func Load(path string) (*Store, error) {
	store := &Store{path: path, pins: map[string]entry{}}
	raw, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return store, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(raw, &store.pins); err != nil {
		return nil, fmt.Errorf("trust store is unreadable: %w", err)
	}
	return store, nil
}

func (s *Store) Pin(peerID string) []byte {
	s.mutex.RLock()
	defer s.mutex.RUnlock()
	return s.pinLocked(peerID)
}

func (s *Store) pinLocked(peerID string) []byte {
	item, ok := s.pins[peerID]
	if !ok {
		return nil
	}
	spki, err := base64.StdEncoding.DecodeString(item.SPKI)
	if err != nil {
		return nil
	}
	return spki
}

func (s *Store) Name(peerID string) string {
	s.mutex.RLock()
	defer s.mutex.RUnlock()
	return s.pins[peerID].Name
}

func (s *Store) Pinned() map[string][]byte {
	s.mutex.RLock()
	defer s.mutex.RUnlock()
	return s.pinnedLocked()
}

func (s *Store) pinnedLocked() map[string][]byte {
	result := make(map[string][]byte, len(s.pins))
	for peerID := range s.pins {
		if pin := s.pinLocked(peerID); pin != nil {
			result[peerID] = pin
		}
	}
	return result
}

func (s *Store) HeldByAnother(peerID string, spki []byte) bool {
	s.mutex.RLock()
	defer s.mutex.RUnlock()
	return s.heldByAnotherLocked(peerID, spki)
}

func (s *Store) heldByAnotherLocked(peerID string, spki []byte) bool {
	for other, pin := range s.pinnedLocked() {
		if other != peerID && bytes.Equal(pin, spki) {
			return true
		}
	}
	return false
}

// SetPin writes trust only when the peer may hold this key. A different key
// for an existing peer is an identity change and needs an explicit re-pair
// (forget first), never a silent overwrite.
func (s *Store) SetPin(peerID string, spki []byte, name string) (bool, error) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	if s.heldByAnotherLocked(peerID, spki) {
		return false, nil
	}
	existing := s.pinLocked(peerID)
	if existing != nil && !bytes.Equal(existing, spki) {
		return false, nil
	}
	s.pins[peerID] = entry{
		SPKI:     base64.StdEncoding.EncodeToString(spki),
		Name:     name,
		PairedAt: time.Now().UTC().Format("2006-01-02T15:04:05Z"),
	}
	if err := s.save(); err != nil {
		return false, err
	}
	return true, nil
}

func (s *Store) Forget(peerID string) error {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	delete(s.pins, peerID)
	return s.save()
}

func (s *Store) save() error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return err
	}
	raw, err := json.MarshalIndent(s.pins, "", " ")
	if err != nil {
		return err
	}
	temporary := s.path + ".tmp"
	if err := os.WriteFile(temporary, raw, 0o600); err != nil {
		return err
	}
	return os.Rename(temporary, s.path)
}
