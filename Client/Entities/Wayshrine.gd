class_name Wayshrine
extends Area3D

## Discoverable Runic Wayshrine for instant fast travel across the 5 Regions & Dragon Valley.

var shrine_id: String = ""
var shrine_name: String = "Ermita Rúnica"
var region_name: String = ""
var world_pos: Vector3 = Vector3.ZERO

@onready var visual_root: Node3D = $VisualRoot
@onready var label_3d: Label3D = $Label3D
var _sigil: Node3D = null


func setup(p_id: String, p_name: String, p_region: String, p_world_pos: Vector3) -> void:
	shrine_id = p_id
	shrine_name = p_name
	region_name = p_region
	world_pos = p_world_pos
	name = "Wayshrine_%s" % p_id
	global_position = GameConfig.world_to_local(p_world_pos)
	if is_node_ready():
		_refresh_visual()


func _ready() -> void:
	add_to_group("wayshrines")
	collision_layer = GameConfig.LAYER_INTERACTABLES
	collision_mask = 0
	_refresh_visual()


func _refresh_visual() -> void:
	var parts: Dictionary = ProceduralMeshFactory.build_structure_visual(visual_root, "altar_order", false, true)
	_sigil = parts.get("sigil_node", null) as Node3D
	if label_3d != null:
		label_3d.text = "[E / Y] %s\n(%s — Mapa: M)" % [shrine_name, region_name]


func _process(delta: float) -> void:
	if _sigil != null:
		_sigil.rotation.y += delta * 1.8
