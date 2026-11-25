extends Control

## godot-controllers demo: press-to-join players, live device family,
## glyph prompts, deadzone visualisation, rebinding and rumble.

const Action := preload("res://addons/controllers/core/ctl_action.gd")
const Layout := preload("res://addons/controllers/core/ctl_layout.gd")
const Glyph := preload("res://addons/controllers/ui/ctl_glyph.gd")
const Features := preload("res://addons/controllers/core/ctl_features.gd")
const StickView := preload("stick_view.gd")

const SHOWN := [&"jump", &"fire", &"rumble", &"menu_accept", &"menu_back", &"pause"]
const REBINDABLE := [&"jump", &"fire", &"rumble"]

var ci: Node
var _panels: Array = []
var _header: Label
var _auto: Label
var _status: Label
var _bot: RefCounted
var _bot_t := 0.0


func _ready() -> void:
	ci = get_node("/root/Controllers")
	_declare()
	# Demo uses press-to-join: start with nobody seated.
	for p in ci.players():
		ci.remove_player(p.index)
	ci.join_mode = ci.JoinMode.PRESS
	ci.join_open = true
	ci.player_joined.connect(func(_p): _rebuild_needed())
	ci.device_assigned.connect(func(_p, _d): _rebuild_needed())
	ci.device_unassigned.connect(func(_p, _d): _rebuild_needed())
	ci.glyphs_changed.connect(func(_i): _rebuild_needed())
	ci.rebind_started.connect(func(i, a): _status.text = "P%d: press a new input for %s (Esc cancels)" % [i + 1, ci.get_action(a).label])
	ci.rebind_finished.connect(func(i, a, b, fam): _status.text = "P%d: %s bound to %s on %s" % [i + 1, ci.get_action(a).label, Layout.glyph(b, fam, ci.confirm_follows).text, Layout.family_display_name(fam)])
	ci.rebind_cancelled.connect(func(i, _a): _status.text = "P%d: rebind cancelled" % [i + 1])
	ci.rebind_conflict.connect(func(i, a, _b, o): _status.text = "P%d: %s conflicts with %s (rejected)" % [i + 1, a, o])
	ci.device_reconnected.connect(func(p, d): _status.text = "P%d: %s reconnected" % [p.index + 1, d.display_name])
	ci.ticked.connect(_on_tick)
	_build()


func _declare() -> void:
	ci.declare_action(&"move", Action.Type.AXIS_2D, &"gameplay", "Move", {
		"kbm": [{"key": KEY_A, "to": "x-"}, {"key": KEY_D, "to": "x+"},
			{"key": KEY_W, "to": "y-"}, {"key": KEY_S, "to": "y+"}],
		"gamepad": [{"pad": &"stick_l"}, {"pad": &"dpad"}]})
	ci.declare_action(&"look", Action.Type.AXIS_2D, &"gameplay", "Look", {
		"kbm": [{"mouse_axis": &"x", "to": "x"}, {"mouse_axis": &"y", "to": "y"}],
		"gamepad": [{"pad": &"stick_r"}]}, {"clamp_output": false})
	ci.declare_action(&"jump", Action.Type.BUTTON, &"gameplay", "Jump", {
		"kbm": [{"key": KEY_SPACE}], "gamepad": [{"pad": &"face_south"}]})
	ci.declare_action(&"fire", Action.Type.BUTTON, &"gameplay", "Fire", {
		"kbm": [{"mouse": MOUSE_BUTTON_LEFT}], "gamepad": [{"pad": &"trigger_r"}]})
	ci.declare_action(&"brake", Action.Type.BUTTON, &"gameplay", "Brake", {
		"kbm": [{"mouse": MOUSE_BUTTON_RIGHT}], "gamepad": [{"pad": &"trigger_l"}]})
	ci.declare_action(&"rumble", Action.Type.BUTTON, &"gameplay", "Rumble", {
		"kbm": [{"key": KEY_R}], "gamepad": [{"pad": &"face_north"}]})
	ci.declare_action(&"menu_accept", Action.Type.BUTTON, &"menu", "Confirm", {
		"kbm": [{"key": KEY_ENTER}], "gamepad": [{"pad": &"confirm"}]})
	ci.declare_action(&"menu_back", Action.Type.BUTTON, &"menu", "Back", {
		"kbm": [{"key": KEY_BACKSPACE}], "gamepad": [{"pad": &"cancel"}]})
	ci.declare_action(&"pause", Action.Type.BUTTON, &"system", "Pause", {
		"kbm": [{"key": KEY_P}], "gamepad": [{"pad": &"start"}]})
	ci.add_conflict_group([&"gameplay", &"system"])


