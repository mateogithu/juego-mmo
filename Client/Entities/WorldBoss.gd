class_name WorldBoss
extends CharacterBody3D

## Colossal Server-Authoritative World Boss (and Dungeon Boss) entity.
## Renders sculpted boss rig, telegraphed ground AoE attack rings, smooth movement,
## and Floating Origin shift compatibility.

var boss_id: String = ""
var boss_name: String = "Jefe de Mundo"
var boss_title: String = ""
var boss_style: String = "behemoth"
var max_hp: float = 1400.0
var hp: float = 1400.0
var is_alive: bool = true

var _net_pos: Vector3 = Vector3.ZERO
var _net_yaw: float = 0.0
var _anim_t: float = 0.0
var _telegraph_timer: float = 0.0
var _telegraph_duration: float = 1.8
var _telegraph_radius: float = 9.5
var _rig: Dictionary = {}

@onready var visual_root: Node3D = $VisualRoot
@onready var telegraph_mesh: MeshInstance3D = $TelegraphRing
@onready var label_3d: Label3D = $Label3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func setup(p_id: String, p_name: String, p_title: String, p_style: String, p_max_hp: float, world_pos: Vector3) -> void:
	boss_id = p_id
	boss_name = p_name
	boss_title = p_title
	boss_style = p_style
	max_hp = p_max_hp
	hp = p_max_hp
	name = "Boss_%s" % p_id
	var lp: Vector3 = GameConfig.world_to_local(world_pos)
	global_position = lp
	_net_pos = lp
	if is_node_ready():
		_rebuild_visual()


func _ready() -> void:
	add_to_group("world_bosses")
	collision_layer = GameConfig.LAYER_PLAYERS
	collision_mask = GameConfig.LAYER_TERRAIN
	_rebuild_visual()
	if telegraph_mesh != null:
		var ring_mat: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(
			Color(1.0, 0.22, 0.1, 0.55), 0.2, 0.0, Color(1.0, 0.25, 0.08), 2.5
		)
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		telegraph_mesh.material_override = ring_mat
		telegraph_mesh.visible = false


func apply_floating_origin_shift(delta_vec: Vector3) -> void:
	global_position += delta_vec
	_net_pos += delta_vec


func _rebuild_visual() -> void:
	_rig = ProceduralMeshFactory.build_world_boss_rig(visual_root, boss_style)
	_update_label()


func apply_sync_state(world_pos: Vector3, yaw: float, new_hp: float, new_max_hp: float, alive: bool) -> void:
	_net_pos = GameConfig.world_to_local(world_pos)
	_net_yaw = yaw
	hp = new_hp
	max_hp = new_max_hp
	is_alive = alive
	visible = alive
	if collision_shape != null:
		collision_shape.disabled = not alive
	_update_label()


func trigger_aoe_telegraph(radius: float, windup_sec: float) -> void:
	_telegraph_radius = radius
	_telegraph_duration = maxf(0.5, windup_sec)
	_telegraph_timer = _telegraph_duration
	if telegraph_mesh != null:
		telegraph_mesh.visible = true
		telegraph_mesh.scale = Vector3(radius * 0.2, 1.0, radius * 0.2)
	AudioSynth.play_dragon_roar()


func _update_label() -> void:
	if label_3d == null:
		return
	label_3d.text = "☠ %s ☠\nHP: %d / %d" % [boss_name, int(ceilf(hp)), int(max_hp)]


func _process(delta: float) -> void:
	if not is_alive:
		return
	_anim_t += delta
	global_position = global_position.lerp(_net_pos, clampf(delta * 8.0, 0.0, 1.0))
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, _net_yaw, clampf(delta * 8.0, 0.0, 1.0))

	var arm_r: Node3D = _rig.get("arm_r", null) as Node3D
	var arm_l: Node3D = _rig.get("arm_l", null) as Node3D
	if arm_r != null:
		arm_r.rotation_degrees.x = sin(_anim_t * 2.4) * 20.0 - (48.0 if _telegraph_timer > 0.0 else 0.0)
	if arm_l != null:
		arm_l.rotation_degrees.x = -sin(_anim_t * 2.4) * 16.0 - (38.0 if _telegraph_timer > 0.0 else 0.0)

	# Animate wyrm wings if Wyrm boss
	var drig: Dictionary = _rig.get("dragon_rig", {}) as Dictionary
	if not drig.is_empty():
		var wl: Node3D = drig.get("wing_l_root", null) as Node3D
		var wr: Node3D = drig.get("wing_r_root", null) as Node3D
		if wl != null and wr != null:
			var beat: float = sin(_anim_t * 3.8) * 32.0
			wl.rotation_degrees.z = beat
			wr.rotation_degrees.z = -beat

	if _telegraph_timer > 0.0:
		_telegraph_timer -= delta
		if telegraph_mesh != null:
			var pct: float = clampf(1.0 - (_telegraph_timer / _telegraph_duration), 0.15, 1.0)
			var cur_r: float = _telegraph_radius * pct
			telegraph_mesh.scale = Vector3(cur_r, 1.0, cur_r)
			if _telegraph_timer <= 0.0:
				telegraph_mesh.visible = false
				AudioSynth.play_fireball()
