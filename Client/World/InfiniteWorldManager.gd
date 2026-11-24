class_name InfiniteWorldManager
extends Node3D

## Infinite deterministic procedural open-world manager with:
## - Seeded chunk streaming (5x5 on ground, 7x7 low-LOD during high dragon flight)
## - Automatic distant chunk & resource unloading (queue_free) for 8 GB RAM / Vega 8
## - Floating Origin (> 2,000 m) to prevent 32-bit float precision jitter anywhere in the world
## - Infinite moving water plane, primordial landmarks, and day/night cycle

const WATER_SHADER: Shader = preload("res://Client/Shaders/water.gdshader")
const RESOURCE_SCENE: PackedScene = preload("res://Client/Entities/ResourceNode.tscn")
const STATION_SCENE: PackedScene = preload("res://Client/Entities/WorldStation.tscn")

@onready var terrain_chunks_root: Node3D = $TerrainChunks
@onready var landmarks_root: Node3D = $Landmarks
@onready var stations_root: Node3D = $Stations
@onready var dungeons_root: Node3D = $Dungeons
@onready var bosses_root: Node3D = $Bosses
@onready var water_plane: MeshInstance3D = $WaterPlane
@onready var players_root: Node3D = $Players
@onready var dragons_root: Node3D = $Dragons
@onready var buildings_root: Node3D = $Buildings
@onready var projectiles_root: Node3D = $Projectiles
@onready var resources_root: Node3D = $Resources
@onready var loot_root: Node3D = $LootContainer
@onready var sun_light: DirectionalLight3D = $SunLight
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var world_auth: WorldAuthority = $WorldAuthority
@onready var building_auth: BuildingAuthority = $BuildingAuthority

var _loaded_chunks: Dictionary = {} # Vector2i -> TerrainChunk
var _loaded_chunk_lod: Dictionary = {} # Vector2i -> int
var _chunk_resources: Dictionary = {} # Vector2i -> Array[ResourceNode]
var _resource_by_key: Dictionary = {} # String -> ResourceNode

var _last_center_chunk: Vector2i = Vector2i(999999, 999999)
var _last_radius: int = -1
var _stream_timer: float = 0.0
var _local_player: PlayerController = null
var _water_mat: ShaderMaterial = null


func _ready() -> void:
	add_to_group("infinite_world_manager")
	GameConfig.world_origin_offset = Vector3.ZERO
	TerrainChunk.update_shader_origin_offset(Vector3.ZERO)
	_setup_water_plane()
	_build_primordial_landmarks()
	_spawn_settlement_stations()
	DungeonGenerator.build_all_dungeons(dungeons_root)
	if world_auth != null:
		world_auth.local_player_ready.connect(_on_local_player_ready)
		world_auth.world_time_updated.connect(_on_world_time_updated)
		world_auth.world_seed_synced.connect(_on_world_seed_synced)
		world_auth.resource_state_changed.connect(_on_resource_state_changed)
		var my_id: int = multiplayer.get_unique_id()
		if not NetworkManager.is_dedicated_server() and world_auth.player_nodes.has(my_id):
			_local_player = world_auth.player_nodes[my_id] as PlayerController
	_update_chunk_streaming(Vector3.ZERO, GameConfig.GROUND_CHUNK_RADIUS, true)


func _spawn_settlement_stations() -> void:
	if stations_root == null:
		return
	for child: Node in stations_root.get_children():
		child.queue_free()
	var station_defs: Array = [
		["forge", "Yunque y Forja de Herrería", Vector2(-14.0, 9.0)],
		["alchemy", "Banco de Alquimia", Vector2(14.0, 9.0)],
		["shop_stall", "Tienda y Mercado del Valle", Vector2(0.0, -15.0)]
	]
	for s_var: Variant in station_defs:
		var sdef: Array = s_var as Array
		var xz: Vector2 = sdef[2] as Vector2
		var wy: float = GameConfig.sample_terrain_height(xz.x, xz.y)
		var st_node: WorldStation = STATION_SCENE.instantiate() as WorldStation
		stations_root.add_child(st_node)
		st_node.setup(str(sdef[0]), str(sdef[1]), Vector3(xz.x, wy, xz.y))


