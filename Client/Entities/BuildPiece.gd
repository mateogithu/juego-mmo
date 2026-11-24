class_name BuildPiece
extends StaticBody3D

## Placed player-built medieval structure (Wall, Gate, Watchtower, Order/Chaos Altar, Trade Post).
## Has real siege HP, destructible via magic & dragon fire, with interactive gates and altars.

var building_id: int = -1
var piece_type: String = "wall"
var owner_name: String = ""
var guild_id: String = ""
var max_hp: float = 400.0
var hp: float = 400.0
var is_open: bool = false

@onready var visual_root: Node3D = $VisualRoot
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var info_label: Label3D = $InfoLabel

var _door_pivot: Node3D = null
var _sigil_node: Node3D = null
var _time: float = 0.0


func setup_from_record(rec: Dictionary) -> void:
	building_id = int(rec.get("id", -1))
	piece_type = str(rec.get("piece_type", "wall"))
	owner_name = str(rec.get("owner", ""))
	guild_id = str(rec.get("guild_id", ""))
	var spec: Dictionary = GameConfig.BUILD_PIECES.get(piece_type, GameConfig.BUILD_PIECES["wall"]) as Dictionary
	max_hp = float(rec.get("max_hp", float(spec.get("max_hp", 400.0))))
	hp = float(rec.get("hp", max_hp))
	is_open = bool(rec.get("is_open", false))
	var pos_arr: Array = rec.get("position", [0.0, 0.0, 0.0]) as Array
	if pos_arr.size() == 3:
		var wp: Vector3 = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		global_position = GameConfig.world_to_local(wp)
	rotation.y = float(rec.get("rotation_y", 0.0))
	name = "Build_%d" % building_id
	if is_node_ready():
		_rebuild_visual_and_collision()


func _ready() -> void:
	add_to_group("buildings")
	collision_layer = GameConfig.LAYER_BUILDINGS | GameConfig.LAYER_INTERACTABLES
	collision_mask = 0
	_rebuild_visual_and_collision()


func _rebuild_visual_and_collision() -> void:
	var parts: Dictionary = ProceduralMeshFactory.build_structure_visual(visual_root, piece_type, false, true)
	_door_pivot = parts.get("door_pivot", null) as Node3D
	_sigil_node = parts.get("sigil_node", null) as Node3D

	var spec: Dictionary = GameConfig.BUILD_PIECES.get(piece_type, GameConfig.BUILD_PIECES["wall"]) as Dictionary
	var sz: Vector3 = spec.get("size", Vector3(4.0, 4.0, 1.5)) as Vector3
	var box: BoxShape3D = BoxShape3D.new()
	box.size = sz
	if collision_shape != null:
		collision_shape.shape = box
		collision_shape.position = Vector3(0.0, sz.y * 0.5, 0.0)
	if info_label != null:
		info_label.position = Vector3(0.0, sz.y + 0.8, 0.0)
	_update_gate_state()
	_update_label()


func _process(delta: float) -> void:
	_time += delta
	if _sigil_node != null:
		_sigil_node.rotation.y += delta * 1.4
		_sigil_node.position.y = 3.15 + sin(_time * 2.4) * 0.16


func update_hp(new_hp: float) -> void:
	hp = clampf(new_hp, 0.0, max_hp)
	_update_label()


func set_gate_open(open_state: bool) -> void:
	is_open = open_state
	_update_gate_state()
	_update_label()


func _update_gate_state() -> void:
	if piece_type != "gate":
		return
	if _door_pivot != null:
		_door_pivot.rotation_degrees.y = -95.0 if is_open else 0.0
	if collision_shape != null:
		collision_shape.disabled = is_open


func _update_label() -> void:
	if info_label == null:
		return
	var spec: Dictionary = GameConfig.BUILD_PIECES.get(piece_type, {}) as Dictionary
	var display_name: String = str(spec.get("name", piece_type))
	var hint: String = ""
	if piece_type == "gate":
		hint = " [E: %s]" % ("Cerrar" if is_open else "Abrir")
	elif piece_type == "trade_post":
		hint = " [E: Mercado]"
	info_label.text = "%s (%s)\nHP: %d / %d%s" % [display_name, owner_name, int(ceilf(hp)), int(max_hp), hint]
	var pct: float = hp / maxf(1.0, max_hp)
	if pct < 0.35:
		info_label.modulate = Color(1.0, 0.32, 0.25)
	elif pct < 0.7:
		info_label.modulate = Color(1.0, 0.78, 0.32)
	else:
		info_label.modulate = Color(0.92, 0.95, 1.0)
