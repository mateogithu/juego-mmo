class_name WorldStation
extends StaticBody3D

## Physical interactive medieval settlement station (Blacksmith Forge, Alchemy Bench, Shop Stall).

var station_type: String = "forge"
var station_title: String = "Yunque y Forja"

@onready var visual_root: Node3D = $VisualRoot
@onready var label_3d: Label3D = $Label3D


func setup(p_type: String, p_title: String, world_pos: Vector3) -> void:
	station_type = p_type
	station_title = p_title
	name = "Station_%s" % p_type
	global_position = GameConfig.world_to_local(world_pos)
	if is_node_ready():
		_refresh_visual()


func _ready() -> void:
	add_to_group("world_stations")
	collision_layer = GameConfig.LAYER_INTERACTABLES | GameConfig.LAYER_TERRAIN
	collision_mask = 0
	_refresh_visual()


func _refresh_visual() -> void:
	ProceduralMeshFactory.build_station_visual(visual_root, station_type)
	if label_3d != null:
		label_3d.text = "[E / Y] %s" % station_title
