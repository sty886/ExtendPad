// Package config holds the sender's on-disk settings and XDG paths.
package config

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// Settings is the saved sender configuration. Field names match the keys the
// previous implementation wrote, so an existing config.json keeps working.
type Settings struct {
	PeerID     string `json:"peer_id,omitempty"`
	Host       string `json:"host,omitempty"`
	Mode       string `json:"mode"`
	FPS        int    `json:"fps"`
	Bitrate    string `json:"bitrate"`
	Preset     string `json:"preset"`
	AllowInput bool   `json:"allow_input"`
	Display    string `json:"display,omitempty"`
	USB        bool   `json:"usb"`
	Autostart  bool   `json:"autostart"`
}

// Defaults returns a settings value with every optional field filled in.
func Defaults() Settings {
	return Settings{
		Mode:       "mirror",
		FPS:        30,
		Bitrate:    "6M",
		Preset:     "veryfast",
		AllowInput: true,
		Autostart:  true,
	}
}

// Load reads config.json, falling back to defaults for missing fields.
func Load() Settings {
	settings := Defaults()
	raw, err := os.ReadFile(ConfigPath())
	if err != nil {
		return settings
	}
	// Unmarshal over the defaults so a partial file still has sane values.
	_ = json.Unmarshal(raw, &settings)
	settings.applyDefaults()
	return settings
}

func (s *Settings) applyDefaults() {
	if s.Mode != "extend" {
		s.Mode = "mirror"
	}
	if s.FPS <= 0 {
		s.FPS = 30
	}
	if s.Bitrate == "" {
		s.Bitrate = "6M"
	}
	if s.Preset == "" {
		s.Preset = "veryfast"
	}
}

// Save writes config.json atomically with private permissions.
func (s Settings) Save() error {
	path := ConfigPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	raw, err := json.MarshalIndent(s, "", " ")
	if err != nil {
		return err
	}
	return writePrivate(path, raw)
}

func writePrivate(path string, data []byte) error {
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, data, 0o600); err != nil {
		return err
	}
	return os.Rename(temporary, path)
}

func home() string {
	if h, err := os.UserHomeDir(); err == nil && h != "" {
		return h
	}
	return os.Getenv("HOME")
}

// StateDir is ~/.local/share/extendpad (or $XDG_DATA_HOME/extendpad).
func StateDir() string {
	if dir := os.Getenv("XDG_DATA_HOME"); dir != "" {
		return filepath.Join(dir, "extendpad")
	}
	return filepath.Join(home(), ".local", "share", "extendpad")
}

// ConfigDir is ~/.config/extendpad (or $XDG_CONFIG_HOME/extendpad).
func ConfigDir() string {
	if dir := os.Getenv("XDG_CONFIG_HOME"); dir != "" {
		return filepath.Join(dir, "extendpad")
	}
	return filepath.Join(home(), ".config", "extendpad")
}

func IdentityDir() string { return filepath.Join(StateDir(), "identity") }
func PinsPath() string    { return filepath.Join(StateDir(), "pins.json") }
func ConfigPath() string  { return filepath.Join(ConfigDir(), "config.json") }

// HomeDir returns the user's home directory (used by the service template).
func HomeDir() string { return home() }
