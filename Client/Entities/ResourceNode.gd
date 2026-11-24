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
	var rarity: String = str(item_def.get("rarity", "Común"))
	var val: int = int(item_def.get("value", 5))
	var rcol: Color = item_def.get("rarity_col", Color(0.85, 0.9, 1.0)) as Color

	# Luminous rarity aura ring around gatherable nodes for clear visibility
	var aura_ring: MeshInstance3D = MeshInstance3D.new()
	aura_ring.name = "RarityAura"
	var tm: TorusMesh = TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.02
	tm.rings = 16
	tm.ring_segments = 6
	aura_ring.mesh = tm
	aura_ring.position = Vector3(0.0, 0.14, 0.0)
	var amat: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(rcol, 0.15, 0.0, rcol, 2.2)
	amat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	amat.albedo_color.a = 0.65
	aura_ring.material_override = amat
	visual_root.add_child(aura_ring)

	if label_3d != null:
		label_3d.modulate = rcol
		label_3d.text = "[E / Y] %s [%s]\nValor ref: %d monedas (%d/%d)" % [display_name, rarity, val, remaining_charges, max_charges]


func set_state(charges: int, depleted: bool) -> void:
	var harvested: bool = charges < remaining_charges
	remaining_charges = charges
	is_depleted = depleted
	if harvested:
		play_harvest_burst()
	visible = not depleted
	if collision_shape != null:
		collision_shape.disabled = depleted
	var item_def: Dictionary = GameConfig.ITEMS.get(resource_type, {}) as Dictionary
	var display_name: String = str(item_def.get("name", resource_type))
	var rarity: String = str(item_def.get("rarity", "Común"))
	var val: int = int(item_def.get("value", 5))
	if label_3d != null:
		label_3d.text = "[E / Y] %s [%s]\nValor ref: %d monedas (%d/%d)" % [display_name, rarity, val, remaining_charges, max_charges]


func play_harvest_burst() -> void:
	if DisplayServer.get_name() == "headless" or get_parent() == null:
		return
	var burst: CPUParticles3D = CPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.amount = 14
	burst.lifetime = 0.55
	burst.direction = Vector3(0.0, 1.0, 0.0)
	burst.spread = 65.0
	burst.initial_velocity_min = 2.5
	burst.initial_velocity_max = 5.5
	burst.gravity = Vector3(0.0, -10.0, 0.0)
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	sm.radial_segments = 6
	sm.rings = 4
	burst.mesh = sm
	var col: Color = Color(0.55, 0.38, 0.2)
	if resource_type == "iron_ore":
		col = Color(0.8, 0.84, 0.92)
	elif resource_type == "arcane_ore":
		col = Color(0.35, 0.82, 1.0)
	elif resource_type == "alchemy_herb":
		col = Color(0.35, 1.0, 0.65)
	burst.material_override = ProceduralMeshFactory.make_pbr_material(col, 0.3, 0.2, col, 1.4)
	get_parent().add_child(burst)
	burst.global_position = global_position + Vector3(0.0, 1.1, 0.0)
	burst.emitting = true
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(burst):
			burst.queue_free()
	)
