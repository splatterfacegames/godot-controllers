class_name CtlLayout
extends RefCounted

## The canonical gamepad layout, device families, family detection and
## per-family labels/glyph descriptors. Pure data + static functions.
##
## Godot (SDL3 underneath since 4.5) reports gamepad buttons by physical
## POSITION: JOY_BUTTON_A is the bottom face button on every pad, whatever
## is printed on it. The canonical layout here is therefore positional, and
## labels are a per-family presentation concern.
##
## Stick Y follows Godot's convention: positive is DOWN.

# ------------------------------------------------------------------ families

const FAMILY_KBM := &"kbm"
const FAMILY_XBOX := &"xbox"
const FAMILY_PLAYSTATION := &"playstation"
const FAMILY_NINTENDO := &"nintendo"
const FAMILY_GENERIC := &"generic"

const PAD_FAMILIES: Array[StringName] = [FAMILY_XBOX, FAMILY_PLAYSTATION, FAMILY_NINTENDO, FAMILY_GENERIC]
const ALL_FAMILIES: Array[StringName] = [FAMILY_KBM, FAMILY_XBOX, FAMILY_PLAYSTATION, FAMILY_NINTENDO, FAMILY_GENERIC]

## USB vendor ids of the three platform holders.
const VENDOR_MICROSOFT := 0x045E
const VENDOR_SONY := 0x054C
const VENDOR_NINTENDO := 0x057E

# ------------------------------------------------------------------ controls

## Digital controls -> Godot JoyButton.
const BUTTONS := {
	&"face_south": JOY_BUTTON_A, &"face_east": JOY_BUTTON_B,
	&"face_west": JOY_BUTTON_X, &"face_north": JOY_BUTTON_Y,
	&"select": JOY_BUTTON_BACK, &"home": JOY_BUTTON_GUIDE, &"start": JOY_BUTTON_START,
	&"stick_l_press": JOY_BUTTON_LEFT_STICK, &"stick_r_press": JOY_BUTTON_RIGHT_STICK,
	&"shoulder_l": JOY_BUTTON_LEFT_SHOULDER, &"shoulder_r": JOY_BUTTON_RIGHT_SHOULDER,
	&"dpad_up": JOY_BUTTON_DPAD_UP, &"dpad_down": JOY_BUTTON_DPAD_DOWN,
	&"dpad_left": JOY_BUTTON_DPAD_LEFT, &"dpad_right": JOY_BUTTON_DPAD_RIGHT,
	&"misc": JOY_BUTTON_MISC1,
	&"paddle_1": JOY_BUTTON_PADDLE1, &"paddle_2": JOY_BUTTON_PADDLE2,
	&"paddle_3": JOY_BUTTON_PADDLE3, &"paddle_4": JOY_BUTTON_PADDLE4,
	&"touchpad": JOY_BUTTON_TOUCHPAD,
	&"misc_2": 21, &"misc_3": 22, &"misc_4": 23, &"misc_5": 24, &"misc_6": 25,
}

## Godot JoyButton -> control (reverse of BUTTONS).
const CONTROL_OF_BUTTON := {
	JOY_BUTTON_A: &"face_south", JOY_BUTTON_B: &"face_east",
	JOY_BUTTON_X: &"face_west", JOY_BUTTON_Y: &"face_north",
	JOY_BUTTON_BACK: &"select", JOY_BUTTON_GUIDE: &"home", JOY_BUTTON_START: &"start",
	JOY_BUTTON_LEFT_STICK: &"stick_l_press", JOY_BUTTON_RIGHT_STICK: &"stick_r_press",
	JOY_BUTTON_LEFT_SHOULDER: &"shoulder_l", JOY_BUTTON_RIGHT_SHOULDER: &"shoulder_r",
	JOY_BUTTON_DPAD_UP: &"dpad_up", JOY_BUTTON_DPAD_DOWN: &"dpad_down",
	JOY_BUTTON_DPAD_LEFT: &"dpad_left", JOY_BUTTON_DPAD_RIGHT: &"dpad_right",
	JOY_BUTTON_MISC1: &"misc",
	JOY_BUTTON_PADDLE1: &"paddle_1", JOY_BUTTON_PADDLE2: &"paddle_2",
	JOY_BUTTON_PADDLE3: &"paddle_3", JOY_BUTTON_PADDLE4: &"paddle_4",
	JOY_BUTTON_TOUCHPAD: &"touchpad",
	21: &"misc_2", 22: &"misc_3", 23: &"misc_4", 24: &"misc_5", 25: &"misc_6",
}

