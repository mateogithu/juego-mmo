class_name IntroLore
extends Node

## Delegates legacy IntroLore ("Crónicas del Mundo") directly to the live 3D
## IntroCinematic.tscn so no opaque solid blue panel ever obscures the 3D valley.

static var enter_world_after: bool = false


func _ready() -> void:
	IntroCinematic.enter_world_after = enter_world_after
	enter_world_after = false
	get_tree().change_scene_to_file.call_deferred("res://Client/UI/IntroCinematic.tscn")
