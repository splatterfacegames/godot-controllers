class_name CtlGlyphTheme
extends RefCounted

## Maps a resolved glyph (family + control / key / mouse) to a texture.
## The bundled theme is Kenney's "Input Prompts" pack (CC0,
## www.kenney.nl; see glyphs/kenney/License.txt), 128 px PNGs, under
## res://addons/controllers/glyphs/kenney/<family>/.
##
## Anything without a texture keeps its procedural CtlGlyph icon, so a
## theme can be partial. Set Controllers.glyph_theme = "" to draw
## everything procedurally, or point `root` at your own folder that uses
## the same file names.

const DEFAULT_ROOT := "res://addons/controllers/glyphs/kenney"

## family -> control -> file (without .png).
const PAD := {
	&"xbox": {
		&"face_south": "xbox_button_color_a", &"face_east": "xbox_button_color_b",
		&"face_west": "xbox_button_color_x", &"face_north": "xbox_button_color_y",
		&"shoulder_l": "xbox_lb", &"shoulder_r": "xbox_rb",
		&"trigger_l": "xbox_lt", &"trigger_r": "xbox_rt",
		&"select": "xbox_button_view", &"start": "xbox_button_menu",
		&"home": "xbox_guide", &"misc": "xbox_button_share",
		&"stick_l_press": "xbox_stick_l_press", &"stick_r_press": "xbox_stick_r_press",
		&"paddle_1": "xbox_elite_paddle_top_right", &"paddle_2": "xbox_elite_paddle_top_left",
		&"paddle_3": "xbox_elite_paddle_bottom_right", &"paddle_4": "xbox_elite_paddle_bottom_left",
	},
	&"playstation": {
		&"face_south": "playstation_button_color_cross", &"face_east": "playstation_button_color_circle",
		&"face_west": "playstation_button_color_square", &"face_north": "playstation_button_color_triangle",
		&"shoulder_l": "playstation_trigger_l1", &"shoulder_r": "playstation_trigger_r1",
		&"trigger_l": "playstation_trigger_l2", &"trigger_r": "playstation_trigger_r2",
		&"select": "playstation5_button_create", &"start": "playstation5_button_options",
		&"misc": "playstation5_button_mute", &"touchpad": "playstation5_touchpad_press",
		&"stick_l_press": "playstation_button_l3", &"stick_r_press": "playstation_button_r3",
		&"paddle_1": "playstation5_elite_rb", &"paddle_2": "playstation5_elite_lb",
		&"paddle_3": "playstation5_elite_fn_r", &"paddle_4": "playstation5_elite_fn_l",
	},
	&"nintendo": {
		&"face_south": "switch_button_b", &"face_east": "switch_button_a",
		&"face_west": "switch_button_y", &"face_north": "switch_button_x",
		&"shoulder_l": "switch_button_l", &"shoulder_r": "switch_button_r",
		&"trigger_l": "switch_button_zl", &"trigger_r": "switch_button_zr",
		&"select": "switch_button_minus", &"start": "switch_button_plus",
		&"home": "switch_button_home", &"misc_2": "switch_button_c",
		&"stick_l_press": "switch_stick_l_press", &"stick_r_press": "switch_stick_r_press",
		&"paddle_1": "switch_button_gr", &"paddle_2": "switch_button_gl",
	},
	&"generic": {},
}

## Prefix for sticks and d-pad per family (generic has sticks only).
const STICK_PREFIX := {&"xbox": "xbox", &"playstation": "playstation", &"nintendo": "switch", &"generic": "generic"}

const MOUSE := {
	MOUSE_BUTTON_LEFT: "mouse_left", MOUSE_BUTTON_RIGHT: "mouse_right",
	MOUSE_BUTTON_MIDDLE: "mouse_scroll", MOUSE_BUTTON_WHEEL_UP: "mouse_scroll_up",
	MOUSE_BUTTON_WHEEL_DOWN: "mouse_scroll_down",
	MOUSE_BUTTON_XBUTTON1: "mouse_side_back", MOUSE_BUTTON_XBUTTON2: "mouse_side_forward",
}
const MOUSE_AXIS := {&"x": "mouse_horizontal", &"y": "mouse_vertical", &"wheel": "mouse_scroll_vertical"}

