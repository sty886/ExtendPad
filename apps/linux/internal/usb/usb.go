// Package usb exposes the receiver's ports over an authorized adb tunnel.
//
// USB is a route, not trust (PROTOCOL.md 2.2a): the receiver's TLS listener is
// an ordinary TCP port on the Android device, adb forward maps it to loopback,
// and the sender dials loopback exactly as it dials a LAN address. Identity
// still comes only from the pinned certificate.
package usb

import (
	"errors"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

type Forward struct {
	LocalPort  int
	RemotePort int
	Serial     string
}

func (f *Forward) Close() {
	if f == nil {
		return
	}
	_, _ = run("forward", "--remove", fmt.Sprintf("tcp:%d", f.LocalPort))
}

func run(arguments ...string) (string, error) {
	path, err := exec.LookPath("adb")
	if err != nil {
		return "", errors.New("adb is not installed")
	}
	output, err := exec.Command(path, arguments...).CombinedOutput()
	text := strings.TrimSpace(string(output))
	if err != nil {
		if text == "" {
			text = err.Error()
		}
		return text, errors.New(text)
	}
	return text, nil
}

func device(serial string) (string, error) {
	output, err := run("devices")
	if err != nil {
		return "", err
	}
	attached := map[string]string{}
	order := []string{}
	for _, line := range strings.Split(output, "\n")[1:] {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		attached[fields[0]] = fields[1]
		order = append(order, fields[0])
	}
	if serial != "" {
		state, ok := attached[serial]
		if !ok {
			return "", fmt.Errorf("%s is not attached", serial)
		}
		if state != "device" {
			return "", fmt.Errorf("%s is %s", serial, state)
		}
		return serial, nil
	}
	for _, identifier := range order {
		if attached[identifier] == "device" {
			return identifier, nil
		}
	}
	return "", errors.New("no authorized Android device; attach the tablet or run adb connect")
}

// Open maps a free loopback port to remotePort on the attached device.
func Open(remotePort int, serial string) (*Forward, error) {
	identifier, err := device(serial)
	if err != nil {
		return nil, err
	}
	output, err := run("-s", identifier, "forward", "tcp:0", fmt.Sprintf("tcp:%d", remotePort))
	if err != nil {
		return nil, err
	}
	lines := strings.Split(output, "\n")
	port, err := strconv.Atoi(strings.TrimSpace(lines[len(lines)-1]))
	if err != nil {
		return nil, errors.New("adb did not report a forwarded port")
	}
	return &Forward{LocalPort: port, RemotePort: remotePort, Serial: identifier}, nil
}
