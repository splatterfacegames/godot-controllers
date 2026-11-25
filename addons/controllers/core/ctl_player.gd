class_name CtlPlayer
extends RefCounted

## One player: their devices, enabled map categories, binding overrides,
## analog settings, rumble and per-action state. Created and ticked by
## CtlInput; games read it through the query methods below.
##
## All queries reflect the most recent input tick, so reading them inside
## _physics_process (default tick mode) or right after a manual
## Controllers.tick() is frame-accurate.

const _Layout := preload("ctl_layout.gd")
const _Proc := preload("ctl_processing.gd")
const _Action := preload("ctl_action.gd")
const _Device := preload("ctl_device.gd")

var index := 0
## Key used for persistence. Defaults to "player<N>"; set it to a profile
## id to keep bindings with a profile instead of a seat.
var profile_key := ""
var devices: Array = []
## Devices lost to disconnect, waiting to come back:
## [{sig, loose, family, name}]
var reservations: Array[Dictionary] = []
## Most recently meaningfully used device (drives glyphs). May be a device
## that has since disconnected; its family is kept for prompts.
var last_device: _Device = null
var last_family: StringName = _Layout.FAMILY_KBM

## family(String) -> {action(String): Array of bindings}
var overrides: Dictionary = {}
var stick_settings := {"stick_l": {}, "stick_r": {}}
var trigger_settings := {}
## 0..1 multiplier on every rumble request (accessibility).
var rumble_scale := 1.0

var time := 0.0
var ticks := 0
var _disabled: Dictionary = {}
var _st: Dictionary = {}
var _warned: Dictionary = {}


func _init(p_index: int) -> void:
	index = p_index
	profile_key = "player%d" % p_index


# ------------------------------------------------------------------ devices

func has_device(dev: _Device) -> bool:
	return dev in devices


func has_pad() -> bool:
	for d in devices:
		if d.kind == _Device.KIND_PAD:
			return true
	return false


func is_present() -> bool:
	return not devices.is_empty() or not reservations.is_empty()


## Family used for glyphs: the last used device's, else the first device's.
func glyph_family() -> StringName:
	if last_device != null:
		return last_device.family
	if not devices.is_empty():
		return devices[0].family
	return last_family


# ------------------------------------------------------------------ categories

func set_category_enabled(category: StringName, enabled: bool, actions: Dictionary = {}) -> void:
	var was := is_category_enabled(category)
	if enabled:
		_disabled.erase(category)
	else:
		_disabled[category] = true
	if enabled and not was:
		# A press carried in from elsewhere (e.g. the menu confirm that
		# resumed play) must not fire in the newly enabled category.
		for a in actions.values():
			if a.category == category and _state(a.name).raw_pressed:
				_state(a.name).suppressed = true


func is_category_enabled(category: StringName) -> bool:
	return not _disabled.has(category)


## Enable exactly the listed categories (others off).
func set_categories(enabled: Array, actions: Dictionary) -> void:
	var known := {}
	for a in actions.values():
		known[a.category] = true
	for c in enabled:
		known[StringName(c)] = true
	for c in known:
		set_category_enabled(c, StringName(c) in enabled or String(c) in enabled, actions)


# ------------------------------------------------------------------ bindings

func bindings_for(action: _Action, family: StringName) -> Array:
	var fam := String(family)
	if overrides.has(fam) and (overrides[fam] as Dictionary).has(String(action.name)):
		return overrides[fam][String(action.name)]
	return action.default_bindings(family)


func set_bindings(action: _Action, family: StringName, list: Array) -> void:
	var fam := String(family)
	if not overrides.has(fam):
		overrides[fam] = {}
	overrides[fam][String(action.name)] = list.duplicate(true)


func clear_overrides(family: StringName = &"") -> void:
	if family == &"":
		overrides.clear()
	else:
		overrides.erase(String(family))


# ------------------------------------------------------------------ tick

func _state(action: StringName) -> Dictionary:
	if not _st.has(action):
		_st[action] = {"raw_pressed": false, "pressed": false, "value": 0.0,
			"vector": Vector2.ZERO, "just_pressed": false, "just_released": false,
			"held_ticks": 0, "held_time": 0.0, "last_press": -1000.0,
			"double": false, "repeated": false, "next_repeat": 0.0,
			"long_now": false, "long_fired": false, "suppressed": false,
			"device": null}
	return _st[action]


