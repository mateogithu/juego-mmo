class_name DungeonEntrance
extends Area3D

## Physical gothic stone dungeon entrance (and underground exit portal).
## Players press E / Y-Triangle to teleport into the explorable underground dungeon chamber.

var dungeon_id: String = ""
var dungeon_name: String = "Mazmorra"
var theme: String = "chaos"
var is_exit_portal: bool = false

@onready var visual_root: Node3D = $VisualRoot
@onready var label_3d: Label3D = $Label3D
var _vortex: Node3D = null


func setup(p_id: String, p_name: String, p_theme: String, world_pos: Vector3, p_is_exit: bool = false) -> void:
	dungeon_id = p_id
	dungeon_name = p_name
	theme = p_theme
	is_exit_portal = p_is_exit
	name = "DungeonPortal_%s_%s" % [p_id, "exit" if p_is_exit else "enter"]
	global_position = GameConfig.world_to_local(world_pos)
	if is_node_ready():
		_refresh_visual()


func _ready() -> void:
	add_to_group("dungeon_portals")
	collision_layer = GameConfig.LAYER_INTERACTABLES
	collision_mask = 0
	_refresh_visual()


func _refresh_visual() -> void:
	_vortex = ProceduralMeshFactory.build_dungeon_portal_visual(visual_root, theme)
	if label_3d != null:
		if is_exit_portal:
			label_3d.text = "[E / Y] Salir de %s (Volver al Mundo)" % dungeon_name
		else:
			label_3d.text = "[E / Y] Mazmorra: %s" % dungeon_name


func _process(delta: float) -> void:
	if _vortex != null:
		_vortex.rotation.z += delta * 1.4
