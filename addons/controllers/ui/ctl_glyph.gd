class_name CtlGlyph
extends Control

## A procedurally drawn input glyph. The library ships no image files and
## no manufacturer artwork or logos: every icon is built from draw_*
## primitives here, so it is covered by the library's MIT licence.
##
## Set `glyph` to a descriptor from CtlLayout.glyph() / Controllers.glyphs(),
## or set `icon` and `text` directly.
##
## Icons: xbox_a/b/x/y, ps_cross/circle/square/triangle, nintendo_button,
## pad_button, face_south/east/west/north, dpad, dpad_up/down/left/right,
## stick_l, stick_r, trigger_l, trigger_r, bumper, menu, view, plus, minus,
## home, touchpad, paddle, mouse, mouse_left/right/middle,
## mouse_wheel_up/down, device_gamepad, device_keyboard. An empty icon
## draws a keycap with `text`.

const FACE_COLORS := {
	&"xbox_a": Color("#4caf50"), &"xbox_b": Color("#e04f4f"),
	&"xbox_x": Color("#3f7fe0"), &"xbox_y": Color("#e8bd3a"),
	&"ps_cross": Color("#6aa8f0"), &"ps_circle": Color("#ef6b6b"),
	&"ps_square": Color("#e294d2"), &"ps_triangle": Color("#4fc48d"),
}
const LETTERS := {&"xbox_a": "A", &"xbox_b": "B", &"xbox_x": "X", &"xbox_y": "Y"}
const BODY := Color("#2b3140")
const EDGE := Color("#69738a")
const INK := Color("#eef1f7")
const HIGHLIGHT := Color("#ffcf5a")

@export var icon: StringName = &"":
	set(v):
		icon = v
		_refresh()
@export var text := "":
	set(v):
		text = v
		_refresh()
@export var glyph_size := 28.0:
	set(v):
		glyph_size = v
		_refresh()
## Also draw `text` to the right of the icon when the icon doesn't carry it.
@export var show_label := true:
	set(v):
		show_label = v
		_refresh()

var _icon_text := ""
var _icon_only := false
## Theme texture (e.g. Kenney Input Prompts); drawn instead of the
## procedural icon when set. The texture carries its own label.
var texture: Texture2D = null:
	set(v):
		texture = v
		_refresh()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


## Apply a glyph descriptor dictionary.
func set_glyph(g: Dictionary) -> void:
	_icon_text = str(g.get("icon_text", ""))
	_icon_only = bool(g.get("icon_only", false))
	var tp := str(g.get("texture", ""))
	texture = load(tp) if tp != "" and ResourceLoader.exists(tp) else null
	icon = StringName(g.get("icon", &""))
	text = str(g.get("text", ""))


func _font() -> Font:
	return get_theme_default_font() if is_inside_tree() else ThemeDB.fallback_font


func _label_visible() -> bool:
	return show_label and text != "" and icon != &"" and not _icon_only and texture == null


func _refresh() -> void:
	var w := glyph_size
	if texture != null:
		var ts := texture.get_size()
		w = glyph_size * (ts.x / ts.y if ts.y > 0 else 1.0)
	elif icon == &"":
		w = maxf(glyph_size, _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(glyph_size * 0.5)).x + glyph_size * 0.5)
	elif _label_visible():
		w += 4.0 + _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(glyph_size * 0.5)).x
	custom_minimum_size = Vector2(w, glyph_size)
	tooltip_text = text
	queue_redraw()


