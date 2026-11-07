// Package input injects receiver input into X11 with XTEST.
//
// Coordinates arrive normalized to the video frame (top-left origin) and are
// mapped onto the captured screen region. Keyboard messages carry USB HID
// usage numbers (keyboard page 0x07), never characters, so they are
// translated through the host keymap; committed text arrives as a Unicode
// string. Held state is tracked so a dropped connection, a mode change, or
// "cancel" releases everything the receiver pressed.
package input

import (
	"fmt"
	"math"
	"os"
	"sync"

	"github.com/jezek/xgb"
	"github.com/jezek/xgb/xproto"
	"github.com/jezek/xgb/xtest"

	"github.com/raiseCatError/ExtendPad/apps/linux/internal/display"
)

const (
	keyShiftL         xproto.Keysym = 0xffe1
	keyShiftR         xproto.Keysym = 0xffe2
	keyControlL       xproto.Keysym = 0xffe3
	keyAltL           xproto.Keysym = 0xffe9
	keySuperL         xproto.Keysym = 0xffeb
	keyISOLevel3Shift xproto.Keysym = 0xfe03

	buttonLeft  = 1
	buttonRight = 3

	scrollPixelsPerClick = 40
)

var modifierKeysyms = map[string]xproto.Keysym{
	"shift":    keyShiftL,
	"control":  keyControlL,
	"option":   keyAltL,
	"alt":      keyAltL,
	"command":  keySuperL,
	"super":    keySuperL,
	"meta":     keySuperL,
	"capsLock": 0xffe5,
}

var hidKeysyms = buildHIDTable()

func buildHIDTable() map[uint32]xproto.Keysym {
	table := map[uint32]xproto.Keysym{}
	for index := 0; index < 26; index++ {
		table[uint32(4+index)] = xproto.Keysym('a' + index)
	}
	for offset, character := range "1234567890" {
		table[uint32(30+offset)] = xproto.Keysym(character)
	}
	table[40] = 0xff0d // Return
	table[41] = 0xff1b // Escape
	table[42] = 0xff08 // Backspace
	table[43] = 0xff09 // Tab
	table[44] = 0x20   // space
	table[45] = 0x2d   // minus
	table[46] = 0x3d   // equal
	table[47] = 0x5b   // bracketleft
	table[48] = 0x5d   // bracketright
	table[49] = 0x5c   // backslash
	table[51] = 0x3b   // semicolon
	table[52] = 0x27   // apostrophe
	table[53] = 0x60   // grave
	table[54] = 0x2c   // comma
	table[55] = 0x2e   // period
	table[56] = 0x2f   // slash
	table[57] = 0xffe5 // Caps_Lock
	for index := 0; index < 12; index++ {
		table[uint32(58+index)] = xproto.Keysym(0xffbe + index) // F1..F12
	}
	table[73] = 0xff63 // Insert
	table[74] = 0xff50 // Home
	table[75] = 0xff55 // Page_Up
	table[76] = 0xffff // Delete
	table[77] = 0xff57 // End
	table[78] = 0xff56 // Page_Down
	table[79] = 0xff53 // Right
	table[80] = 0xff51 // Left
	table[81] = 0xff54 // Down
	table[82] = 0xff52 // Up
	table[83] = 0xff7f // Num_Lock
	table[84] = 0xffaf // KP_Divide
	table[85] = 0xffaa // KP_Multiply
	table[86] = 0xffad // KP_Subtract
	table[87] = 0xffab // KP_Add
	table[88] = 0xff8d // KP_Enter
	for index := 0; index < 9; index++ {
		table[uint32(89+index)] = xproto.Keysym(0xffb1 + index) // KP_1..KP_9
	}
	table[98] = 0xffb0  // KP_0
	table[99] = 0xffae  // KP_Decimal
	table[103] = 0xffbd // KP_Equal
	for index := 0; index < 8; index++ {
		table[uint32(104+index)] = xproto.Keysym(0xffca + index) // F13..F20
	}
	table[133] = 0xffac // KP_Separator
	table[224] = keyControlL
	table[225] = keyShiftL
	table[226] = keyAltL
	table[227] = keySuperL
	table[228] = 0xffe4 // Control_R
	table[229] = keyShiftR
	table[230] = 0xffea // Alt_R
	table[231] = 0xffec // Super_R
	return table
}

