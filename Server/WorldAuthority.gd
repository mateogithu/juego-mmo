class_name WorldAuthority
extends Node

## Server-authoritative MMORPG simulation for the Infinite Procedural Open World:
## - Syncs world_seed so all players see identical infinite terrain & resource veins
## - Skill-based PvP combat with zero level-gating, iframes dodge, directional block, and class magic
## - Gracia Combativa x2.0 (+100%) multiplicative stat scaling stacked over all active buffs
## - Chunk-delta persisted PvP loot chests (non-cosmetic inventory + gold) & player bounty payouts
## - Creator Avatar (AVATAR_ORDEN / AVATAR_CAOS) live GM commands

signal local_player_ready(player: PlayerController)
signal world_time_updated(time_of_day: float)
signal world_seed_synced(seed_val: int)
signal resource_state_changed(resource_key: String, charges: int, depleted: bool)
signal player_roster_updated(usernames: PackedStringArray)

const PLAYER_SCENE: PackedScene = preload("res://Client/Entities/PlayerCharacter.tscn")
const DRAGON_SCENE: PackedScene = preload("res://Client/Entities/DragonMount.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://Client/Entities/MagicProjectile.tscn")
const LOOT_SCENE: PackedScene = preload("res://Client/Entities/LootCorpse.tscn")

@export var players_container_path: NodePath = NodePath("../Players")
@export var dragons_container_path: NodePath = NodePath("../Dragons")
@export var projectiles_container_path: NodePath = NodePath("../Projectiles")
@export var loot_container_path: NodePath = NodePath("../LootContainer")

var _players_container: Node3D = null
var _dragons_container: Node3D = null
var _projectiles_container: Node3D = null
var _loot_container: Node3D = null

var player_nodes: Dictionary = {} # peer_id -> PlayerController
var dragon_nodes: Dictionary = {} # peer_id -> DragonController
var loot_nodes: Dictionary = {} # loot_id -> LootCorpse

# Synced resource delta states ("chunk_x,chunk_z:slot" -> {charges, depleted, respawn_at})
var known_resource_states: Dictionary = {}

# Authoritative server-only combat/runtime state per peer_id
var _server_states: Dictionary = {}
var _server_loot: Dictionary = {} # loot_id -> record dict
var _next_proj_id: int = 1

var world_time_of_day: float = 0.28
var _regen_accum: float = 0.0
var _time_sync_accum: float = 0.0
var _pos_save_accum: float = 0.0
var _grace_scheduler: CombatGraceScheduler = null
var _building_auth: BuildingAuthority = null


func _ready() -> void:
	add_to_group("world_authority")
	_players_container = get_node_or_null(players_container_path) as Node3D
	_dragons_container = get_node_or_null(dragons_container_path) as Node3D
	_projectiles_container = get_node_or_null(projectiles_container_path) as Node3D
	_loot_container = get_node_or_null(loot_container_path) as Node3D
	_grace_scheduler = get_tree().get_first_node_in_group("combat_grace_scheduler") as CombatGraceScheduler
	_building_auth = get_tree().get_first_node_in_group("building_authority") as BuildingAuthority

	if NetworkManager.is_server_running():
		_load_persisted_loot_chests()
		NetworkManager.peer_session_ended.connect(_on_peer_session_ended)
		if not NetworkManager.is_dedicated_server():
			var host_id: int = multiplayer.get_unique_id()
			_server_spawn_player_for_peer(host_id)
	else:
		_rpc_client_world_ready.rpc_id(1)


func _get_sender_id() -> int:
	var s: int = multiplayer.get_remote_sender_id()
	return multiplayer.get_unique_id() if s == 0 else s


func _load_persisted_loot_chests() -> void:
	var records: Array = DatabaseManager.get_all_loot_records()
	for rec_var: Variant in records:
		var rec: Dictionary = rec_var as Dictionary
		var lid: int = int(rec.get("id", -1))
		if lid <= 0:
			continue
		var pos_arr: Array = rec.get("position", [0.0, 1.5, 0.0]) as Array
		var wp: Vector3 = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])) if pos_arr.size() == 3 else Vector3.ZERO
		_server_loot[lid] = rec
		_spawn_local_loot(lid, str(rec.get("victim", "")), wp, int(rec.get("gold", 0)), rec.get("items", {}) as Dictionary)


func _process(delta: float) -> void:
	world_time_of_day = fmod(world_time_of_day + delta / GameConfig.DAY_CYCLE_DURATION_SEC, 1.0)
	world_time_updated.emit(world_time_of_day)

	if not NetworkManager.is_server_running():
		return

	_regen_accum += delta
	if _regen_accum >= 0.5:
		_server_tick_vitals(_regen_accum)
		_server_tick_resource_respawns()
		_regen_accum = 0.0

	_time_sync_accum += delta
	if _time_sync_accum >= 5.0:
		_time_sync_accum = 0.0
		_rpc_sync_world_time.rpc(world_time_of_day)

	_pos_save_accum += delta
	if _pos_save_accum >= 10.0:
		_pos_save_accum = 0.0
		for pid_var: Variant in _server_states.keys():
			var pid: int = int(pid_var)
			var st: Dictionary = _server_states[pid] as Dictionary
			var pos_arr: Array = st.get("position", [0.0, 2.0, 0.0]) as Array
			if pos_arr.size() == 3:
				DatabaseManager.update_player_position(str(st.get("username", "")), Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])))


# --- Infinite Deterministic Chunk Resource Respawn Deltas ---

func _server_tick_resource_respawns() -> void:
	var now: float = Time.get_unix_time_from_system()
	var restored: Array[String] = []
	for rkey_var: Variant in known_resource_states.keys():
		var rkey: String = str(rkey_var)
		var r: Dictionary = known_resource_states[rkey] as Dictionary
		if bool(r.get("depleted", false)) and now >= float(r.get("respawn_at", 0.0)):
			restored.append(rkey)
	for rkey: String in restored:
		known_resource_states.erase(rkey)
		_rpc_update_resource_state.rpc(rkey, 5, false)


# --- Player Join / Spawn / Stat Computation ---

@rpc("any_peer", "reliable")
func _rpc_client_world_ready() -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	if NetworkManager.get_peer_username_key(sender_id).is_empty():
		return
	_server_spawn_player_for_peer(sender_id)


