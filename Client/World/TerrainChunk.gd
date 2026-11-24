class_name TerrainChunk
extends StaticBody3D

## Dynamically streamed procedural terrain chunk with 3-tier LOD (ground 5x5 & high-altitude 7x7),
## Floating Origin coordinate positioning, and baked trimesh collision for Vega 8 / 8 GB RAM.

const TERRAIN_SHADER: Shader = preload("res://Client/Shaders/terrain.gdshader")

var chunk_coord: Vector2i = Vector2i.ZERO
var lod_level: int = 1
var mesh_instance: MeshInstance3D = null
var collision_shape: CollisionShape3D = null

static var _shared_material: ShaderMaterial = null


static func get_terrain_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = TERRAIN_SHADER
	return _shared_material


static func update_shader_origin_offset(offset: Vector3) -> void:
	var mat: ShaderMaterial = get_terrain_material()
	mat.set_shader_parameter("world_origin_offset", offset)


func build_chunk(coord: Vector2i, lod_step: int = 1) -> void:
	chunk_coord = coord
	lod_level = clampi(lod_step, 1, 3)
	name = "TerrainChunk_%d_%d" % [coord.x, coord.y]
	collision_layer = GameConfig.LAYER_TERRAIN
	collision_mask = 0

	var size: float = GameConfig.CHUNK_SIZE
	var res: int = GameConfig.CHUNK_RESOLUTION
	if lod_level == 2:
		res = maxi(6, GameConfig.CHUNK_RESOLUTION / 2)
	elif lod_level >= 3:
		res = 5
	var cell: float = size / float(res)
	var origin_x: float = float(coord.x) * size
	var origin_z: float = float(coord.y) * size

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var verts: Array[Vector3] = []
	var norms: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var stride: int = res + 1
	verts.resize(stride * stride)
	norms.resize(stride * stride)
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
			norms[idx] = GameConfig.sample_terrain_normal(wx, wz)
			uvs[idx] = Vector2(float(gx) / float(res), float(gz) / float(res))

	for gz: int in range(res):
		for gx: int in range(res):
			var i00: int = gz * stride + gx
			var i10: int = i00 + 1
			var i01: int = i00 + stride
			var i11: int = i01 + 1

			st.set_normal(norms[i00])
			st.set_uv(uvs[i00])
			st.add_vertex(verts[i00])

			st.set_normal(norms[i10])
			st.set_uv(uvs[i10])
			st.add_vertex(verts[i10])

			st.set_normal(norms[i11])
			st.set_uv(uvs[i11])
			st.add_vertex(verts[i11])

			st.set_normal(norms[i00])
			st.set_uv(uvs[i00])
			st.add_vertex(verts[i00])

			st.set_normal(norms[i11])
			st.set_uv(uvs[i11])
			st.add_vertex(verts[i11])

			st.set_normal(norms[i01])
			st.set_uv(uvs[i01])
			st.add_vertex(verts[i01])

	var mesh: ArrayMesh = st.commit()

	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "ChunkMesh"
		add_child(mesh_instance)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = get_terrain_material()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Outer high-flight LOD 3 chunks skip heavy trimesh collider until player approaches
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
