class_name CtlInput
extends Node

## The input manager. Add one (the editor plugin registers it as the
## `Controllers` autoload, or instance it yourself) and:
##
##   Controllers.declare_action(&"jump", CtlAction.Type.BUTTON, &"gameplay", "Jump",
##       {"kbm": [{"key": KEY_SPACE}], "gamepad": [{"pad": &"face_south"}]})
##   Controllers.declare_action(&"move", CtlAction.Type.AXIS_2D, &"gameplay", "Move",
##       {"kbm": [{"key": KEY_A, "to": "x-"}, {"key": KEY_D, "to": "x+"},
##                {"key": KEY_W, "to": "y-"}, {"key": KEY_S, "to": "y+"}],
##        "gamepad": [{"pad": &"stick_l"}, {"pad": &"dpad"}]})
##   ...
##   var p := Controllers.player(0)
##   if p.is_just_pressed(&"jump"): ...
##   velocity = p.get_vector(&"move") * speed
##
## Responsibilities: device registry and hotplug, players and joining,
## reconnect reservations, the input tick, rebinding capture with conflict
## policy, persistence, glyph lookup and focus handling.

signal device_connected(device)
signal device_disconnected(device)
signal player_joined(player)
signal player_left(player)
signal device_assigned(player, device)
signal device_unassigned(player, device)
## A device came back and was given back to the player that lost it.
signal device_reconnected(player, device)
## The device a player last used changed (glyphs should refresh).
signal active_device_changed(player, device)
## Glyphs for a player may differ now (device family or bindings changed).
signal glyphs_changed(player_index: int)
signal bindings_changed(player_index: int)
signal rebind_started(player_index: int, action: StringName)
signal rebind_finished(player_index: int, action: StringName, binding: Dictionary, family: StringName)
signal rebind_cancelled(player_index: int, action: StringName)
## Policy "reject" (or any refusal): nothing changed.
signal rebind_conflict(player_index: int, action: StringName, binding: Dictionary, other_action: StringName)
## Emitted after every tick (players are up to date).
signal ticked(dt: float)

const _Layout := preload("ctl_layout.gd")
const _Proc := preload("ctl_processing.gd")
const _Action := preload("ctl_action.gd")
const _Player := preload("ctl_player.gd")
const _Device := preload("ctl_device.gd")
const _Joypad := preload("ctl_joypad_device.gd")
const _Kbm := preload("ctl_kbm_device.gd")
const _Virtual := preload("ctl_virtual_device.gd")

enum JoinMode { AUTO, PRESS, MANUAL }
enum TickMode { PHYSICS, PROCESS, MANUAL }

const POLICY_SWAP := &"swap"
const POLICY_REPLACE := &"replace"
const POLICY_REJECT := &"reject"
const POLICY_ALLOW := &"allow"

@export var join_mode: JoinMode = JoinMode.AUTO
@export var tick_mode: TickMode = TickMode.PHYSICS:
	set(v):
		tick_mode = v
		_apply_tick_mode()
@export var max_players := 4
## AUTO: the player that keyboard+mouse joins (-1 = keyboard joins like a
## pad, by pressing a join control).
@export var kbm_player := 0
## PRESS: whether new devices can join right now.
@export var join_open := true
## "position" (default) or "label": see CtlLayout.resolve().
@export var confirm_follows: StringName = _Layout.CONFIRM_BY_POSITION:
	set(v):
		confirm_follows = v
		for p in _players:
			glyphs_changed.emit(p.index)
@export var conflict_policy: StringName = POLICY_SWAP
## Release everything and ignore input while the window is unfocused.
@export var release_on_focus_loss := true
## Persist bindings/settings here ("" disables persistence).
@export var storage_path := "user://controllers/input.cfg"

## PRESS mode join inputs.
var join_bindings: Array = [{"pad": &"start"}, {"pad": &"confirm"},
	{"key": KEY_ENTER}, {"key": KEY_SPACE}]