## Analog controls -> Godot JoyAxis. Sticks are -1..1, triggers 0..1.
const AXES := {
	&"stick_l_x": JOY_AXIS_LEFT_X, &"stick_l_y": JOY_AXIS_LEFT_Y,
	&"stick_r_x": JOY_AXIS_RIGHT_X, &"stick_r_y": JOY_AXIS_RIGHT_Y,
	&"trigger_l": JOY_AXIS_TRIGGER_LEFT, &"trigger_r": JOY_AXIS_TRIGGER_RIGHT,
}

const TRIGGERS: Array[StringName] = [&"trigger_l", &"trigger_r"]

## 2D controls -> [x control, y control]. `dpad` is built from four buttons.
const STICKS := {
	&"stick_l": [&"stick_l_x", &"stick_l_y"],
	&"stick_r": [&"stick_r_x", &"stick_r_y"],
}
const STICK_OF_AXIS := {
	&"stick_l_x": &"stick_l", &"stick_l_y": &"stick_l",
	&"stick_r_x": &"stick_r", &"stick_r_y": &"stick_r",
}

## Pseudo-controls resolved per family and per the game's confirm setting.
const CONFIRM := &"confirm"
const CANCEL := &"cancel"

## confirm_follows values.
const CONFIRM_BY_POSITION := &"position"  # confirm = south on every pad
const CONFIRM_BY_LABEL := &"label"        # confirm = the button labelled "A"


static func is_button(c: StringName) -> bool:
	return BUTTONS.has(c)


static func is_axis(c: StringName) -> bool:
	return AXES.has(c)


static func is_stick(c: StringName) -> bool:
	return STICKS.has(c) or c == &"dpad"


static func is_trigger(c: StringName) -> bool:
	return c in TRIGGERS


## Resolve confirm/cancel to a positional control for a family.
static func resolve(c: StringName, family: StringName, confirm_follows: StringName) -> StringName:
	if c != CONFIRM and c != CANCEL:
		return c
	var swap := confirm_follows == CONFIRM_BY_LABEL and family == FAMILY_NINTENDO
	if c == CONFIRM:
		return &"face_east" if swap else &"face_south"
	return &"face_south" if swap else &"face_east"


# ------------------------------------------------------------------ detection

## Vendor/product from get_joy_info() when the platform reports it, else
## decoded from the SDL-style GUID string (16 bytes, hex): bytes 4-5 vendor
## and 8-9 product, little-endian, with bytes 6-7 and 10-11 zero. GUIDs that
## don't follow that shape (e.g. XInput-only identities) return ZERO.
static func vendor_product(guid: String, info: Dictionary, device_name_hint := "") -> Vector2i:
	if info.has("vendor_id"):
		return Vector2i(int(info.get("vendor_id", 0)), int(info.get("product_id", 0)))
	if guid.length() != 32 or not guid.is_valid_hex_number():
		return Vector2i.ZERO if device_name_hint == "" else vendor_from_name(device_name_hint)
	var b := guid.hex_decode()
	if b.size() < 12 or b[6] != 0 or b[7] != 0 or b[10] != 0 or b[11] != 0:
		return Vector2i.ZERO
	return Vector2i(b[4] | (b[5] << 8), b[8] | (b[9] << 8))


## Browsers put USB ids in the gamepad id string instead of a GUID:
## Chrome "... (STANDARD GAMEPAD Vendor: 054c Product: 0ce6)", Firefox
## "054c-0ce6-DualSense Wireless Controller".
static func vendor_from_name(n: String) -> Vector2i:
	var re := RegEx.create_from_string("(?i)vendor:\\s*([0-9a-f]{4})\\s*product:\\s*([0-9a-f]{4})")
	var m := re.search(n)
	if m == null:
		re = RegEx.create_from_string("^([0-9a-f]{4})-([0-9a-f]{4})-")
		m = re.search(n.to_lower())
	if m == null:
		return Vector2i.ZERO
	return Vector2i(m.get_string(1).hex_to_int(), m.get_string(2).hex_to_int())


## Family from vendor id first, then conservative name matching. A generic
## XInput identity is NOT branded as Xbox: unknown stays generic.
static func detect_family(device_name: String, guid: String, info: Dictionary) -> StringName:
	match vendor_product(guid, info, device_name).x:
		VENDOR_MICROSOFT:
			return FAMILY_XBOX
		VENDOR_SONY:
			return FAMILY_PLAYSTATION
		VENDOR_NINTENDO:
			return FAMILY_NINTENDO
	var n := device_name.to_lower()
	if n.contains("xbox") or n.contains("x-box"):
		return FAMILY_XBOX
	for s in ["playstation", "dualsense", "dualshock", "ps5", "ps4", "ps3", "sony"]:
		if n.contains(s):
			return FAMILY_PLAYSTATION
	for s in ["nintendo", "switch", "joy-con", "joycon"]:
		if n.contains(s):
			return FAMILY_NINTENDO
	return FAMILY_GENERIC


# ------------------------------------------------------------------ labels

