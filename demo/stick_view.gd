extends Control

## Deadzone visualiser for one stick: outer square = raw range, dark disc
## = inner deadzone, ring = outer deadzone, grey dot = raw sample, yellow
## dot = processed output (what the game reads).

var raw := Vector2.ZERO
var processed := Vector2.ZERO
var settings: Dictionary = {}
var title := ""
var trigger_raw := -1.0
var trigger_out := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(120, 140)


func _draw() -> void:
	var s := minf(size.x, size.y - 20.0)
	var c := Vector2(size.x * 0.5, s * 0.5)
	var r := s * 0.46
	var mode := StringName(settings.get("mode", &"radial"))
	var inner := float(settings.get("inner", 0.15))
	var outer := float(settings.get("outer", 0.95))
	draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2), Color("#1b1f29"))
	draw_arc(c, r, 0, TAU, 48, Color("#3a4252"), 1.0, true)
	if mode == &"axial":
		draw_rect(Rect2(c.x - inner * r, c.y - r, inner * r * 2, r * 2), Color(0.8, 0.3, 0.3, 0.25))
		draw_rect(Rect2(c.x - r, c.y - inner * r, r * 2, inner * r * 2), Color(0.8, 0.3, 0.3, 0.25))
	else:
		draw_circle(c, inner * r, Color(0.8, 0.3, 0.3, 0.35))
	draw_arc(c, outer * r, 0, TAU, 48, Color(0.4, 0.8, 0.5, 0.7), 1.5, true)
	draw_circle(c + raw * r, 4.0, Color("#9aa3b5"))
	draw_circle(c + processed * r, 5.0, Color("#ffcf5a"))
	var f := get_theme_default_font()
	draw_string(f, Vector2(4, s + 14), "%s  %.2f,%.2f" % [title, processed.x, processed.y],
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 12, Color("#c8cede"))