func tick(dt: float, actions: Dictionary, ctx: Dictionary) -> void:
	time += dt
	ticks += 1
	var focused: bool = ctx.get("focused", true)
	for a in actions.values():
		var st := _state(a.name)
		var ev := _evaluate(a, ctx, st.raw_pressed)
		st.raw_pressed = ev.pressed and focused
		var out_on: bool = focused and is_category_enabled(a.category)
		if st.suppressed:
			if not st.raw_pressed:
				st.suppressed = false
			out_on = false
		var was: bool = st.pressed
		var now: bool = out_on and st.raw_pressed
		st.pressed = now
		st.value = ev.value if out_on else 0.0
		st.vector = ev.vector if out_on else Vector2.ZERO
		st.device = ev.device
		st.just_pressed = now and not was
		st.just_released = was and not now
		st.double = false
		st.repeated = false
		st.long_now = false
		if now:
			st.held_ticks += 1
			st.held_time += dt
		else:
			st.held_ticks = 0
			st.held_time = 0.0
			st.long_fired = false
		if st.just_pressed:
			if time - float(st.last_press) <= a.double_tap_window:
				st.double = true
				st.last_press = -1000.0
			else:
				st.last_press = time
			st.repeated = true
			st.next_repeat = time + a.repeat_delay
		elif now and time >= float(st.next_repeat):
			st.repeated = true
			st.next_repeat = float(st.next_repeat) + a.repeat_interval
			if st.next_repeat < time:
				st.next_repeat = time + a.repeat_interval
		if now and not st.long_fired and st.held_time >= a.long_press:
			st.long_fired = true
			st.long_now = true


## Read every binding on every device into one action value.
func _evaluate(a: _Action, ctx: Dictionary, was_pressed: bool) -> Dictionary:
	var confirm: StringName = ctx.get("confirm_follows", _Layout.CONFIRM_BY_POSITION)
	var digital := false
	var strength := 0.0
	var trig_strength := 0.0
	var axis_a := 0.0
	var axis_d := 0.0
	var vec_a := Vector2.ZERO
	var vec_d := Vector2.ZERO
	var source_dev: _Device = null
	var best := 0.0
	for dev in devices:
		if not dev.connected:
			continue
		for b in bindings_for(a, dev.family):
			var r := _read(dev, b, a, confirm)
			if r.is_empty():
				continue
			var v: Variant = r.v
			var is_dig: bool = r.digital
			var mag := (v as Vector2).length() if v is Vector2 else absf(float(v))
			if mag > best:
				best = mag
				source_dev = dev
			match a.type:
				_Action.Type.BUTTON:
					if is_dig:
						digital = digital or mag >= 0.5
					elif r.trigger:
						trig_strength = maxf(trig_strength, mag)
					else:
						strength = maxf(strength, mag)
				_Action.Type.AXIS:
					var sign := -1.0 if str(b.get("to", "+")) == "-" else 1.0
					var f: float = (v as Vector2).x if v is Vector2 else float(v)
					if is_dig:
						axis_d += f * sign
					else:
						axis_a += f * sign
				_Action.Type.AXIS_2D:
					var to := str(b.get("to", "xy"))
					var add := Vector2.ZERO
					if v is Vector2:
						add = v
						if to == "x":
							add = Vector2(add.x, 0)
						elif to == "y":
							add = Vector2(0, add.y)
					else:
						var f2 := float(v)
						match to:
							"x", "x+": add = Vector2(f2, 0)
							"x-": add = Vector2(-f2, 0)
							"y", "y+": add = Vector2(0, f2)
							"y-": add = Vector2(0, -f2)
							_: add = Vector2(f2, 0)
					if is_dig:
						vec_d += add
					else:
						vec_a += add
	var out := {"pressed": false, "value": 0.0, "vector": Vector2.ZERO, "device": source_dev}
	match a.type:
		_Action.Type.BUTTON:
			var t := _Proc.with_defaults(trigger_settings, _Proc.TRIGGER_DEFAULTS)
			var p := digital \
				or _Proc.hysteresis(trig_strength, was_pressed, float(t.press), float(t.release)) \
				or _Proc.hysteresis(strength, was_pressed, a.press_threshold, a.release_threshold)
			out.pressed = p
			out.value = 1.0 if digital else maxf(strength, trig_strength)
		_Action.Type.AXIS:
			var total := axis_a + clampf(axis_d, -1.0, 1.0)
			if a.clamp_output:
				total = clampf(total, -1.0, 1.0)
			out.value = total
			out.vector = Vector2(total, 0)
			out.pressed = _Proc.hysteresis(absf(total), was_pressed, a.press_threshold, a.release_threshold)
		_Action.Type.AXIS_2D:
			if vec_d.length() > 1.0:
				vec_d = vec_d.normalized()
			var total2 := vec_a + vec_d
			if a.clamp_output:
				total2 = total2.limit_length(1.0)
			out.vector = total2
			out.value = total2.length()
			out.pressed = _Proc.hysteresis(total2.length(), was_pressed, a.press_threshold, a.release_threshold)
	return out


