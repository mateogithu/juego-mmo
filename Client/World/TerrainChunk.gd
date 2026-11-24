class_name TerrainChunk
extends StaticBody3D

## Dynamically streamed organic terrain chunk with:
## - Smooth per-vertex normals via SurfaceTool.index() + generate_normals()
## - GPU-instanced MultiMeshInstance3D vegetation & props (pines, oaks, bushes, sculpted rocks, swaying grass)
## - 3-tier LOD for 60 FPS on Radeon Vega 8 & 8 GB RAM + Floating Origin support

const TERRAIN_SHADER: Shader = preload("res://Client/Shaders/terrain.gdshader")
const GRASS_WIND_SHADER: Shader = preload("res://Client/Shaders/grass_wind.gdshader")

var chunk_coord: Vector2i = Vector2i.ZERO
var lod_level: int = 1
var mesh_instance: MeshInstance3D = null
var collision_shape: CollisionShape3D = null
var foliage_root: Node3D = null

static var _shared_material: ShaderMaterial = null
static var _grass_mat: ShaderMaterial = null
static var _pine_mesh: ArrayMesh = null
static var _oak_mesh: ArrayMesh = null
static var _rock_mesh: ArrayMesh = null
static var _grass_mesh: ArrayMesh = null


static func get_terrain_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = TERRAIN_SHADER
	return _shared_material


static func update_shader_origin_offset(offset: Vector3) -> void:
	get_terrain_material().set_shader_parameter("world_origin_offset", offset)


static func _ensure_shared_foliage_meshes() -> void:
	if _pine_mesh != null:
		return
	_pine_mesh = _build_pine_tree_mesh()
	_oak_mesh = _build_oak_tree_mesh()
	_rock_mesh = _build_organic_rock_mesh()
	_grass_mesh = _build_grass_tuft_mesh()
	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = GRASS_WIND_SHADER


func build_chunk(coord: Vector2i, lod_step: int = 1) -> void:
	chunk_coord = coord
	lod_level = clampi(lod_step, 1, 3)
	name = "TerrainChunk_%d_%d" % [coord.x, coord.y]
	collision_layer = GameConfig.LAYER_TERRAIN
	collision_mask = 0

	var size: float = GameConfig.CHUNK_SIZE
	var res: int = 24
	if lod_level == 2:
		res = 12
	elif lod_level >= 3:
		res = 6
	var cell: float = size / float(res)
	var origin_x: float = float(coord.x) * size
	var origin_z: float = float(coord.y) * size

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)

	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var stride: int = res + 1
	verts.resize(stride * stride)
	uvs.resize(stride * stride)

	for gz: int in range(stride):
		for gx: int in range(stride):
			var lx: float = float(gx) * cell
			var lz: float = float(gz) * cell
			var wx: float = origin_x + lx
			var wz: float = origin_z + lz
			var wy: float = GameConfig.sample_terrain_height(wx, wz)
			var idx: int = gz * stride + gx
			verts[idx] = Vector3(lx, wy, lz)
			uvs[idx] = Vector2(float(gx) / float(res), float(gz) / float(res))

	for gz: int in range(res):
		for gx: int in range(res):
			var i00: int = gz * stride + gx
			var i10: int = i00 + 1
			var i01: int = i00 + stride
			var i11: int = i01 + 1

			st.set_uv(uvs[i00])
			st.add_vertex(verts[i00])
			st.set_uv(uvs[i10])
			st.add_vertex(verts[i10])
			st.set_uv(uvs[i11])
			st.add_vertex(verts[i11])

			st.set_uv(uvs[i00])
			st.add_vertex(verts[i00])
			st.set_uv(uvs[i11])
			st.add_vertex(verts[i11])
			st.set_uv(uvs[i01])
			st.add_vertex(verts[i01])

	st.index()
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()

	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "ChunkMesh"
		add_child(mesh_instance)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = get_terrain_material()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if lod_level <= 2:
		if collision_shape == null:
			collision_shape = CollisionShape3D.new()
			collision_shape.name = "ChunkCollision"
			add_child(collision_shape)
		collision_shape.shape = mesh.create_trimesh_shape()
		collision_shape.disabled = false
	elif collision_shape != null:
		collision_shape.disabled = true

	position = GameConfig.world_to_local(Vector3(origin_x, 0.0, origin_z))

	# Populate GPU-instanced vegetation & rocks on non-headless clients (LOD 1 & 2)
	if DisplayServer.get_name() != "headless":
		_populate_multimesh_foliage(coord, origin_x, origin_z)