const LABELS := {
	FAMILY_XBOX: {
		&"face_south": "A", &"face_east": "B", &"face_west": "X", &"face_north": "Y",
		&"shoulder_l": "LB", &"shoulder_r": "RB", &"trigger_l": "LT", &"trigger_r": "RT",
		&"select": "View", &"start": "Menu", &"home": "Guide", &"misc": "Share",
		&"stick_l": "LS", &"stick_r": "RS", &"stick_l_press": "LS", &"stick_r_press": "RS",
		&"paddle_1": "P1", &"paddle_2": "P2", &"paddle_3": "P3", &"paddle_4": "P4",
	},
	FAMILY_PLAYSTATION: {
		&"face_south": "Cross", &"face_east": "Circle", &"face_west": "Square", &"face_north": "Triangle",
		&"shoulder_l": "L1", &"shoulder_r": "R1", &"trigger_l": "L2", &"trigger_r": "R2",
		&"select": "Create", &"start": "Options", &"home": "PS", &"misc": "Mic",
		&"touchpad": "Touchpad",
		&"stick_l": "L", &"stick_r": "R", &"stick_l_press": "L3", &"stick_r_press": "R3",
		&"paddle_1": "RB", &"paddle_2": "LB", &"paddle_3": "RFn", &"paddle_4": "LFn",
	},
	FAMILY_NINTENDO: {
		# Positional south is labelled B on Nintendo pads, east is A.
		&"face_south": "B", &"face_east": "A", &"face_west": "Y", &"face_north": "X",
		&"shoulder_l": "L", &"shoulder_r": "R", &"trigger_l": "ZL", &"trigger_r": "ZR",
		&"select": "−", &"start": "+", &"home": "Home", &"misc": "Capture",
		&"stick_l": "L", &"stick_r": "R", &"stick_l_press": "L Press", &"stick_r_press": "R Press",
		&"paddle_1": "GR", &"paddle_2": "GL", &"paddle_3": "P3", &"paddle_4": "P4",
		&"misc_2": "C",
	},
	FAMILY_GENERIC: {
		&"face_south": "Bottom", &"face_east": "Right", &"face_west": "Left", &"face_north": "Top",
		&"shoulder_l": "L1", &"shoulder_r": "R1", &"trigger_l": "L2", &"trigger_r": "R2",
		&"select": "Select", &"start": "Start", &"home": "Home", &"misc": "Misc",
		&"touchpad": "Touchpad",
		&"stick_l": "L Stick", &"stick_r": "R Stick", &"stick_l_press": "L3", &"stick_r_press": "R3",
	},
}

const DPAD_TEXT := {
	&"dpad_up": "D-Pad Up", &"dpad_down": "D-Pad Down",
	&"dpad_left": "D-Pad Left", &"dpad_right": "D-Pad Right", &"dpad": "D-Pad",
}

const FACE_STYLE := {
	FAMILY_XBOX: {&"face_south": &"xbox_a", &"face_east": &"xbox_b", &"face_west": &"xbox_x", &"face_north": &"xbox_y"},
	FAMILY_PLAYSTATION: {&"face_south": &"ps_cross", &"face_east": &"ps_circle", &"face_west": &"ps_square", &"face_north": &"ps_triangle"},
}


static func family_display_name(family: StringName) -> String:
	match family:
		FAMILY_KBM: return "Keyboard & Mouse"
		FAMILY_XBOX: return "Xbox"
		FAMILY_PLAYSTATION: return "PlayStation"
		FAMILY_NINTENDO: return "Nintendo"
	return "Generic gamepad"


## User-facing name of a pad control on a family.
static func control_label(c: StringName, family: StringName, confirm_follows := CONFIRM_BY_POSITION) -> String:
	c = resolve(c, family, confirm_follows)
	if DPAD_TEXT.has(c):
		return DPAD_TEXT[c]
	var table: Dictionary = LABELS.get(family, LABELS[FAMILY_GENERIC])
	if table.has(c):
		return table[c]
	if STICK_OF_AXIS.has(c):
		var stick: StringName = STICK_OF_AXIS[c]
		return "%s %s" % [control_label(stick, family), "X" if String(c).ends_with("_x") else "Y"]
	if LABELS[FAMILY_GENERIC].has(c):
		return LABELS[FAMILY_GENERIC][c]
	return String(c).capitalize()


# ------------------------------------------------------------------ glyphs

