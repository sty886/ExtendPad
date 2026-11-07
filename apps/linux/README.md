# ExtendPad Linux sender

Shows a Linux X11 desktop on any ExtendPad receiver (Android tablet or Mac)
and lets the receiver's touch and keyboard drive it. It speaks the same wire
protocol as the Mac sender (`docs/PROTOCOL.md`, pv 22); the receiver needs no
changes.

Two transports, one protocol:

* **Wi-Fi / LAN** — the sender discovers the receiver over Bonjour
  (`_opensidecar._tcp`) and dials its pinned mutual-TLS listener on 9001.
* **USB** — `adb forward` exposes the receiver's ports on loopback; the same
  TLS connection runs through the cable. USB is a route, never trust
  (`docs/PROTOCOL.md` §2.2).

Everything is pinned: TLS 1.3 only, the receiver's certificate SPKI must equal
the pin stored at pairing, and pairing itself is the v13 commit-reveal
ceremony with a six-digit code shown on both screens.

This is a single static Go binary (no interpreter, no runtime dependencies).
Capture and encode are done by ffmpeg, so the CPU cost lives in libx264.

## Requirements

* Ubuntu 22.04+ (or any Linux with X11 and ffmpeg)
* `ffmpeg` with libx264 — `sudo apt install ffmpeg`
* `x11-xserver-utils` (xrandr) and `xcvt` (`cvt`) — needed for extend mode
* For USB: `adb`, and the tablet visible to this machine's adb server
* A running X display (a VNC session on a server is fine; the sender detects
  it, e.g. `:2`)

The package declares these dependencies; `apt` installs them automatically.

## Install

```sh
sudo dpkg -i extendpad-sender_0.1.0_amd64.deb
# or, if a dependency is missing:
sudo apt install ./extendpad-sender_0.1.0_amd64.deb
```

The post-install script enables `extendpad@<user>.service` for the user who
ran the install (`$SUDO_USER`). One process does three things: it advertises
this host as `_opendisplay-mac-pair._tcp` (so the tablet's **Available
hosts** list shows it), answers receiver-initiated pairing, and listens for
the tablet's Connect/Wake request on port 9003 before dialing.

To choose explicitly:

```sh
sudo systemctl enable --now extendpad@ty.service
```

## Pair once

From the tablet (receiver-initiated). Keep the service running; with nothing
paired it only advertises:

```sh
# In ExtendPad: Available hosts -> "Ubuntu (ty)" -> Connect -> Wi-Fi
# The tablet shows the code, and the sender logs:
#   pairing request from MRX-W39: code 123 456 — run "extendpad confirm 123456" within 60 s
extendpad confirm 123456                    # only after the tablet shows the same code
```

If another tablet is already streaming (one session at a time), stop
`extendpad@ty.service` while pairing the new one.

Or from the server (sender-initiated), which also works without the pair
service:

```sh
extendpad doctor                       # checks ffmpeg, X, identity
extendpad pair --host 192.168.31.244   # or --usb
```

Both screens show the same six-digit code. Confirm it on the tablet
(**Codes Match**) and answer `y` here. Trust is written only after both
confirmations are authenticated.

Over USB the tablet must be attached to *this* machine (`adb devices` must
list it as `device`); wireless debugging reached with `adb connect` works too.

Then start the streaming service:

```sh
sudo systemctl restart extendpad@ty.service
journalctl -u extendpad@ty.service -f
```

## Run by hand

```sh
extendpad run                 # keeps reconnecting, Ctrl-C to stop
extendpad run --host 192.168.31.244
extendpad run --usb
extendpad run --mode extend   # virtual second monitor instead of mirroring
extendpad run --no-input      # view only
```

On a server the usual setup is a mirror of the existing X/VNC desktop, so the
tablet shows exactly what an operator would see at the console. `--mode
extend` makes the output's mode cover both screens, then splits it with
`xrandr --setmonitor` and captures the new region; the original mode is
restored when the session ends, including on SIGTERM.

## Commands

| command | purpose |
|---|---|
| `extendpad pair` | sender-initiated pairing (Wi-Fi or `--usb`) |
| `extendpad serve` | advertise for pairing (receiver-initiated) |
| `extendpad confirm <code>` | accept the waiting pairing request |
| `extendpad reject` | decline the waiting pairing request |
| `extendpad run` | stream and reconnect |
| `extendpad devices` | list paired receivers and fingerprints |
| `extendpad forget <id>` | remove a pin |
| `extendpad doctor` | check ffmpeg, X, identity, pins, adb |
| `extendpad status` | show saved settings |

Settings live in `~/.config/extendpad/config.json`; identity and pins in
`~/.local/share/extendpad/` (private key mode 0600). Files written by the
earlier Python implementation are read unchanged, so an existing pairing keeps
working after upgrading.

## Input

Input is granted per connection by this sender (`allowInputState`). The
receiver still has to request control; every session starts with input off on
the receiver side. Touch maps to the X pointer, `scroll.dx/dy` to wheel
buttons, keyboard HID usages to the host keymap, and committed text through
Unicode keysyms. All held keys/buttons/modifiers are released when the session
ends, pauses, or the receiver sends `cancel`.

Use `--no-input` for a pure monitoring session.

## Build the package

```sh
sudo apt install golang-go dpkg-dev
cd apps/linux
./build-deb.sh                 # build/extendpad-sender_0.1.0_amd64.deb
VERSION=0.2.0 ./build-deb.sh
```

The binary is built with `CGO_ENABLED=0`, so it is statically linked and has
no shared-library dependencies beyond the X server at runtime.

## Tests

```sh
go test ./...
```

The pairing implementation is checked byte-for-byte against
`fixtures/receiver-protocol/swift-vectors.json`, the same vectors the Swift
and Kotlin implementations use.

## Troubleshooting

* **Pairing fails while the tablet is casting** — the pairing prompt only
  renders on the receiver's home screen. End the current session first.
* **No receiver found** — pass `--host`; discovery is a hint, not a
  requirement.
* **Display not found** — check that the X/VNC session runs for this user and
  pass `--display :2`.
* **USB** — `adb devices` must show an authorized device on this host; the
  tablet cannot be attached to a different computer.
* **The service runs as the wrong user** — the template uses
  `HOME=/home/<user>`; for another home layout, copy the unit and adjust it.