func _populate_multimesh_foliage(coord: Vector2i, origin_x: float, origin_z: float) -> void:
	if foliage_root != null:
		foliage_root.queue_free()
		foliage_root = null
	if lod_level >= 3:
		return

	_ensure_shared_foliage_meshes()
	foliage_root = Node3D.new()
	foliage_root.name = "Foliage"
	add_child(foliage_root)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = (GameConfig.world_seed * 2654435761) ^ (coord.x * 92837111) ^ (coord.y * 689287499)

	var pine_xforms: Array[Transform3D] = []
	var oak_xforms: Array[Transform3D] = []
	var rock_xforms: Array[Transform3D] = []
	var grass_xforms: Array[Transform3D] = []

	var tree_attempts: int = 16 if lod_level == 1 else 8
	for i: int in range(tree_attempts):
		var lx: float = rng.randf_range(2.0, GameConfig.CHUNK_SIZE - 2.0)
		var lz: float = rng.randf_range(2.0, GameConfig.CHUNK_SIZE - 2.0)
		var wx: float = origin_x + lx
		var wz: float = origin_z + lz
		# Keep central valley settlement plaza open
		if sqrt(wx * wx + wz * wz) < 30.0:
			continue
		var wy: float = GameConfig.sample_terrain_height(wx, wz)
		var n: Vector3 = GameConfig.sample_terrain_normal(wx, wz)
		if wy < GameConfig.WATER_LEVEL + 1.0 or wy > 23.0 or n.y < 0.74:
			continue
		var yaw: float = rng.randf_range(0.0, TAU)
		var sc: float = rng.randf_range(0.85, 1.45)
		var xf: Transform3D = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(lx, wy - 0.15, lz))
		if wy > 9.5 or rng.randf() < 0.58:
			pine_xforms.append(xf)
		else:
			oak_xforms.append(xf)

	var rock_attempts: int = 10 if lod_level == 1 else 5
	for i: int in range(rock_attempts):
		var lx: float = rng.randf_range(2.0, GameConfig.CHUNK_SIZE - 2.0)
		var lz: float = rng.randf_range(2.0, GameConfig.CHUNK_SIZE - 2.0)
		var wx: float = origin_x + lx
		var wz: float = origin_z + lz
		if sqrt(wx * wx + wz * wz) < 26.0:
			continue
		var wy: float = GameConfig.sample_terrain_height(wx, wz)
		if wy < GameConfig.WATER_LEVEL - 0.5:
			continue
		var rot: Vector3 = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, TAU), rng.randf_range(-0.3, 0.3))
		var sc_v: Vector3 = Vector3(rng.randf_range(0.7, 2.2), rng.randf_range(0.55, 1.4), rng.randf_range(0.7, 2.1))
		rock_xforms.append(Transform3D(Basis.from_euler(rot).scaled(sc_v), Vector3(lx, wy - 0.2, lz)))

	# Dense swaying tall grass & shrubs on LOD 1 chunks (single MultiMesh draw call!)
	if lod_level == 1:
		for i: int in range(72):
			var lx: float = rng.randf_range(1.0, GameConfig.CHUNK_SIZE - 1.0)
			var lz: float = rng.randf_range(1.0, GameConfig.CHUNK_SIZE - 1.0)
			var wx: float = origin_x + lx
			var wz: float = origin_z + lz
			if sqrt(wx * wx + wz * wz) < 16.0:
				continue
			var wy: float = GameConfig.sample_terrain_height(wx, wz)
			var n: Vector3 = GameConfig.sample_terrain_normal(wx, wz)
			if wy < GameConfig.WATER_LEVEL + 0.6 or wy > 16.0 or n.y < 0.78:
				continue
			var yaw: float = rng.randf_range(0.0, TAU)
			var sc: float = rng.randf_range(0.75, 1.45)
			grass_xforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.3), sc)), Vector3(lx, wy - 0.05, lz)))

	_spawn_multimesh("PineForest", _pine_mesh, null, pine_xforms, true)
	_spawn_multimesh("OakForest", _oak_mesh, null, oak_xforms, true)
	_spawn_multimesh("BoulderField", _rock_mesh, null, rock_xforms, false)
	_spawn_multimesh("TallGrass", _grass_mesh, _grass_mat, grass_xforms, false)


func _spawn_multimesh(node_name: String, mesh: Mesh, mat_override: Material, xforms: Array[Transform3D], cast_shadows: bool) -> void:
	if xforms.is_empty():
		return
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = node_name
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i: int in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	mmi.multimesh = mm
	if mat_override != null:
		mmi.material_override = mat_override
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foliage_root.add_child(mmi)


# --- Organic Sculpted MultiMesh Builders (Zero BoxMesh) ---