const KEYS := {
	KEY_SPACE: "keyboard_space", KEY_ENTER: "keyboard_enter", KEY_KP_ENTER: "keyboard_numpad_enter",
	KEY_ESCAPE: "keyboard_escape", KEY_TAB: "keyboard_tab", KEY_BACKSPACE: "keyboard_backspace",
	KEY_SHIFT: "keyboard_shift", KEY_CTRL: "keyboard_ctrl", KEY_ALT: "keyboard_alt",
	KEY_META: "keyboard_win", KEY_CAPSLOCK: "keyboard_capslock",
	KEY_UP: "keyboard_arrow_up", KEY_DOWN: "keyboard_arrow_down",
	KEY_LEFT: "keyboard_arrow_left", KEY_RIGHT: "keyboard_arrow_right",
	KEY_HOME: "keyboard_home", KEY_END: "keyboard_end", KEY_INSERT: "keyboard_insert",
	KEY_DELETE: "keyboard_delete", KEY_PAGEUP: "keyboard_page_up", KEY_PAGEDOWN: "keyboard_page_down",
	KEY_PAUSE: "keyboard_pause", KEY_PRINT: "keyboard_printscreen", KEY_SCROLLLOCK: "keyboard_scroll_lock",
	KEY_NUMLOCK: "keyboard_numlock", KEY_KP_ADD: "keyboard_numpad_plus",
	KEY_APOSTROPHE: "keyboard_apostrophe", KEY_COMMA: "keyboard_comma", KEY_PERIOD: "keyboard_period",
	KEY_MINUS: "keyboard_minus", KEY_EQUAL: "keyboard_equals", KEY_SLASH: "keyboard_slash_forward",
	KEY_BACKSLASH: "keyboard_slash_back", KEY_SEMICOLON: "keyboard_semicolon",
	KEY_BRACKETLEFT: "keyboard_bracket_open", KEY_BRACKETRIGHT: "keyboard_bracket_close",
	KEY_QUOTELEFT: "keyboard_tilde",
}

var root := DEFAULT_ROOT
var _cache: Dictionary = {}


func _init(p_root := DEFAULT_ROOT) -> void:
	root = p_root


## Texture path for a binding resolved on `family` ("" if none).
## `g` is the CtlLayout.glyph() descriptor (it carries the resolved control).
func path_for(binding: Dictionary, g: Dictionary, family: StringName) -> String:
	var file := ""
	var dir := String(family)
	if binding.has("key"):
		dir = "kbm"
		file = _key_file(int(binding.key))
	elif binding.has("mouse"):
		dir = "kbm"
		file = MOUSE.get(int(binding.mouse), "")
	elif binding.has("mouse_axis"):
		dir = "kbm"
		file = MOUSE_AXIS.get(StringName(binding.mouse_axis), "")
	elif binding.has("pad"):
		file = _pad_file(StringName(g.get("control", binding.pad)), int(binding.get("half", 0)), family)
	if file == "":
		return ""
	return _existing("%s/%s/%s.png" % [root, dir, file])


func texture_for(binding: Dictionary, g: Dictionary, family: StringName) -> Texture2D:
	var p := path_for(binding, g, family)
	return load(p) if p != "" else null


func _existing(p: String) -> String:
	if not _cache.has(p):
		_cache[p] = ResourceLoader.exists(p)
	return p if _cache[p] else ""


func _pad_file(c: StringName, half: int, family: StringName) -> String:
	var table: Dictionary = PAD.get(family, {})
	if table.has(c):
		return table[c]
	var pre: String = STICK_PREFIX.get(family, "")
	if pre == "":
		return ""
	var s := String(c)
	if c == &"stick_l" or c == &"stick_r":
		return "%s_%s" % [pre, s]
	if s.begins_with("stick_") and (s.ends_with("_x") or s.ends_with("_y")):
		var stick := s.substr(0, 7)  # stick_l / stick_r
		if s.ends_with("_x"):
			return "%s_%s_%s" % [pre, stick, "horizontal" if half == 0 else ("left" if half < 0 else "right")]
		return "%s_%s_%s" % [pre, stick, "vertical" if half == 0 else ("up" if half < 0 else "down")]
	if family == &"generic":
		return ""
	if c == &"dpad":
		return "%s_dpad" % pre
	if s.begins_with("dpad_"):
		return "%s_%s" % [pre, s]
	return ""


## Key file by the cap the user sees (physical -> current layout).
func _key_file(physical: int) -> String:
	var code := physical
	if DisplayServer.get_name() != "headless":
		var logical := DisplayServer.keyboard_get_keycode_from_physical(physical)
		if logical != 0:
			code = logical
	if KEYS.has(code):
		return KEYS[code]
	if (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9):
		return "keyboard_" + char(code).to_lower()
	if code >= KEY_F1 and code <= KEY_F12:
		return "keyboard_f%d" % (code - KEY_F1 + 1)
	return ""