func _draw() -> void:
	var s := glyph_size
	var c := Vector2(s, s) * 0.5
	var r := s * 0.45
	if texture != null:
		var ts := texture.get_size()
		var w := s * (ts.x / ts.y if ts.y > 0 else 1.0)
		draw_texture_rect(texture, Rect2(0, 0, w, s), false)
		return
	match icon:
		&"":
			_keycap(s)
		&"xbox_a", &"xbox_b", &"xbox_x", &"xbox_y":
			draw_circle(c, r, FACE_COLORS[icon])
			_center_text(c, LETTERS[icon], s * 0.55, Color.WHITE)
		&"ps_cross", &"ps_circle", &"ps_square", &"ps_triangle":
			draw_circle(c, r, BODY)
			_ps_symbol(c, r * 0.52, FACE_COLORS[icon], s)
		&"nintendo_button", &"pad_button":
			draw_circle(c, r, BODY)
			draw_arc(c, r, 0, TAU, 32, EDGE, maxf(1.0, s * 0.06), true)
			_center_text(c, _icon_text if _icon_text != "" else "", s * 0.52, INK)
		&"face_south", &"face_east", &"face_west", &"face_north":
			_face_diamond(c, r)
		&"dpad", &"dpad_up", &"dpad_down", &"dpad_left", &"dpad_right":
			_dpad(c, s)
		&"stick_l", &"stick_r", &"stick":
			draw_circle(c, r, BODY)
			draw_arc(c, r, 0, TAU, 32, EDGE, maxf(1.0, s * 0.05), true)
			draw_circle(c, r * 0.58, Color("#454d60"))
			_center_text(c, "L" if icon == &"stick_l" else ("R" if icon == &"stick_r" else ""), s * 0.42, INK)
		&"trigger_l", &"trigger_r":
			var pts := PackedVector2Array([
				Vector2(s * 0.22, s * 0.92), Vector2(s * 0.22, s * 0.32),
				Vector2(s * 0.40, s * 0.10), Vector2(s * 0.78, s * 0.10),
				Vector2(s * 0.78, s * 0.92)])
			if icon == &"trigger_l":
				for i in pts.size():
					pts[i].x = s - pts[i].x
			draw_colored_polygon(pts, BODY)
			pts.append(pts[0])
			draw_polyline(pts, EDGE, maxf(1.0, s * 0.05), true)
			_center_text(c + Vector2(0, s * 0.08), _icon_text, s * 0.36, INK)
		&"bumper":
			var rect := Rect2(s * 0.04, s * 0.26, s * 0.92, s * 0.48)
			_round_rect(rect, BODY, s * 0.22)
			_round_rect_outline(rect, EDGE, s * 0.22, maxf(1.0, s * 0.05))
			_center_text(c, _icon_text, s * 0.34, INK)
		&"menu":
			draw_circle(c, r, BODY)
			for i in 3:
				var y := c.y + (i - 1) * s * 0.14
				draw_line(Vector2(c.x - s * 0.18, y), Vector2(c.x + s * 0.18, y), INK, maxf(1.0, s * 0.07))
		&"view":
			draw_circle(c, r, BODY)
			var a := Rect2(c + Vector2(-s * 0.20, -s * 0.16), Vector2(s * 0.24, s * 0.20))
			draw_rect(a, INK, false, maxf(1.0, s * 0.05))
			draw_rect(Rect2(a.position + Vector2(s * 0.12, s * 0.10), a.size), INK, false, maxf(1.0, s * 0.05))
		&"plus":
			draw_circle(c, r, BODY)
			draw_line(c - Vector2(s * 0.2, 0), c + Vector2(s * 0.2, 0), INK, maxf(1.0, s * 0.08))
			draw_line(c - Vector2(0, s * 0.2), c + Vector2(0, s * 0.2), INK, maxf(1.0, s * 0.08))
		&"minus":
			draw_circle(c, r, BODY)
			draw_line(c - Vector2(s * 0.2, 0), c + Vector2(s * 0.2, 0), INK, maxf(1.0, s * 0.08))
		&"home":
			draw_circle(c, r, BODY)
			var h := PackedVector2Array([
				c + Vector2(-s * 0.2, s * 0.2), c + Vector2(-s * 0.2, -s * 0.02),
				c + Vector2(0, -s * 0.22), c + Vector2(s * 0.2, -s * 0.02),
				c + Vector2(s * 0.2, s * 0.2), c + Vector2(-s * 0.2, s * 0.2)])
			draw_polyline(h, INK, maxf(1.0, s * 0.06), true)
		&"touchpad":
			var tr := Rect2(s * 0.06, s * 0.22, s * 0.88, s * 0.56)
			_round_rect(tr, BODY, s * 0.12)
			_round_rect_outline(tr, EDGE, s * 0.12, maxf(1.0, s * 0.05))
			draw_circle(c, s * 0.07, INK)
		&"paddle":
			var pr := Rect2(s * 0.30, s * 0.08, s * 0.40, s * 0.84)
			_round_rect(pr, BODY, s * 0.18)
			_round_rect_outline(pr, EDGE, s * 0.18, maxf(1.0, s * 0.05))
		&"mouse", &"mouse_left", &"mouse_right", &"mouse_middle", &"mouse_wheel_up", &"mouse_wheel_down":
			_mouse(s)
		&"device_gamepad":
			_device_gamepad(s)
		&"device_keyboard":
			_device_keyboard(s)
		_:
			draw_circle(c, r, BODY)
			_center_text(c, "?", s * 0.5, INK)
	if _label_visible():
		var f := _font()
		var fs := int(s * 0.5)
		var y := (s + f.get_ascent(fs) - f.get_descent(fs)) * 0.5
		draw_string(f, Vector2(s + 4.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)


func _center_text(c: Vector2, t: String, px: float, col: Color) -> void:
	if t == "":
		return
	var f := _font()
	var fs := maxi(6, int(px))
	var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := Vector2(c.x - sz.x * 0.5, c.y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5)
	draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _keycap(s: float) -> void:
	var w := size.x if size.x > 0 else custom_minimum_size.x
	var rect := Rect2(1, 1, w - 2, s - 2)
	_round_rect(rect, Color("#e6e9f0"), s * 0.18)
	_round_rect(Rect2(rect.position + Vector2(0, rect.size.y * 0.82), Vector2(rect.size.x, rect.size.y * 0.18)), Color("#a9afbd"), s * 0.1)
	_center_text(Vector2(w * 0.5, s * 0.46), text, s * 0.48, Color("#1d2230"))


func _round_rect(rect: Rect2, col: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)


func _round_rect_outline(rect: Rect2, col: Color, radius: float, width: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = col
	sb.set_border_width_all(int(maxf(1.0, width)))
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, rect)


func _ps_symbol(c: Vector2, k: float, col: Color, s: float) -> void:
	var w := maxf(1.5, s * 0.075)
	match icon:
		&"ps_cross":
			draw_line(c + Vector2(-k, -k), c + Vector2(k, k), col, w, true)
			draw_line(c + Vector2(-k, k), c + Vector2(k, -k), col, w, true)
		&"ps_circle":
			draw_arc(c, k, 0, TAU, 28, col, w, true)
		&"ps_square":
			draw_rect(Rect2(c - Vector2(k, k) * 0.9, Vector2(k, k) * 1.8), col, false, w)
		&"ps_triangle":
			var t := PackedVector2Array([c + Vector2(0, -k), c + Vector2(k, k * 0.75),
				c + Vector2(-k, k * 0.75), c + Vector2(0, -k)])
			draw_polyline(t, col, w, true)


## Four dots in a diamond with the bound position filled: an unbranded,
## position-explicit face-button glyph for generic pads.
func _face_diamond(c: Vector2, r: float) -> void:
	draw_circle(c, r, BODY)
	var d := r * 0.5
	var spots := {&"face_north": Vector2(0, -d), &"face_south": Vector2(0, d),
		&"face_west": Vector2(-d, 0), &"face_east": Vector2(d, 0)}
	for k in spots:
		if k == icon:
			draw_circle(c + spots[k], r * 0.24, HIGHLIGHT)
		else:
			draw_arc(c + spots[k], r * 0.2, 0, TAU, 16, EDGE, maxf(1.0, r * 0.08), true)


func _dpad(c: Vector2, s: float) -> void:
	var arm := s * 0.30
	var t := s * 0.15
	draw_rect(Rect2(c.x - t, c.y - arm - t, t * 2, (arm + t) * 2), BODY)
	draw_rect(Rect2(c.x - arm - t, c.y - t, (arm + t) * 2, t * 2), BODY)
	var dir := Vector2.ZERO
	match icon:
		&"dpad_up": dir = Vector2.UP
		&"dpad_down": dir = Vector2.DOWN
		&"dpad_left": dir = Vector2.LEFT
		&"dpad_right": dir = Vector2.RIGHT
	if dir != Vector2.ZERO:
		var p := c + dir * arm
		draw_rect(Rect2(p - Vector2(t, t) * 0.85, Vector2(t, t) * 1.7), HIGHLIGHT)


func _mouse(s: float) -> void:
	var body := Rect2(s * 0.22, s * 0.06, s * 0.56, s * 0.88)
	_round_rect(body, BODY, s * 0.26)
	_round_rect_outline(body, EDGE, s * 0.26, maxf(1.0, s * 0.05))
	var mid := s * 0.5
	draw_line(Vector2(mid, s * 0.08), Vector2(mid, s * 0.42), EDGE, maxf(1.0, s * 0.04))
	draw_line(Vector2(s * 0.24, s * 0.42), Vector2(s * 0.76, s * 0.42), EDGE, maxf(1.0, s * 0.04))
	match icon:
		&"mouse_left":
			draw_rect(Rect2(s * 0.27, s * 0.12, s * 0.21, s * 0.28), HIGHLIGHT)
		&"mouse_right":
			draw_rect(Rect2(s * 0.52, s * 0.12, s * 0.21, s * 0.28), HIGHLIGHT)
		&"mouse_middle", &"mouse_wheel_up", &"mouse_wheel_down":
			draw_rect(Rect2(s * 0.45, s * 0.14, s * 0.10, s * 0.22), HIGHLIGHT)
	if icon == &"mouse_wheel_up" or icon == &"mouse_wheel_down":
		var sg := -1.0 if icon == &"mouse_wheel_up" else 1.0
		var tip := Vector2(mid, s * 0.66 + sg * s * 0.12)
		draw_colored_polygon(PackedVector2Array([tip, Vector2(mid - s * 0.09, s * 0.66),
			Vector2(mid + s * 0.09, s * 0.66)]), INK)


func _device_gamepad(s: float) -> void:
	var body := Rect2(s * 0.04, s * 0.24, s * 0.92, s * 0.52)
	_round_rect(body, BODY, s * 0.24)
	_round_rect_outline(body, EDGE, s * 0.24, maxf(1.0, s * 0.04))
	var l := Vector2(s * 0.28, s * 0.5)
	draw_line(l - Vector2(s * 0.1, 0), l + Vector2(s * 0.1, 0), INK, maxf(1.0, s * 0.06))
	draw_line(l - Vector2(0, s * 0.1), l + Vector2(0, s * 0.1), INK, maxf(1.0, s * 0.06))
	draw_circle(Vector2(s * 0.70, s * 0.43), s * 0.045, INK)
	draw_circle(Vector2(s * 0.79, s * 0.53), s * 0.045, INK)


func _device_keyboard(s: float) -> void:
	var body := Rect2(s * 0.04, s * 0.26, s * 0.92, s * 0.48)
	_round_rect(body, BODY, s * 0.08)
	for row in 2:
		for col in 5:
			draw_rect(Rect2(s * (0.1 + col * 0.165), s * (0.33 + row * 0.15), s * 0.11, s * 0.09), INK)
	draw_rect(Rect2(s * 0.27, s * 0.62, s * 0.46, s * 0.06), INK)
