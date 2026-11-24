class_name ResourceNode
extends StaticBody3D

## Infinite-world gatherable resource node (Wood tree, Stone boulder, Arcane Ore vein).
## Deterministically identified by resource_key ("chunk_x,chunk_z:slot") from world_seed.

var resource_key: String = ""
var resource_type: String = "wood"
var world_pos: Vector3 = Vector3.ZERO
var remaining_charges: int = 5
var max_charges: int = 5
var is_depleted: bool = false

@onready var visual_root: Node3D = $VisualRoot
@onready var label_3d: Label3D = $Label3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func setup(p_key: String, p_type: String, p_world_pos: Vector3) -> void:
	resource_key = p_key
	resource_type = p_type
	world_pos = p_world_pos
	name = "Resource_%s" % p_key.replace(",", "_").replace(":", "_")
	global_position = GameConfig.world_to_local(p_world_pos)
	if is_node_ready():
		_refresh_visual()


func _ready() -> void:
	add_to_group("resource_nodes")
	collision_layer = GameConfig.LAYER_INTERACTABLES | GameConfig.LAYER_TERRAIN
	collision_mask = 0
	_refresh_visual()


func _refresh_visual() -> void:
	ProceduralMeshFactory.build_resource_visual(visual_root, resource_type)
	var item_def: Dictionary = GameConfig.ITEMS.get(resource_type, {}) as Dictionary
	var display_name: String = str(item_def.get("name", resource_type))
	if label_3d != null:
		label_3d.text = "[E / Y] %s (%d/%d)" % [display_name, remaining_charges, max_charges]


func set_state(charges: int, depleted: bool) -> void:
	remaining_charges = charges
	is_depleted = depleted
	visible = not depleted
	if collision_shape != null:
		collision_shape.disabled = depleted
	var item_def: Dictionary = GameConfig.ITEMS.get(resource_type, {}) as Dictionary
	var display_name: String = str(item_def.get("name", resource_type))
	if label_3d != null:
		label_3d.text = "[E / Y] %s (%d/%d)" % [display_name, remaining_charges, max_charges]