var _actions: Dictionary = {}          # StringName -> CtlAction
var _devices: Dictionary = {}          # id -> CtlDevice
var _players: Array = []               # CtlPlayer, index == position
var _kbm: _Device
var _next_virtual := _Virtual.FIRST_ID
var _focused := true
var _conflict_groups: Array = []       # Array of Arrays of category names
var _rebind: Dictionary = {}
var _cfg := ConfigFile.new()
var _cfg_loaded := false
var _last_any_device: _Device = null


func _init() -> void:
	_kbm = _Kbm.new()
	_devices[_kbm.id] = _kbm


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -1000
	process_priority = -1000
	_load_cfg()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for joy in Input.get_connected_joypads():
		_add_joypad(joy)
	if join_mode == JoinMode.AUTO and kbm_player >= 0:
		assign_device(kbm_player, _kbm)
	_apply_tick_mode()


func _apply_tick_mode() -> void:
	if not is_inside_tree():
		return
	set_physics_process(tick_mode == TickMode.PHYSICS)
	set_process(tick_mode == TickMode.PROCESS)


func _physics_process(delta: float) -> void:
	tick(delta)


func _process(delta: float) -> void:
	tick(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_kbm.latch_event(event)
	elif event is InputEventJoypadButton:
		var d: _Device = _devices.get(event.device)
		if d != null and not d.is_virtual():
			d.latch_event(event)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if release_on_focus_loss:
			_focused = false
			_kbm.clear_held()
			for p in _players:
				p.stop_rumble()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_focused = true


## Testing/QA: behave as if focus changed.
func set_focused(focused: bool) -> void:
	_notification(NOTIFICATION_APPLICATION_FOCUS_IN if focused else NOTIFICATION_APPLICATION_FOCUS_OUT)


func is_focused() -> bool:
	return _focused


# ================================================================== actions

func declare_action(name: StringName, type: _Action.Type, category: StringName, label := "",
		defaults: Dictionary = {}, opts: Dictionary = {}) -> _Action:
	var a := _Action.new(name, type, category, label, defaults)
	a.configure(opts)
	_actions[name] = a
	for p in _players:
		glyphs_changed.emit(p.index)
	return a


func get_action(name: StringName) -> _Action:
	return _actions.get(name)


func actions() -> Dictionary:
	return _actions


func categories() -> Array:
	var out := []
	for a in _actions.values():
		if not a.category in out:
			out.append(a.category)
	return out


## Categories that can be active together, so a binding in one conflicts
## with a binding in another (a category always conflicts with itself).
func add_conflict_group(categories_list: Array) -> void:
	_conflict_groups.append(categories_list.map(func(c): return StringName(c)))


func _categories_conflict(a: StringName, b: StringName) -> bool:
	if a == b:
		return true
	for g in _conflict_groups:
		if a in g and b in g:
			return true
	return false


# ================================================================== players

func player(index: int) -> _Player:
	while _players.size() <= index:
		var p := _Player.new(_players.size())
		_players.append(p)
		_load_player(p)
	return _players[index]


func players() -> Array:
	return _players


## Players that have a device or are waiting for one to reconnect.
func active_players() -> Array:
	return _players.filter(func(p): return p.is_present())


func player_count() -> int:
	return active_players().size()


func player_of(device: _Device) -> _Player:
	for p in _players:
		if p.has_device(device):
			return p
	return null


func set_category_enabled(player_index: int, category: StringName, enabled: bool) -> void:
	player(player_index).set_category_enabled(category, enabled, _actions)


## Every existing player.
func set_category_enabled_all(category: StringName, enabled: bool) -> void:
	for p in _players:
		p.set_category_enabled(category, enabled, _actions)


func remove_player(index: int) -> void:
	if index >= _players.size():
		return
	var p: _Player = _players[index]
	for d in p.devices.duplicate():
		unassign_device(d)
	p.reservations.clear()
	player_left.emit(p)


# ================================================================== devices

func devices() -> Array:
	return _devices.values()


func get_device(id: int) -> _Device:
	return _devices.get(id)


func keyboard_mouse() -> _Device:
	return _kbm


## Last device with meaningful input across everyone (for single-player
## prompts before any player is assigned).
func last_used_device() -> _Device:
	return _last_any_device


func set_family_override(device: _Device, family: StringName) -> void:
	device.family = family if family != &"" else device.detected_family
	var p := player_of(device)
	if p != null:
		glyphs_changed.emit(p.index)


func assign_device(player_index: int, device: _Device) -> void:
	if device == null:
		return
	var prev := player_of(device)
	if prev != null:
		if prev.index == player_index:
			return
		unassign_device(device)
	var p := player(player_index)
	var was_present := p.is_present()
	p.devices.append(device)
	if p.last_device == null or p.last_device.kind == device.kind or not p.last_device.connected:
		p.last_device = device
		p.last_family = device.family
	if not was_present:
		player_joined.emit(p)
	device_assigned.emit(p, device)
	glyphs_changed.emit(p.index)


func unassign_device(device: _Device) -> void:
	var p := player_of(device)
	if p == null:
		return
	p.devices.erase(device)
	device.stop_rumble()
	device_unassigned.emit(p, device)
	glyphs_changed.emit(p.index)


func add_virtual_device(family: StringName = _Layout.FAMILY_XBOX, label := "automated") -> _Virtual:
	var d := _Virtual.new(_next_virtual, family, label)
	_next_virtual += 1
	_devices[d.id] = d
	device_connected.emit(d)
	return d


func remove_virtual_device(d: _Virtual) -> void:
	if d == null or not _devices.has(d.id):
		return
	unassign_device(d)
	d.connected = false
	_devices.erase(d.id)
	device_disconnected.emit(d)


## Labels of every virtual device currently assigned to a player. Show
## these in any capture overlay ("AUTOMATED INPUT: ...").
func automation_labels() -> Array[String]:
	var out: Array[String] = []
	for p in _players:
		for d in p.devices:
			if d.is_virtual() and not d.label in out:
				out.append(d.label)
	return out


func _add_joypad(joy: int) -> _Device:
	var d := _Joypad.new(joy)
	_devices[joy] = d
	device_connected.emit(d)
	# Reconnect: exact signature first, then GUID+name.
	for pass_i in 2:
		for p in _players:
			for i in p.reservations.size():
				var r: Dictionary = p.reservations[i]
				var hit: bool = r.sig == d.signature() if pass_i == 0 else r.loose == d.signature_loose()
				if hit:
					p.reservations.remove_at(i)
					if r.has("family_override") and r.family_override != d.detected_family:
						d.family = r.family_override
					assign_device(p.index, d)
					device_reconnected.emit(p, d)
					return d
	if join_mode == JoinMode.AUTO:
		for i in max_players:
			var p := player(i)
			if not p.has_pad() and p.reservations.is_empty():
				assign_device(i, d)
				break
	return d


func _on_joy_connection_changed(joy: int, connected: bool) -> void:
	if connected:
		if _devices.has(joy):
			_drop_joypad(joy)
		_add_joypad(joy)
	else:
		_drop_joypad(joy)


func _drop_joypad(joy: int) -> void:
	var d: _Device = _devices.get(joy)
	if d == null or d.is_virtual():
		return
	d.connected = false
	_devices.erase(joy)
	var p := player_of(d)
	if p != null:
		p.devices.erase(d)
		var r := {"sig": d.signature(), "loose": d.signature_loose(), "name": d.display_name,
			"family": d.family}
		if d.family != d.detected_family:
			r["family_override"] = d.family
		p.reservations.append(r)
		device_unassigned.emit(p, d)
	device_disconnected.emit(d)


## QA hook: simulate a hotplug of a real joy id (state reads 0 when the OS
## doesn't know the id).
func simulate_joy_connection(joy: int, connected: bool) -> void:
	_on_joy_connection_changed(joy, connected)


# ================================================================== tick

## Advance input by one tick. Called automatically in PHYSICS/PROCESS
## modes; in MANUAL mode call it at the top of your fixed-step simulation.
func tick(dt: float) -> void:
	for d in _devices.values():
		d.poll()
	if not _focused:
		for d in _devices.values():
			d.rising.clear()
			d.active_this_tick = false
	# Activity, joins.
	for d in _devices.values():
		if not d.active_this_tick:
			continue
		_last_any_device = d
		var p := player_of(d)
		if p == null:
			_try_join(d)
			p = player_of(d)
		if p != null and p.last_device != d:
			var fam_changed: bool = p.glyph_family() != d.family
			p.last_device = d
			p.last_family = d.family
			active_device_changed.emit(p, d)
			if fam_changed:
				glyphs_changed.emit(p.index)
	if not _rebind.is_empty():
		_tick_rebind(dt)
	var ctx := {"confirm_follows": confirm_follows, "focused": _focused}
	for p in _players:
		p.tick(dt, _actions, ctx)
	ticked.emit(dt)


func _try_join(d: _Device) -> void:
	if join_mode != JoinMode.PRESS or not join_open:
		return
	var hit := false
	for r in d.rising:
		for jb in join_bindings:
			if _same_source(r, jb, d.family):
				hit = true
	if not hit:
		return
	for i in max_players:
		var p := player(i)
		if not p.is_present():
			assign_device(i, d)
			# The join press must not also act in gameplay.
			for a in _actions.values():
				p._state(a.name).suppressed = true
			return


# ================================================================== rebinding

## Start capturing a new binding for (player, action, slot).
## opts:
##   kind:    &"pad" | &"kbm" | &"any" (default: the player's last device kind)
##   to:      target component for AXIS/AXIS_2D digital captures ("x-", "+", ...)
##   policy:  conflict policy override
##   timeout: seconds (default 10; 0 = none)
func begin_rebind(player_index: int, action: StringName, slot := 0, opts: Dictionary = {}) -> bool:
	if not _actions.has(action):
		return false
	var p := player(player_index)
	var kind: StringName = opts.get("kind", &"")
	if kind == &"":
		kind = p.last_device.kind if p.last_device != null else &"any"
	_rebind = {"player": player_index, "action": action, "slot": slot, "kind": kind,
		"to": str(opts.get("to", "")), "policy": StringName(opts.get("policy", conflict_policy)),
		"timeout": float(opts.get("timeout", 10.0)), "elapsed": 0.0, "armed": false}
	rebind_started.emit(player_index, action)
	return true


func is_rebinding() -> bool:
	return not _rebind.is_empty()


func cancel_rebind() -> void:
	if _rebind.is_empty():
		return
	var r := _rebind
	_rebind = {}
	rebind_cancelled.emit(r.player, r.action)


func _rebind_devices() -> Array:
	var p := player(_rebind.player)
	var src: Array = p.devices if not p.devices.is_empty() else _devices.values()
	return src.filter(func(d): return _rebind.kind == &"any" or d.kind == _rebind.kind)


func _tick_rebind(dt: float) -> void:
	_rebind.elapsed += dt
	if _rebind.timeout > 0.0 and _rebind.elapsed >= _rebind.timeout:
		cancel_rebind()
		return
	# Escape always cancels (it is never captured as a binding).
	if _kbm.key(KEY_ESCAPE) and _kbm.rising.any(func(r): return r.get("key") == KEY_ESCAPE):
		cancel_rebind()
		return
	var devs := _rebind_devices()
	if not _rebind.armed:
		# Wait until everything is released so the press that opened the
		# rebind prompt is never captured.
		if devs.all(func(d): return d.is_neutral()):
			_rebind.armed = true
		return
	for d in devs:
		for r in d.rising:
			var b := _shape_capture(r, _actions[_rebind.action])
			if b.is_empty():
				continue
			var info := _rebind
			_rebind = {}
			apply_binding(info.player, info.action, d.family, info.slot, b, info.policy)
			return


## Turn a raw captured source into a binding suited to the action type.
func _shape_capture(r: Dictionary, a: _Action) -> Dictionary:
	var b := r.duplicate()
	var to: String = _rebind.get("to", "")
	var c: StringName = StringName(r.get("pad", &""))
	match a.type:
		_Action.Type.AXIS:
			if _Layout.STICK_OF_AXIS.has(c) and to == "":
				b.erase("half")  # whole axis
			elif to != "":
				b["to"] = to
		_Action.Type.AXIS_2D:
			if _Layout.STICK_OF_AXIS.has(c) and to == "":
				return {"pad": _Layout.STICK_OF_AXIS[c]}  # whole stick
			if c in [&"dpad_up", &"dpad_down", &"dpad_left", &"dpad_right"] and to == "":
				return {"pad": &"dpad"}
			if to == "":
				return {}  # a single button can't drive a 2D action alone
			b["to"] = to
	return b


## Physical source of a binding, normalised for comparisons on a family.
func _source_key(b: Dictionary, family: StringName) -> String:
	if b.has("pad"):
		var c := _Layout.resolve(StringName(b.pad), family, confirm_follows)
		return "pad:%s:%d" % [c, int(b.get("half", 0))]
	if b.has("key"):
		return "key:%d" % int(b.key)
	if b.has("mouse"):
		return "mouse:%d" % int(b.mouse)
	if b.has("mouse_axis"):
		return "maxis:%s" % b.mouse_axis
	return ""


func _same_source(a: Dictionary, b: Dictionary, family: StringName) -> bool:
	return _source_key(a, family) != "" and _source_key(a, family) == _source_key(b, family)


## Which other action already uses this source (in a conflicting
## category) for this player and family. &"" if none.
func find_conflict(player_index: int, action: StringName, family: StringName, binding: Dictionary) -> StringName:
	var p := player(player_index)
	var a: _Action = _actions[action]
	for other in _actions.values():
		if other.name == action or not _categories_conflict(a.category, other.category):
			continue
		for ob in p.bindings_for(other, family):
			if _same_source(ob, binding, family):
				return other.name
	return &""


## Set slot `slot` of (player, action, family) to `binding`, resolving
## conflicts by `policy`. Returns true if applied.
func apply_binding(player_index: int, action: StringName, family: StringName, slot: int,
		binding: Dictionary, policy: StringName = &"") -> bool:
	if policy == &"":
		policy = conflict_policy
	var p := player(player_index)
	var a: _Action = _actions[action]
	var list: Array = p.bindings_for(a, family).duplicate(true)
	var old: Variant = list[slot] if slot < list.size() else null
	var other := find_conflict(player_index, action, family, binding)
	if other != &"" and policy != POLICY_ALLOW:
		if policy == POLICY_REJECT:
			rebind_conflict.emit(player_index, action, binding, other)
			return false
		var oa: _Action = _actions[other]
		var olist: Array = p.bindings_for(oa, family).duplicate(true)
		for i in olist.size():
			if _same_source(olist[i], binding, family):
				if policy == POLICY_SWAP and old != null:
					var swapped: Dictionary = (old as Dictionary).duplicate()
					# Keep the other action's own component targeting.
					if olist[i].has("to"):
						swapped["to"] = olist[i].to
					else:
						swapped.erase("to")
					olist[i] = swapped
				else:
					olist[i] = null
		p.set_bindings(oa, family, olist.filter(func(x): return x != null))
	# Within this action, drop duplicates of the new source.
	for i in range(list.size() - 1, -1, -1):
		if i != slot and _same_source(list[i], binding, family):
			list.remove_at(i)
			if i < slot:
				slot -= 1
	if slot < list.size():
		list[slot] = binding
	else:
		list.append(binding)
	p.set_bindings(a, family, list)
	_save_player(p)
	bindings_changed.emit(player_index)
	glyphs_changed.emit(player_index)
	rebind_finished.emit(player_index, action, binding, family)
	return true


func remove_binding(player_index: int, action: StringName, family: StringName, slot: int) -> void:
	var p := player(player_index)
	var a: _Action = _actions[action]
	var list: Array = p.bindings_for(a, family).duplicate(true)
	if slot < list.size():
		list.remove_at(slot)
	p.set_bindings(a, family, list)
	_save_player(p)
	bindings_changed.emit(player_index)
	glyphs_changed.emit(player_index)


## Restore defaults for one family ("" = all families) of a player.
func reset_bindings(player_index: int, family: StringName = &"") -> void:
	var p := player(player_index)
	p.clear_overrides(family)
	_save_player(p)
	bindings_changed.emit(player_index)
	glyphs_changed.emit(player_index)


## Copy a player's bindings from one pad family to another (e.g. apply an
## Xbox layout the player built to their PlayStation pad).
func copy_bindings(player_index: int, from_family: StringName, to_family: StringName) -> void:
	var p := player(player_index)
	for a in _actions.values():
		p.set_bindings(a, to_family, p.bindings_for(a, from_family))
	_save_player(p)
	bindings_changed.emit(player_index)
	glyphs_changed.emit(player_index)


func save_player_settings(player_index: int) -> void:
	_save_player(player(player_index))


# ================================================================== glyphs

## Glyph descriptors for an action on the player's current device family.
## slot >= 0 returns just that binding. Falls back to the other device kind
## so a prompt is never empty. Each entry: see CtlLayout.glyph().
func glyphs(player_index: int, action: StringName, slot := -1) -> Array:
	var a: _Action = _actions.get(action)
	if a == null:
		return []
	var p := player(player_index)
	var family := p.glyph_family()
	if p.devices.is_empty() and p.last_device == null and _last_any_device != null:
		family = _last_any_device.family
	return glyphs_for_family(player_index, action, family, slot)


func glyphs_for_family(player_index: int, action: StringName, family: StringName, slot := -1) -> Array:
	var a: _Action = _actions.get(action)
	if a == null:
		return []
	var p := player(player_index)
	var list: Array = p.bindings_for(a, family)
	if slot >= 0:
		list = [list[slot]] if slot < list.size() else []
	var out := []
	for b in list:
		out.append(_Layout.glyph(b, family, confirm_follows))
	if out.is_empty() and slot < 0:
		var other: StringName = _Layout.FAMILY_XBOX if family == _Layout.FAMILY_KBM else _Layout.FAMILY_KBM
		for b in p.bindings_for(a, other):
			out.append(_Layout.glyph(b, other, confirm_follows))
	if out.is_empty():
		out.append({"text": "Unbound", "style": &"unbound", "icon": &""})
	return out


func glyph_text(player_index: int, action: StringName) -> String:
	return " / ".join(glyphs(player_index, action).map(func(g): return g.text))


# ================================================================== persistence

func _load_cfg() -> void:
	if _cfg_loaded or storage_path == "":
		return
	_cfg_loaded = true
	if FileAccess.file_exists(storage_path):
		_cfg.load(storage_path)


func _load_player(p: _Player) -> void:
	_load_cfg()
	if storage_path == "":
		return
	var key := p.profile_key
	if _cfg.has_section_key("bindings", key):
		var o: Variant = _cfg.get_value("bindings", key)
		if o is Dictionary:
			p.overrides = (o as Dictionary).duplicate(true)
	if _cfg.has_section_key("settings", key):
		var s: Variant = _cfg.get_value("settings", key)
		if s is Dictionary:
			p.import_settings(s)


## Re-read a player's saved data (after changing its profile_key).
func reload_player(player_index: int) -> void:
	var p := player(player_index)
	p.overrides.clear()
	_load_player(p)
	glyphs_changed.emit(player_index)


func _save_player(p: _Player) -> void:
	if storage_path == "":
		return
	_cfg.set_value("bindings", p.profile_key, p.overrides.duplicate(true))
	var s := p.export_settings()
	for st in s.stick_settings.values():
		st.erase("custom")  # Curve resources aren't persisted
	s.trigger_settings.erase("custom")
	_cfg.set_value("settings", p.profile_key, s)
	var dir := storage_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	_cfg.save(storage_path)


# ================================================================== debug

func describe() -> Dictionary:
	var ps := []
	for p in _players:
		ps.append({"index": p.index, "devices": p.devices.map(func(d): return d.describe()),
			"reservations": p.reservations, "glyph_family": p.glyph_family()})
	return {"devices": _devices.values().map(func(d): return d.describe()), "players": ps,
		"focused": _focused, "automation": automation_labels()}
