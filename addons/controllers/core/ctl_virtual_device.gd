class_name CtlVirtualDevice
extends "ctl_device.gd"

## Scripted/recorded input that runs through exactly the same pipeline as
## a real device: assign it to a player and the player's actions, edges,
## processing and glyphs behave as for hardware of the emulated family.
##
## Always labelled (e.g. "journey driver") so overlays and logs can say
## the input was automated. Every injection is appended to `injection_log` with the
## device tick it took effect on.
##
##   var bot := Controllers.add_virtual_device(&"xbox", "journey driver")
##   Controllers.assign_device(0, bot)
##   bot.tap(&"face_south")           # one-tick press
##   bot.set_stick(&"stick_l", Vector2(1, 0))
##   bot.play(CtlRecorder.load_file("res://journeys/intro.json"))

const FIRST_ID := 1000

var tick := 0
var injection_log: Array[Dictionary] = []
## Optional playback: frames from CtlRecorder ([{t, state}]...).
var _playback: Array = []
var _play_index := 0
var _play_start := 0
var _pending: Dictionary = {}
var _taps: Dictionary = {}
var rumble_log: Array[Dictionary] = []


func _init(virtual_id: int, emulated_family: StringName, p_label: String) -> void:
	id = virtual_id
	family = emulated_family
	detected_family = emulated_family
	kind = KIND_KBM if emulated_family == _Layout.FAMILY_KBM else KIND_PAD
	label = p_label if p_label != "" else "virtual"
	display_name = "Virtual %s (%s)" % [_Layout.family_display_name(emulated_family), label]
	guid = "virtual-%d" % virtual_id


func is_virtual() -> bool:
	return true


func _note(what: String, args: Variant = null) -> void:
	injection_log.append({"tick": tick, "label": label, "what": what, "args": args})


# ------------------------------------------------------------------ inject

func press(control: StringName) -> void:
	_pending["b:" + String(control)] = true
	_note("press", control)


func release(control: StringName) -> void:
	_pending.erase("b:" + String(control))
	_note("release", control)


## Pressed for exactly the next poll, then released.
func tap(control: StringName) -> void:
	_taps["b:" + String(control)] = true
	_note("tap", control)


func set_axis(control: StringName, value: float) -> void:
	var k := "a:" + String(control)
	if value == 0.0:
		_pending.erase(k)
	else:
		_pending[k] = value
	_note("axis", [control, value])


func set_stick(stick: StringName, v: Vector2) -> void:
	var pair: Array = _Layout.STICKS.get(stick, [])
	if pair.size() == 2:
		set_axis(pair[0], v.x)
		set_axis(pair[1], v.y)


func key_down(physical: int) -> void:
	_pending["k:%d" % physical] = true
	_note("key_down", physical)


func key_up(physical: int) -> void:
	_pending.erase("k:%d" % physical)
	_note("key_up", physical)


func key_tap(physical: int) -> void:
	_taps["k:%d" % physical] = true
	_note("key_tap", physical)


func mouse_down(b: int) -> void:
	_pending["m:%d" % b] = true
	_note("mouse_down", b)


func mouse_up(b: int) -> void:
	_pending.erase("m:%d" % b)
	_note("mouse_up", b)


func mouse_move(rel: Vector2) -> void:
	_taps["mm"] = _taps.get("mm", Vector2.ZERO) + rel
	_note("mouse_move", rel)


func release_all() -> void:
	_pending.clear()
	_taps.clear()
	_note("release_all")


## Replace the whole raw state (used by playback).
func set_state(s: Dictionary) -> void:
	_pending = s.duplicate()


## Play a recording (CtlRecorder frames). Starts on the next poll.
func play(frames: Array) -> void:
	_playback = frames
	_play_index = 0
	_play_start = tick + 1
	_note("play", frames.size())


func is_playing() -> bool:
	return _play_index < _playback.size()


func _read_live() -> Dictionary:
	tick += 1
	while _play_index < _playback.size() and int(_playback[_play_index].t) + _play_start <= tick:
		_pending = (_playback[_play_index].state as Dictionary).duplicate()
		_play_index += 1
	var s := _pending.duplicate()
	for k in _taps:
		s[k] = _taps[k]
	_taps.clear()
	return s


func can_rumble() -> bool:
	return true


func rumble(weak: float, strong: float, duration: float) -> bool:
	rumble_log.append({"tick": tick, "weak": weak, "strong": strong, "duration": duration})
	return true


func stop_rumble() -> void:
	rumble_log.append({"tick": tick, "stop": true})