## One binding on one device -> {v: float|Vector2, digital: bool, trigger: bool}
## or {} when the binding doesn't apply to this device.
func _read(dev: _Device, b: Dictionary, a: _Action, confirm: StringName) -> Dictionary:
	var v: Variant = null
	var dig := false
	var trig := false
	if b.has("pad"):
		if dev.kind != _Device.KIND_PAD:
			return {}
		var c := _Layout.resolve(StringName(b.pad), dev.family, confirm)
		if _Layout.is_button(c):
			v = 1.0 if dev.button(c) else 0.0
			dig = true
		elif c == &"dpad":
			v = dev.dpad()
			dig = true
		elif _Layout.STICKS.has(c):
			v = processed_stick(dev, c)
		elif _Layout.STICK_OF_AXIS.has(c):
			var s := processed_stick(dev, _Layout.STICK_OF_AXIS[c])
			v = s.x if String(c).ends_with("_x") else s.y
		elif _Layout.is_trigger(c):
			v = _Proc.trigger(dev.axis(c), trigger_settings)
			trig = true
		else:
			return {}
	elif b.has("key"):
		if dev.kind != _Device.KIND_KBM:
			return {}
		v = 1.0 if dev.key(int(b.key)) else 0.0
		dig = true
	elif b.has("mouse"):
		if dev.kind != _Device.KIND_KBM:
			return {}
		v = 1.0 if dev.mouse_button(int(b.mouse)) else 0.0
		dig = true
	elif b.has("mouse_axis"):
		if dev.kind != _Device.KIND_KBM:
			return {}
		match StringName(b.mouse_axis):
			&"x": v = dev.mouse_motion().x * a.mouse_scale
			&"y": v = dev.mouse_motion().y * a.mouse_scale
			&"wheel": v = dev.wheel()
			_: return {}
	else:
		return {}
	var half := int(b.get("half", 0))
	if half != 0 and not (v is Vector2):
		v = maxf(0.0, float(v) * half)
	if b.get("invert", false):
		v = -v
	if b.has("scale"):
		v = v * float(b.scale)
	return {"v": v, "digital": dig, "trigger": trig}


## A stick on a device after this player's deadzone/curve settings.
func processed_stick(dev: _Device, stick: StringName) -> Vector2:
	if stick == &"dpad":
		return dev.dpad()
	return _Proc.stick(dev.stick_raw(stick), stick_settings.get(String(stick), {}))


# ------------------------------------------------------------------ queries

func _q(action: StringName) -> Dictionary:
	if not _st.has(action):
		if not _warned.has(action):
			_warned[action] = true
		return _state(action)
	return _st[action]


func is_pressed(action: StringName) -> bool:
	return _q(action).pressed


func is_just_pressed(action: StringName) -> bool:
	return _q(action).just_pressed


func is_just_released(action: StringName) -> bool:
	return _q(action).just_released


## BUTTON: 0..1 strength; AXIS: -1..1; AXIS_2D: vector length.
func get_value(action: StringName) -> float:
	return _q(action).value


func get_vector(action: StringName) -> Vector2:
	return _q(action).vector


func held_time(action: StringName) -> float:
	return _q(action).held_time


func held_ticks(action: StringName) -> int:
	return _q(action).held_ticks


## True on the tick of a second press within the action's window.
func is_double_tapped(action: StringName) -> bool:
	return _q(action).double


## True on the initial press, then every repeat_interval after repeat_delay
## while held. Use for menu navigation.
func is_repeated(action: StringName) -> bool:
	return _q(action).repeated


## True once, on the tick the hold reaches the action's long_press time.
func is_long_pressed(action: StringName) -> bool:
	return _q(action).long_now


## The device that contributed most to the action this tick (or null).
func action_device(action: StringName) -> _Device:
	return _q(action).device


# ------------------------------------------------------------------ rumble

## Vibrate every pad this player holds. Returns true if any device took it.
func rumble(weak: float, strong: float, duration: float) -> bool:
	var any := false
	for d in devices:
		if d.rumble(weak * rumble_scale, strong * rumble_scale, duration):
			any = true
	return any


func stop_rumble() -> void:
	for d in devices:
		d.stop_rumble()


# ------------------------------------------------------------------ persistence

func export_settings() -> Dictionary:
	return {"stick_settings": stick_settings.duplicate(true),
		"trigger_settings": trigger_settings.duplicate(true), "rumble_scale": rumble_scale}


func import_settings(d: Dictionary) -> void:
	if d.get("stick_settings") is Dictionary:
		for k in d.stick_settings:
			stick_settings[String(k)] = (d.stick_settings[k] as Dictionary).duplicate(true)
	if d.get("trigger_settings") is Dictionary:
		trigger_settings = (d.trigger_settings as Dictionary).duplicate(true)
	rumble_scale = float(d.get("rumble_scale", rumble_scale))
