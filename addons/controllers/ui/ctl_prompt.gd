@tool
class_name CtlPrompt
extends HBoxContainer

## Shows the glyph(s) for an action on a player's current device and
## updates live when that player switches device family or rebinds.
##
## Finds the manager at /root/Controllers unless `input` is set.

@export var action: StringName = &"":
	set(v):
		action = v
		refresh()
@export var player_index := 0:
	set(v):
		player_index = v
		refresh()
@export var glyph_size := 28.0
## Show only the first binding.
@export var primary_only := true
## Optional text after the glyphs (e.g. "Jump").
@export var caption := "":
	set(v):
		caption = v
		refresh()

const _Glyph := preload("ctl_glyph.gd")

var input: Node


func _ready() -> void:
	if input == null and not Engine.is_editor_hint():
		input = get_node_or_null("/root/Controllers")
	if input != null and not input.glyphs_changed.is_connected(_on_glyphs_changed):
		input.glyphs_changed.connect(_on_glyphs_changed)
	refresh()


func _on_glyphs_changed(p: int) -> void:
	if p == player_index:
		refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		c.queue_free()
	var gs: Array = []
	if input != null and action != &"":
		gs = input.glyphs(player_index, action)
	if primary_only and gs.size() > 1:
		gs = [gs[0]]
	for g in gs:
		var gl := _Glyph.new()
		gl.glyph_size = glyph_size
		gl.set_glyph(g)
		add_child(gl)
	if caption != "":
		var l := Label.new()
		l.text = caption
		add_child(l)
