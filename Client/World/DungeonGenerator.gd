class_name DungeonGenerator
extends RefCounted

## Procedurally generates complex 3-chamber 4-player underground medieval dungeons
## (Room 1: Entrance Vestibule -> Room 2: Guardian Pillared Hall -> Room 3: Grand Boss Sanctum)
## using 1K Stone PBR materials, runic braziers, and synchronized exit portals.

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

		var entrance: DungeonEntrance = PORTAL_SCENE.instantiate() as DungeonEntrance
		parent.add_child(entrance)
		entrance.setup(did, dname, theme, entrance_pos, false)

		_build_multi_room_dungeon(parent, did, dname, theme, arena_origin)


static func _build_multi_room_dungeon(parent: Node3D, did: String, dname: String, theme: String, world_origin: Vector3) -> void:
	var chamber: StaticBody3D = StaticBody3D.new()
	chamber.name = "DungeonComplex_%s" % did
	chamber.collision_layer = GameConfig.LAYER_TERRAIN
	chamber.collision_mask = 0
	chamber.position = GameConfig.world_to_local(world_origin)
	parent.add_child(chamber)

	var is_order: bool = (theme == "order")
	var floor_mat: StandardMaterial3D = ProceduralMeshFactory.make_stone_pbr_material(
		Color(0.42, 0.46, 0.54) if is_order else Color(0.28, 0.22, 0.24)
	)
	var wall_mat: StandardMaterial3D = ProceduralMeshFactory.make_stone_pbr_material(
		Color(0.35, 0.38, 0.45) if is_order else Color(0.22, 0.16, 0.18)
	)
	var fire_col: Color = Color(0.42, 0.84, 1.0) if is_order else Color(1.0, 0.36, 0.1)
	var brazier_mat: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(fire_col, 0.15, 0.0, fire_col, 3.2)

	# Continuous 3-room stone floor & vaulted ceiling (48m wide x 104m long, Z from +52 to -52)
	_add_static_box(chamber, Vector3(48.0, 1.0, 104.0), Vector3(0.0, -0.5, 0.0), floor_mat, "DungeonFloor")
	_add_static_box(chamber, Vector3(48.0, 1.0, 104.0), Vector3(0.0, 13.0, 0.0), wall_mat, "Ceiling")

	# Outer Perimeter Walls
	_add_static_box(chamber, Vector3(48.0, 13.0, 1.6), Vector3(0.0, 6.5, -52.0), wall_mat, "WallNorth")
	_add_static_box(chamber, Vector3(48.0, 13.0, 1.6), Vector3(0.0, 6.5, 52.0), wall_mat, "WallSouth")
	_add_static_box(chamber, Vector3(1.6, 13.0, 104.0), Vector3(-24.0, 6.5, 0.0), wall_mat, "WallWest")
	_add_static_box(chamber, Vector3(1.6, 13.0, 104.0), Vector3(24.0, 6.5, 0.0), wall_mat, "WallEast")

	# Internal Dividing Walls with wide central Archways (Room 1 -> Room 2 -> Room 3 Boss Sanctum)
	for z_div: float in [24.0, -10.0]:
		_add_static_box(chamber, Vector3(16.0, 13.0, 1.8), Vector3(-16.0, 6.5, z_div), wall_mat, "DivL_%d" % int(z_div))
		_add_static_box(chamber, Vector3(16.0, 13.0, 1.8), Vector3(16.0, 6.5, z_div), wall_mat, "DivR_%d" % int(z_div))
		_add_static_box(chamber, Vector3(16.0, 4.5, 1.8), Vector3(0.0, 10.75, z_div), wall_mat, "Arch_%d" % int(z_div))

	# Pillars & Runic Torch Braziers along all 3 chambers
	for z_off: float in [38.0, 14.0, 2.0, -20.0, -34.0, -44.0]:
		for x_side: float in [-13.5, 13.5]:
			var pil: MeshInstance3D = MeshInstance3D.new()
			var cm: CylinderMesh = CylinderMesh.new()
			cm.top_radius = 0.85
			cm.bottom_radius = 1.1
			cm.height = 12.6
			cm.radial_segments = 10
			pil.mesh = cm
			pil.material_override = wall_mat
			pil.position = Vector3(x_side, 6.3, z_off)
			chamber.add_child(pil)

			var orb: MeshInstance3D = MeshInstance3D.new()
			var sm: SphereMesh = SphereMesh.new()
			sm.radius = 0.44
			sm.height = 0.88
			orb.mesh = sm
			orb.material_override = brazier_mat
			orb.position = Vector3(x_side * 0.82, 3.8, z_off)
			chamber.add_child(orb)

	# Three low-cost point lights (one per chamber) for Radeon Vega 8 efficiency
	for z_light: float in [38.0, 6.0, -32.0]:
		var light: OmniLight3D = OmniLight3D.new()
		light.position = Vector3(0.0, 9.0, z_light)
		light.light_color = fire_col.lerp(Color.WHITE, 0.35)
		light.light_energy = 2.6
		light.omni_range = 38.0
		chamber.add_child(light)

	# Exit Portal inside Room 1 Entrance Vestibule
	var exit_portal: DungeonEntrance = PORTAL_SCENE.instantiate() as DungeonEntrance
	parent.add_child(exit_portal)
	exit_portal.setup(did, dname, theme, world_origin + Vector3(0.0, 0.0, 47.0), true)


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