static func _append_cone(st: SurfaceTool, base_y: float, top_y: float, base_r: float, top_r: float, segs: int, color: Color) -> void:
	st.set_color(color)
	for i: int in range(segs):
		var a0: float = (float(i) / float(segs)) * TAU
		var a1: float = (float(i + 1) / float(segs)) * TAU
		var b0: Vector3 = Vector3(cos(a0) * base_r, base_y, sin(a0) * base_r)
		var b1: Vector3 = Vector3(cos(a1) * base_r, base_y, sin(a1) * base_r)
		var t0: Vector3 = Vector3(cos(a0) * top_r, top_y, sin(a0) * top_r)
		var t1: Vector3 = Vector3(cos(a1) * top_r, top_y, sin(a1) * top_r)
		st.add_vertex(b0)
		st.add_vertex(t1)
		st.add_vertex(t0)
		st.add_vertex(b0)
		st.add_vertex(b1)
		st.add_vertex(t1)


static func _build_pine_tree_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	_append_cone(st, 0.0, 2.8, 0.36, 0.14, 7, Color(0.28, 0.19, 0.12))
	_append_cone(st, 1.9, 4.6, 2.1, 0.25, 8, Color(0.11, 0.27, 0.13))
	_append_cone(st, 3.6, 6.2, 1.65, 0.18, 8, Color(0.14, 0.33, 0.15))
	_append_cone(st, 5.1, 7.6, 1.15, 0.02, 8, Color(0.18, 0.38, 0.17))
	st.index()
	st.generate_normals()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.86
	st.set_material(mat)
	return st.commit()


static func _build_oak_tree_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	_append_cone(st, 0.0, 3.2, 0.44, 0.22, 8, Color(0.32, 0.22, 0.14))
	# Organic rounded leafy crown spheres merged into one vertex-colored mesh
	var crown_blobs: Array = [
		[Vector3(0.0, 4.4, 0.0), 2.15, Color(0.18, 0.38, 0.14)],
		[Vector3(1.2, 3.8, 0.7), 1.5, Color(0.22, 0.43, 0.16)],
		[Vector3(-1.1, 4.0, -0.6), 1.6, Color(0.15, 0.34, 0.13)],
		[Vector3(0.2, 5.4, -0.3), 1.4, Color(0.25, 0.46, 0.17)]
	]
	for blob_var: Variant in crown_blobs:
		var blob: Array = blob_var as Array
		_append_displaced_sphere(st, blob[0] as Vector3, float(blob[1]), 7, 5, 0.18, blob[2] as Color)
	st.index()
	st.generate_normals()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.84
	st.set_material(mat)
	return st.commit()


static func _append_displaced_sphere(st: SurfaceTool, center: Vector3, radius: float, segs: int, rings: int, jitter: float, color: Color) -> void:
	st.set_color(color)
	var grid: Array[Vector3] = []
	for r: int in range(rings + 1):
		var phi: float = (float(r) / float(rings)) * PI
		for s: int in range(segs + 1):
			var theta: float = (float(s) / float(segs)) * TAU
			var dir: Vector3 = Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var disp: float = 1.0 + sin(dir.x * 5.2 + dir.y * 4.1) * cos(dir.z * 5.7) * jitter
			grid.append(center + dir * radius * disp)
	var stride: int = segs + 1
	for r: int in range(rings):
		for s: int in range(segs):
			var i00: int = r * stride + s
			var i10: int = i00 + 1
			var i01: int = i00 + stride
			var i11: int = i01 + 1
			st.add_vertex(grid[i00])
			st.add_vertex(grid[i10])
			st.add_vertex(grid[i11])
			st.add_vertex(grid[i00])
			st.add_vertex(grid[i11])
			st.add_vertex(grid[i01])


static func _build_organic_rock_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	_append_displaced_sphere(st, Vector3(0.0, 0.45, 0.0), 0.95, 9, 6, 0.28, Color(0.42, 0.42, 0.45))
	st.index()
	st.generate_normals()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	st.set_material(mat)
	return st.commit()


static func _build_grass_tuft_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: int in range(3):
		var ang: float = float(b) * (PI / 3.0)
		var dx: float = cos(ang) * 0.34
		var dz: float = sin(ang) * 0.34
		st.set_normal(Vector3(-sin(ang), 0.3, cos(ang)).normalized())
		st.add_vertex(Vector3(-dx, 0.0, -dz))
		st.add_vertex(Vector3(dx, 0.0, dz))
		st.add_vertex(Vector3(dx * 0.25, 0.95, dz * 0.25))
		st.add_vertex(Vector3(-dx * 0.7, 0.0, -dz * 0.7))
		st.add_vertex(Vector3(dx * 0.6, 0.0, dz * 0.6))
		st.add_vertex(Vector3(-dx * 0.2, 0.78, -dz * 0.2))
	return st.commit()
