// Package display finds the X display to stream and creates the optional
// virtual second monitor.
//
// On a server the desktop usually exists as a VNC/Xorg session the user
// already has, so mirror mode simply captures that screen. Extend mode makes
// the output's mode cover both screens (otherwise the X server paints nothing
// outside the old CRTC and the new area is black), then splits it with
// xrandr --setmonitor. Both are undone by Restore.
package display

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func ownsSocket(info os.FileInfo) bool {
	stat, ok := info.Sys().(*syscall.Stat_t)
	return ok && int(stat.Uid) == os.Getuid()
}

type Display struct {
	Name       string
	XAuthority string
	Width      int
	Height     int
}

type Region struct {
	X, Y, Width, Height int
}

func (r Region) Size() (int, int) { return r.Width, r.Height }

type Output struct {
	Name   string
	Width  int
	Height int
	Mode   string
}

var ErrNoDisplay = errors.New("no X display found")

var currentSize = regexp.MustCompile(`current (\d+) x (\d+)`)
var socketName = regexp.MustCompile(`^X(\d+)$`)
var connected = regexp.MustCompile(`^(\S+) connected (\d+)x(\d+)\+`)

// Env returns the process environment with DISPLAY/XAUTHORITY replaced.
func (d *Display) Env() []string {
	environment := make([]string, 0, len(os.Environ())+2)
	for _, item := range os.Environ() {
		if strings.HasPrefix(item, "DISPLAY=") || strings.HasPrefix(item, "XAUTHORITY=") {
			continue
		}
		environment = append(environment, item)
	}
	environment = append(environment, "DISPLAY="+d.Name)
	if d.XAuthority != "" {
		environment = append(environment, "XAUTHORITY="+d.XAuthority)
	}
	return environment
}

// Run executes a command against this display and returns combined output.
func (d *Display) Run(name string, arguments ...string) (string, error) {
	command := exec.Command(name, arguments...)
	command.Env = d.Env()
	output, err := command.CombinedOutput()
	text := strings.TrimSpace(string(output))
	if err != nil {
		if text == "" {
			text = err.Error()
		}
		return text, fmt.Errorf("%s: %s", name, text)
	}
	return text, nil
}