type Injector struct {
	conn   *xgb.Conn
	root   xproto.Window
	width  int
	height int
	region display.Region

	keymap *keymap

	heldButtons   map[byte]bool
	heldKeys      map[uint32]bool
	heldModifiers map[string]bool

	scrollX float64
	scrollY float64

	mutex sync.Mutex
}

func New(screen *display.Display, region display.Region) (*Injector, error) {
	if screen.XAuthority != "" {
		_ = os.Setenv("XAUTHORITY", screen.XAuthority)
	}
	_ = os.Setenv("DISPLAY", screen.Name)
	conn, err := xgb.NewConnDisplay(screen.Name)
	if err != nil {
		return nil, err
	}
	if err := xtest.Init(conn); err != nil {
		conn.Close()
		return nil, fmt.Errorf("XTEST extension: %w", err)
	}
	setup := xproto.Setup(conn)
	info := setup.DefaultScreen(conn)
	injector := &Injector{
		conn:          conn,
		root:          info.Root,
		width:         int(info.WidthInPixels),
		height:        int(info.HeightInPixels),
		region:        region,
		heldButtons:   map[byte]bool{},
		heldKeys:      map[uint32]bool{},
		heldModifiers: map[string]bool{},
	}
	if err := injector.loadKeymap(); err != nil {
		conn.Close()
		return nil, err
	}
	return injector, nil
}

// Close releases everything held and closes the X connection.
func (i *Injector) Close() {
	i.ReleaseAll()
	if i.conn != nil {
		i.conn.Close()
	}
}

// ------------------------------------------------------------- geometry

func (i *Injector) absolute(x, y float64) (int16, int16) {
	px := i.region.X + int(math.Round(clamp(x)*float64(i.region.Width)))
	py := i.region.Y + int(math.Round(clamp(y)*float64(i.region.Height)))
	if px < i.region.X {
		px = i.region.X
	}
	if px >= i.region.X+i.region.Width {
		px = i.region.X + i.region.Width - 1
	}
	if py < i.region.Y {
		py = i.region.Y
	}
	if py >= i.region.Y+i.region.Height {
		py = i.region.Y + i.region.Height - 1
	}
	return int16(px), int16(py)
}

func (i *Injector) moveToPixel(x, y int) {
	i.fake(xproto.MotionNotify, 0, int16(x), int16(y))
}

func (i *Injector) MoveTo(x, y float64) {
	px, py := i.absolute(x, y)
	i.moveToPixel(int(px), int(py))
}

func (i *Injector) MoveRelative(dx, dy float64) {
	reply, err := xproto.QueryPointer(i.conn, i.root).Reply()
	if err != nil {
		return
	}
	x := int(reply.RootX) + int(math.Round(dx))
	y := int(reply.RootY) + int(math.Round(dy))
	if x < 0 {
		x = 0
	}
	if y < 0 {
		y = 0
	}
	if x >= i.width {
		x = i.width - 1
	}
	if y >= i.height {
		y = i.height - 1
	}
	i.moveToPixel(x, y)
}

func clamp(value float64) float64 {
	if math.IsNaN(value) {
		return 0
	}
	return math.Min(1, math.Max(0, value))
}

// -------------------------------------------------------------- buttons

func (i *Injector) ButtonDown(button string) {
	code := byte(buttonLeft)
	if button == "right" {
		code = buttonRight
	}
	i.fake(xproto.ButtonPress, code, 0, 0)
	i.heldButtons[code] = true
}

func (i *Injector) ButtonUp(button string) {
	code := byte(buttonLeft)
	if button == "right" {
		code = buttonRight
	}
	i.fake(xproto.ButtonRelease, code, 0, 0)
	delete(i.heldButtons, code)
}

func (i *Injector) Click(button string, x, y float64) {
	i.MoveTo(x, y)
	i.ButtonDown(button)
	i.ButtonUp(button)
}

func (i *Injector) Touch(phase string, x, y float64) {
	switch phase {
	case "began":
		i.MoveTo(x, y)
		i.ButtonDown("left")
	case "moved":
		if i.heldButtons[buttonLeft] {
			i.MoveTo(x, y)
		}
	case "ended":
		i.MoveTo(x, y)
		i.ButtonUp("left")
	case "cancelled":
		if i.heldButtons[buttonLeft] {
			i.ButtonUp("left")
		}
	}
}