# ------------------------------------------------------------------ UI

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#11141b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 12
	root.offset_right = -16
	root.offset_bottom = -12
	add_child(root)
	_header = Label.new()
	_header.text = "godot-controllers demo — press Start / Confirm (pad) or Enter / Space (keyboard) to join. Up to 4 players."
	root.add_child(_header)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm follows: position"
	confirm_btn.pressed.connect(func():
		ci.confirm_follows = Layout.CONFIRM_BY_LABEL if ci.confirm_follows == Layout.CONFIRM_BY_POSITION else Layout.CONFIRM_BY_POSITION
		confirm_btn.text = "Confirm follows: %s" % ci.confirm_follows)
	bar.add_child(confirm_btn)
	var bot_btn := Button.new()
	bot_btn.text = "Add scripted bot"
	bot_btn.pressed.connect(_toggle_bot.bind(bot_btn))
	bar.add_child(bot_btn)
	var join_btn := Button.new()
	join_btn.text = "Joining: open"
	join_btn.pressed.connect(func():
		ci.join_open = not ci.join_open
		join_btn.text = "Joining: %s" % ("open" if ci.join_open else "closed"))
	bar.add_child(join_btn)
	_auto = Label.new()
	_auto.add_theme_color_override("font_color", Color("#ff7a7a"))
	bar.add_child(_auto)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("#ffcf5a"))
	root.add_child(_status)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	root.add_child(grid)
	for i in 4:
		var panel := _make_panel(i)
		grid.add_child(panel.root)
		_panels.append(panel)
	_rebuild_needed()


func _make_panel(i: int) -> Dictionary:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1a1f2a")
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var dev_icon := Glyph.new()
	dev_icon.glyph_size = 30
	head.add_child(dev_icon)
	var title := Label.new()
	title.text = "P%d — waiting to join" % (i + 1)
	head.add_child(title)
	var devices := Label.new()
	devices.add_theme_font_size_override("font_size", 12)
	devices.add_theme_color_override("font_color", Color("#9aa3b5"))
	v.add_child(devices)
	var prompts := HFlowContainer.new()
	v.add_child(prompts)
	var body := HBoxContainer.new()
	v.add_child(body)
	var sl := StickView.new()
	sl.title = "L"
	body.add_child(sl)
	var sr := StickView.new()
	sr.title = "R"
	body.add_child(sr)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var trig := Label.new()
	trig.add_theme_font_size_override("font_size", 12)
	right.add_child(trig)
	var states := Label.new()
	states.add_theme_font_size_override("font_size", 12)
	right.add_child(states)
	var controls := HFlowContainer.new()
	v.add_child(controls)
	for a in REBINDABLE:
		var b := Button.new()
		b.text = "Rebind %s" % a
		b.pressed.connect(func(): ci.begin_rebind(i, a, 0, {}))
		controls.add_child(b)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(func(): ci.reset_bindings(i))
	controls.add_child(reset)
	var mode := OptionButton.new()
	for m in ["radial", "axial", "hybrid"]:
		mode.add_item(m)
	mode.item_selected.connect(func(idx): _set_stick(i, "mode", StringName(mode.get_item_text(idx))))
	controls.add_child(mode)
	var curve := OptionButton.new()
	for m in ["linear", "power"]:
		curve.add_item(m)
	curve.item_selected.connect(func(idx): _set_stick(i, "curve", StringName(curve.get_item_text(idx))))
	controls.add_child(curve)
	var inner := _slider("inner", 0.0, 0.5, 0.15, func(x): _set_stick(i, "inner", x))
	controls.add_child(inner)
	var outer := _slider("outer", 0.5, 1.0, 0.95, func(x): _set_stick(i, "outer", x))
	controls.add_child(outer)
	return {"root": pc, "title": title, "icon": dev_icon, "devices": devices, "prompts": prompts,
		"sl": sl, "sr": sr, "trig": trig, "states": states, "counts": {}}


func _slider(label: String, lo: float, hi: float, val: float, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 12)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = val
	s.custom_minimum_size = Vector2(90, 0)
	s.value_changed.connect(cb)
	h.add_child(s)
	return h


func _set_stick(i: int, key: String, value: Variant) -> void:
	var p = ci.player(i)
	for st in ["stick_l", "stick_r"]:
		p.stick_settings[st][key] = value
	ci.save_player_settings(i)


var _dirty := true


func _rebuild_needed() -> void:
	_dirty = true