func _on_local_player_ready(pc: PlayerController) -> void:
	_local_player = pc
	var wp: Vector3 = GameConfig.local_to_world(pc.global_position)
	_update_chunk_streaming(wp, GameConfig.GROUND_CHUNK_RADIUS, true)


func _on_world_seed_synced(new_seed: int) -> void:
	if new_seed == GameConfig.world_seed and not _loaded_chunks.is_empty():
		return
	GameConfig.set_world_seed(new_seed)
	_rebuild_all_chunks()


func _rebuild_all_chunks() -> void:
	for coord_var: Variant in _loaded_chunks.keys():
		var chunk: TerrainChunk = _loaded_chunks[coord_var] as TerrainChunk
		if is_instance_valid(chunk):
			chunk.queue_free()
	_loaded_chunks.clear()
	_loaded_chunk_lod.clear()
	for coord_var: Variant in _chunk_resources.keys():
		for rn: ResourceNode in (_chunk_resources[coord_var] as Array):
			if is_instance_valid(rn):
				rn.queue_free()
	_chunk_resources.clear()
	_resource_by_key.clear()
	for child: Node in landmarks_root.get_children():
		child.queue_free()
	_build_primordial_landmarks()
	_spawn_settlement_stations()
	DungeonGenerator.build_all_dungeons(dungeons_root)
	var focus_world: Vector3 = GameConfig.local_to_world(_local_player.global_position) if (_local_player != null and is_instance_valid(_local_player)) else Vector3.ZERO
	_update_chunk_streaming(focus_world, GameConfig.GROUND_CHUNK_RADIUS, true)


func _process(delta: float) -> void:
	_stream_timer += delta
	if _stream_timer < 0.35:
		return
	_stream_timer = 0.0

	var focus_local: Vector3 = Vector3.ZERO
	var high_flight: bool = false
	if _local_player != null and is_instance_valid(_local_player):
		focus_local = _local_player.global_position
		if Vector2(focus_local.x, focus_local.z).length() > GameConfig.FLOATING_ORIGIN_THRESHOLD:
			_perform_floating_origin_shift(focus_local)
			focus_local = _local_player.global_position

		var focus_world_chk: Vector3 = GameConfig.local_to_world(focus_local)
		var ground_y: float = GameConfig.sample_terrain_height(focus_world_chk.x, focus_world_chk.z)
		var altitude: float = focus_world_chk.y - ground_y
		high_flight = _local_player.is_mounted and altitude >= GameConfig.FLIGHT_HIGH_ALTITUDE_THRESHOLD

	if water_plane != null:
		water_plane.position = Vector3(focus_local.x, GameConfig.WATER_LEVEL, focus_local.z)

	var desired_radius: int = 1 if NetworkManager.is_dedicated_server() else (
		GameConfig.FLIGHT_CHUNK_RADIUS if high_flight else GameConfig.GROUND_CHUNK_RADIUS
	)
	var focus_world: Vector3 = GameConfig.local_to_world(focus_local)
	_update_chunk_streaming(focus_world, desired_radius, false)


func _perform_floating_origin_shift(focus_local: Vector3) -> void:
	var shift_x: float = snappedf(focus_local.x, GameConfig.CHUNK_SIZE)
	var shift_z: float = snappedf(focus_local.z, GameConfig.CHUNK_SIZE)
	var shift: Vector3 = Vector3(shift_x, 0.0, shift_z)
	if shift.length_squared() < 1.0:
		return

	GameConfig.world_origin_offset += shift
	var delta_vec: Vector3 = -shift

	for container: Node3D in [terrain_chunks_root, landmarks_root, stations_root, dungeons_root, buildings_root, projectiles_root, resources_root, loot_root]:
		if container == null:
			continue
		for child: Node in container.get_children():
			if child is Node3D:
				(child as Node3D).position += delta_vec

	if bosses_root != null:
		for child: Node in bosses_root.get_children():
			if child is WorldBoss:
				(child as WorldBoss).apply_floating_origin_shift(delta_vec)
			elif child is Node3D:
				(child as Node3D).position += delta_vec

	if players_root != null:
		for child: Node in players_root.get_children():
			if child is PlayerController:
				(child as PlayerController).apply_floating_origin_shift(delta_vec)
			elif child is Node3D:
				(child as Node3D).position += delta_vec

	if dragons_root != null:
		for child: Node in dragons_root.get_children():
			if child is DragonController:
				(child as DragonController).apply_floating_origin_shift(delta_vec)
			elif child is Node3D:
				(child as Node3D).position += delta_vec

	TerrainChunk.update_shader_origin_offset(GameConfig.world_origin_offset)
	if _water_mat != null:
		_water_mat.set_shader_parameter("world_origin_offset", GameConfig.world_origin_offset)


