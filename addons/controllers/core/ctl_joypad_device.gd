class_name CtlJoypadDevice
extends "ctl_device.gd"

## A physical gamepad/joystick known to Godot by its joy id.

static var _button_controls: Dictionary = {}


func _init(joy_id: int) -> void:
	id = joy_id
	kind = KIND_PAD
	display_name = Input.get_joy_name(joy_id)
	guid = Input.get_joy_guid(joy_id)
	info = Input.get_joy_info(joy_id)
	detected_family = _Layout.detect_family(display_name, guid, info)
	family = detected_family
	if _button_controls.is_empty():
		for c in _Layout.BUTTONS:
			_button_controls[_Layout.BUTTONS[c]] = c


## Godot knows a gamepad mapping for this device (SDL database or custom).
## Unmapped joysticks still work but their button numbering is raw.
func is_mapped() -> bool:
	return Input.is_joy_known(id)


func latch_event(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		var c: Variant = _button_controls.get(event.button_index)
		if c != null:
			_latched["b:" + String(c)] = true


func _read_live() -> Dictionary:
	var s := {}
	for c in _Layout.BUTTONS:
		if Input.is_joy_button_pressed(id, _Layout.BUTTONS[c]):
			s["b:" + String(c)] = true
	for c in _Layout.AXES:
		var v := Input.get_joy_axis(id, _Layout.AXES[c])
		if v != 0.0:
			s["a:" + String(c)] = v
	return s


func can_rumble() -> bool:
	return Input.has_joy_vibration(id)


func rumble(weak: float, strong: float, duration: float) -> bool:
	if not connected:
		return false
	Input.start_joy_vibration(id, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), maxf(duration, 0.0))
	return Input.has_joy_vibration(id)


func stop_rumble() -> void:
	Input.stop_joy_vibration(id)