func xauthority() string {
	if configured := os.Getenv("XAUTHORITY"); configured != "" {
		if _, err := os.Stat(configured); err == nil {
			return configured
		}
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	candidate := filepath.Join(home, ".Xauthority")
	if _, err := os.Stat(candidate); err == nil {
		return candidate
	}
	return ""
}

// Detect returns the first usable X display, honouring DISPLAY or explicit.
func Detect(explicit string) (*Display, error) {
	var candidates []string
	add := func(name string) {
		if name == "" {
			return
		}
		for _, existing := range candidates {
			if existing == name {
				return
			}
		}
		candidates = append(candidates, name)
	}
	add(explicit)
	add(os.Getenv("DISPLAY"))
	sockets, _ := filepath.Glob("/tmp/.X11-unix/X*")
	for _, socket := range sockets {
		match := socketName.FindStringSubmatch(filepath.Base(socket))
		if match == nil {
			continue
		}
		info, err := os.Stat(socket)
		if err != nil || !ownsSocket(info) {
			continue
		}
		add(":" + match[1])
	}

	authority := xauthority()
	for _, name := range candidates {
		probe := &Display{Name: name, XAuthority: authority}
		output, err := probe.Run("xrandr", "--query")
		if err != nil {
			continue
		}
		match := currentSize.FindStringSubmatch(output)
		if match == nil {
			continue
		}
		width, _ := strconv.Atoi(match[1])
		height, _ := strconv.Atoi(match[2])
		if width < 32 || height < 32 {
			continue
		}
		probe.Width, probe.Height = width, height
		return probe, nil
	}
	return nil, ErrNoDisplay
}

// Wait retries Detect until timeout or context cancellation.
func Wait(ctx context.Context, timeout time.Duration, explicit string) (*Display, error) {
	deadline := time.Now().Add(timeout)
	for {
		if found, err := Detect(explicit); err == nil {
			return found, nil
		}
		if time.Now().After(deadline) {
			return nil, ErrNoDisplay
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
}

func (d *Display) ScreenSize() (int, int) {
	output, err := d.Run("xrandr", "--query")
	if err != nil {
		return d.Width, d.Height
	}
	match := currentSize.FindStringSubmatch(output)
	if match == nil {
		return d.Width, d.Height
	}
	width, _ := strconv.Atoi(match[1])
	height, _ := strconv.Atoi(match[2])
	return width, height
}

// Outputs parses connected outputs and their current mode.
func (d *Display) Outputs() ([]Output, error) {
	text, err := d.Run("xrandr", "--query")
	if err != nil {
		return nil, err
	}
	var outputs []Output
	current := -1
	for _, line := range strings.Split(text, "\n") {
		if match := connected.FindStringSubmatch(line); match != nil {
			width, _ := strconv.Atoi(match[2])
			height, _ := strconv.Atoi(match[3])
			outputs = append(outputs, Output{Name: match[1], Width: width, Height: height})
			current = len(outputs) - 1
			continue
		}
		if current >= 0 && outputs[current].Mode == "" && strings.Contains(line, "*") {
			fields := strings.Fields(line)
			if len(fields) > 0 && !strings.HasPrefix(fields[0], "Screen") {
				outputs[current].Mode = fields[0]
			}
		}
	}
	return outputs, nil
}

// modeline asks cvt for a timing of width x height at 60 Hz.
func modeline(width, height int) (string, []string, error) {
	cvt, err := exec.LookPath("cvt")
	if err != nil {
		return "", nil, errors.New("cvt is not installed")
	}
	output, err := exec.Command(cvt, strconv.Itoa(width), strconv.Itoa(height), "60").Output()
	if err != nil {
		return "", nil, err
	}
	for _, line := range strings.Split(string(output), "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "Modeline") {
			continue
		}
		rest := strings.TrimSpace(strings.TrimPrefix(line, "Modeline"))
		fields := strings.Fields(rest)
		if len(fields) < 2 {
			break
		}
		name := strings.Trim(fields[0], `"`)
		return name, fields[1:], nil
	}
	return "", nil, errors.New("cvt produced no modeline")
}

type ExtendedMonitor struct {
	display      *Display
	width        int
	height       int
	output       Output
	combinedMode string
	originalMode string
	region       Region
	active       bool
}

func NewExtended(display *Display, width, height int) *ExtendedMonitor {
	return &ExtendedMonitor{display: display, width: width, height: height}
}

func (m *ExtendedMonitor) Create() (Region, error) {
	baseWidth, baseHeight := m.display.ScreenSize()
	totalWidth := baseWidth + m.width
	totalHeight := max(baseHeight, m.height)
	name, arguments, err := modeline(totalWidth, totalHeight)
	if err != nil {
		return Region{}, err
	}
	outputs, err := m.display.Outputs()
	if err != nil {
		return Region{}, err
	}
	found := false
	for _, output := range outputs {
		if output.Mode != "" {
			m.output = output
			found = true
			break
		}
	}
	if !found {
		return Region{}, errors.New("no mode-switchable X output")
	}
	m.combinedMode = name
	m.originalMode = m.output.Mode

	if _, err := m.display.Run("xrandr", append([]string{"--newmode", name}, arguments...)...); err != nil {
		m.Restore()
		return Region{}, err
	}
	if _, err := m.display.Run("xrandr", "--addmode", m.output.Name, name); err != nil {
		m.Restore()
		return Region{}, err
	}
	if _, err := m.display.Run("xrandr", "--output", m.output.Name, "--mode", name); err != nil {
		m.Restore()
		return Region{}, err
	}
	millimetresW := max(1, int(float64(m.width)*25.4/96))
	millimetresH := max(1, int(float64(m.height)*25.4/96))
	geometry := fmt.Sprintf("%d/%dx%d/%d+%d+0",
		m.width, millimetresW, m.height, millimetresH, baseWidth)
	if _, err := m.display.Run("xrandr", "--setmonitor", "EXTENDPAD", geometry, "none"); err != nil {
		m.Restore()
		return Region{}, err
	}
	m.active = true
	m.region = Region{X: baseWidth, Y: 0, Width: m.width, Height: m.height}
	return m.region, nil
}

func (m *ExtendedMonitor) Restore() {
	if !m.active && m.combinedMode == "" {
		return
	}
	_, _ = m.display.Run("xrandr", "--delmonitor", "EXTENDPAD")
	if m.originalMode != "" {
		_, _ = m.display.Run("xrandr", "--output", m.output.Name, "--mode", m.originalMode)
	}
	if m.combinedMode != "" {
		_, _ = m.display.Run("xrandr", "--delmode", m.output.Name, m.combinedMode)
		_, _ = m.display.Run("xrandr", "--rmmode", m.combinedMode)
	}
	m.active = false
	m.combinedMode = ""
}