## Glyph descriptor for one binding on a family. Keys:
##   text      accessible name / fallback label (always present)
##   icon      CtlGlyph icon name (see ui/ctl_glyph.gd)
##   style     colour/style class
##   icon_only the icon carries the label (letters/symbols), hide text
##   icon_text text drawn inside the icon
##   family, control  what it was resolved from
## The dictionary shape is shared with tokyo_retro's TRPromptChip.
static func glyph(binding: Dictionary, family: StringName, confirm_follows := CONFIRM_BY_POSITION) -> Dictionary:
	if binding.has("key"):
		return {"text": key_label(int(binding.key)), "style": &"keycap", "icon": &"",
			"family": FAMILY_KBM}
	if binding.has("mouse"):
		match int(binding.mouse):
			MOUSE_BUTTON_LEFT: return {"text": "LMB", "style": &"mouse", "icon": &"mouse_left", "family": FAMILY_KBM}
			MOUSE_BUTTON_RIGHT: return {"text": "RMB", "style": &"mouse", "icon": &"mouse_right", "family": FAMILY_KBM}
			MOUSE_BUTTON_MIDDLE: return {"text": "MMB", "style": &"mouse", "icon": &"mouse_middle", "family": FAMILY_KBM}
			MOUSE_BUTTON_WHEEL_UP: return {"text": "Wheel Up", "style": &"mouse", "icon": &"mouse_wheel_up", "family": FAMILY_KBM}
			MOUSE_BUTTON_WHEEL_DOWN: return {"text": "Wheel Down", "style": &"mouse", "icon": &"mouse_wheel_down", "family": FAMILY_KBM}
		return {"text": "Mouse %d" % int(binding.mouse), "style": &"mouse", "icon": &"mouse", "family": FAMILY_KBM}
	if binding.has("mouse_axis"):
		var t := {&"x": "Mouse X", &"y": "Mouse Y", &"wheel": "Wheel"}.get(StringName(binding.mouse_axis), "Mouse")
		return {"text": t, "style": &"mouse", "icon": &"mouse", "family": FAMILY_KBM}
	if not binding.has("pad"):
		return {"text": "?", "style": &"unknown", "icon": &""}
	var c := resolve(StringName(binding.pad), family, confirm_follows)
	var label := control_label(c, family)
	var half := int(binding.get("half", 0))
	var out := {"text": label, "style": &"pad_button", "icon": &"pad_button", "family": family, "control": c}
	if c in [&"face_south", &"face_east", &"face_west", &"face_north"]:
		if FACE_STYLE.has(family):
			out.style = FACE_STYLE[family][c]
			out.icon = out.style
			# Xbox letters are drawn in the icon; PlayStation symbols are
			# not self-naming, so keep the text beside them.
			out.icon_only = family == FAMILY_XBOX
		elif family == FAMILY_NINTENDO:
			out.style = &"nintendo_button"
			out.icon = &"nintendo_button"
			out.icon_text = label
			out.icon_only = true
		else:
			out.icon = StringName("face_" + String(c).trim_prefix("face_"))
			out.style = &"pad_button"
		return out
	if DPAD_TEXT.has(c):
		out.style = &"pad_dpad"
		out.icon = c
		return out
	if STICKS.has(c) or STICK_OF_AXIS.has(c):
		var stick: StringName = STICK_OF_AXIS.get(c, c)
		out.style = &"pad_axis"
		out.icon = stick
		if half != 0 and STICK_OF_AXIS.has(c):
			var is_x := String(c).ends_with("_x")
			var arrow := ""
			if is_x:
				arrow = "←" if half < 0 else "→"
			else:
				arrow = "↑" if half < 0 else "↓"
			out.text = "%s %s" % [control_label(stick, family), arrow]
		return out
	match c:
		&"trigger_l", &"trigger_r":
			out.style = &"pad_axis"
			out.icon = c
			out.icon_text = label
			out.icon_only = true
		&"shoulder_l", &"shoulder_r":
			out.icon = &"bumper"
			out.icon_text = label
			out.icon_only = true
		&"stick_l_press":
			out.icon = &"stick_l"
		&"stick_r_press":
			out.icon = &"stick_r"
		&"start":
			out.icon = &"plus" if family == FAMILY_NINTENDO else &"menu"
		&"select":
			out.icon = &"minus" if family == FAMILY_NINTENDO else &"view"
		&"home":
			out.icon = &"home"
		&"touchpad":
			out.icon = &"touchpad"
		&"paddle_1", &"paddle_2", &"paddle_3", &"paddle_4":
			out.icon = &"paddle"
	return out


## Whether the display server can map physical keys through the current
## keyboard layout (not headless, not the Web, which logs an error per call).
static func can_map_physical_keys() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.has_feature("web")


## Key cap text for a PHYSICAL keycode, through the current keyboard layout
## when a display server can resolve it.
static func key_label(physical: int) -> String:
	if can_map_physical_keys():
		var logical := DisplayServer.keyboard_get_keycode_from_physical(physical)
		if logical != 0:
			var s := OS.get_keycode_string(logical)
			if s != "":
				return s
	var s2 := OS.get_keycode_string(physical)
	return s2 if s2 != "" else "Key %d" % physical
