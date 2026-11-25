extends SceneTree

## Compile every script under addons/ and demo/ (headless smoke check).

func _init() -> void:
	var bad := 0
	for dir in ["res://addons/controllers/core", "res://addons/controllers/ui", "res://demo"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				var s: Script = load(dir + "/" + f)
				if s == null or not s.can_instantiate():
					print("FAIL ", dir, "/", f)
					bad += 1
	print("compile check: %d failing" % bad)
	quit(1 if bad else 0)
