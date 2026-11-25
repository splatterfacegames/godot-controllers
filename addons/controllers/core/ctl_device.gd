class_name CtlDevice
extends RefCounted

## One input device as the rest of the library sees it: a snapshot of raw
## canonical state, rebuilt once per input tick by poll().
##
## State keys (only non-neutral entries are present):
##   "b:<control>"  pad button held            -> true
##   "a:<control>"  pad axis raw value          -> float (sticks -1..1, triggers 0..1)
##   "k:<keycode>"  physical key held           -> true
##   "m:<button>"   mouse button held           -> true
##   "mm"           mouse motion this tick (px) -> Vector2
##   "w"            wheel notches this tick     -> float (+ up)
##
## Presses shorter than one tick are latched from events so they are seen
## for exactly one poll. Subclasses fill `_read_live()`.

const KIND_PAD := &"pad"
const KIND_KBM := &"kbm"

const _Layout := preload("ctl_layout.gd")

## Axis edge thresholds used for activity, join and rebind capture.
const AXIS_RISE := 0.6
const AXIS_REST := 0.3

var id := 0
var kind: StringName = KIND_PAD
var family: StringName = _Layout.FAMILY_GENERIC
## Detected family before any override.
var detected_family: StringName = _Layout.FAMILY_GENERIC
var display_name := ""
var guid := ""
var info: Dictionary = {}
var connected := true
## Non-empty for automated (virtual/recorded) devices; shown in overlays.
var label := ""

var state: Dictionary = {}
var _prev: Dictionary = {}
## Sources newly pressed this tick, as binding dictionaries.
var rising: Array[Dictionary] = []
## Ticks since this device was polled with meaningful activity.
var active_this_tick := false
var last_active_usec := 0
var _latched: Dictionary = {}


func is_virtual() -> bool:
	return false


## Stable identity for reconnect matching.
func signature() -> String:
	var serial := str(info.get("serial_number", info.get("serial", "")))
	return "%s|%s|%s" % [guid, display_name, serial]


func signature_loose() -> String:
	return "%s|%s" % [guid, display_name]


## Called by CtlInput for every InputEvent addressed to this device.
func latch_event(_event: InputEvent) -> void:
	pass


func poll() -> void:
	_prev = state
	state = _read_live()
	for k in _latched:
		if not state.has(k):
			state[k] = _latched[k]
	_latched.clear()
	_compute_edges()


func _read_live() -> Dictionary:
	return {}


func _compute_edges() -> void:
	rising.clear()
	for k in state:
		var ks := String(k)
		if _prev.has(k) and not ks.begins_with("a:"):
			continue
		match ks.substr(0, 2):
			"b:":
				rising.append({"pad": StringName(ks.substr(2))})
			"k:":
				rising.append({"key": int(ks.substr(2))})
			"m:":
				rising.append({"mouse": int(ks.substr(2))})
			"a:":
				var v := float(state[k])
				var was := absf(float(_prev.get(k, 0.0)))
				if absf(v) >= AXIS_RISE and was < AXIS_RISE:
					var c := StringName(ks.substr(2))
					if _Layout.is_trigger(c):
						rising.append({"pad": c})
					else:
						rising.append({"pad": c, "half": 1 if v > 0.0 else -1})
	var moved: Vector2 = state.get("mm", Vector2.ZERO)
	active_this_tick = not rising.is_empty() or moved.length() >= 4.0
	if active_this_tick:
		last_active_usec = Time.get_ticks_usec()


## True when nothing is held and every axis is near rest.
func is_neutral() -> bool:
	for k in state:
		var ks := String(k)
		if ks.begins_with("a:"):
			if absf(float(state[k])) >= AXIS_REST:
				return false
		elif ks != "mm" and ks != "w":
			return false
	return true


# ------------------------------------------------------------------ reads

func button(control: StringName) -> bool:
	if control == &"dpad":
		return dpad() != Vector2.ZERO
	return state.has("b:" + String(control))


func axis(control: StringName) -> float:
	return float(state.get("a:" + String(control), 0.0))


func stick_raw(stick: StringName) -> Vector2:
	if stick == &"dpad":
		return dpad()
	var pair: Array = _Layout.STICKS.get(stick, [])
	if pair.is_empty():
		return Vector2.ZERO
	return Vector2(axis(pair[0]), axis(pair[1]))


func dpad() -> Vector2:
	var v := Vector2(
		float(state.has("b:dpad_right")) - float(state.has("b:dpad_left")),
		float(state.has("b:dpad_down")) - float(state.has("b:dpad_up")))
	return v.normalized() if v != Vector2.ZERO else v


func key(physical: int) -> bool:
	return state.has("k:%d" % physical)


func mouse_button(b: int) -> bool:
	return state.has("m:%d" % b)


func mouse_motion() -> Vector2:
	return state.get("mm", Vector2.ZERO)


func wheel() -> float:
	return float(state.get("w", 0.0))


# ------------------------------------------------------------------ output

## Rumble (weak = high-frequency motor, strong = low-frequency motor).
## Returns false when the device can't vibrate.
func rumble(_weak: float, _strong: float, _duration: float) -> bool:
	return false


func stop_rumble() -> void:
	pass


func can_rumble() -> bool:
	return false


func describe() -> Dictionary:
	return {"id": id, "kind": kind, "family": family, "name": display_name,
		"guid": guid, "connected": connected, "label": label}