func (i *Injector) Scroll(dx, dy float64) {
	i.scrollX += dx
	i.scrollY += dy
	vertical := int(i.scrollY / scrollPixelsPerClick)
	horizontal := int(i.scrollX / scrollPixelsPerClick)
	if vertical != 0 {
		i.scrollY -= float64(vertical * scrollPixelsPerClick)
		button := byte(4)
		if vertical > 0 {
			button = 5 // natural scrolling: content follows the fingers
		}
		i.wheel(button, abs(vertical))
	}
	if horizontal != 0 {
		i.scrollX -= float64(horizontal * scrollPixelsPerClick)
		button := byte(6)
		if horizontal > 0 {
			button = 7
		}
		i.wheel(button, abs(horizontal))
	}
}

func (i *Injector) wheel(button byte, count int) {
	for index := 0; index < count; index++ {
		i.fake(xproto.ButtonPress, button, 0, 0)
		i.fake(xproto.ButtonRelease, button, 0, 0)
	}
}

// ------------------------------------------------------------- keyboard

func (i *Injector) KeyPress(usage uint32, modifiers []string) {
	keysym, ok := hidKeysyms[usage]
	if !ok {
		return
	}
	pressed := make([]byte, 0, len(modifiers))
	for _, name := range modifiers {
		if code, ok := i.modifierKeycode(name); ok {
			i.fake(xproto.KeyPress, code, 0, 0)
			pressed = append(pressed, code)
		}
	}
	i.tapKeysym(keysym)
	for index := len(pressed) - 1; index >= 0; index-- {
		i.fake(xproto.KeyRelease, pressed[index], 0, 0)
	}
}

func (i *Injector) KeyDown(usage uint32, modifiers []string) {
	keysym, ok := hidKeysyms[usage]
	if !ok || i.heldKeys[usage] {
		return
	}
	for _, name := range modifiers {
		i.pressModifierName(name)
	}
	if code, _, ok := i.keymap.find(keysym); ok {
		i.fake(xproto.KeyPress, code, 0, 0)
		i.heldKeys[usage] = true
	}
}

func (i *Injector) KeyUp(usage uint32, modifiers []string) {
	keysym, ok := hidKeysyms[usage]
	if !ok || !i.heldKeys[usage] {
		return
	}
	if code, _, ok := i.keymap.find(keysym); ok {
		i.fake(xproto.KeyRelease, code, 0, 0)
	}
	delete(i.heldKeys, usage)
	for _, name := range modifiers {
		i.releaseModifierName(name)
	}
}

func (i *Injector) ModifierDown(name string) { i.pressModifierName(name) }
func (i *Injector) ModifierUp(name string)   { i.releaseModifierName(name) }

func (i *Injector) TypeText(text string) {
	for _, character := range text {
		switch character {
		case '\n', '\r':
			i.tapKeysym(0xff0d)
			continue
		case '\t':
			i.tapKeysym(0xff09)
			continue
		}
		if keysym, ok := unicodeKeysym(character); ok {
			i.tapKeysym(keysym)
		}
	}
}

func unicodeKeysym(character rune) (xproto.Keysym, bool) {
	code := uint32(character)
	if code < 0x20 || code == 0x7f {
		return 0, false
	}
	if code < 0x100 {
		return xproto.Keysym(code), true
	}
	return xproto.Keysym(0x01000000 + code), true
}

func (i *Injector) tapKeysym(keysym xproto.Keysym) {
	keycode, level, ok := i.keymap.find(keysym)
	if !ok {
		i.tapRemapped(keysym)
		return
	}
	var modifiers []byte
	if level&1 != 0 {
		if code, _, ok := i.keymap.find(keyShiftL); ok {
			modifiers = append(modifiers, code)
		}
	}
	if level&2 != 0 {
		if code, _, ok := i.keymap.find(keyISOLevel3Shift); ok {
			modifiers = append(modifiers, code)
		}
	}
	for _, code := range modifiers {
		i.fake(xproto.KeyPress, code, 0, 0)
	}
	i.fake(xproto.KeyPress, keycode, 0, 0)
	i.fake(xproto.KeyRelease, keycode, 0, 0)
	for index := len(modifiers) - 1; index >= 0; index-- {
		i.fake(xproto.KeyRelease, modifiers[index], 0, 0)
	}
}