func _server_spawn_player_for_peer(peer_id: int) -> void:
	var profile: Dictionary = NetworkManager.get_peer_profile(peer_id)
	if profile.is_empty():
		return
	var pos_arr: Array = profile.get("position", [0.0, 2.0, 0.0]) as Array
	var spawn_pos: Vector3 = Vector3(0.0, GameConfig.sample_terrain_height(0.0, 0.0) + 1.5, 0.0)
	if pos_arr.size() == 3:
		var px: float = float(pos_arr[0])
		var pz: float = float(pos_arr[2])
		var gy: float = GameConfig.sample_terrain_height(px, pz)
		spawn_pos = Vector3(px, maxf(float(pos_arr[1]), gy + 0.5), pz)

	# Sync world_seed first so client builds identical infinite terrain
	if peer_id != multiplayer.get_unique_id():
		_rpc_sync_world_seed.rpc_id(peer_id, GameConfig.world_seed)
	else:
		world_seed_synced.emit(GameConfig.world_seed)

	var state: Dictionary = _build_initial_server_state(peer_id, profile, spawn_pos)
	_server_states[peer_id] = state
	_recompute_stats(state, profile, true)

	_rpc_spawn_player.rpc(peer_id, _pack_public_state(state))

	if peer_id != multiplayer.get_unique_id():
		for other_pid_var: Variant in _server_states.keys():
			var other_pid: int = int(other_pid_var)
			if other_pid != peer_id:
				_rpc_spawn_player.rpc_id(peer_id, other_pid, _pack_public_state(_server_states[other_pid] as Dictionary))
				var ost: Dictionary = _server_states[other_pid] as Dictionary
				if bool(ost.get("has_dragon", false)):
					_rpc_spawn_or_update_dragon.rpc_id(
						peer_id,
						other_pid,
						str(ost.get("dragon_skin", "crimson_wyrm")),
						str(ost.get("trail_id", "none")),
						bool(ost.get("has_combat_grace", false)),
						ost.get("dragon_pos", Vector3.ZERO) as Vector3,
						bool(ost.get("is_mounted", false))
					)
		for lid_var: Variant in _server_loot.keys():
			var lrec: Dictionary = _server_loot[lid_var] as Dictionary
			var lp_arr: Array = lrec.get("position", [0.0, 1.5, 0.0]) as Array
			var lpos: Vector3 = Vector3(float(lp_arr[0]), float(lp_arr[1]), float(lp_arr[2])) if lp_arr.size() == 3 else Vector3.ZERO
			_rpc_spawn_loot.rpc_id(peer_id, int(lrec["id"]), str(lrec["victim"]), lpos, int(lrec["gold"]), lrec["items"] as Dictionary)
		for rkey_var: Variant in known_resource_states.keys():
			var rkey: String = str(rkey_var)
			var rrec: Dictionary = known_resource_states[rkey] as Dictionary
			_rpc_update_resource_state.rpc_id(peer_id, rkey, int(rrec.get("charges", 5)), bool(rrec.get("depleted", false)))
		_rpc_sync_world_time.rpc_id(peer_id, world_time_of_day)

	if _building_auth != null:
		_building_auth.sync_all_to_peer(peer_id)
	if _grace_scheduler != null:
		_grace_scheduler.sync_to_peer(peer_id)

	NetworkManager.push_profile_to_peer(peer_id)
	_broadcast_roster()


@rpc("authority", "reliable")
func _rpc_sync_world_seed(seed_val: int) -> void:
	world_seed_synced.emit(seed_val)


func _on_peer_session_ended(peer_id: int, _username: String) -> void:
	if _server_states.has(peer_id):
		var st: Dictionary = _server_states[peer_id] as Dictionary
		var pos_arr: Array = st.get("position", [0.0, 2.0, 0.0]) as Array
		if pos_arr.size() == 3:
			DatabaseManager.update_player_position(str(st.get("username", "")), Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])))
		_server_states.erase(peer_id)
	_rpc_despawn_player.rpc(peer_id)
	_broadcast_roster()


func _broadcast_roster() -> void:
	if not NetworkManager.is_server_running():
		return
	var names: PackedStringArray = PackedStringArray(NetworkManager.get_connected_usernames())
	_rpc_update_roster.rpc(names)


@rpc("authority", "call_local", "reliable")
func _rpc_update_roster(names: PackedStringArray) -> void:
	player_roster_updated.emit(names)


func _build_initial_server_state(peer_id: int, profile: Dictionary, pos: Vector3) -> Dictionary:
	var cos: Dictionary = profile.get("cosmetics", {}) as Dictionary
	var uname: String = str(profile.get("username", "Viajero"))
	var has_grace: bool = _grace_scheduler != null and _grace_scheduler.is_player_blessed(uname)
	return {
		"peer_id": peer_id,
		"username": uname,
		"role": str(profile.get("role", GameConfig.ROLE_PLAYER)),
		"class_id": str(profile.get("class_id", "ARCANE_KNIGHT")),
		"philosophy": str(profile.get("philosophy", GameConfig.PHILOSOPHY_NEUTRAL)),
		"armor_skin": str(cos.get("equipped_armor", "default_iron")),
		"dragon_skin": str(cos.get("equipped_dragon", "crimson_wyrm")),
		"trail_id": str(cos.get("equipped_trail", "none")),
		"position": [pos.x, pos.y, pos.z],
		"yaw": 0.0,
		"max_hp": 120.0,
		"hp": 120.0,
		"max_mana": 100.0,
		"mana": 100.0,
		"max_stamina": 100.0,
		"stamina": 100.0,
		"attack_power": 20.0,
		"spell_power": 20.0,
		"defense": 10.0,
		"shield_hp": 0.0,
		"shield_until": 0.0,
		"buff_mult": 1.0,
		"buff_until": 0.0,
		"favor_mult": 1.0,
		"favor_until": 0.0,
		"iframe_until": 0.0,
		"stealth_until": 0.0,
		"is_blocking": false,
		"is_divine_form": false,
		"has_combat_grace": has_grace,
		"has_dragon": false,
		"is_mounted": false,
		"dragon_pos": pos,
		"last_attack_at": 0.0
	}


func _recompute_stats(st: Dictionary, profile: Dictionary, fill_vitals: bool = false) -> void:
	var class_def: Dictionary = GameConfig.CLASSES.get(str(st.get("class_id", "ARCANE_KNIGHT")), GameConfig.CLASSES["ARCANE_KNIGHT"]) as Dictionary
	var now: float = Time.get_unix_time_from_system()

	var base_hp: float = float(class_def.get("max_hp", 120.0))
	var base_mana: float = float(class_def.get("max_mana", 100.0))
	var base_stam: float = float(class_def.get("max_stamina", 100.0))
	var base_atk: float = float(class_def.get("attack_power", 20.0))
	var base_spl: float = float(class_def.get("spell_power", 20.0))
	var base_def: float = float(class_def.get("defense", 10.0))

	var w_id: String = str(profile.get("equipped_weapon", ""))
	if GameConfig.ITEMS.has(w_id):
		var w_def: Dictionary = GameConfig.ITEMS[w_id] as Dictionary
		base_atk += float(w_def.get("atk_bonus", 0.0))
		base_spl += float(w_def.get("spell_bonus", 0.0))
	var a_id: String = str(profile.get("equipped_armor_item", ""))
	if GameConfig.ITEMS.has(a_id):
		var a_def: Dictionary = GameConfig.ITEMS[a_id] as Dictionary
		base_def += float(a_def.get("def_bonus", 0.0))
		base_hp += float(a_def.get("hp_bonus", 0.0))

	var stack_mult: float = 1.0
	if now < float(st.get("buff_until", 0.0)):
		stack_mult *= float(st.get("buff_mult", 1.0))
	if now < float(st.get("favor_until", 0.0)):
		stack_mult *= float(st.get("favor_mult", 1.0))

	# GRACIA COMBATIVA: +100% (x2.0) to ALL stats stacking over all other active buffs
	var has_grace: bool = _grace_scheduler != null and _grace_scheduler.is_player_blessed(str(st.get("username", "")))
	st["has_combat_grace"] = has_grace
	var grace_mult: float = GameConfig.COMBAT_GRACE_MULTIPLIER if has_grace else 1.0
	var total_mult: float = stack_mult * grace_mult

	var hp_ratio: float = clampf(float(st.get("hp", base_hp)) / maxf(1.0, float(st.get("max_hp", base_hp))), 0.0, 1.0)
	st["max_hp"] = base_hp * total_mult
	st["max_mana"] = base_mana * total_mult
	st["max_stamina"] = base_stam * total_mult
	st["attack_power"] = base_atk * total_mult
	st["spell_power"] = base_spl * total_mult
	st["defense"] = base_def * total_mult

	if fill_vitals:
		st["hp"] = st["max_hp"]
		st["mana"] = st["max_mana"]
		st["stamina"] = st["max_stamina"]
	else:
		st["hp"] = clampf(hp_ratio * float(st["max_hp"]), 1.0, float(st["max_hp"]))
		st["mana"] = minf(float(st["mana"]), float(st["max_mana"]))
		st["stamina"] = minf(float(st["stamina"]), float(st["max_stamina"]))


