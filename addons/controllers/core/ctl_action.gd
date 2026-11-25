class_name CtlAction
extends RefCounted

## A game action declared once and read per player.
##
## Bindings are Dictionaries (see docs/DESIGN.md):
##   {"pad": &"face_south"}          canonical pad control (or &"confirm"/&"cancel")
##   {"pad": &"stick_l"}             a whole stick (AXIS_2D)
##   {"pad": &"stick_l_y", "half": -1}  one half of an axis (axis -> button)
##   {"key": KEY_W}                  physical keycode
##   {"mouse": MOUSE_BUTTON_LEFT}
##   {"mouse_axis": &"x" | &"y" | &"wheel"}
## Modifiers: "to" (target component: "+","-" for AXIS; "x","y","x+","x-",
## "y+","y-" for AXIS_2D), "invert": bool, "scale": float.
##
## `defaults` maps binding family -> Array of bindings. Keys: "kbm",
## "gamepad" (any pad), and optional "xbox"/"playstation"/"nintendo"/
## "generic" that override "gamepad" for that family.

enum Type { BUTTON, AXIS, AXIS_2D }

var name: StringName
var type: Type = Type.BUTTON
var category: StringName = &"gameplay"
var label := ""
var defaults: Dictionary = {}

## Analog -> pressed hysteresis (trigger bindings use the player's trigger
## thresholds instead).
var press_threshold := 0.5
var release_threshold := 0.35
## Clamp AXIS to -1..1 and AXIS_2D to unit length. Turn off for mouse look.
var clamp_output := true
## Mouse pixels -> axis units.
var mouse_scale := 0.05
## Query timing, in seconds of input time.
var double_tap_window := 0.3
var repeat_delay := 0.4
var repeat_interval := 0.09
var long_press := 0.6


func _init(p_name: StringName, p_type: Type, p_category: StringName, p_label: String,
		p_defaults: Dictionary) -> void:
	name = p_name
	type = p_type
	category = p_category
	label = p_label if p_label != "" else String(p_name).capitalize()
	defaults = p_defaults.duplicate(true)


## Apply optional settings by name ({"press_threshold": 0.3, ...}).
func configure(opts: Dictionary) -> RefCounted:
	for k in opts:
		if k in self:
			set(k, opts[k])
	return self


func default_bindings(family: StringName) -> Array:
	if defaults.has(String(family)):
		return defaults[String(family)]
	if defaults.has(family):
		return defaults[family]
	if family != &"kbm":
		return defaults.get("gamepad", defaults.get(&"gamepad", []))
	return []