func _update_chunk_streaming(focus_world: Vector3, radius: int, force: bool) -> void:
	var center: Vector2i = GameConfig.world_to_chunk(focus_world)
	if not force and center == _last_center_chunk and radius == _last_radius:
		return
	var chunk_changed: bool = (center != _last_center_chunk)
	_last_center_chunk = center
	_last_radius = radius

	var desired: Dictionary = {}
	for dz: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var coord: Vector2i = Vector2i(center.x + dx, center.y + dz)
			var dist_cheb: int = maxi(absi(dx), absi(dz))
			var lod_step: int = 1 if dist_cheb <= 1 else (2 if dist_cheb == 2 else 3)
			desired[coord] = lod_step
			if not _loaded_chunks.has(coord) or int(_loaded_chunk_lod.get(coord, -1)) != lod_step:
				if _loaded_chunks.has(coord):
					(_loaded_chunks[coord] as TerrainChunk).queue_free()
				var chunk: TerrainChunk = TerrainChunk.new()
				terrain_chunks_root.add_child(chunk)
				chunk.build_chunk(coord, lod_step)
				_loaded_chunks[coord] = chunk
				_loaded_chunk_lod[coord] = lod_step
				if not _chunk_resources.has(coord) and dist_cheb <= 2:
					_spawn_chunk_resources(coord)

	# Immediately free distant chunks & their resources to stay comfortably under 8 GB RAM
	var to_remove: Array[Vector2i] = []
	for coord_var: Variant in _loaded_chunks.keys():
		var coord: Vector2i = coord_var as Vector2i
		if not desired.has(coord):
			to_remove.append(coord)
	for coord: Vector2i in to_remove:
		var chunk: TerrainChunk = _loaded_chunks[coord] as TerrainChunk
		if is_instance_valid(chunk):
			chunk.queue_free()
		_loaded_chunks.erase(coord)
		_loaded_chunk_lod.erase(coord)
		_unload_chunk_resources(coord)

	if chunk_changed and building_auth != null and not NetworkManager.is_dedicated_server():
		building_auth.request_chunks_around(center, radius + 1)


func _spawn_chunk_resources(coord: Vector2i) -> void:
	var defs: Array[Dictionary] = GameConfig.get_chunk_resources(coord)
	var spawned: Array[ResourceNode] = []
	for d: Dictionary in defs:
		var rkey: String = str(d["key"])
		if _resource_by_key.has(rkey):
			continue
		var rn: ResourceNode = RESOURCE_SCENE.instantiate() as ResourceNode
		resources_root.add_child(rn)
		rn.setup(rkey, str(d["type"]), d["world_pos"] as Vector3)
		if world_auth != null and world_auth.known_resource_states.has(rkey):
			var st: Dictionary = world_auth.known_resource_states[rkey] as Dictionary
			rn.set_state(int(st.get("charges", 5)), bool(st.get("depleted", false)))
		spawned.append(rn)
		_resource_by_key[rkey] = rn
	_chunk_resources[coord] = spawned


func _unload_chunk_resources(coord: Vector2i) -> void:
	if not _chunk_resources.has(coord):
		return
	var nodes: Array = _chunk_resources[coord] as Array
	for rn_var: Variant in nodes:
		var rn: ResourceNode = rn_var as ResourceNode
		if is_instance_valid(rn):
			_resource_by_key.erase(rn.resource_key)
			rn.queue_free()
	_chunk_resources.erase(coord)