func _pack_public_state(st: Dictionary) -> Dictionary:
	var now: float = Time.get_unix_time_from_system()
	return {
		"username": st.get("username", ""),
		"role": st.get("role", GameConfig.ROLE_PLAYER),
		"class_id": st.get("class_id", "ARCANE_KNIGHT"),
		"philosophy": st.get("philosophy", GameConfig.PHILOSOPHY_NEUTRAL),
		"armor_skin": st.get("armor_skin", "default_iron"),
		"dragon_skin": st.get("dragon_skin", "crimson_wyrm"),
		"trail_id": st.get("trail_id", "none"),
		"position": st.get("position", [0.0, 2.0, 0.0]),
		"max_hp": st.get("max_hp", 120.0),
		"hp": st.get("hp", 120.0),
		"max_mana": st.get("max_mana", 100.0),
		"mana": st.get("mana", 100.0),
		"max_stamina": st.get("max_stamina", 100.0),
		"stamina": st.get("stamina", 100.0),
		"shield_hp": st.get("shield_hp", 0.0),
		"has_combat_grace": st.get("has_combat_grace", false),
		"is_divine_form": st.get("is_divine_form", false),
		"is_stealthed": now < float(st.get("stealth_until", 0.0))
	}


func server_recalculate_player_stats(peer_id: int) -> void:
	if not NetworkManager.is_server_running() or not _server_states.has(peer_id):
		return
	var st: Dictionary = _server_states[peer_id] as Dictionary
	var profile: Dictionary = NetworkManager.get_peer_profile(peer_id)
	_recompute_stats(st, profile, false)
	_rpc_update_player_state.rpc(peer_id, _pack_public_state(st))


func server_refresh_player_cosmetics(peer_id: int) -> void:
	if not NetworkManager.is_server_running() or not _server_states.has(peer_id):
		return
	var st: Dictionary = _server_states[peer_id] as Dictionary
	var profile: Dictionary = NetworkManager.get_peer_profile(peer_id)
	var cos: Dictionary = profile.get("cosmetics", {}) as Dictionary
	st["armor_skin"] = str(cos.get("equipped_armor", "default_iron"))
	st["dragon_skin"] = str(cos.get("equipped_dragon", "crimson_wyrm"))
	st["trail_id"] = str(cos.get("equipped_trail", "none"))
	st["philosophy"] = str(profile.get("philosophy", GameConfig.PHILOSOPHY_NEUTRAL))
	_rpc_update_player_state.rpc(peer_id, _pack_public_state(st))
	if bool(st.get("has_dragon", false)):
		_rpc_update_dragon_cosmetics.rpc(peer_id, str(st["dragon_skin"]), str(st["trail_id"]), bool(st.get("has_combat_grace", false)))


func server_on_combat_grace_changed(old_user: String, new_user: String) -> void:
	if not NetworkManager.is_server_running():
		return
	for pid_var: Variant in _server_states.keys():
		var pid: int = int(pid_var)
		var st: Dictionary = _server_states[pid] as Dictionary
		var uname: String = str(st.get("username", ""))
		if uname.to_lower() == old_user.to_lower() or uname.to_lower() == new_user.to_lower():
			var profile: Dictionary = NetworkManager.get_peer_profile(pid)
			var is_new_blessed: bool = uname.to_lower() == new_user.to_lower() and not new_user.is_empty()
			_recompute_stats(st, profile, is_new_blessed)
			_rpc_update_player_state.rpc(pid, _pack_public_state(st))
			if bool(st.get("has_dragon", false)):
				_rpc_update_dragon_cosmetics.rpc(pid, str(st["dragon_skin"]), str(st["trail_id"]), bool(st.get("has_combat_grace", false)))


func server_get_player_position(peer_id: int) -> Vector3:
	if not _server_states.has(peer_id):
		return Vector3.ZERO
	var arr: Array = (_server_states[peer_id] as Dictionary).get("position", [0.0, 0.0, 0.0]) as Array
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func server_consume_item(peer_id: int, item_id: String) -> bool:
	if not _server_states.has(peer_id) or not GameConfig.ITEMS.has(item_id):
		return false
	var st: Dictionary = _server_states[peer_id] as Dictionary
	var item_def: Dictionary = GameConfig.ITEMS[item_id] as Dictionary
	if item_def.has("heal"):
		st["hp"] = minf(float(st["max_hp"]), float(st["hp"]) + float(item_def["heal"]))
		_rpc_update_player_state.rpc(peer_id, _pack_public_state(st))
		return true
	if item_def.has("mana"):
		st["mana"] = minf(float(st["max_mana"]), float(st["mana"]) + float(item_def["mana"]))
		_rpc_update_player_state.rpc(peer_id, _pack_public_state(st))
		return true
	if item_def.has("siege_damage") and _building_auth != null:
		var pos: Vector3 = server_get_player_position(peer_id)
		_building_auth.server_damage_buildings_in_radius(pos, 7.5, float(item_def["siege_damage"]), str(st.get("username", "")))
		return true
	return false


func _server_tick_vitals(dt: float) -> void:
	var now: float = Time.get_unix_time_from_system()
	for pid_var: Variant in _server_states.keys():
		var pid: int = int(pid_var)
		var st: Dictionary = _server_states[pid] as Dictionary
		var grace_bonus: float = 2.0 if bool(st.get("has_combat_grace", false)) else 1.0
		var dirty: bool = false

		if float(st["hp"]) < float(st["max_hp"]):
			st["hp"] = minf(float(st["max_hp"]), float(st["hp"]) + 2.2 * grace_bonus * dt)
			dirty = true
		if float(st["mana"]) < float(st["max_mana"]):
			st["mana"] = minf(float(st["max_mana"]), float(st["mana"]) + 6.5 * grace_bonus * dt)
			dirty = true
		if not bool(st.get("is_blocking", false)) and float(st["stamina"]) < float(st["max_stamina"]):
			st["stamina"] = minf(float(st["max_stamina"]), float(st["stamina"]) + 16.0 * grace_bonus * dt)
			dirty = true
		if float(st["shield_hp"]) > 0.0 and now >= float(st.get("shield_until", 0.0)):
			st["shield_hp"] = 0.0
			dirty = true
		if float(st.get("buff_until", 0.0)) > 0.0 and now >= float(st["buff_until"]):
			st["buff_until"] = 0.0
			st["buff_mult"] = 1.0
			_recompute_stats(st, NetworkManager.get_peer_profile(pid), false)
			dirty = true
		if float(st.get("favor_until", 0.0)) > 0.0 and now >= float(st["favor_until"]):
			st["favor_until"] = 0.0
			st["favor_mult"] = 1.0
			_recompute_stats(st, NetworkManager.get_peer_profile(pid), false)
			dirty = true

		if dirty:
			_rpc_update_player_vitals.rpc(pid, float(st["hp"]), float(st["max_hp"]), float(st["mana"]), float(st["max_mana"]), float(st["stamina"]), float(st["max_stamina"]), float(st["shield_hp"]), now < float(st.get("stealth_until", 0.0)))


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_player(peer_id: int, state: Dictionary) -> void:
	if player_nodes.has(peer_id):
		(player_nodes[peer_id] as PlayerController).apply_full_state(state)
		return
	var pc: PlayerController = PLAYER_SCENE.instantiate() as PlayerController
	_players_container.add_child(pc)
	var is_local: bool = (not NetworkManager.is_dedicated_server()) and (peer_id == multiplayer.get_unique_id())
	pc.setup_player(peer_id, is_local, state)
	player_nodes[peer_id] = pc
	if is_local:
		local_player_ready.emit(pc)


