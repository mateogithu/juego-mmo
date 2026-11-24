class_name StorageChest
extends StaticBody3D

## Persistent lockable House Storage Chest (60 secure slots stored in server_database.json).
## Players can store extra sets, materials, and their Dragon Mount Stone safely inside their house.

var building_id: int = -1
var owner_name: String = ""
var used_slots: int = 0

@onready var visual_root: Node3D = $VisualRoot
@onready var label_3d: Label3D = $Label3D


func setup(p_bid: int, p_owner: String, world_pos: Vector3, rot_y: float) -> void:
	building_id = p_bid
	owner_name = p_owner
	name = "StorageChest_%d" % p_bid
	global_position = GameConfig.world_to_local(world_pos)
	rotation.y = rot_y
	if is_node_ready():
		_refresh_visual()


func _ready() -> void:
	add_to_group("storage_chests")
	collision_layer = GameConfig.LAYER_BUILDINGS | GameConfig.LAYER_INTERACTABLES
	collision_mask = 0
	_refresh_visual()


func _refresh_visual() -> void:
	ProceduralMeshFactory.build_loot_chest_visual(visual_root)
	if label_3d != null:
		label_3d.text = "[E / Y] Cajón de Guardado (%s)\nCapacidad: %d / %d espacios" % [owner_name, used_slots, GameConfig.STORAGE_CHEST_SLOTS]
