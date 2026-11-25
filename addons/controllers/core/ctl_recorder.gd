class_name CtlRecorder
extends RefCounted

## Records a device's raw canonical state once per input tick (changes
## only) and plays it back through a CtlVirtualDevice, so a recorded
## session drives the exact same pipeline as the original hardware.
##
##   var rec := CtlRecorder.new(Controllers, Controllers.player(0).devices[0], "intro run")
##   rec.start()  ... rec.stop(); rec.save_file("user://intro.json")
##   var bot := Controllers.add_virtual_device(&"xbox", "replay: intro run")
##   bot.play(CtlRecorder.load_file("user://intro.json").frames)
##
## Frame format: {"t": tick offset, "state": device state dict}. Vector2
## values (mouse motion) are stored as [x, y] in JSON.

var label := ""
var family: StringName = &""
var frames: Array = []
var recording := false

var _input: Node
var _device: RefCounted
var _tick := 0
var _last: Dictionary = {}


func _init(input: Node = null, device: RefCounted = null, p_label := "") -> void:
	_input = input
	_device = device
	label = p_label
	if device != null:
		family = device.family


func start() -> void:
	frames.clear()
	_tick = 0
	_last = {}
	recording = true
	if not _input.ticked.is_connected(_on_ticked):
		_input.ticked.connect(_on_ticked)


func stop() -> void:
	recording = false
	if _input != null and _input.ticked.is_connected(_on_ticked):
		_input.ticked.disconnect(_on_ticked)
	# Close with a neutral frame so playback releases everything.
	frames.append({"t": _tick + 1, "state": {}})


func _on_ticked(_dt: float) -> void:
	if not recording:
		return
	var s: Dictionary = _device.state
	if s != _last or s.has("mm") or s.has("w"):
		frames.append({"t": _tick, "state": s.duplicate()})
		_last = s.duplicate()
	_tick += 1


func to_dict() -> Dictionary:
	var out := []
	for f in frames:
		var st := {}
		for k in f.state:
			var v: Variant = f.state[k]
			st[k] = [v.x, v.y] if v is Vector2 else v
		out.append({"t": f.t, "state": st})
	return {"format": "godot-controllers.recording/1", "label": label,
		"family": String(family), "frames": out}


func save_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


## Returns {label, family, frames} with Vector2 restored, or {} on error.
static func from_dict(d: Dictionary) -> Dictionary:
	var frames := []
	for f in d.get("frames", []):
		var st := {}
		for k in f.state:
			var v: Variant = f.state[k]
			if v is Array and v.size() == 2:
				v = Vector2(v[0], v[1])
			elif v is float and (String(k).begins_with("b:") or String(k).begins_with("k:") or String(k).begins_with("m:")):
				v = true
			st[k] = v
		frames.append({"t": int(f.t), "state": st})
	return {"label": str(d.get("label", "")), "family": StringName(d.get("family", "xbox")),
		"frames": frames}


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(d) if d is Dictionary else {}
