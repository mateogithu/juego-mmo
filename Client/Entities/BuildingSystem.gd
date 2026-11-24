class_name BuildingSystem
extends Node3D

## Client-side interactive building mode with translucent ghost preview,
## snap-to-grid or free placement, rotation controls, and server-validated placement.

signal build_mode_changed(active: bool, selected_piece: String, snap_enabled: bool)

var is_active: bool = false
var selected_piece: String = "wall"
var snap_to_grid: bool = true
var grid_step: float = 2.0
var rotation_y: float = 0.0
var max_build_distance: float = 18.0

var _ghost_root: Node3D = null
var _last_valid: bool = false
var _last_piece_built: String = ""
var _placement_pos: Vector3 = Vector3.ZERO
var _placement_valid: bool = false


func _ready() -> void:
	_ghost_root = Node3D.new()
	_ghost_root.name = "BuildGhost"
	_ghost_root.visible = false
	add_child(_ghost_root)


func toggle_build_mode() -> void:
	set_build_mode(not is_active)


func set_build_mode(active: bool) -> void:
	is_active = active
	if _ghost_root != null:
		_ghost_root.visible = is_active
	if is_active:
		_rebuild_ghost(true)
	build_mode_changed.emit(is_active, selected_piece, snap_to_grid)


func select_piece(piece_type: String) -> void:
	if not GameConfig.BUILD_PIECES.has(piece_type):
		return
	selected_piece = piece_type
	if is_active:
		_rebuild_ghost(_placement_valid)
	build_mode_changed.emit(is_active, selected_piece, snap_to_grid)


func toggle_snap() -> void:
	snap_to_grid = not snap_to_grid
	build_mode_changed.emit(is_active, selected_piece, snap_to_grid)


func rotate_ghost(step_deg: float = 15.0) -> void:
	rotation_y = wrapf(rotation_y + deg_to_rad(step_deg), 0.0, TAU)


func cycle_piece(step: int) -> void:
	var keys: Array = GameConfig.BUILD_PIECES.keys()
	if keys.is_empty():
		return
	var idx: int = keys.find(selected_piece)
	if idx < 0:
		idx = 0
	idx = posmod(idx + step, keys.size())
	select_piece(str(keys[idx]))


func update_preview(camera: Camera3D, player_local_pos: Vector3) -> void:
	if not is_active or camera == null:
		return

	var forward: Vector3 = -camera.global_transform.basis.z
	var origin: Vector3 = camera.global_position
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + forward * 28.0)
	query.collision_mask = GameConfig.LAYER_TERRAIN | GameConfig.LAYER_BUILDINGS
	var hit: Dictionary = space.intersect_ray(query)

	var target_world: Vector3
	if not hit.is_empty():
		target_world = GameConfig.local_to_world(hit["position"] as Vector3)
	else:
		var flat_fwd: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
		if flat_fwd.length_squared() < 0.01:
			flat_fwd = Vector3.FORWARD
		target_world = GameConfig.local_to_world(player_local_pos) + flat_fwd * 8.0
		target_world.y = GameConfig.sample_terrain_height(target_world.x, target_world.z)

	if snap_to_grid:
		target_world.x = snappedf(target_world.x, grid_step)
		target_world.z = snappedf(target_world.z, grid_step)
		target_world.y = GameConfig.sample_terrain_height(target_world.x, target_world.z)

	_placement_pos = target_world
	var player_world: Vector3 = GameConfig.local_to_world(player_local_pos)
	var dist: float = player_world.distance_to(target_world)
	var has_resources: bool = _local_has_resources(selected_piece)
	var above_water: bool = target_world.y >= GameConfig.WATER_LEVEL + 0.2
	_placement_valid = dist <= max_build_distance and has_resources and above_water

	if _placement_valid != _last_valid or _last_piece_built != selected_piece:
		_rebuild_ghost(_placement_valid)

	_ghost_root.global_position = GameConfig.world_to_local(_placement_pos)
	_ghost_root.global_rotation = Vector3(0.0, rotation_y, 0.0)


func try_place_current() -> void:
	if not is_active or not _placement_valid:
		return
	var ba: Node = get_tree().get_first_node_in_group("building_authority")
	if ba != null and ba.has_method("request_place_building"):
		ba.call("request_place_building", selected_piece, _placement_pos, rotation_y)
		AudioSynth.play_build_place()


func _rebuild_ghost(valid: bool) -> void:
	_last_valid = valid
	_last_piece_built = selected_piece
	ProceduralMeshFactory.build_structure_visual(_ghost_root, selected_piece, true, valid)


func _local_has_resources(piece_type: String) -> bool:
	var spec: Dictionary = GameConfig.BUILD_PIECES.get(piece_type, {}) as Dictionary
	var cost: Dictionary = spec.get("cost", {}) as Dictionary
	var inv: Dictionary = NetworkManager.local_profile.get("inventory", {}) as Dictionary
	for item_id: Variant in cost.keys():
		if int(inv.get(str(item_id), 0)) < int(cost[item_id]):
			return false
	return true
