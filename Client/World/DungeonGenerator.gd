class_name DungeonGenerator
extends RefCounted

## Procedurally generates explorable underground stone medieval dungeon chambers
## (stone floor, perimeter walls, vaulted colonnade pillars, torchlight braziers,
## boss arena, and exit portal) synchronized identically on server and clients.

const PORTAL_SCENE: PackedScene = preload("res://Client/Entities/DungeonEntrance.tscn")


static func build_all_dungeons(parent: Node3D) -> void:
	for child: Node in parent.get_children():
		child.queue_free()

	for d_def: Dictionary in GameConfig.DUNGEONS:
		var did: String = str(d_def["id"])
		var dname: String = str(d_def["name"])
		var theme: String = str(d_def["theme"])
		var exz: Vector2 = d_def["entrance_xz"] as Vector2
		var entrance_pos: Vector3 = Vector3(exz.x, GameConfig.sample_terrain_height(exz.x, exz.y), exz.y)
		var arena_origin: Vector3 = d_def["arena_origin"] as Vector3

		# 1. Surface Physical Entrance Portal
		var entrance: DungeonEntrance = PORTAL_SCENE.instantiate() as DungeonEntrance
		parent.add_child(entrance)
		entrance.setup(did, dname, theme, entrance_pos, false)

		# 2. Underground Explorable Stone Dungeon Arena
		_build_underground_chamber(parent, did, dname, theme, arena_origin)


static func _build_underground_chamber(parent: Node3D, did: String, dname: String, theme: String, world_origin: Vector3) -> void:
	var chamber: StaticBody3D = StaticBody3D.new()
	chamber.name = "DungeonChamber_%s" % did
	chamber.collision_layer = GameConfig.LAYER_TERRAIN
	chamber.collision_mask = 0
	chamber.position = GameConfig.world_to_local(world_origin)
	parent.add_child(chamber)

	var is_order: bool = (theme == "order")
	var floor_mat: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(
		Color(0.32, 0.34, 0.4) if is_order else Color(0.2, 0.16, 0.18), 0.85, 0.1
	)
	var wall_mat: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(
		Color(0.26, 0.28, 0.34) if is_order else Color(0.16, 0.12, 0.14), 0.9, 0.08
	)
	var fire_col: Color = Color(0.42, 0.84, 1.0) if is_order else Color(1.0, 0.36, 0.1)
	var brazier_mat: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(fire_col, 0.15, 0.0, fire_col, 3.0)

	# Floor slab (46m x 56m) + Collider
	_add_static_box(chamber, Vector3(46.0, 1.0, 56.0), Vector3(0.0, -0.5, 0.0), floor_mat, "DungeonFloor")
	# Perimeter Walls
	_add_static_box(chamber, Vector3(46.0, 12.0, 1.6), Vector3(0.0, 6.0, -28.0), wall_mat, "WallNorth")
	_add_static_box(chamber, Vector3(46.0, 12.0, 1.6), Vector3(0.0, 6.0, 28.0), wall_mat, "WallSouth")
	_add_static_box(chamber, Vector3(1.6, 12.0, 56.0), Vector3(-23.0, 6.0, 0.0), wall_mat, "WallWest")
	_add_static_box(chamber, Vector3(1.6, 12.0, 56.0), Vector3(23.0, 6.0, 0.0), wall_mat, "WallEast")
	# Vaulted Ceiling
	_add_static_box(chamber, Vector3(46.0, 1.0, 56.0), Vector3(0.0, 12.0, 0.0), wall_mat, "Ceiling")

	# Colonnade Pillars & Glowing Torch Braziers
	for z_off: float in [-16.0, -4.0, 8.0, 18.0]:
		for x_side: float in [-13.0, 13.0]:
			var pil: MeshInstance3D = MeshInstance3D.new()
			var cm: CylinderMesh = CylinderMesh.new()
			cm.top_radius = 0.85
			cm.bottom_radius = 1.05
			cm.height = 11.6
			cm.radial_segments = 10
			pil.mesh = cm
			pil.material_override = wall_mat
			pil.position = Vector3(x_side, 5.8, z_off)
			chamber.add_child(pil)

			var orb: MeshInstance3D = MeshInstance3D.new()
			var sm: SphereMesh = SphereMesh.new()
			sm.radius = 0.42
			sm.height = 0.84
			orb.mesh = sm
			orb.material_override = brazier_mat
			orb.position = Vector3(x_side * 0.82, 3.6, z_off)
			chamber.add_child(orb)

	# Ambient point light inside chamber (low cost on Vega 8)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = Vector3(0.0, 8.5, 0.0)
	light.light_color = fire_col.lerp(Color.WHITE, 0.4)
	light.light_energy = 2.8
	light.omni_range = 42.0
	chamber.add_child(light)

	# Exit Portal near south entrance of chamber
	var exit_portal: DungeonEntrance = PORTAL_SCENE.instantiate() as DungeonEntrance
	parent.add_child(exit_portal)
	exit_portal.setup(did, dname, theme, world_origin + Vector3(0.0, 0.0, 21.0), true)


static func _add_static_box(parent: StaticBody3D, sz: Vector3, pos: Vector3, mat: Material, node_name: String) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	var bm: BoxMesh = BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

	var col: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = sz
	col.shape = bs
	col.position = pos
	parent.add_child(col)