// tapRemapped borrows the highest keycode for characters the layout lacks.
func (i *Injector) tapRemapped(keysym xproto.Keysym) {
	scratch := i.keymap.scratch
	reply, err := xproto.GetKeyboardMapping(i.conn, scratch, 1).Reply()
	if err != nil || reply == nil || len(reply.Keysyms) == 0 {
		return
	}
	original := append([]xproto.Keysym{}, reply.Keysyms...)
	replacement := make([]xproto.Keysym, len(original))
	for index := range replacement {
		replacement[index] = keysym
	}
	xproto.ChangeKeyboardMapping(i.conn, 1, scratch, byte(len(original)), replacement)
	i.conn.Sync()
	i.fake(xproto.KeyPress, byte(scratch), 0, 0)
	i.fake(xproto.KeyRelease, byte(scratch), 0, 0)
	xproto.ChangeKeyboardMapping(i.conn, 1, scratch, byte(len(original)), original)
	i.conn.Sync()
}

func (i *Injector) modifierKeycode(name string) (byte, bool) {
	keysym, ok := modifierKeysyms[name]
	if !ok {
		return 0, false
	}
	code, _, found := i.keymap.find(keysym)
	return code, found
}

func (i *Injector) pressModifierName(name string) {
	if i.heldModifiers[name] {
		return
	}
	code, ok := i.modifierKeycode(name)
	if !ok {
		return
	}
	i.fake(xproto.KeyPress, code, 0, 0)
	i.heldModifiers[name] = true
}

func (i *Injector) releaseModifierName(name string) {
	if !i.heldModifiers[name] {
		return
	}
	if code, ok := i.modifierKeycode(name); ok {
		i.fake(xproto.KeyRelease, code, 0, 0)
	}
	delete(i.heldModifiers, name)
}

// --------------------------------------------------------------- release

func (i *Injector) ReleaseAll() {
	for code := range i.heldButtons {
		i.fake(xproto.ButtonRelease, code, 0, 0)
		delete(i.heldButtons, code)
	}
	for usage := range i.heldKeys {
		if keysym, ok := hidKeysyms[usage]; ok {
			if code, _, ok := i.keymap.find(keysym); ok {
				i.fake(xproto.KeyRelease, code, 0, 0)
			}
		}
		delete(i.heldKeys, usage)
	}
	for name := range i.heldModifiers {
		i.releaseModifierName(name)
	}
}

// ---------------------------------------------------------------- low level

func (i *Injector) fake(kind, detail byte, x, y int16) {
	i.mutex.Lock()
	defer i.mutex.Unlock()
	if i.conn == nil {
		return
	}
	xtest.FakeInput(i.conn, kind, detail, 0, i.root, x, y, 0)
	i.conn.Sync()
}

func abs(value int) int {
	if value < 0 {
		return -value
	}
	return value
}

// ---------------------------------------------------------------- keymap

type keymap struct {
	min        xproto.Keycode
	max        xproto.Keycode
	scratch    xproto.Keycode
	perKeycode int
	keysyms    []xproto.Keysym
}

func (i *Injector) loadKeymap() error {
	setup := xproto.Setup(i.conn)
	first := setup.MinKeycode
	count := setup.MaxKeycode - setup.MinKeycode + 1
	reply, err := xproto.GetKeyboardMapping(i.conn, first, byte(count)).Reply()
	if err != nil {
		return err
	}
	i.keymap = &keymap{
		min:        first,
		max:        setup.MaxKeycode,
		scratch:    setup.MaxKeycode,
		perKeycode: int(reply.KeysymsPerKeycode),
		keysyms:    reply.Keysyms,
	}
	return nil
}

func (k *keymap) levels(keycode xproto.Keycode) []xproto.Keysym {
	index := int(keycode-k.min) * k.perKeycode
	if k.perKeycode == 0 || index < 0 || index+k.perKeycode > len(k.keysyms) {
		return nil
	}
	return k.keysyms[index : index+k.perKeycode]
}

func (k *keymap) find(keysym xproto.Keysym) (byte, int, bool) {
	for keycode := k.min; keycode <= k.max; keycode++ {
		for level, candidate := range k.levels(keycode) {
			if candidate == keysym && level < 4 {
				return byte(keycode), level, true
			}
		}
	}
	return 0, 0, false
}
