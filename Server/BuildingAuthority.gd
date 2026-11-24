class_name BuildingAuthority
extends Node

## Server-authoritative player building, siege damage, gate interaction,
## and chunk-indexed delta streaming/persistence for the infinite procedural world.

const BUILD_PIECE_SCENE: PackedScene = preload("res://Client/Entities/BuildPiece.tscn")

@export var buildings_container_path: NodePath = NodePath("../Buildings")

var _buildings_container: Node3D = null
var _building_nodes: Dictionary = {} # int building_id -> BuildPiece
var _building_records: Dictionary = {} # int building_id -> Dictionary
var _chunk_building_ids: Dictionary = {} # String chunk_key -> Array[int]


func _ready() -> void:
	add_to_group("building_authority")
	_buildings_container = get_node_or_null(buildings_container_path) as Node3D
	if NetworkManager.is_server_running():
		_load_persisted_buildings()


func _get_sender_id() -> int:
	var s: int = multiplayer.get_remote_sender_id()
	return multiplayer.get_unique_id() if s == 0 else s


func _record_world_pos(rec: Dictionary) -> Vector3:
	var pos_arr: Array = rec.get("position", [0.0, 0.0, 0.0]) as Array
	if pos_arr.size() == 3:
		return Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	return Vector3.ZERO


func _record_chunk_key(rec: Dictionary) -> String:
	if rec.has("chunk_x") and rec.has("chunk_z"):
		return "%d,%d" % [int(rec["chunk_x"]), int(rec["chunk_z"])]
	return GameConfig.chunk_key(GameConfig.world_to_chunk(_record_world_pos(rec)))


func _index_record(rec: Dictionary) -> void:
	var bid: int = int(rec.get("id", -1))
	var ckey: String = _record_chunk_key(rec)
	_building_records[bid] = rec
	if not _chunk_building_ids.has(ckey):
		_chunk_building_ids[ckey] = []
	var arr: Array = _chunk_building_ids[ckey] as Array
	if not arr.has(bid):
		arr.append(bid)


func _unindex_record(bid: int) -> void:
	if _building_records.has(bid):
		var ckey: String = _record_chunk_key(_building_records[bid] as Dictionary)
		if _chunk_building_ids.has(ckey):
			(_chunk_building_ids[ckey] as Array).erase(bid)
		_building_records.erase(bid)


func _load_persisted_buildings() -> void:
	var records: Array = DatabaseManager.get_buildings()
	for rec_var: Variant in records:
		var rec: Dictionary = rec_var as Dictionary
		_index_record(rec)
		_spawn_local_building(rec)


func sync_all_to_peer(peer_id: int) -> void:
	if not NetworkManager.is_server_running():
		return
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	var center_pos: Vector3 = Vector3.ZERO
	if wa != null and wa.has_method("server_get_player_position"):
		center_pos = wa.call("server_get_player_position", peer_id) as Vector3
	var center_chunk: Vector2i = GameConfig.world_to_chunk(center_pos)
	_server_send_chunks_to_peer(peer_id, center_chunk, GameConfig.FLIGHT_CHUNK_RADIUS + 1)


func request_chunks_around(center_chunk: Vector2i, radius: int) -> void:
	if NetworkManager.is_server_running():
		_client_prune_distant_buildings(center_chunk, radius + 2)
		_server_send_chunks_to_peer(multiplayer.get_unique_id(), center_chunk, radius)
	else:
		_client_prune_distant_buildings(center_chunk, radius + 2)
		_rpc_request_chunks_around.rpc_id(1, center_chunk, mini(radius, 5))


@rpc("any_peer", "reliable")
func _rpc_request_chunks_around(center_chunk: Vector2i, radius: int) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	_server_send_chunks_to_peer(sender_id, center_chunk, clampi(radius, 1, 5))


func _server_send_chunks_to_peer(peer_id: int, center_chunk: Vector2i, radius: int) -> void:
	var payload: Array = []
	for dz: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var ckey: String = GameConfig.chunk_key(Vector2i(center_chunk.x + dx, center_chunk.y + dz))
			if _chunk_building_ids.has(ckey):
				for bid_var: Variant in (_chunk_building_ids[ckey] as Array):
					var bid: int = int(bid_var)
					if _building_records.has(bid):
						payload.append(_building_records[bid])
	if payload.is_empty():
		return
	if peer_id == multiplayer.get_unique_id():
		_apply_chunk_buildings(payload)
	else:
		_rpc_sync_chunk_buildings.rpc_id(peer_id, payload)


@rpc("authority", "reliable")
func _rpc_sync_chunk_buildings(records: Array) -> void:
	_apply_chunk_buildings(records)


func _apply_chunk_buildings(records: Array) -> void:
	for rec_var: Variant in records:
		var rec: Dictionary = rec_var as Dictionary
		var bid: int = int(rec.get("id", -1))
		_index_record(rec)
		if not _building_nodes.has(bid):
			_spawn_local_building(rec)


