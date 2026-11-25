class_name CtlFeatures
extends RefCounted

## Optional, hardware-specific features behind honest capability checks.
##
## Implemented on Godot's own APIs (4.7+): motion sensors (gyroscope,
## accelerometer, gravity) and the controller light. Whether a given pad
## exposes them is reported by Godot/SDL at runtime; `supports()` asks.
##
## NOT supported (Godot has no API, so these are never faked):
##   adaptive_triggers  DualSense trigger resistance/effects
##   hd_rumble          Nintendo HD rumble / per-actuator waveforms
##   trigger_rumble     Xbox impulse triggers (per-trigger motors)
##   haptics_audio      audio-driven haptics
## Their setters return ERR_UNAVAILABLE. A platform module could implement
## them later behind the same calls.

const MOTION := &"motion"
const LIGHT := &"light"
const RUMBLE := &"rumble"
const ADAPTIVE_TRIGGERS := &"adaptive_triggers"
const HD_RUMBLE := &"hd_rumble"
const TRIGGER_RUMBLE := &"trigger_rumble"
const HAPTICS_AUDIO := &"haptics_audio"

const UNSUPPORTED_NOTE := {
	ADAPTIVE_TRIGGERS: "Not supported yet: Godot exposes no DualSense trigger-effect API.",
	HD_RUMBLE: "Not supported yet: Godot exposes no HD rumble waveform API; plain rumble works.",
	TRIGGER_RUMBLE: "Not supported yet: Godot exposes no per-trigger motor API.",
	HAPTICS_AUDIO: "Not supported yet: Godot exposes no audio-haptics API.",
}


static func _joy(device: RefCounted) -> int:
	if device == null or device.is_virtual() or device.kind != &"pad" or not device.connected:
		return -1
	return device.id


static func supports(device: RefCounted, feature: StringName) -> bool:
	var joy := _joy(device)
	if joy < 0:
		return false
	match feature:
		MOTION: return Input.has_joy_motion_sensors(joy)
		LIGHT: return Input.has_joy_light(joy)
		RUMBLE: return Input.has_joy_vibration(joy)
	return false


static func note(feature: StringName) -> String:
	return UNSUPPORTED_NOTE.get(feature, "")


# ------------------------------------------------------------------ motion

static func set_motion_enabled(device: RefCounted, enabled: bool) -> Error:
	var joy := _joy(device)
	if joy < 0 or not Input.has_joy_motion_sensors(joy):
		return ERR_UNAVAILABLE
	Input.set_joy_motion_sensors_enabled(joy, enabled)
	return OK


## Angular velocity (Godot's units/axes as reported by the platform).
static func gyroscope(device: RefCounted) -> Vector3:
	var joy := _joy(device)
	return Input.get_joy_gyroscope(joy) if joy >= 0 else Vector3.ZERO


static func accelerometer(device: RefCounted) -> Vector3:
	var joy := _joy(device)
	return Input.get_joy_accelerometer(joy) if joy >= 0 else Vector3.ZERO


static func gravity(device: RefCounted) -> Vector3:
	var joy := _joy(device)
	return Input.get_joy_gravity(joy) if joy >= 0 else Vector3.ZERO


static func start_motion_calibration(device: RefCounted) -> Error:
	var joy := _joy(device)
	if joy < 0 or not Input.has_joy_motion_sensors(joy):
		return ERR_UNAVAILABLE
	Input.start_joy_motion_sensors_calibration(joy)
	return OK


static func stop_motion_calibration(device: RefCounted) -> Error:
	var joy := _joy(device)
	if joy < 0:
		return ERR_UNAVAILABLE
	Input.stop_joy_motion_sensors_calibration(joy)
	return OK


# ------------------------------------------------------------------ light

static func set_light(device: RefCounted, color: Color) -> Error:
	var joy := _joy(device)
	if joy < 0 or not Input.has_joy_light(joy):
		return ERR_UNAVAILABLE
	Input.set_joy_light(joy, color)
	return OK


# ------------------------------------------------------------------ unsupported

static func set_adaptive_trigger(_device: RefCounted, _trigger: StringName, _effect: Dictionary) -> Error:
	return ERR_UNAVAILABLE


static func play_hd_rumble(_device: RefCounted, _waveform: Dictionary) -> Error:
	return ERR_UNAVAILABLE


static func trigger_rumble(_device: RefCounted, _left: float, _right: float, _duration: float) -> Error:
	return ERR_UNAVAILABLE
