class_name CtlKbmDevice
extends "ctl_device.gd"

## The shared keyboard + mouse, as one device (id -1). State is built from
## events: held keys/buttons are tracked by press/release, motion and wheel
## accumulate between polls. Keys are PHYSICAL keycodes (board position).

const ID := -1

var _held: Dictionary = {}
var _motion := Vector2.ZERO
var _wheel := 0.0


func _init() -> void:
	id = ID
	kind = KIND_KBM
	family = _Layout.FAMILY_KBM
	detected_family = family
	display_name = "Keyboard & Mouse"


func signature() -> String:
	return "kbm"


func signature_loose() -> String:
	return "kbm"


func latch_event(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.echo:
			return
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var k := "k:%d" % code
		if event.pressed:
			_held[k] = true
			_latched[k] = true
		else:
			_held.erase(k)
	elif event is InputEventMouseButton:
		var k := "m:%d" % event.button_index
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_wheel += maxf(event.factor, 1.0) if event.factor != 0.0 else 1.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_wheel -= maxf(event.factor, 1.0) if event.factor != 0.0 else 1.0
		if event.pressed:
			_held[k] = true
			_latched[k] = true
		else:
			_held.erase(k)
		# Wheel "buttons" never send a held state; they are one-tick taps.
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			_held.erase(k)
	elif event is InputEventMouseMotion:
		_motion += event.relative


func _read_live() -> Dictionary:
	var s := _held.duplicate()
	if _motion != Vector2.ZERO:
		s["mm"] = _motion
	if _wheel != 0.0:
		s["w"] = _wheel
	_motion = Vector2.ZERO
	_wheel = 0.0
	return s


## Focus loss: forget everything held (no release events arrive while
## another window has focus).
func clear_held() -> void:
	_held.clear()
	_latched.clear()
	_motion = Vector2.ZERO
	_wheel = 0.0
