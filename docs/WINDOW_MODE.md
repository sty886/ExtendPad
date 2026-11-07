# Window mode

Besides **Mirror** (show a Mac display) and **Extend** (add a separate
desktop), a device can choose **Windows** in the app to open **Window view**:
the individual **Mac windows** you pick, arranged side by side on that
device. The in-app label is **Windows**, but on the website and in public
marketing we say **Mac windows** or **Window view** so it cannot be
confused with the Windows operating system (a separate unplanned idea,
[#84](https://github.com/raiseCatError/meowdisplay/issues/84)).
Each receiver makes its own choice; another receiver's mode does not change.

- Every receiver, including compact Android phones: up to **9** panes.
- Minimum pane size and the space available decide which arrangements fit.
- One window is the default.

The limit follows the space the app actually has (split screen, a folded
cover screen, Stage Manager), not the device model. When the space shrinks,
extra windows move to **Hidden on this screen** in the window overview; none is
removed, and the arrangement comes back when the space returns.

## Using it

| | Android | Mac Receiver |
| --- | --- | --- |
| Open the window overview | Hold three fingers still, use the rail, or Settings → Display → Choose Windows… | Windows in the title bar, or ⌃⌥W |
| Quick switch | Stage Peek: hold an edge, slide to browse, then tap a window. Full Desktop returns to the whole Mac screen. Rail is optional in Settings. | Overview |
| Switch view | Stage Peek's Full Desktop card or the overview's Mirror/Extend | — |
| Tile options | Tap a tile's name for typing, window choice, rotation, fit, layout and removal controls | Same, while Arrange is on |
| Move a tile | Press and hold its name, then drag to swap or split | Same, while Arrange is on |
| Tabs in a pane | Drag windows onto labels to add, move or reorder tabs | — |
| Drag an app in | Drag an app from Stage Peek onto a pane | — |
| Resize | Arrange Tiles, then drag the grips between tiles | Same |

Removing a tile never closes the Mac window. **Close Window on Mac…** is
separate, asks first, and needs control of the Mac.

Each tile can be rotated on its own (0°, 90°, 180°, 270°). Only the picture
turns; the Mac window doesn't, and clicks, drags, scrolling and Pencil land
where you touch.

## Pointer and keyboard

There is one pointer across all tiles. Moving it over another tile only
highlights that tile; it never changes what you type into. Clicking a tile
makes it the one you type into (its window comes to the front on the Mac) and
that same click goes through. A drag stays in the window it started in, even
if it crosses into another tile.

macOS has one keyboard focus. MeowDisplay sends keys only to the tile you
selected, and only while that window's app really is in front on the Mac. If
something else comes to the front, the tile shows **Typing paused** and
nothing is typed until you tap to resume.

Control still needs the Mac's permission for each session (Request Control). View
Only sessions can arrange tiles and pick windows but send nothing to the Mac.

A press into a tile brings its window to the front first when another window
covers it on the Mac, then lands in it. On Android, hardware keyboards can't
send ⌘ shortcuts (Android keeps the Meta key's combinations for itself): use
the on-screen ⌘ key, or turn on Settings → Input → **Control Key Types ⌘**.

## How it works (sender)

Measured on macOS 27 (integration evidence `W1-sck`): ScreenCaptureKit's
`SCContentFilter(desktopIndependentWindow:)` captures a window's own content
when it is covered, off-screen (including negative coordinates) or belongs to
a hidden app on another Space. Minimized windows and hidden apps deliver no
frames (stills fail with -3811) and resume on the same stream when restored.

So Window mode creates **no virtual display** and never moves, resizes or
re-Spaces a window:

1. one ScreenCaptureKit stream per chosen window, scaled to its tile by the
   window server, at full rate for the active tile and reduced rates for the
   others (30 / 15 / 10 fps as tiles increase; 0 while minimized), at most 16
   window streams on the Mac at once;
2. a GPU compositor (Core Image on Metal) draws the tiles into one canvas the
   size of the receiver's panel, with each tile's fit and rotation;
3. the session's existing encoder sends it as before (H.264 or HEVC).

One encode per receiver keeps hardware encoders and the receivers' decoders
within limits; nine windows never mean nine streams to decode on a phone.
A tiny display stream keeps the Mac's audio and the usual capture lifecycle
(pause, Video Off, recovery).

Windows are listed by identity and metadata, not by position: MeowDisplay's
own windows, system UI, password prompts, the Stage Manager strip, every
app's menu-bar backdrop and untitled off-screen helpers are left out; titled
windows on other Spaces or minimized are kept. A window id is tied to its
process for the session, so a reused id is a different window and a tile
holding the old one is refused, never pointed at the new one.

## Limits

- **Other macOS accounts.** Each account runs its own MeowDisplay (see
  SAME_MAC_SESSIONS.md). A switched-out account has nothing on screen and
  can't be captured, so windows from two accounts can't be shown at the same
  time. Pairing with one account never gives access to another.
- **Several Macs in one workspace.** The protocol carries the host on every
  tile and each Mac handles only its own; receivers connect to one Mac at a
  time today.
- **Headless Macs.** Window mode needs windows on some display, even a virtual
  one. With no display at all it says so and suggests Extend, which creates
  one.
- **Input over covered windows.** macOS delivers clicks to whatever is on top
  at a point. MeowDisplay raises the target window first and sends nothing if
  something still covers it there. Background-window hover isn't possible
  without moving the Mac pointer, so hover reaches the Mac only over the
  active tile.
- **Zoom.** On Android, tile handles follow the unzoomed picture.
- **Stage Manager.** Windows on the current stage stream live. A window in
  the side strip doesn't: measured on macOS 27.0 (26A428) with a disposable
  window drawing a frame counter, ScreenCaptureKit's per-window stream
  suspends, its screenshot fails (-3811), and neither the legacy
  CGWindowListCreateImage nor SkyLight's private CGSHWCaptureWindowList (with
  or without the `fullSize` option) returns the real window — only the
  tilted thumbnail, or nothing while the strip is hidden. The pane keeps its
  last picture and says why; with control, **Show on Mac** brings that window
  onto the stage, and **Turn Off Stage Manager** switches it off for Window
  mode (back on afterwards). macOS applies Stage Manager only through its own
  control, so that runs two shortcuts the owner makes once with the
  "Set Stage Manager" action (Settings → System → Stage Manager); writing the
  `GloballyEnabled` preference has no visible effect (measured). A window
  that returns to the stage gets a fresh stream within about 2 s.
  Evidence: the integration folder's RESEARCH-2026-10-30-stage-manager-capture-lab.md.

## Turning it off

Mac: Settings → Displays → Windows → **Let devices show individual windows**.
Off, the Mac doesn't offer Window mode and ignores window messages.