func _client_prune_distant_buildings(center_chunk: Vector2i, keep_radius: int) -> void:
	# Dedicated/Host server keeps authoritative nodes or recreates on demand; only prune pure clients
	if NetworkManager.is_server_running():
		return
	var to_free: Array[int] = []
	for bid_var: Variant in _building_nodes.keys():
		var bid: int = int(bid_var)
		if not _building_records.has(bid):
			continue
		var rec: Dictionary = _building_records[bid] as Dictionary
		var ccoord: Vector2i = Vector2i(int(rec.get("chunk_x", 0)), int(rec.get("chunk_z", 0)))
		if maxi(absi(ccoord.x - center_chunk.x), absi(ccoord.y - center_chunk.y)) > keep_radius:
			to_free.append(bid)
	for bid: int in to_free:
		var bp: BuildPiece = _building_nodes[bid] as BuildPiece
		if is_instance_valid(bp):
			bp.queue_free()
		_building_nodes.erase(bid)


func request_place_building(piece_type: String, world_pos: Vector3, rotation_y: float) -> void:
	_rpc_request_place_building.rpc_id(1, piece_type, world_pos, rotation_y)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_place_building(piece_type: String, world_pos: Vector3, rotation_y: float) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var key: String = NetworkManager.get_peer_username_key(sender_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	if acc.is_empty() or not GameConfig.BUILD_PIECES.has(piece_type):
		return

	var ground_y: float = GameConfig.sample_terrain_height(world_pos.x, world_pos.z)
	if ground_y < GameConfig.WATER_LEVEL + 0.1:
		return

	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	var is_creator_divine: bool = GameConfig.is_avatar_role(str(acc.get("role", "")))
	if wa != null and wa.has_method("server_get_player_position"):
		var ppos: Vector3 = wa.call("server_get_player_position", sender_id) as Vector3
		if not is_creator_divine and ppos.distance_to(world_pos) > 26.0:
			return

	var spec: Dictionary = GameConfig.BUILD_PIECES[piece_type] as Dictionary
	var cost: Dictionary = spec.get("cost", {}) as Dictionary
	if not is_creator_divine:
		if not DatabaseManager.consume_items(key, cost):
			NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Construcción", "Sistema", "No tenés recursos suficientes.", "#ff8888")
			return
		NetworkManager.push_profile_to_peer(sender_id)

	var bid: int = DatabaseManager.allocate_building_id()
	var max_hp: float = float(spec.get("max_hp", 400.0))
	var ccoord: Vector2i = GameConfig.world_to_chunk(world_pos)
	var record: Dictionary = {
		"id": bid,
		"chunk_x": ccoord.x,
		"chunk_z": ccoord.y,
		"piece_type": piece_type,
		"owner": str(acc.get("username", "")),
		"guild_id": str(acc.get("guild_id", "")),
		"position": [world_pos.x, ground_y, world_pos.z],
		"rotation_y": rotation_y,
		"hp": max_hp,
		"max_hp": max_hp,
		"is_open": false
	}
	DatabaseManager.add_building_record(record)
	_index_record(record)
	_rpc_spawn_building.rpc(record)

	if piece_type == "altar_order" or piece_type == "altar_chaos":
		var label: String = str(spec.get("name", piece_type))
		NetworkManager.broadcast_system_message("%s ha erigido un %s en (%d, %d)." % [
			str(acc.get("username", "")),
			label,
			int(world_pos.x),
			int(world_pos.z)
		], "#ffd866" if piece_type == "altar_order" else "#ff6b4a")


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_building(record: Dictionary) -> void:
	_index_record(record)
	_spawn_local_building(record)


func _spawn_local_building(record: Dictionary) -> void:
	if _buildings_container == null:
		_buildings_container = get_node_or_null(buildings_container_path) as Node3D
	if _buildings_container == null:
		return
	var bid: int = int(record.get("id", -1))
	if _building_nodes.has(bid):
		return
	var piece: BuildPiece = BUILD_PIECE_SCENE.instantiate() as BuildPiece
	_buildings_container.add_child(piece)
	piece.setup_from_record(record)
	_building_nodes[bid] = piece


func request_toggle_gate(building_id: int) -> void:
	_rpc_toggle_gate.rpc_id(1, building_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_toggle_gate(building_id: int) -> void:
	if not NetworkManager.is_server_running():
		return
	if not _building_records.has(building_id):
		return
	var rec: Dictionary = _building_records[building_id] as Dictionary
	if str(rec.get("piece_type", "")) != "gate":
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = DatabaseManager.get_account_mutable(NetworkManager.get_peer_username_key(sender_id))
	if acc.is_empty():
		return
	var uname: String = str(acc.get("username", ""))
	var is_owner: bool = uname == str(rec.get("owner", ""))
	var same_guild: bool = not str(rec.get("guild_id", "")).is_empty() and str(acc.get("guild_id", "")) == str(rec.get("guild_id", ""))
	var is_avatar: bool = GameConfig.is_avatar_role(str(acc.get("role", "")))
	var breached: bool = float(rec.get("hp", 100.0)) < float(rec.get("max_hp", 100.0)) * 0.25
	if not (is_owner or same_guild or is_avatar or breached):
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Puerta", "Sistema", "Esta puerta pertenece a %s. Solo su reino puede abrirla (o derribala en asedio)." % str(rec.get("owner", "")), "#ffaa66")
		return
	var new_open: bool = not bool(rec.get("is_open", false))
	rec["is_open"] = new_open
	DatabaseManager.mark_dirty()
	_rpc_update_gate_state.rpc(building_id, new_open)


@rpc("authority", "call_local", "reliable")
func _rpc_update_gate_state(building_id: int, open_state: bool) -> void:
	if _building_records.has(building_id):
		(_building_records[building_id] as Dictionary)["is_open"] = open_state
	if _building_nodes.has(building_id):
		var bp: BuildPiece = _building_nodes[building_id] as BuildPiece
		bp.set_gate_open(open_state)


func server_damage_building(building_id: int, damage: float, attacker_name: String) -> void:
	if not NetworkManager.is_server_running() or not _building_records.has(building_id):
		return
	var rec: Dictionary = _building_records[building_id] as Dictionary
	var new_hp: float = maxf(0.0, float(rec.get("hp", 100.0)) - damage)
	rec["hp"] = new_hp
	DatabaseManager.mark_dirty()
	if new_hp <= 0.0:
		var spec: Dictionary = GameConfig.BUILD_PIECES.get(str(rec.get("piece_type", "")), {}) as Dictionary
		var bname: String = str(spec.get("name", "Estructura"))
		var owner_name: String = str(rec.get("owner", ""))
		var ckey: String = _record_chunk_key(rec)
		DatabaseManager.remove_building_record(building_id, ckey)
		_unindex_record(building_id)
		_rpc_destroy_building.rpc(building_id)
		NetworkManager.broadcast_system_message("¡ASEDIO! %s destruyó %s de %s." % [attacker_name, bname, owner_name], "#ff6b4a")
	else:
		_rpc_update_building_hp.rpc(building_id, new_hp)


func server_damage_buildings_in_radius(world_center: Vector3, radius: float, damage: float, attacker_name: String) -> void:
	if not NetworkManager.is_server_running():
		return
	var center_chunk: Vector2i = GameConfig.world_to_chunk(world_center)
	var hit_ids: Array[int] = []
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var ckey: String = GameConfig.chunk_key(Vector2i(center_chunk.x + dx, center_chunk.y + dz))
			if not _chunk_building_ids.has(ckey):
				continue
			for bid_var: Variant in (_chunk_building_ids[ckey] as Array):
				var bid: int = int(bid_var)
				if _building_records.has(bid):
					var bpos: Vector3 = _record_world_pos(_building_records[bid] as Dictionary)
					if bpos.distance_to(world_center) <= radius + 2.8:
						hit_ids.append(bid)
	for bid: int in hit_ids:
		server_damage_building(bid, damage, attacker_name)


func server_admin_repair_nearest(world_pos: Vector3) -> String:
	var best_id: int = -1
	var best_dist: float = 24.0
	for bid_var: Variant in _building_records.keys():
		var bid: int = int(bid_var)
		var bpos: Vector3 = _record_world_pos(_building_records[bid] as Dictionary)
		var d: float = bpos.distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best_id = bid
	if best_id == -1:
		return "No hay estructuras cerca para reparar."
	var rec: Dictionary = _building_records[best_id] as Dictionary
	var max_hp: float = float(rec.get("max_hp", 400.0))
	rec["hp"] = max_hp
	DatabaseManager.mark_dirty()
	_rpc_update_building_hp.rpc(best_id, max_hp)
	return "Estructura #%d reparada al 100%%." % best_id


@rpc("authority", "call_local", "reliable")
func _rpc_update_building_hp(building_id: int, new_hp: float) -> void:
	if _building_records.has(building_id):
		(_building_records[building_id] as Dictionary)["hp"] = new_hp
	if _building_nodes.has(building_id):
		var bp: BuildPiece = _building_nodes[building_id] as BuildPiece
		bp.update_hp(new_hp)


@rpc("authority", "call_local", "reliable")
func _rpc_destroy_building(building_id: int) -> void:
	_unindex_record(building_id)
	if _building_nodes.has(building_id):
		var bp: BuildPiece = _building_nodes[building_id] as BuildPiece
		if is_instance_valid(bp):
			bp.queue_free()
		_building_nodes.erase(building_id)