func _refresh_static() -> void:
	_dirty = false
	for i in _panels.size():
		var panel: Dictionary = _panels[i]
		var p = ci.player(i)
		var joined: bool = p.is_present()
		var fam: StringName = p.glyph_family()
		panel.title.text = "P%d — %s" % [i + 1, Layout.family_display_name(fam) if joined else "waiting to join"]
		panel.icon.icon = &"device_keyboard" if fam == Layout.FAMILY_KBM else &"device_gamepad"
		var lines := []
		for d in p.devices:
			var extra := ""
			if d.is_virtual():
				extra = "  [AUTOMATED: %s]" % d.label
			elif d.kind == &"pad":
				extra = "  rumble:%s motion:%s light:%s" % [
					"yes" if d.can_rumble() else "no",
					"yes" if Features.supports(d, Features.MOTION) else "no",
					"yes" if Features.supports(d, Features.LIGHT) else "no"]
			lines.append("%s  [%s, id %d]%s" % [d.display_name, d.family, d.id, extra])
		for r in p.reservations:
			lines.append("(disconnected, waiting: %s)" % r.name)
		panel.devices.text = "\n".join(lines) if not lines.is_empty() else "—"
		for c in panel.prompts.get_children():
			c.queue_free()
		if joined:
			for a in SHOWN:
				var box := HBoxContainer.new()
				for g in ci.glyphs(i, a):
					var gl := Glyph.new()
					gl.glyph_size = 26
					gl.set_glyph(g)
					box.add_child(gl)
				var l := Label.new()
				l.text = String(ci.get_action(a).label) + "   "
				box.add_child(l)
				panel.prompts.add_child(box)


func _toggle_bot(btn: Button) -> void:
	if _bot != null:
		ci.remove_virtual_device(_bot)
		_bot = null
		btn.text = "Add scripted bot"
		return
	_bot = ci.add_virtual_device(Layout.FAMILY_PLAYSTATION, "demo bot (scripted)")
	for i in ci.max_players:
		if not ci.player(i).is_present():
			ci.assign_device(i, _bot)
			break
	btn.text = "Remove scripted bot"


func _on_tick(dt: float) -> void:
	if _bot != null:
		_bot_t += dt
		_bot.set_stick(&"stick_l", Vector2(cos(_bot_t * 2.0), sin(_bot_t * 2.0)) * (0.5 + 0.5 * absf(sin(_bot_t * 0.7))))
		if fmod(_bot_t, 1.5) < dt:
			_bot.tap(&"face_south")
		_bot.set_axis(&"trigger_r", 0.5 + 0.5 * sin(_bot_t * 1.3))
	for i in _panels.size():
		var p = ci.player(i)
		if p.is_just_pressed(&"rumble"):
			p.rumble(0.4, 0.9, 0.25)
			_status.text = "P%d: rumble" % (i + 1)
		var panel: Dictionary = _panels[i]
		for a in [&"jump", &"fire", &"brake", &"rumble", &"menu_accept", &"menu_back", &"pause"]:
			if p.is_just_pressed(a):
				panel.counts[a] = int(panel.counts.get(a, 0)) + 1
			if p.is_double_tapped(a):
				panel.counts[String(a) + "_x2"] = int(panel.counts.get(String(a) + "_x2", 0)) + 1


func _process(_delta: float) -> void:
	if _dirty:
		_refresh_static()
	var labels: Array = ci.automation_labels()
	_auto.text = ("AUTOMATED INPUT: " + ", ".join(labels)) if not labels.is_empty() else ""
	for i in _panels.size():
		var panel: Dictionary = _panels[i]
		var p = ci.player(i)
		var pad: RefCounted = null
		for d in p.devices:
			if d.kind == &"pad":
				pad = d
		for key in ["sl", "sr"]:
			var view = panel[key]
			var stick := &"stick_l" if key == "sl" else &"stick_r"
			view.settings = p.stick_settings.get(String(stick), {}).duplicate()
			if pad != null:
				view.raw = pad.stick_raw(stick)
				view.processed = p.processed_stick(pad, stick)
			else:
				view.raw = Vector2.ZERO
				view.processed = Vector2.ZERO
			view.queue_redraw()
		var lt: float = pad.axis(&"trigger_l") if pad != null else 0.0
		var rt: float = pad.axis(&"trigger_r") if pad != null else 0.0
		panel.trig.text = "LT raw %.2f  out %.2f\nRT raw %.2f  out %.2f\nmove %s\nlook %s" % [
			lt, p.get_value(&"brake"), rt, p.get_value(&"fire"),
			_v(p.get_vector(&"move")), _v(p.get_vector(&"look"))]
		var lines := []
		for a in [&"jump", &"fire", &"brake", &"rumble", &"menu_accept", &"menu_back", &"pause"]:
			lines.append("%-12s %s  presses %d  double %d  held %.2fs" % [a,
				"■" if p.is_pressed(a) else "□", int(panel.counts.get(a, 0)),
				int(panel.counts.get(String(a) + "_x2", 0)), p.held_time(a)])
		panel.states.text = "\n".join(lines)


func _v(v: Vector2) -> String:
	return "(%.2f, %.2f)" % [v.x, v.y]