@rpc("authority", "call_local", "reliable")
func _rpc_despawn_player(peer_id: int) -> void:
	if player_nodes.has(peer_id):
		var pc: PlayerController = player_nodes[peer_id] as PlayerController
		if is_instance_valid(pc):
			pc.queue_free()
		player_nodes.erase(peer_id)
	if dragon_nodes.has(peer_id):
		var dc: DragonController = dragon_nodes[peer_id] as DragonController
		if is_instance_valid(dc):
			dc.queue_free()
		dragon_nodes.erase(peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_update_player_state(peer_id: int, state: Dictionary) -> void:
	if player_nodes.has(peer_id):
		var pc: PlayerController = player_nodes[peer_id] as PlayerController
		var saved_pos: Vector3 = pc.global_position
		pc.apply_full_state(state)
		if pc.is_local:
			pc.global_position = saved_pos


@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_update_player_vitals(peer_id: int, hp: float, max_hp: float, mana: float, max_mana: float, stamina: float, max_stamina: float, shield_hp: float, stealthed: bool) -> void:
	if not player_nodes.has(peer_id):
		return
	var pc: PlayerController = player_nodes[peer_id] as PlayerController
	pc.hp = hp
	pc.max_hp = max_hp
	pc.mana = mana
	pc.max_mana = max_mana
	pc.stamina = stamina
	pc.max_stamina = max_stamina
	pc.shield_hp = shield_hp
	if pc.is_stealthed != stealthed:
		pc.is_stealthed = stealthed
		pc._apply_status_visuals()
	pc._update_nameplate()


@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_sync_world_time(t: float) -> void:
	world_time_of_day = t
	world_time_updated.emit(world_time_of_day)


# --- Infinite World Coordinate Transform Sync ---

func send_client_transform(world_pos: Vector3, yaw: float, anim_speed: float, attacking: bool, blocking: bool, dodging: bool, mounted: bool, d_world_pos: Vector3, d_rot: Vector3, d_state: int, d_breath: bool) -> void:
	_rpc_client_transform.rpc_id(1, world_pos, yaw, anim_speed, attacking, blocking, dodging, mounted, d_world_pos, d_rot, d_state, d_breath)


@rpc("any_peer", "call_local", "unreliable_ordered")
func _rpc_client_transform(world_pos: Vector3, yaw: float, anim_speed: float, attacking: bool, blocking: bool, dodging: bool, mounted: bool, d_world_pos: Vector3, d_rot: Vector3, d_state: int, d_breath: bool) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	if not _server_states.has(sender_id):
		return
	var st: Dictionary = _server_states[sender_id] as Dictionary
	var safe_pos: Vector3 = Vector3(world_pos.x, clampf(world_pos.y, GameConfig.WATER_LEVEL - 2.0, 260.0), world_pos.z)
	st["position"] = [safe_pos.x, safe_pos.y, safe_pos.z]
	st["yaw"] = yaw
	if mounted and bool(st.get("is_mounted", false)):
		st["dragon_pos"] = d_world_pos
	_rpc_broadcast_transform.rpc(sender_id, safe_pos, yaw, anim_speed, attacking, blocking, dodging, mounted, d_world_pos, d_rot, d_state, d_breath, bool(st.get("has_combat_grace", false)))


@rpc("authority", "call_local", "unreliable_ordered")
func _rpc_broadcast_transform(peer_id: int, world_pos: Vector3, yaw: float, anim_speed: float, attacking: bool, blocking: bool, dodging: bool, mounted: bool, d_world_pos: Vector3, d_rot: Vector3, d_state: int, d_breath: bool, grace: bool) -> void:
	if player_nodes.has(peer_id):
		var pc: PlayerController = player_nodes[peer_id] as PlayerController
		pc.apply_remote_transform(GameConfig.world_to_local(world_pos), yaw, anim_speed, attacking, blocking, dodging)
	if mounted and dragon_nodes.has(peer_id):
		var dc: DragonController = dragon_nodes[peer_id] as DragonController
		dc.apply_network_snapshot(GameConfig.world_to_local(d_world_pos), d_rot, d_state, d_breath, grace)


# --- Skill-Based Combat (Zero Level-Gating) ---

func request_dodge() -> void:
	_rpc_request_dodge.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_dodge() -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	if not _server_states.has(sender_id):
		return
	var st: Dictionary = _server_states[sender_id] as Dictionary
	if float(st["stamina"]) < 22.0:
		return
	st["stamina"] = float(st["stamina"]) - 22.0
	st["iframe_until"] = Time.get_unix_time_from_system() + 0.45


func request_set_blocking(blocking: bool) -> void:
	_rpc_set_blocking.rpc_id(1, blocking)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_blocking(blocking: bool) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	if _server_states.has(sender_id):
		(_server_states[sender_id] as Dictionary)["is_blocking"] = blocking


func request_primary_attack(world_origin: Vector3, aim_dir: Vector3) -> void:
	_rpc_primary_attack.rpc_id(1, world_origin, aim_dir)


@rpc("any_peer", "call_local", "reliable")
func _rpc_primary_attack(world_origin: Vector3, aim_dir: Vector3) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	if not _server_states.has(sender_id):
		return
	var st: Dictionary = _server_states[sender_id] as Dictionary
	var now: float = Time.get_unix_time_from_system()
	if now - float(st.get("last_attack_at", 0.0)) < 0.38:
		return
	st["last_attack_at"] = now
	st["stealth_until"] = 0.0

	var dir: Vector3 = aim_dir.normalized()
	var class_id: String = str(st.get("class_id", "ARCANE_KNIGHT"))
	if class_id == "PYROMANCER":
		var dmg: float = float(st.get("spell_power", 25.0)) * 0.9
		_server_spawn_projectile(sender_id, world_origin + dir * 1.1, dir, 30.0, dmg, 1.5, Color(1.0, 0.5, 0.12), 0.75)
		return

	var melee_dmg: float = float(st.get("attack_power", 20.0))
	var reach: float = 3.8
	for target_pid_var: Variant in _server_states.keys():
		var target_pid: int = int(target_pid_var)
		if target_pid == sender_id:
			continue
		var tpos: Vector3 = server_get_player_position(target_pid) + Vector3(0.0, 1.0, 0.0)
		var to_target: Vector3 = tpos - world_origin
		var dist: float = to_target.length()
		if dist <= reach and to_target.normalized().dot(dir) >= 0.32:
			_server_apply_damage_to_player(target_pid, sender_id, melee_dmg, world_origin)

	if _building_auth != null:
		_building_auth.server_damage_buildings_in_radius(world_origin + dir * 2.4, 2.2, melee_dmg * 0.85, str(st.get("username", "")))


func request_cast_ability(slot: int, world_origin: Vector3, aim_dir: Vector3) -> void:
	_rpc_cast_ability.rpc_id(1, slot, world_origin, aim_dir)


@rpc("any_peer", "call_local", "reliable")
func _rpc_cast_ability(slot: int, world_origin: Vector3, aim_dir: Vector3) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	if not _server_states.has(sender_id):
		return
	var st: Dictionary = _server_states[sender_id] as Dictionary
	var class_def: Dictionary = GameConfig.CLASSES.get(str(st.get("class_id", "")), {}) as Dictionary
	var abilities: Array = class_def.get("abilities", []) as Array
	if slot < 0 or slot >= abilities.size():
		return
	var ab: Dictionary = abilities[slot] as Dictionary
	var cost_m: float = float(ab.get("cost_mana", 0.0))
	var cost_s: float = float(ab.get("cost_stamina", 0.0))
	if float(st["mana"]) < cost_m or float(st["stamina"]) < cost_s:
		return
	st["mana"] = float(st["mana"]) - cost_m
	st["stamina"] = float(st["stamina"]) - cost_s
	var now: float = Time.get_unix_time_from_system()
	var ab_type: String = str(ab.get("type", "projectile"))
	var dir: Vector3 = aim_dir.normalized()
	var grace_mult: float = GameConfig.COMBAT_GRACE_MULTIPLIER if bool(st.get("has_combat_grace", false)) else 1.0
	var spell_scale: float = float(st.get("spell_power", 20.0)) / 20.0

	if ab_type == "projectile":
		st["stealth_until"] = 0.0
		var dmg: float = float(ab.get("damage", 35.0)) * maxf(0.85, spell_scale)
		var splash: float = float(ab.get("splash", 0.0))
		var col: Color = ab.get("color", Color(1.0, 0.5, 0.2)) as Color
		var proj_scale: float = 1.65 if splash >= 4.0 else 1.0
		_server_spawn_projectile(sender_id, world_origin + dir * 1.2, dir, 32.0, dmg, splash, col, proj_scale)
	elif ab_type == "aoe":
		st["stealth_until"] = 0.0
		var dmg: float = float(ab.get("damage", 35.0)) * maxf(0.85, spell_scale)
		var rad: float = float(ab.get("radius", 5.5))
		var caster_pos: Vector3 = server_get_player_position(sender_id)
		for target_pid_var: Variant in _server_states.keys():
			var target_pid: int = int(target_pid_var)
			if target_pid == sender_id:
				continue
			if server_get_player_position(target_pid).distance_to(caster_pos) <= rad:
				_server_apply_damage_to_player(target_pid, sender_id, dmg, caster_pos)
		if _building_auth != null:
			_building_auth.server_damage_buildings_in_radius(caster_pos, rad, dmg * 1.15, str(st.get("username", "")))
		if ab.has("heal"):
			st["hp"] = minf(float(st["max_hp"]), float(st["hp"]) + float(ab["heal"]) * grace_mult)
	elif ab_type == "heal":
		var heal_amt: float = float(ab.get("heal", 50.0)) * grace_mult
		var rad: float = float(ab.get("radius", 8.0))
		var caster_pos: Vector3 = server_get_player_position(sender_id)
		var caster_guild: String = str(NetworkManager.get_peer_profile(sender_id).get("guild_id", ""))
		for target_pid_var: Variant in _server_states.keys():
			var target_pid: int = int(target_pid_var)
			var t_guild: String = str(NetworkManager.get_peer_profile(target_pid).get("guild_id", ""))
			if target_pid == sender_id or (not caster_guild.is_empty() and t_guild == caster_guild):
				if server_get_player_position(target_pid).distance_to(caster_pos) <= rad:
					var tst: Dictionary = _server_states[target_pid] as Dictionary
					tst["hp"] = minf(float(tst["max_hp"]), float(tst["hp"]) + heal_amt)
					_rpc_update_player_state.rpc(target_pid, _pack_public_state(tst))
	elif ab_type == "shield":
		st["shield_hp"] = float(ab.get("shield", 65.0)) * grace_mult
		st["shield_until"] = now + float(ab.get("duration", 6.0))
	elif ab_type == "buff":
		st["buff_mult"] = float(ab.get("buff_mult", 1.25))
		st["buff_until"] = now + float(ab.get("duration", 8.0))
		_recompute_stats(st, NetworkManager.get_peer_profile(sender_id), false)
	elif ab_type == "dash":
		st["iframe_until"] = now + 0.5
	elif ab_type == "stealth":
		st["stealth_until"] = now + float(ab.get("duration", 5.0))

	_rpc_update_player_state.rpc(sender_id, _pack_public_state(st))


func _server_spawn_projectile(owner_peer: int, world_origin: Vector3, dir: Vector3, speed: float, damage: float, splash: float, col: Color, p_scale: float) -> void:
	var pid: int = _next_proj_id
	_next_proj_id += 1
	_rpc_spawn_projectile.rpc(pid, owner_peer, world_origin, dir, speed, damage, splash, col, p_scale)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_projectile(proj_id: int, owner_peer: int, world_origin: Vector3, dir: Vector3, speed: float, damage: float, splash: float, col: Color, p_scale: float) -> void:
	var proj: MagicProjectile = PROJECTILE_SCENE.instantiate() as MagicProjectile
	_projectiles_container.add_child(proj)
	proj.setup(proj_id, owner_peer, world_origin, dir, speed, damage, splash, col, p_scale)


func server_on_projectile_impact(owner_peer: int, world_impact_pos: Vector3, damage: float, splash: float, b_mult: float, hit_body: Node3D) -> void:
	if not NetworkManager.is_server_running() or not _server_states.has(owner_peer):
		return
	var attacker_name: String = str((_server_states[owner_peer] as Dictionary).get("username", ""))
	if hit_body is PlayerController:
		var target_pc: PlayerController = hit_body as PlayerController
		if target_pc.peer_id != owner_peer:
			_server_apply_damage_to_player(target_pc.peer_id, owner_peer, damage, world_impact_pos)
	elif hit_body is BuildPiece and _building_auth != null:
		_building_auth.server_damage_building((hit_body as BuildPiece).building_id, damage * b_mult, attacker_name)

	if splash > 0.2:
		for target_pid_var: Variant in _server_states.keys():
			var target_pid: int = int(target_pid_var)
			if target_pid == owner_peer:
				continue
			if server_get_player_position(target_pid).distance_to(world_impact_pos) <= splash:
				_server_apply_damage_to_player(target_pid, owner_peer, damage * 0.75, world_impact_pos)
		if _building_auth != null:
			_building_auth.server_damage_buildings_in_radius(world_impact_pos, splash, damage * b_mult, attacker_name)


func request_dragon_breath(world_origin: Vector3, aim_dir: Vector3) -> void:
	_rpc_dragon_breath.rpc_id(1, world_origin, aim_dir)


@rpc("any_peer", "call_local", "reliable")
func _rpc_dragon_breath(world_origin: Vector3, aim_dir: Vector3) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	if not _server_states.has(sender_id):
		return
	var st: Dictionary = _server_states[sender_id] as Dictionary
	if not bool(st.get("is_mounted", false)):
		return
	var grace_mult: float = GameConfig.COMBAT_GRACE_MULTIPLIER if bool(st.get("has_combat_grace", false)) else 1.0
	var breath_dmg: float = 22.0 * grace_mult
	var dir: Vector3 = aim_dir.normalized()
	var attacker_name: String = str(st.get("username", ""))

	for target_pid_var: Variant in _server_states.keys():
		var target_pid: int = int(target_pid_var)
		if target_pid == sender_id:
			continue
		var tpos: Vector3 = server_get_player_position(target_pid) + Vector3(0.0, 1.0, 0.0)
		var delta_v: Vector3 = tpos - world_origin
		var dist: float = delta_v.length()
		if dist <= 24.0 and delta_v.normalized().dot(dir) >= 0.76:
			_server_apply_damage_to_player(target_pid, sender_id, breath_dmg, world_origin)

	if _building_auth != null:
		var sample_ground: Vector3 = world_origin + dir * 15.0
		_building_auth.server_damage_buildings_in_radius(sample_ground, 6.5, breath_dmg * 1.4, attacker_name)


func _server_apply_damage_to_player(target_pid: int, attacker_pid: int, raw_damage: float, hit_world_origin: Vector3) -> void:
	if not _server_states.has(target_pid):
		return
	var tst: Dictionary = _server_states[target_pid] as Dictionary
	var now: float = Time.get_unix_time_from_system()

	if now < float(tst.get("iframe_until", 0.0)):
		return
	if bool(tst.get("is_divine_form", false)):
		return

	var defense: float = float(tst.get("defense", 10.0))
	var dmg: float = maxf(4.0, raw_damage - defense * 0.45)

	if bool(tst.get("is_blocking", false)) and float(tst.get("stamina", 0.0)) >= 14.0:
		var yaw: float = float(tst.get("yaw", 0.0))
		var facing: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
		var tpos: Vector3 = server_get_player_position(target_pid)
		var to_hit: Vector3 = Vector3(hit_world_origin.x - tpos.x, 0.0, hit_world_origin.z - tpos.z).normalized()
		if facing.dot(to_hit) >= 0.25:
			dmg *= 0.35
			tst["stamina"] = maxf(0.0, float(tst["stamina"]) - 16.0)

	var shield: float = float(tst.get("shield_hp", 0.0))
	if shield > 0.0:
		var absorbed: float = minf(shield, dmg)
		tst["shield_hp"] = shield - absorbed
		dmg -= absorbed

	tst["hp"] = maxf(0.0, float(tst["hp"]) - dmg)
	if float(tst["hp"]) <= 0.0:
		_server_handle_player_death(target_pid, attacker_pid)
	else:
		_rpc_update_player_state.rpc(target_pid, _pack_public_state(tst))


func _server_handle_player_death(victim_pid: int, killer_pid: int) -> void:
	var vst: Dictionary = _server_states[victim_pid] as Dictionary
	var victim_name: String = str(vst.get("username", ""))
	var killer_name: String = str((_server_states.get(killer_pid, {}) as Dictionary).get("username", "el mundo"))
	var death_pos: Vector3 = server_get_player_position(victim_pid)
	death_pos.y = GameConfig.sample_terrain_height(death_pos.x, death_pos.z) + 0.1

	var acc: Dictionary = DatabaseManager.get_account_mutable(victim_name)
	if not acc.is_empty():
		var inv: Dictionary = acc["inventory"] as Dictionary
		var dropped_items: Dictionary = inv.duplicate(true)
		inv.clear()
		var eq_w: String = str(acc.get("equipped_weapon", ""))
		if not eq_w.is_empty():
			dropped_items[eq_w] = int(dropped_items.get(eq_w, 0)) + 1
			acc["equipped_weapon"] = ""
		var eq_a: String = str(acc.get("equipped_armor_item", ""))
		if not eq_a.is_empty():
			dropped_items[eq_a] = int(dropped_items.get(eq_a, 0)) + 1
			acc["equipped_armor_item"] = ""
		var cur_gold: int = int(acc.get("gold", 0))
		var dropped_gold: int = cur_gold / 2
		acc["gold"] = cur_gold - dropped_gold

		if not dropped_items.is_empty() or dropped_gold > 0:
			var lid: int = DatabaseManager.allocate_loot_id()
			var lrec: Dictionary = {
				"id": lid,
				"victim": victim_name,
				"position": [death_pos.x, death_pos.y, death_pos.z],
				"gold": dropped_gold,
				"items": dropped_items
			}
			DatabaseManager.add_loot_record(lrec)
			_server_loot[lid] = lrec
			_rpc_spawn_loot.rpc(lid, victim_name, death_pos, dropped_gold, dropped_items)

		if killer_pid != victim_pid and _server_states.has(killer_pid):
			_check_bounty_payout(victim_name, killer_pid, killer_name)

		DatabaseManager.mark_dirty()
		DatabaseManager.save_database()
		NetworkManager.push_profile_to_peer(victim_pid)

	if bool(vst.get("is_mounted", false)):
		vst["is_mounted"] = false
		_rpc_set_player_mounted.rpc(victim_pid, false)

	var respawn_x: float = randf_range(-10.0, 10.0)
	var respawn_z: float = randf_range(-10.0, 10.0)
	var respawn_pos: Vector3 = Vector3(respawn_x, GameConfig.sample_terrain_height(respawn_x, respawn_z) + 1.5, respawn_z)
	vst["position"] = [respawn_pos.x, respawn_pos.y, respawn_pos.z]
	_recompute_stats(vst, NetworkManager.get_peer_profile(victim_pid), true)
	_rpc_teleport_player.rpc(victim_pid, respawn_pos)
	_rpc_update_player_state.rpc(victim_pid, _pack_public_state(vst))
	NetworkManager.broadcast_system_message("⚔ %s cayó en combate ante %s. Su botín yace en (%d, %d)." % [
		victim_name, killer_name, int(death_pos.x), int(death_pos.z)
	], "#ff7866")


func _check_bounty_payout(victim_name: String, killer_pid: int, killer_name: String) -> void:
	var bounties: Array = DatabaseManager.get_bounties()
	var paid_any: bool = false
	for i: int in range(bounties.size() - 1, -1, -1):
		var b: Dictionary = bounties[i] as Dictionary
		if str(b.get("target_name", "")).to_lower() == victim_name.to_lower():
			var reward: int = int(b.get("reward_gold", 0))
			var k_acc: Dictionary = DatabaseManager.get_account_mutable(killer_name)
			if not k_acc.is_empty():
				k_acc["gold"] = int(k_acc.get("gold", 0)) + reward
				NetworkManager.broadcast_system_message("CONTRATO CUMPLIDO: %s cobró %d oro por derrotar a %s." % [killer_name, reward, victim_name], "#ffd866")
			bounties.remove_at(i)
			paid_any = true
	if paid_any:
		NetworkManager.push_profile_to_peer(killer_pid)
		NetworkManager.broadcast_social_data()


# --- Loot & Infinite Chunk Gathering ---

@rpc("authority", "call_local", "reliable")
func _rpc_spawn_loot(loot_id: int, victim: String, world_pos: Vector3, gold: int, items: Dictionary) -> void:
	_spawn_local_loot(loot_id, victim, world_pos, gold, items)


func _spawn_local_loot(loot_id: int, victim: String, world_pos: Vector3, gold: int, items: Dictionary) -> void:
	if loot_nodes.has(loot_id) or _loot_container == null:
		return
	var lc: LootCorpse = LOOT_SCENE.instantiate() as LootCorpse
	_loot_container.add_child(lc)
	lc.setup(loot_id, victim, world_pos, gold, items)
	loot_nodes[loot_id] = lc


func request_loot_corpse(loot_id: int) -> void:
	_rpc_loot_corpse.rpc_id(1, loot_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_loot_corpse(loot_id: int) -> void:
	if not NetworkManager.is_server_running() or not _server_loot.has(loot_id):
		return
	var sender_id: int = _get_sender_id()
	var lrec: Dictionary = _server_loot[loot_id] as Dictionary
	var lp_arr: Array = lrec.get("position", [0.0, 0.0, 0.0]) as Array
	var lpos: Vector3 = Vector3(float(lp_arr[0]), float(lp_arr[1]), float(lp_arr[2])) if lp_arr.size() == 3 else Vector3.ZERO
	var ppos: Vector3 = server_get_player_position(sender_id)
	if ppos.distance_to(lpos) > 9.0:
		return
	var key: String = NetworkManager.get_peer_username_key(sender_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	if acc.is_empty():
		return
	var gold: int = int(lrec.get("gold", 0))
	acc["gold"] = int(acc.get("gold", 0)) + gold
	var items: Dictionary = lrec["items"] as Dictionary
	for item_id: Variant in items.keys():
		DatabaseManager.add_item(key, str(item_id), int(items[item_id]))
	var ckey: String = "%d,%d" % [int(lrec.get("chunk_x", 0)), int(lrec.get("chunk_z", 0))]
	DatabaseManager.remove_loot_record(loot_id, ckey)
	_server_loot.erase(loot_id)
	DatabaseManager.mark_dirty()
	DatabaseManager.save_database()
	NetworkManager.push_profile_to_peer(sender_id)
	_rpc_remove_loot.rpc(loot_id)
	NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Botín", "Sistema", "Saqueaste el cofre de %s (+%d oro)." % [str(lrec.get("victim", "")), gold], "#ffd866")


@rpc("authority", "call_local", "reliable")
func _rpc_remove_loot(loot_id: int) -> void:
	if loot_nodes.has(loot_id):
		var lc: LootCorpse = loot_nodes[loot_id] as LootCorpse
		if is_instance_valid(lc):
			lc.queue_free()
		loot_nodes.erase(loot_id)


func request_gather_resource(resource_key: String) -> void:
	_rpc_gather_resource.rpc_id(1, resource_key)


@rpc("any_peer", "call_local", "reliable")
func _rpc_gather_resource(resource_key: String) -> void:
	if not NetworkManager.is_server_running():
		return
	var parts: PackedStringArray = resource_key.split(":")
	if parts.size() != 2:
		return
	var cparts: PackedStringArray = parts[0].split(",")
	if cparts.size() != 2:
		return
	var coord: Vector2i = Vector2i(int(cparts[0]), int(cparts[1]))
	var slot_idx: int = int(parts[1])
	var defs: Array[Dictionary] = GameConfig.get_chunk_resources(coord)
	var target_def: Dictionary = {}
	for d: Dictionary in defs:
		if int(d["slot"]) == slot_idx:
			target_def = d
			break
	if target_def.is_empty():
		return

	var sender_id: int = _get_sender_id()
	var rpos: Vector3 = target_def["world_pos"] as Vector3
	if server_get_player_position(sender_id).distance_to(rpos) > 8.5:
		return

	var cur_state: Dictionary = known_resource_states.get(resource_key, {"charges": 5, "depleted": false, "respawn_at": 0.0}) as Dictionary
	if bool(cur_state.get("depleted", false)):
		return

	var key: String = NetworkManager.get_peer_username_key(sender_id)
	if key.is_empty():
		return
	var rtype: String = str(target_def["type"])
	var yield_qty: int = 3 if rtype != "arcane_ore" else 2
	DatabaseManager.add_item(key, rtype, yield_qty)

	var new_charges: int = int(cur_state.get("charges", 5)) - 1
	var depleted: bool = new_charges <= 0
	known_resource_states[resource_key] = {
		"charges": maxi(0, new_charges),
		"depleted": depleted,
		"respawn_at": Time.get_unix_time_from_system() + 60.0 if depleted else 0.0
	}
	NetworkManager.push_profile_to_peer(sender_id)
	_rpc_update_resource_state.rpc(resource_key, maxi(0, new_charges), depleted)


@rpc("authority", "call_local", "reliable")
func _rpc_update_resource_state(resource_key: String, charges: int, depleted: bool) -> void:
	if not depleted and charges >= 5:
		known_resource_states.erase(resource_key)
	else:
		known_resource_states[resource_key] = {"charges": charges, "depleted": depleted}
	resource_state_changed.emit(resource_key, charges, depleted)


# --- Dragon Mount Summon / Mount / Dismount ---

func request_toggle_dragon() -> void:
	_rpc_toggle_dragon.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_toggle_dragon() -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	if not _server_states.has(sender_id):
		return
	var st: Dictionary = _server_states[sender_id] as Dictionary
	var now_mounted: bool = not bool(st.get("is_mounted", false))
	st["is_mounted"] = now_mounted
	if now_mounted:
		var ppos: Vector3 = server_get_player_position(sender_id)
		var dpos: Vector3 = ppos + Vector3(0.0, 0.2, 0.0)
		st["has_dragon"] = true
		st["dragon_pos"] = dpos
		_rpc_spawn_or_update_dragon.rpc(
			sender_id,
			str(st.get("dragon_skin", "crimson_wyrm")),
			str(st.get("trail_id", "none")),
			bool(st.get("has_combat_grace", false)),
			dpos,
			true
		)
	else:
		_rpc_set_player_mounted.rpc(sender_id, false)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_or_update_dragon(owner_peer: int, skin_id: String, trail_id: String, grace: bool, world_spawn_pos: Vector3, mounted: bool) -> void:
	var local_pos: Vector3 = GameConfig.world_to_local(world_spawn_pos)
	var dc: DragonController
	if dragon_nodes.has(owner_peer):
		dc = dragon_nodes[owner_peer] as DragonController
		dc.apply_cosmetics(skin_id, trail_id)
		dc.set_combat_grace(grace)
		dc.global_position = local_pos
	else:
		dc = DRAGON_SCENE.instantiate() as DragonController
		_dragons_container.add_child(dc)
		dc.setup(owner_peer, skin_id, trail_id, grace, local_pos)
		dragon_nodes[owner_peer] = dc
	_apply_mount_link(owner_peer, mounted)


@rpc("authority", "call_local", "reliable")
func _rpc_update_dragon_cosmetics(owner_peer: int, skin_id: String, trail_id: String, grace: bool) -> void:
	if dragon_nodes.has(owner_peer):
		var dc: DragonController = dragon_nodes[owner_peer] as DragonController
		dc.apply_cosmetics(skin_id, trail_id)
		dc.set_combat_grace(grace)


@rpc("authority", "call_local", "reliable")
func _rpc_set_player_mounted(owner_peer: int, mounted: bool) -> void:
	_apply_mount_link(owner_peer, mounted)


func _apply_mount_link(owner_peer: int, mounted: bool) -> void:
	if not player_nodes.has(owner_peer):
		return
	var pc: PlayerController = player_nodes[owner_peer] as PlayerController
	var dc: DragonController = dragon_nodes.get(owner_peer, null) as DragonController
	if mounted and dc != null:
		dc.set_first_person(pc.is_first_person)
		dc.set_mounted(true, pc.is_local)
		pc.set_mounted_dragon(dc)
	else:
		if dc != null:
			dc.set_mounted(false, false)
		pc.set_mounted_dragon(null)


# --- Creator Avatar (AVATAR_ORDEN & AVATAR_CAOS) Live GM Commands (F1) ---

func _is_sender_avatar(sender_id: int) -> Dictionary:
	var acc: Dictionary = DatabaseManager.get_account_mutable(NetworkManager.get_peer_username_key(sender_id))
	if acc.is_empty() or not GameConfig.is_avatar_role(str(acc.get("role", ""))):
		return {}
	return acc


func request_avatar_toggle_divine_form() -> void:
	_rpc_avatar_toggle_divine_form.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_avatar_toggle_divine_form() -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = _is_sender_avatar(sender_id)
	if acc.is_empty() or not _server_states.has(sender_id):
		return
	var st: Dictionary = _server_states[sender_id] as Dictionary
	var new_form: bool = not bool(st.get("is_divine_form", false))
	st["is_divine_form"] = new_form
	_rpc_update_player_state.rpc(sender_id, _pack_public_state(st))
	var role_str: String = str(acc.get("role", ""))
	if new_form:
		var title: String = "¡EL AVATAR DEL ORDEN HA DESCENDIDO!" if role_str == GameConfig.ROLE_AVATAR_ORDEN else "¡EL AVATAR DEL CAOS HA DESCENDIDO!"
		var col: String = "#ffe066" if role_str == GameConfig.ROLE_AVATAR_ORDEN else "#ff4d36"
		NetworkManager.broadcast_banner(title, "%s camina entre los mortales en forma divina." % str(acc.get("username", "")), col)


func request_avatar_teleport(target_username: String, world_coords: Vector3) -> void:
	_rpc_avatar_teleport.rpc_id(1, target_username, world_coords)


@rpc("any_peer", "call_local", "reliable")
func _rpc_avatar_teleport(target_username: String, world_coords: Vector3) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = _is_sender_avatar(sender_id)
	if acc.is_empty() or not _server_states.has(sender_id):
		return
	var dest: Vector3 = world_coords
	if not target_username.strip_edges().is_empty():
		var target_peer: int = int(NetworkManager.username_to_peer.get(target_username.strip_edges().to_lower(), -1))
		if target_peer > 0 and _server_states.has(target_peer):
			dest = server_get_player_position(target_peer) + Vector3(3.0, 1.0, 0.0)
	dest.y = maxf(dest.y, GameConfig.sample_terrain_height(dest.x, dest.z) + 1.5)
	(_server_states[sender_id] as Dictionary)["position"] = [dest.x, dest.y, dest.z]
	_rpc_teleport_player.rpc(sender_id, dest)


@rpc("authority", "call_local", "reliable")
func _rpc_teleport_player(peer_id: int, world_dest: Vector3) -> void:
	if player_nodes.has(peer_id):
		var local_dest: Vector3 = GameConfig.world_to_local(world_dest)
		var pc: PlayerController = player_nodes[peer_id] as PlayerController
		pc.global_position = local_dest
		if pc.is_mounted and pc.mounted_dragon != null:
			pc.mounted_dragon.global_position = local_dest


func request_avatar_trigger_grace(forced_target: String) -> void:
	_rpc_avatar_trigger_grace.rpc_id(1, forced_target)


@rpc("any_peer", "call_local", "reliable")
func _rpc_avatar_trigger_grace(forced_target: String) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = _is_sender_avatar(sender_id)
	if acc.is_empty() or _grace_scheduler == null:
		return
	var label: String = "El Avatar del Orden (%s)" % str(acc["username"]) if str(acc["role"]) == GameConfig.ROLE_AVATAR_ORDEN else "El Avatar del Caos (%s)" % str(acc["username"])
	var res: Dictionary = _grace_scheduler.server_trigger_roll_now(label, forced_target)
	if not bool(res.get("ok", false)):
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Avatar", "Sistema", str(res.get("error", "Error")), "#ff8888")


func request_avatar_grant_favor(target_username: String) -> void:
	_rpc_avatar_grant_favor.rpc_id(1, target_username)


@rpc("any_peer", "call_local", "reliable")
func _rpc_avatar_grant_favor(target_username: String) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = _is_sender_avatar(sender_id)
	if acc.is_empty():
		return
	var target_peer: int = int(NetworkManager.username_to_peer.get(target_username.strip_edges().to_lower(), -1))
	if target_peer <= 0 or not _server_states.has(target_peer):
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Avatar", "Sistema", "Jugador no conectado.", "#ff8888")
		return
	var tst: Dictionary = _server_states[target_peer] as Dictionary
	tst["favor_mult"] = 1.35
	tst["favor_until"] = Time.get_unix_time_from_system() + 300.0
	var tacc: Dictionary = DatabaseManager.get_account_mutable(str(tst["username"]))
	if not tacc.is_empty():
		tacc["gold"] = int(tacc.get("gold", 0)) + 250
		DatabaseManager.add_item(str(tst["username"]), "wood", 25)
		DatabaseManager.add_item(str(tst["username"]), "stone", 25)
		DatabaseManager.add_item(str(tst["username"]), "arcane_ore", 12)
		NetworkManager.push_profile_to_peer(target_peer)
	_recompute_stats(tst, NetworkManager.get_peer_profile(target_peer), true)
	_rpc_update_player_state.rpc(target_peer, _pack_public_state(tst))
	var deity: String = "El Avatar del Orden" if str(acc["role"]) == GameConfig.ROLE_AVATAR_ORDEN else "El Avatar del Caos"
	NetworkManager.broadcast_banner("FAVOR DIVINO", "%s bendijo a %s (+35%% stats acumulados, +250 oro y materiales)." % [deity, str(tst["username"])], "#7ce8ff")


func request_avatar_world_command(cmd: String, arg_text: String) -> void:
	_rpc_avatar_world_command.rpc_id(1, cmd, arg_text)


@rpc("any_peer", "call_local", "reliable")
func _rpc_avatar_world_command(cmd: String, arg_text: String) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = _is_sender_avatar(sender_id)
	if acc.is_empty():
		return
	if cmd == "announce":
		var deity: String = "VOZ DEL ORDEN" if str(acc["role"]) == GameConfig.ROLE_AVATAR_ORDEN else "VOZ DEL CAOS"
		var col: String = "#ffe066" if str(acc["role"]) == GameConfig.ROLE_AVATAR_ORDEN else "#ff553b"
		NetworkManager.broadcast_banner(deity, arg_text.strip_edges().substr(0, 180), col)
	elif cmd == "set_day":
		world_time_of_day = 0.28
		_rpc_sync_world_time.rpc(world_time_of_day)
		NetworkManager.broadcast_system_message("Un Avatar ha invocado el amanecer sobre el mundo.", "#ffe066")
	elif cmd == "set_night":
		world_time_of_day = 0.82
		_rpc_sync_world_time.rpc(world_time_of_day)
		NetworkManager.broadcast_system_message("Un Avatar ha cubierto los cielos con la noche eterna.", "#b388ff")
	elif cmd == "repair_nearest" and _building_auth != null:
		var msg: String = _building_auth.server_admin_repair_nearest(server_get_player_position(sender_id))
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Avatar", "Sistema", msg, "#88f2a2")
	elif cmd == "kick":
		var tpeer: int = int(NetworkManager.username_to_peer.get(arg_text.strip_edges().to_lower(), -1))
		if tpeer > 1:
			multiplayer.multiplayer_peer.disconnect_peer(tpeer)
			NetworkManager.broadcast_system_message("%s fue expulsado del plano mortal por un Avatar." % arg_text.strip_edges(), "#ff6666")
