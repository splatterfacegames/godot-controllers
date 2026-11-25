@tool
extends EditorPlugin

const AUTOLOAD := "Controllers"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD, "res://addons/controllers/core/ctl_input.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD)