func _on_resource_state_changed(resource_key: String, charges: int, depleted: bool) -> void:
	if _resource_by_key.has(resource_key):
		var rn: ResourceNode = _resource_by_key[resource_key] as ResourceNode
		if is_instance_valid(rn):
			rn.set_state(charges, depleted)


func _setup_water_plane() -> void:
	if water_plane == null:
		return
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(GameConfig.CHUNK_SIZE * 10.0, GameConfig.CHUNK_SIZE * 10.0)
	pm.subdivide_width = 40
	pm.subdivide_depth = 40
	water_plane.mesh = pm
	water_plane.position = Vector3(0.0, GameConfig.WATER_LEVEL, 0.0)
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = WATER_SHADER
	_water_mat.set_shader_parameter("world_origin_offset", GameConfig.world_origin_offset)
	water_plane.material_override = _water_mat
	water_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_primordial_landmarks() -> void:
	if landmarks_root == null:
		return
	var stone_mat: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(Color(0.5, 0.5, 0.54), 0.85, 0.08)
	var order_glow: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(Color(1.0, 0.86, 0.34), 0.15, 0.5, Color(1.0, 0.84, 0.3), 2.4)
	var chaos_glow: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(Color(1.0, 0.28, 0.14), 0.15, 0.5, Color(1.0, 0.24, 0.12), 2.4)

	var center_y: float = GameConfig.sample_terrain_height(0.0, 0.0)
	var plaza: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 12.0
	disc.bottom_radius = 13.0
	disc.height = 0.4
	disc.radial_segments = 16
	plaza.mesh = disc
	plaza.material_override = stone_mat
	plaza.position = GameConfig.world_to_local(Vector3(0.0, center_y - 0.1, 0.0))
	landmarks_root.add_child(plaza)

	_spawn_obelisk(Vector3(-42.0, GameConfig.sample_terrain_height(-42.0, -24.0), -24.0), stone_mat, order_glow, "ObeliskOrder")
	_spawn_obelisk(Vector3(42.0, GameConfig.sample_terrain_height(42.0, 24.0), 24.0), stone_mat, chaos_glow, "ObeliskChaos")


func _spawn_obelisk(world_pos: Vector3, stone_mat: Material, glow_mat: Material, node_name: String) -> void:
	var root: Node3D = Node3D.new()
	root.name = node_name
	root.position = GameConfig.world_to_local(world_pos)
	landmarks_root.add_child(root)

	var base: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(5.0, 2.0, 5.0)
	base.mesh = bm
	base.material_override = stone_mat
	base.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(base)

	var spire: MeshInstance3D = MeshInstance3D.new()
	var sm: CylinderMesh = CylinderMesh.new()
	sm.top_radius = 0.55
	sm.bottom_radius = 1.65
	sm.height = 14.0
	sm.radial_segments = 6
	spire.mesh = sm
	spire.material_override = stone_mat
	spire.position = Vector3(0.0, 9.0, 0.0)
	root.add_child(spire)

	var orb: MeshInstance3D = MeshInstance3D.new()
	var om: SphereMesh = SphereMesh.new()
	om.radius = 1.05
	om.height = 2.1
	orb.mesh = om
	orb.material_override = glow_mat
	orb.position = Vector3(0.0, 17.5, 0.0)
	root.add_child(orb)


func _on_world_time_updated(t: float) -> void:
	if sun_light == null or world_env == null or world_env.environment == null:
		return
	var sun_angle: float = t * TAU - PI * 0.5
	sun_light.rotation.x = -sun_angle
	sun_light.rotation.y = deg_to_rad(32.0)

	var day_factor: float = clampf(sin(t * TAU) * 1.4 + 0.35, 0.0, 1.0)
	sun_light.light_energy = lerpf(0.18, 1.25, day_factor)
	sun_light.light_color = Color(0.55, 0.62, 0.85).lerp(Color(1.0, 0.95, 0.84), day_factor)

	var env: Environment = world_env.environment
	env.ambient_light_energy = lerpf(0.28, 0.62, day_factor)
	env.fog_light_color = Color(0.08, 0.1, 0.18).lerp(Color(0.58, 0.68, 0.8), day_factor)
	env.fog_density = lerpf(0.0046, 0.0028, day_factor)
