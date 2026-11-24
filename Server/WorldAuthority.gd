class_name WorldAuthority
extends Node

## Server-authoritative MMORPG simulation (Release 2.0):
## - Levels 1-8000 (Infinity for Creator Avatars) with zero level-gating & full PvP skill combat
## - Two Indestructible Safe Zones (PvP blocked) + Full Loot Open World (incl. dragon_mount_stone)
## - 4-Piece Armor Sets, Elemental Forging (Fire/Lightning/Ice), Survival Hunger & Cooking
## - Dragon Mounts stored inside 150-slot Backpack (summon storm + auto-return on dismount)
## - Supreme Dragon World Bosses (drop dragon_mount_stone), 4-Player Party Dungeons, Wayshrines
## - GodsInterventionSystem (Auto Population Balance, Disguised Level-1 Novice, Faction Grace)
## - 30-Day Monthly Territorial Season Reset

signal local_player_ready(player: PlayerController)
signal world_time_updated(time_of_day: float)
signal world_seed_synced(seed_val: int)
signal resource_state_changed(resource_key: String, charges: int, depleted: bool)
signal player_roster_updated(usernames: PackedStringArray)

const PLAYER_SCENE: PackedScene = preload("res://Client/Entities/PlayerCharacter.tscn")
const DRAGON_SCENE: PackedScene = preload("res://Client/Entities/DragonMount.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://Client/Entities/MagicProjectile.tscn")
const LOOT_SCENE: PackedScene = preload("res://Client/Entities/LootCorpse.tscn")
const BOSS_SCENE: PackedScene = preload("res://Client/Entities/WorldBoss.tscn")
const DRAGON_BOSS_SCENE: PackedScene = preload("res://Client/Entities/DragonWorldBoss.tscn")

@export var players_container_path: NodePath = NodePath("../Players")
@export var dragons_container_path: NodePath = NodePath("../Dragons")
@export var projectiles_container_path: NodePath = NodePath("../Projectiles")
@export var loot_container_path: NodePath = NodePath("../LootContainer")
@export var bosses_container_path: NodePath = NodePath("../Bosses")

var _players_container: Node3D = null
var _dragons_container: Node3D = null
var _projectiles_container: Node3D = null
var _loot_container: Node3D = null
var _bosses_container: Node3D = null

var player_nodes: Dictionary = {} # peer_id -> PlayerController
var dragon_nodes: Dictionary = {} # peer_id -> DragonController
var loot_nodes: Dictionary = {} # loot_id -> LootCorpse
var boss_nodes: Dictionary = {} # boss_id -> WorldBoss / DragonWorldBoss

var known_resource_states: Dictionary = {}

var _server_states: Dictionary = {}
var _server_loot: Dictionary = {}
var _server_bosses: Dictionary = {}
var _next_proj_id: int = 1

var world_time_of_day: float = 0.28
var _regen_accum: float = 0.0
var _boss_accum: float = 0.0
var _time_sync_accum: float = 0.0
var _pos_save_accum: float = 0.0
var _balance_accum: float = 0.0
var _grace_scheduler: CombatGraceScheduler = null
var _building_auth: BuildingAuthority = null


func _ready() -> void:
	add_to_group("world_authority")
	_players_container = get_node_or_null(players_container_path) as Node3D
	_dragons_container = get_node_or_null(dragons_container_path) as Node3D
	_projectiles_container = get_node_or_null(projectiles_container_path) as Node3D
	_loot_container = get_node_or_null(loot_container_path) as Node3D
	_bosses_container = get_node_or_null(bosses_container_path) as Node3D
	_grace_scheduler = get_tree().get_first_node_in_group("combat_grace_scheduler") as CombatGraceScheduler
	_building_auth = get_tree().get_first_node_in_group("building_authority") as BuildingAuthority

	if NetworkManager.is_server_running():
		_load_persisted_loot_chests()
		_server_init_bosses()
		NetworkManager.peer_session_ended.connect(_on_peer_session_ended)
		if not NetworkManager.is_dedicated_server():
			var host_id: int = multiplayer.get_unique_id()
			_server_spawn_player_for_peer(host_id)
	else:
		_rpc_client_world_ready.rpc_id(1)


func _get_sender_id() -> int:
	var s: int = multiplayer.get_remote_sender_id()
	return multiplayer.get_unique_id() if s == 0 else s


func server_is_peer_disguised(peer_id: int) -> bool:
	if not _server_states.has(peer_id):
		return false
	return bool((_server_states[peer_id] as Dictionary).get("disguised_novice", false))


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

	_boss_accum += delta
	if _boss_accum >= 0.2:
		_server_tick_bosses(_boss_accum)
		_boss_accum = 0.0

	_regen_accum += delta
	if _regen_accum >= 0.5:
		_server_tick_vitals(_regen_accum)
		_server_tick_resource_respawns()
		_regen_accum = 0.0

	_time_sync_accum += delta
	if _time_sync_accum >= 5.0:
		_time_sync_accum = 0.0
		_rpc_sync_world_time.rpc(world_time_of_day)

	_balance_accum += delta
	if _balance_accum >= 30.0:
		_balance_accum = 0.0
		GodsInterventionSystem.evaluate_population_balance()
		if SeasonResetSystem.check_monthly_reset(_building_auth):
			NetworkManager.broadcast_season_data()

	_pos_save_accum += delta
	if _pos_save_accum >= 10.0:
		_pos_save_accum = 0.0
		for pid_var: Variant in _server_states.keys():
			var pid: int = int(pid_var)
			var st: Dictionary = _server_states[pid] as Dictionary
			var pos_arr: Array = st.get("position", [0.0, 2.0, 0.0]) as Array
			if pos_arr.size() == 3:
				DatabaseManager.update_player_position(str(st.get("username", "")), Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])))


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
		var py: float = float(pos_arr[1])
		var pz: float = float(pos_arr[2])
		if py > -80.0:
			var gy: float = GameConfig.sample_terrain_height(px, pz)
			spawn_pos = Vector3(px, maxf(py, gy + 0.5), pz)
		else:
			spawn_pos = Vector3(px, py, pz)

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
				if bool(ost.get("is_mounted", false)):
					_rpc_spawn_or_update_dragon.rpc_id(
						peer_id,
						other_pid,
						str(ost.get("dragon_skin", "crimson_wyrm")),
						str(ost.get("trail_id", "none")),
						bool(ost.get("has_combat_grace", false)),
						ost.get("dragon_pos", Vector3.ZERO) as Vector3,
						true
					)
		for lid_var: Variant in _server_loot.keys():
			var lrec: Dictionary = _server_loot[lid_var] as Dictionary
			var lp_arr: Array = lrec.get("position", [0.0, 1.5, 0.0]) as Array
			var lpos: Vector3 = Vector3(float(lp_arr[0]), float(lp_arr[1]), float(lp_arr[2])) if lp_arr.size() == 3 else Vector3.ZERO
			_rpc_spawn_loot.rpc_id(peer_id, int(lrec["id"]), str(lrec["victim"]), lpos, int(lrec["gold"]), lrec["items"] as Dictionary)
		for bid_var: Variant in _server_bosses.keys():
			var b: Dictionary = _server_bosses[bid_var] as Dictionary
			_rpc_spawn_or_sync_boss.rpc_id(
				peer_id,
				str(b["id"]),
				str(b["name"]),
				str(b["title"]),
				str(b["style"]),
				bool(b.get("is_supreme_dragon", false)),
				b["pos"] as Vector3,
				float(b["yaw"]),
				float(b["hp"]),
				float(b["max_hp"]),
				bool(b["alive"])
			)
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
	NetworkManager.broadcast_season_data()
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
		"level": int(profile.get("level", 1)),
		"class_id": str(profile.get("class_id", "ARCANE_KNIGHT")),
		"race_id": str(profile.get("race_id", "HUMAN_VALLEY")),
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
		"hunger": float(profile.get("hunger", 100.0)),
		"attack_power": 20.0,
		"spell_power": 20.0,
		"defense": 10.0,
		"weapon_element": "",
		"armor_set_bonus": "",
		"shield_hp": 0.0,
		"shield_until": 0.0,
		"buff_mult": 1.0,
		"buff_until": 0.0,
		"favor_mult": 1.0,
		"favor_until": 0.0,
		"faction_grace_until": 0.0,
		"iframe_until": 0.0,
		"stealth_until": 0.0,
		"stun_until": 0.0,
		"is_blocking": false,
		"is_divine_form": false,
		"disguised_novice": false,
		"has_combat_grace": has_grace,
		"has_dragon": false,
		"is_mounted": false,
		"dragon_pos": pos,
		"last_attack_at": 0.0
	}


func _recompute_stats(st: Dictionary, profile: Dictionary, fill_vitals: bool = false) -> void:
	var class_def: Dictionary = GameConfig.CLASSES.get(str(st.get("class_id", "ARCANE_KNIGHT")), GameConfig.CLASSES["ARCANE_KNIGHT"]) as Dictionary
	var now: float = Time.get_unix_time_from_system()
	var role: String = str(profile.get("role", GameConfig.ROLE_PLAYER))
	var lvl: int = int(profile.get("level", 1))
	st["level"] = lvl
	st["philosophy"] = str(profile.get("philosophy", GameConfig.PHILOSOPHY_NEUTRAL))
	var lvl_mult: float = LevelingSystem.get_level_stat_multiplier(lvl, role)
	if bool(st.get("disguised_novice", false)):
		lvl_mult = 1.0

	var gear: Dictionary = CraftingSystem.evaluate_gear_bonuses(profile)
	var base_hp: float = (float(class_def.get("max_hp", 120.0)) + float(gear.get("hp_bonus", 0.0))) * lvl_mult
	var base_mana: float = float(class_def.get("max_mana", 100.0)) * lvl_mult
	var base_stam: float = float(class_def.get("max_stamina", 100.0)) * lvl_mult
	var base_atk: float = (float(class_def.get("attack_power", 20.0)) + float(gear.get("atk_bonus", 0.0))) * lvl_mult
	var base_spl: float = (float(class_def.get("spell_power", 20.0)) + float(gear.get("spell_bonus", 0.0))) * lvl_mult
	var base_def: float = (float(class_def.get("defense", 10.0)) + float(gear.get("def_bonus", 0.0))) * lvl_mult
	st["weapon_element"] = str(gear.get("weapon_element", ""))
	st["armor_set_bonus"] = str(gear.get("set_bonus", ""))

	# Survival food buff + auto faction population balance
	var faction: String = str(st.get("philosophy", GameConfig.PHILOSOPHY_NEUTRAL))
	var bal_dmg: float = GodsInterventionSystem.get_balance_damage_mult(faction)
	var bal_def: float = GodsInterventionSystem.get_balance_defense_mult(faction)
	var food_mult: float = 1.15 if (now < float(profile.get("food_buff_until", 0.0)) and not str(profile.get("food_buff", "")).is_empty()) else 1.0

	var stack_mult: float = food_mult
	if now < float(st.get("buff_until", 0.0)):
		stack_mult *= float(st.get("buff_mult", 1.0))
	if now < float(st.get("favor_until", 0.0)):
		stack_mult *= float(st.get("favor_mult", 1.0))

	# GRACIA COMBATIVA (daily roll OR Faction-wide Avatar Grace): +100% (x2.0)
	var has_daily_grace: bool = _grace_scheduler != null and _grace_scheduler.is_player_blessed(str(st.get("username", "")))
	var has_faction_grace: bool = now < float(st.get("faction_grace_until", 0.0))
	var has_grace: bool = has_daily_grace or has_faction_grace
	st["has_combat_grace"] = has_grace
	var grace_mult: float = GameConfig.COMBAT_GRACE_MULTIPLIER if has_grace else 1.0
	var total_mult: float = stack_mult * grace_mult

	var hp_ratio: float = clampf(float(st.get("hp", base_hp)) / maxf(1.0, float(st.get("max_hp", base_hp))), 0.0, 1.0)
	st["max_hp"] = base_hp * total_mult
	st["max_mana"] = base_mana * total_mult
	st["max_stamina"] = base_stam * total_mult
	st["attack_power"] = base_atk * total_mult * bal_dmg
	st["spell_power"] = base_spl * total_mult * bal_dmg
	st["defense"] = base_def * total_mult * bal_def

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
		"level": st.get("level", 1),
		"disguised_novice": st.get("disguised_novice", false),
		"class_id": st.get("class_id", "ARCANE_KNIGHT"),
		"race_id": st.get("race_id", "HUMAN_VALLEY"),
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
		"hunger": st.get("hunger", 100.0),
		"shield_hp": st.get("shield_hp", 0.0),
		"has_combat_grace": st.get("has_combat_grace", false),
		"is_divine_form": st.get("is_divine_form", false) and not bool(st.get("disguised_novice", false)),
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
	st["race_id"] = str(profile.get("race_id", "HUMAN_VALLEY"))
	_rpc_update_player_state.rpc(peer_id, _pack_public_state(st))
	if bool(st.get("is_mounted", false)):
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
			if bool(st.get("is_mounted", false)):
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
	var key: String = NetworkManager.get_peer_username_key(peer_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	if str(item_def.get("type", "")) == "food":
		if SurvivalSystem.eat_cooked_meal(acc, st, item_id):
			_recompute_stats(st, NetworkManager.get_peer_profile(peer_id), false)
			_rpc_update_player_state.rpc(peer_id, _pack_public_state(st))
			NetworkManager._rpc_receive_chat.rpc_id(peer_id, "Supervivencia", "Sistema", "Comiste %s (Saciedad %d%%)." % [str(item_def.get("name", item_id)), int(st.get("hunger", 100.0))], "#88f2a2")
			return true
		return false
	if item_def.has("heal"):
		st["hp"] = minf(float(st["max_hp"]), float(st["hp"]) + float(item_def["heal"]))
		_rpc_update_player_state.rpc(peer_id, _pack_public_state(st))
		return true
	if item_def.has("mana"):
		st["mana"] = minf(float(st["max_mana"]), float(st["mana"]) + float(item_def["mana"]))
		_rpc_update_player_state.rpc(peer_id, _pack_public_state(st))
		return true
	if item_def.has("buff_mult"):
		st["buff_mult"] = float(item_def["buff_mult"])
		st["buff_until"] = Time.get_unix_time_from_system() + float(item_def.get("duration", 45.0))
		_recompute_stats(st, NetworkManager.get_peer_profile(peer_id), false)
		_rpc_update_player_state.rpc(peer_id, _pack_public_state(st))
		return true
	if item_def.has("siege_damage") and _building_auth != null:
		var pos: Vector3 = server_get_player_position(peer_id)
		_building_auth.server_damage_buildings_in_radius(pos, 7.5, float(item_def["siege_damage"]), str(st.get("username", "")))
		return true
	return false


func _server_grant_xp_with_party(peer_id: int, raw_xp: int) -> void:
	var members: Array[int] = PartySystem.get_party_members(peer_id)
	if members.is_empty():
		members = [peer_id]
	var per_member: int = maxi(10, int(float(raw_xp) / float(members.size()) * (1.2 if members.size() > 1 else 1.0)))
	for pid: int in members:
		if not _server_states.has(pid):
			continue
		var key: String = NetworkManager.get_peer_username_key(pid)
		var st: Dictionary = _server_states[pid] as Dictionary
		var bal_xp: float = GodsInterventionSystem.get_balance_xp_mult(str(st.get("philosophy", "")))
		var res: Dictionary = LevelingSystem.grant_xp(key, int(float(per_member) * bal_xp))
		if bool(res.get("leveled_up", false)):
			var new_lvl: int = int(res.get("level", 1))
			_recompute_stats(st, NetworkManager.get_peer_profile(pid), true)
			_rpc_update_player_state.rpc(pid, _pack_public_state(st))
			NetworkManager._rpc_receive_chat.rpc_id(pid, "Nivel", "Progreso", "¡SUBISTE AL NIVEL %d! Tus estadísticas aumentaron." % new_lvl, "#ffe066")
		NetworkManager.push_profile_to_peer(pid)


func _server_tick_vitals(dt: float) -> void:
	var now: float = Time.get_unix_time_from_system()
	for pid_var: Variant in _server_states.keys():
		var pid: int = int(pid_var)
		var st: Dictionary = _server_states[pid] as Dictionary
		var is_admin: bool = GameConfig.is_avatar_role(str(st.get("role", ""))) and not bool(st.get("disguised_novice", false))
		var key: String = NetworkManager.get_peer_username_key(pid)
		var acc: Dictionary = DatabaseManager.get_account_mutable(key)
		var hunger_regen: float = SurvivalSystem.tick_player_hunger(acc, st, dt) if not acc.is_empty() else 1.0
		var grace_bonus: float = 2.0 if bool(st.get("has_combat_grace", false)) else 1.0
		var dirty: bool = false

		if is_admin:
			st["mana"] = st["max_mana"]
			st["stamina"] = st["max_stamina"]
			st["hunger"] = 100.0
		if float(st["hp"]) < float(st["max_hp"]):
			st["hp"] = minf(float(st["max_hp"]), float(st["hp"]) + 2.4 * grace_bonus * hunger_regen * dt)
			dirty = true
		if float(st["mana"]) < float(st["max_mana"]):
			st["mana"] = minf(float(st["max_mana"]), float(st["mana"]) + 6.5 * grace_bonus * hunger_regen * dt)
			dirty = true
		if not bool(st.get("is_blocking", false)) and float(st["stamina"]) < float(st["max_stamina"]):
			st["stamina"] = minf(float(st["max_stamina"]), float(st["stamina"]) + 16.0 * grace_bonus * hunger_regen * dt)
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
		if float(st.get("faction_grace_until", 0.0)) > 0.0 and now >= float(st["faction_grace_until"]):
			st["faction_grace_until"] = 0.0
			_recompute_stats(st, NetworkManager.get_peer_profile(pid), false)
			dirty = true

		if dirty or hunger_regen < 1.0:
			_rpc_update_player_vitals.rpc(pid, float(st["hp"]), float(st["max_hp"]), float(st["mana"]), float(st["max_mana"]), float(st["stamina"]), float(st["max_stamina"]), float(st["shield_hp"]), float(st.get("hunger", 100.0)), now < float(st.get("stealth_until", 0.0)))


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
func _rpc_update_player_vitals(peer_id: int, hp: float, max_hp: float, mana: float, max_mana: float, stamina: float, max_stamina: float, shield_hp: float, hunger: float, stealthed: bool) -> void:
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
	pc.hunger = hunger
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
	var safe_pos: Vector3 = Vector3(world_pos.x, clampf(world_pos.y, -220.0, 260.0), world_pos.z)
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


# --- Skill-Based Combat, SafeZone Protection, Unlimited Admin Magic & Elemental Weapons ---

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
	var is_admin: bool = GameConfig.is_avatar_role(str(st.get("role", ""))) and not bool(st.get("disguised_novice", false))
	if not is_admin:
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
	if now < float(st.get("stun_until", 0.0)):
		return
	var is_admin: bool = GameConfig.is_avatar_role(str(st.get("role", ""))) and not bool(st.get("disguised_novice", false))
	if not is_admin and now - float(st.get("last_attack_at", 0.0)) < 0.36:
		return
	st["last_attack_at"] = now
	st["stealth_until"] = 0.0

	var dir: Vector3 = aim_dir.normalized()
	var class_id: String = str(st.get("class_id", "ARCANE_KNIGHT"))
	var elem: String = str(st.get("weapon_element", ""))
	var elem_mult: float = CraftingSystem.get_element_damage_multiplier(elem)
	var elem_col: Color = Color(1.0, 0.45, 0.12)
	if elem == "lightning":
		elem_col = Color(0.55, 0.85, 1.0)
	elif elem == "ice":
		elem_col = Color(0.45, 0.95, 1.0)

	if class_id == "PYROMANCER":
		var dmg: float = float(st.get("spell_power", 25.0)) * 0.9 * elem_mult
		_server_spawn_projectile(sender_id, world_origin + dir * 1.1, dir, 30.0, dmg, 1.5, elem_col, 0.75)
		return
	if class_id == "VALLEY_HUNTER":
		var arrow_dmg: float = float(st.get("attack_power", 24.0)) * 0.95 * elem_mult
		_server_spawn_projectile(sender_id, world_origin + dir * 1.1, dir, 42.0, arrow_dmg, 0.0, Color(0.9, 0.82, 0.48), 0.45)
		return

	var melee_dmg: float = float(st.get("attack_power", 20.0)) * elem_mult
	var reach: float = 3.8
	for target_pid_var: Variant in _server_states.keys():
		var target_pid: int = int(target_pid_var)
		if target_pid == sender_id:
			continue
		var tpos: Vector3 = server_get_player_position(target_pid) + Vector3(0.0, 1.0, 0.0)
		var to_target: Vector3 = tpos - world_origin
		var dist: float = to_target.length()
		if dist <= reach and to_target.normalized().dot(dir) >= 0.32:
			_server_apply_damage_to_player(target_pid, sender_id, melee_dmg, world_origin, elem)

	_server_damage_bosses_in_radius(world_origin + dir * 2.4, 4.4, melee_dmg, sender_id, str(st.get("username", "")))

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
	var now: float = Time.get_unix_time_from_system()
	if now < float(st.get("stun_until", 0.0)):
		return
	var class_def: Dictionary = GameConfig.CLASSES.get(str(st.get("class_id", "")), {}) as Dictionary
	var abilities: Array = class_def.get("abilities", []) as Array
	if slot < 0 or slot >= abilities.size():
		return
	var ab: Dictionary = abilities[slot] as Dictionary
	var elem: String = str(st.get("weapon_element", ""))
	var cost_mult: float = CraftingSystem.get_element_cost_multiplier(elem)
	var is_admin: bool = GameConfig.is_avatar_role(str(st.get("role", ""))) and not bool(st.get("disguised_novice", false))
	var cost_m: float = 0.0 if is_admin else float(ab.get("cost_mana", 0.0)) * cost_mult
	var cost_s: float = 0.0 if is_admin else float(ab.get("cost_stamina", 0.0)) * cost_mult
	if float(st["mana"]) < cost_m or float(st["stamina"]) < cost_s:
		return
	st["mana"] = float(st["mana"]) - cost_m
	st["stamina"] = float(st["stamina"]) - cost_s
	var ab_type: String = str(ab.get("type", "projectile"))
	var dir: Vector3 = aim_dir.normalized()
	var grace_mult: float = GameConfig.COMBAT_GRACE_MULTIPLIER if bool(st.get("has_combat_grace", false)) else 1.0
	var spell_scale: float = float(st.get("spell_power", 20.0)) / 20.0
	var elem_mult: float = CraftingSystem.get_element_damage_multiplier(elem)

	if ab_type == "projectile":
		st["stealth_until"] = 0.0
		var dmg: float = float(ab.get("damage", 35.0)) * maxf(0.85, spell_scale) * elem_mult
		var splash: float = float(ab.get("splash", 0.0))
		var col: Color = ab.get("color", Color(1.0, 0.5, 0.2)) as Color
		var proj_scale: float = 1.65 if splash >= 4.0 else 1.0
		_server_spawn_projectile(sender_id, world_origin + dir * 1.2, dir, 34.0, dmg, splash, col, proj_scale)
	elif ab_type == "aoe":
		st["stealth_until"] = 0.0
		var dmg: float = float(ab.get("damage", 35.0)) * maxf(0.85, spell_scale) * elem_mult
		var rad: float = float(ab.get("radius", 5.5))
		var caster_pos: Vector3 = server_get_player_position(sender_id)
		for target_pid_var: Variant in _server_states.keys():
			var target_pid: int = int(target_pid_var)
			if target_pid == sender_id:
				continue
			if server_get_player_position(target_pid).distance_to(caster_pos) <= rad:
				_server_apply_damage_to_player(target_pid, sender_id, dmg, caster_pos, elem)
		_server_damage_bosses_in_radius(caster_pos, rad + 2.5, dmg, sender_id, str(st.get("username", "")))
		if _building_auth != null:
			_building_auth.server_damage_buildings_in_radius(caster_pos, rad, dmg * 1.15, str(st.get("username", "")))
		if ab.has("heal"):
			st["hp"] = minf(float(st["max_hp"]), float(st["hp"]) + float(ab["heal"]) * grace_mult)
	elif ab_type == "heal":
		var ice_bonus: float = 1.3 if elem == "ice" else 1.0
		var heal_amt: float = float(ab.get("heal", 50.0)) * grace_mult * ice_bonus
		var rad: float = float(ab.get("radius", 10.0))
		var caster_pos: Vector3 = server_get_player_position(sender_id)
		var caster_guild: String = str(NetworkManager.get_peer_profile(sender_id).get("guild_id", ""))
		for target_pid_var: Variant in _server_states.keys():
			var target_pid: int = int(target_pid_var)
			var t_guild: String = str(NetworkManager.get_peer_profile(target_pid).get("guild_id", ""))
			var is_ally: bool = target_pid == sender_id or PartySystem.are_in_same_party(sender_id, target_pid) or (not caster_guild.is_empty() and t_guild == caster_guild)
			if is_ally and server_get_player_position(target_pid).distance_to(caster_pos) <= rad:
				var tst: Dictionary = _server_states[target_pid] as Dictionary
				tst["hp"] = minf(float(tst["max_hp"]), float(tst["hp"]) + heal_amt)
				if elem == "ice":
					tst["shield_hp"] = maxf(float(tst.get("shield_hp", 0.0)), 45.0 * grace_mult)
					tst["shield_until"] = now + 6.0
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
	var ost: Dictionary = _server_states[owner_peer] as Dictionary
	var attacker_name: String = str(ost.get("username", ""))
	var elem: String = str(ost.get("weapon_element", ""))
	if hit_body is PlayerController:
		var target_pc: PlayerController = hit_body as PlayerController
		if target_pc.peer_id != owner_peer:
			_server_apply_damage_to_player(target_pc.peer_id, owner_peer, damage, world_impact_pos, elem)
	elif hit_body is WorldBoss:
		_server_damage_boss((hit_body as WorldBoss).boss_id, damage, owner_peer, attacker_name)
	elif hit_body is BuildPiece and _building_auth != null:
		_building_auth.server_damage_building((hit_body as BuildPiece).building_id, damage * b_mult, attacker_name)

	if splash > 0.2:
		for target_pid_var: Variant in _server_states.keys():
			var target_pid: int = int(target_pid_var)
			if target_pid == owner_peer:
				continue
			if server_get_player_position(target_pid).distance_to(world_impact_pos) <= splash:
				_server_apply_damage_to_player(target_pid, owner_peer, damage * 0.75, world_impact_pos, elem)
		_server_damage_bosses_in_radius(world_impact_pos, splash + 2.5, damage * 0.85, owner_peer, attacker_name)
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
	var breath_dmg: float = 26.0 * grace_mult
	var dir: Vector3 = aim_dir.normalized()
	var attacker_name: String = str(st.get("username", ""))

	for target_pid_var: Variant in _server_states.keys():
		var target_pid: int = int(target_pid_var)
		if target_pid == sender_id:
			continue
		var tpos: Vector3 = server_get_player_position(target_pid) + Vector3(0.0, 1.0, 0.0)
		var delta_v: Vector3 = tpos - world_origin
		var dist: float = delta_v.length()
		if dist <= 26.0 and delta_v.normalized().dot(dir) >= 0.76:
			_server_apply_damage_to_player(target_pid, sender_id, breath_dmg, world_origin, "fire")

	var sample_ground: Vector3 = world_origin + dir * 15.0
	_server_damage_bosses_in_radius(sample_ground, 9.5, breath_dmg * 1.25, sender_id, attacker_name)
	if _building_auth != null:
		_building_auth.server_damage_buildings_in_radius(sample_ground, 6.5, breath_dmg * 1.4, attacker_name)


func _server_apply_damage_to_player(target_pid: int, attacker_pid: int, raw_damage: float, hit_world_origin: Vector3, element: String = "") -> void:
	if not _server_states.has(target_pid):
		return
	var tst: Dictionary = _server_states[target_pid] as Dictionary
	var now: float = Time.get_unix_time_from_system()

	# SafeZone 100% PvP Protection (Santuario del Alba & Ciudadela del Caos)
	if attacker_pid > 0:
		var tpos_safe: Vector3 = server_get_player_position(target_pid)
		var apos_safe: Vector3 = server_get_player_position(attacker_pid)
		if SafeZone.is_in_safe_zone(tpos_safe) or SafeZone.is_in_safe_zone(apos_safe):
			NetworkManager._rpc_receive_chat.rpc_id(attacker_pid, "Santuario", "Protección", "🛡️ Bajo protección del Santuario — PvP y robos bloqueados en Zona Segura.", "#88f2a2")
			return
		# Party friendly-fire protection
		if PartySystem.are_in_same_party(attacker_pid, target_pid):
			return

	if now < float(tst.get("iframe_until", 0.0)):
		return
	if bool(tst.get("is_divine_form", false)) and not bool(tst.get("disguised_novice", false)):
		return

	var defense: float = float(tst.get("defense", 10.0))
	var dmg: float = maxf(4.0, raw_damage - defense * 0.45)

	if element == "lightning":
		tst["stun_until"] = maxf(float(tst.get("stun_until", 0.0)), now + 0.65)

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

	# Auto-dismount dragon so it is dropped as loot if carried in backpack
	if bool(vst.get("is_mounted", false)):
		vst["is_mounted"] = false
		vst["has_dragon"] = false
		_rpc_despawn_dragon.rpc(victim_pid)

	var acc: Dictionary = DatabaseManager.get_account_mutable(victim_name)
	if not acc.is_empty():
		var inv: Dictionary = acc["inventory"] as Dictionary
		var dropped_items: Dictionary = inv.duplicate(true)
		inv.clear()
		for eq_key: String in ["equipped_weapon", "equipped_helmet", "equipped_chest", "equipped_legs", "equipped_boots"]:
			var eq_id: String = str(acc.get(eq_key, ""))
			if not eq_id.is_empty():
				dropped_items[eq_id] = int(dropped_items.get(eq_id, 0)) + 1
				acc[eq_key] = ""
		var cur_gold: int = int(acc.get("gold", 0))
		var dropped_gold: int = cur_gold / 2
		acc["gold"] = cur_gold - dropped_gold

		if not dropped_items.is_empty() or dropped_gold > 0:
			server_spawn_world_loot_bag(victim_name, death_pos, dropped_gold, dropped_items)

		if killer_pid > 0 and killer_pid != victim_pid and _server_states.has(killer_pid):
			_check_bounty_payout(victim_name, killer_pid, killer_name)
			_server_grant_xp_with_party(killer_pid, 350)
			AlignmentSystem.apply_action(NetworkManager.get_peer_username_key(killer_pid), -20)

		DatabaseManager.mark_dirty()
		DatabaseManager.save_database()
		NetworkManager.push_profile_to_peer(victim_pid)

	# Respawn inside the player's allied Safe Zone (Ciudadela del Caos or Santuario del Alba)
	var respawn_center: Vector2 = Vector2(260.0, 260.0) if str(vst.get("philosophy", "")) == GameConfig.PHILOSOPHY_CHAOS else Vector2(0.0, 0.0)
	var respawn_x: float = respawn_center.x + randf_range(-8.0, 8.0)
	var respawn_z: float = respawn_center.y + randf_range(-8.0, 8.0)
	var respawn_pos: Vector3 = Vector3(respawn_x, GameConfig.sample_terrain_height(respawn_x, respawn_z) + 1.5, respawn_z)
	vst["position"] = [respawn_pos.x, respawn_pos.y, respawn_pos.z]
	_recompute_stats(vst, NetworkManager.get_peer_profile(victim_pid), true)
	_rpc_teleport_player.rpc(victim_pid, respawn_pos)
	_rpc_update_player_state.rpc(victim_pid, _pack_public_state(vst))
	NetworkManager.broadcast_system_message("⚔ %s cayó en combate ante %s. Todo su botín yace en (%d, %d)." % [
		victim_name, killer_name, int(death_pos.x), int(death_pos.z)
	], "#ff7866")


func server_spawn_world_loot_bag(label: String, world_pos: Vector3, gold: int, items: Dictionary) -> void:
	if not NetworkManager.is_server_running():
		return
	var lid: int = DatabaseManager.allocate_loot_id()
	var lrec: Dictionary = {
		"id": lid,
		"victim": label,
		"position": [world_pos.x, world_pos.y, world_pos.z],
		"gold": gold,
		"items": items
	}
	DatabaseManager.add_loot_record(lrec)
	_server_loot[lid] = lrec
	_rpc_spawn_loot.rpc(lid, label, world_pos, gold, items)


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


# --- Loot (150-Slot Limit Enforced) & Infinite Chunk Gathering ---

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
	lrec["gold"] = 0
	var items: Dictionary = lrec["items"] as Dictionary
	var leftover: Dictionary = {}
	for item_id_var: Variant in items.keys():
		var iid: String = str(item_id_var)
		var qty: int = int(items[iid])
		if not DatabaseManager.add_item(key, iid, qty):
			leftover[iid] = qty
	if leftover.is_empty():
		var ckey: String = "%d,%d" % [int(lrec.get("chunk_x", 0)), int(lrec.get("chunk_z", 0))]
		DatabaseManager.remove_loot_record(loot_id, ckey)
		_server_loot.erase(loot_id)
		_rpc_remove_loot.rpc(loot_id)
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Botín", "Sistema", "Saqueaste todo el cofre de %s (+%d oro)." % [str(lrec.get("victim", "")), gold], "#ffd866")
	else:
		lrec["items"] = leftover
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Mochila Llena", "Sistema", "Tu mochila (150 espacios) se llenó. Guardá objetos en un Cajón de tu casa para saquear el resto.", "#ffaa66")
	DatabaseManager.mark_dirty()
	DatabaseManager.save_database()
	NetworkManager.push_profile_to_peer(sender_id)


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
	var yield_qty: int = 3 if (rtype == "wood" or rtype == "stone" or rtype == "iron_ore") else 2
	if not DatabaseManager.add_item(key, rtype, yield_qty):
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Mochila Llena", "Sistema", "Mochila al máximo (%d/150). Guardá materiales en tu Cajón de Guardado." % GameConfig.BACKPACK_MAX_SLOTS, "#ffaa66")
		return

	var new_charges: int = int(cur_state.get("charges", 5)) - 1
	var depleted: bool = new_charges <= 0
	known_resource_states[resource_key] = {
		"charges": maxi(0, new_charges),
		"depleted": depleted,
		"respawn_at": Time.get_unix_time_from_system() + 60.0 if depleted else 0.0
	}
	_server_grant_xp_with_party(sender_id, 35)
	_rpc_update_resource_state.rpc(resource_key, maxi(0, new_charges), depleted)


@rpc("authority", "call_local", "reliable")
func _rpc_update_resource_state(resource_key: String, charges: int, depleted: bool) -> void:
	if not depleted and charges >= 5:
		known_resource_states.erase(resource_key)
	else:
		known_resource_states[resource_key] = {"charges": charges, "depleted": depleted}
	resource_state_changed.emit(resource_key, charges, depleted)


# --- Wayshrine Discovery & Fast Travel ---

func request_discover_wayshrine(wayshrine_id: String) -> void:
	_rpc_discover_wayshrine.rpc_id(1, wayshrine_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_discover_wayshrine(wayshrine_id: String) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var key: String = NetworkManager.get_peer_username_key(sender_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	if acc.is_empty():
		return
	var wdef: Dictionary = {}
	for w: Dictionary in GameConfig.WAYSHRINES:
		if str(w.get("id", "")) == wayshrine_id:
			wdef = w
			break
	if wdef.is_empty():
		return
	var discovered: Array = acc.get("discovered_wayshrines", []) as Array
	if not discovered.has(wayshrine_id):
		discovered.append(wayshrine_id)
		acc["discovered_wayshrines"] = discovered
		DatabaseManager.mark_dirty()
		DatabaseManager.save_database()
		NetworkManager.push_profile_to_peer(sender_id)
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Ermita", "Descubrimiento", "✦ Descubriste %s. Ya podés viajar rápido desde el Mapa (M)." % str(wdef.get("name", wayshrine_id)), "#7ce8ff")


func request_wayshrine_teleport(wayshrine_id: String) -> void:
	_rpc_wayshrine_teleport.rpc_id(1, wayshrine_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_wayshrine_teleport(wayshrine_id: String) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	if not _server_states.has(sender_id):
		return
	var key: String = NetworkManager.get_peer_username_key(sender_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	if acc.is_empty():
		return
	var wdef: Dictionary = {}
	for w: Dictionary in GameConfig.WAYSHRINES:
		if str(w.get("id", "")) == wayshrine_id:
			wdef = w
			break
	if wdef.is_empty():
		return
	var discovered: Array = acc.get("discovered_wayshrines", []) as Array
	var is_admin: bool = GameConfig.is_avatar_role(str(acc.get("role", "")))
	if not (is_admin or discovered.has(wayshrine_id) or bool(wdef.get("default_unlocked", false))):
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Mapa", "Sistema", "Debés descubrir esta Ermita explorando primero.", "#ffaa66")
		return
	var xz: Vector2 = wdef.get("xz", Vector2.ZERO) as Vector2
	var dest: Vector3 = Vector3(xz.x + 2.5, GameConfig.sample_terrain_height(xz.x + 2.5, xz.y) + 1.5, xz.y)
	(_server_states[sender_id] as Dictionary)["position"] = [dest.x, dest.y, dest.z]
	_rpc_teleport_player.rpc(sender_id, dest)
	NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Viaje Rápido", "Ermita", "Viajaste a %s." % str(wdef.get("name", wayshrine_id)), "#7ce8ff")


# --- Dragon Mount Stored in 150-Slot Backpack (Requires dragon_mount_stone) ---

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
	var key: String = NetworkManager.get_peer_username_key(sender_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	var is_admin: bool = GameConfig.is_avatar_role(str(st.get("role", "")))
	var now_mounted: bool = not bool(st.get("is_mounted", false))

	if now_mounted:
		var inv: Dictionary = acc.get("inventory", {}) as Dictionary
		if not is_admin and int(inv.get("dragon_mount_stone", 0)) <= 0:
			NetworkManager._rpc_receive_chat.rpc_id(
				sender_id,
				"Montura Dragón",
				"Requisito",
				"🐉 Necesitás una 'Piedra de Vínculo de Dragón' en tu mochila. Derrotá a los Jefes Dragón Supremos en el Valle Dracónico para obtenerla.",
				"#ffaa66"
			)
			return
		st["is_mounted"] = true
		st["has_dragon"] = true
		var ppos: Vector3 = server_get_player_position(sender_id)
		var dpos: Vector3 = ppos + Vector3(0.0, 0.2, 0.0)
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
		# Dismounting automatically returns the dragon to the player's 150-slot backpack!
		st["is_mounted"] = false
		st["has_dragon"] = false
		_rpc_despawn_dragon.rpc(sender_id)
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Montura Dragón", "Mochila", "Tu dragón regresó automáticamente a la Piedra de Vínculo en tu mochila.", "#8fc7ff")


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
	dc.trigger_summon_storm()
	_apply_mount_link(owner_peer, mounted)


@rpc("authority", "call_local", "reliable")
func _rpc_despawn_dragon(owner_peer: int) -> void:
	_apply_mount_link(owner_peer, false)
	if dragon_nodes.has(owner_peer):
		var dc: DragonController = dragon_nodes[owner_peer] as DragonController
		if is_instance_valid(dc):
			dc.queue_free()
		dragon_nodes.erase(owner_peer)


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


# --- Creator Avatar (AVATAR_ORDEN & AVATAR_CAOS) Live GM & Disguised Novice Commands ---

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
	if new_form:
		st["disguised_novice"] = false
	_recompute_stats(st, NetworkManager.get_peer_profile(sender_id), true)
	_rpc_update_player_state.rpc(sender_id, _pack_public_state(st))
	var role_str: String = str(acc.get("role", ""))
	if new_form:
		var title: String = "♾️ ¡EL AVATAR DEL ORDEN HA DESCENDIDO!" if role_str == GameConfig.ROLE_AVATAR_ORDEN else "♾️ ¡EL AVATAR DEL CAOS HA DESCENDIDO!"
		var col: String = "#ffe066" if role_str == GameConfig.ROLE_AVATAR_ORDEN else "#ff4d36"
		NetworkManager.broadcast_banner(title, "%s camina entre los mortales con poder infinito." % str(acc.get("username", "")), col)


func request_avatar_toggle_disguised_novice() -> void:
	_rpc_avatar_toggle_disguised_novice.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_avatar_toggle_disguised_novice() -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = _is_sender_avatar(sender_id)
	if acc.is_empty() or not _server_states.has(sender_id):
		return
	var st: Dictionary = _server_states[sender_id] as Dictionary
	var now_disguised: bool = not bool(st.get("disguised_novice", false))
	st["disguised_novice"] = now_disguised
	if now_disguised:
		st["is_divine_form"] = false
	_recompute_stats(st, NetworkManager.get_peer_profile(sender_id), true)
	_rpc_update_player_state.rpc(sender_id, _pack_public_state(st))
	if now_disguised:
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Encarnación", "Sigilo", "🎭 Ahora caminás de incógnito como un Novato Nivel 1. Tu símbolo ♾️ y aura divina están ocultos.", "#b8e0ff")
	else:
		var role_str: String = str(acc.get("role", ""))
		var title: String = "♾️ ¡REVELACIÓN DEL AVATAR DEL ORDEN!" if role_str == GameConfig.ROLE_AVATAR_ORDEN else "♾️ ¡REVELACIÓN DEL AVATAR DEL CAOS!"
		var col: String = "#ffe066" if role_str == GameConfig.ROLE_AVATAR_ORDEN else "#ff4d36"
		NetworkManager.broadcast_banner(title, "%s reveló su verdadera identidad primordial ♾️ entre los jugadores." % str(acc.get("username", "")), col)


func request_avatar_grant_faction_grace() -> void:
	_rpc_avatar_grant_faction_grace.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_avatar_grant_faction_grace() -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = _is_sender_avatar(sender_id)
	if acc.is_empty():
		return
	var role_str: String = str(acc.get("role", ""))
	var target_faction: String = GameConfig.PHILOSOPHY_ORDER if role_str == GameConfig.ROLE_AVATAR_ORDEN else GameConfig.PHILOSOPHY_CHAOS
	var until_ts: float = Time.get_unix_time_from_system() + 1800.0
	var blessed_count: int = 0
	for pid_var: Variant in _server_states.keys():
		var pid: int = int(pid_var)
		var tst: Dictionary = _server_states[pid] as Dictionary
		if str(tst.get("philosophy", "")) == target_faction:
			tst["faction_grace_until"] = until_ts
			_recompute_stats(tst, NetworkManager.get_peer_profile(pid), true)
			_rpc_update_player_state.rpc(pid, _pack_public_state(tst))
			blessed_count += 1
	var col: String = "#ffe066" if target_faction == GameConfig.PHILOSOPHY_ORDER else "#ff4d36"
	NetworkManager.broadcast_banner(
		"⚡ ¡GRACIA COMBATIVA PARA %s!" % target_faction.to_upper(),
		"%s otorgó +100%% a todas las estadísticas durante 30 min a %d campeones de su facción." % [str(acc.get("username", "")), blessed_count],
		col
	)


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
	elif cmd == "respawn_bosses":
		_server_respawn_all_bosses_now()
		NetworkManager.broadcast_banner("¡DESPERTAR DE COLOSOS Y DRAGONES!", "Los Jefes de Mundo y Dragones Supremos del Valle Dracónico han resurgido.", "#ff6644")
	elif cmd == "season_reset":
		SeasonResetSystem.execute_season_reset(_building_auth)
		NetworkManager.broadcast_season_data()
	elif cmd == "kick":
		var tpeer: int = int(NetworkManager.username_to_peer.get(arg_text.strip_edges().to_lower(), -1))
		if tpeer > 1:
			multiplayer.multiplayer_peer.disconnect_peer(tpeer)
			NetworkManager.broadcast_system_message("%s fue expulsado del plano mortal por un Avatar." % arg_text.strip_edges(), "#ff6666")


# --- Authoritative World Bosses, Supreme Dragon Bosses & 4-Player Dungeon Bosses ---

func _server_init_bosses() -> void:
	_server_bosses.clear()
	for bdef: Dictionary in GameConfig.WORLD_BOSSES:
		var xz: Vector2 = bdef["spawn_xz"] as Vector2
		var wy: float = GameConfig.sample_terrain_height(xz.x, xz.y)
		var bpos: Vector3 = Vector3(xz.x, wy, xz.y)
		var bid: String = str(bdef["id"])
		var is_sup: bool = bool(bdef.get("is_supreme_dragon", false))
		_server_bosses[bid] = {
			"id": bid,
			"name": str(bdef["name"]),
			"title": str(bdef["title"]),
			"style": str(bdef["style"]),
			"is_supreme_dragon": is_sup,
			"spawn_pos": bpos,
			"pos": bpos,
			"yaw": 0.0,
			"max_hp": float(bdef["max_hp"]),
			"hp": float(bdef["max_hp"]),
			"damage": float(bdef["damage"]),
			"aoe_damage": float(bdef["aoe_damage"]),
			"aoe_radius": float(bdef["aoe_radius"]),
			"aggro_range": float(bdef["aggro_range"]),
			"respawn_sec": float(bdef["respawn_sec"]),
			"xp_reward": int(bdef.get("xp_reward", 2400)),
			"gold_reward": 650 if is_sup else 350,
			"is_dungeon": false,
			"alive": true,
			"respawn_at": 0.0,
			"melee_cd": 0.0,
			"aoe_cd": 5.0,
			"pending_aoe_at": 0.0
		}
		_rpc_spawn_or_sync_boss.rpc(bid, str(bdef["name"]), str(bdef["title"]), str(bdef["style"]), is_sup, bpos, 0.0, float(bdef["max_hp"]), float(bdef["max_hp"]), true)

	for ddef: Dictionary in GameConfig.DUNGEONS:
		var did: String = "dungeon_boss_" + str(ddef["id"])
		var arena: Vector3 = ddef["arena_origin"] as Vector3
		var bpos: Vector3 = arena + Vector3(0.0, 0.2, -32.0)
		var style: String = "seraphim" if str(ddef["theme"]) == "order" else "behemoth"
		var b_hp: float = float(ddef["boss_hp"])
		_server_bosses[did] = {
			"id": did,
			"name": str(ddef["boss_name"]),
			"title": str(ddef["name"]),
			"style": style,
			"is_supreme_dragon": false,
			"spawn_pos": bpos,
			"pos": bpos,
			"yaw": 0.0,
			"max_hp": b_hp,
			"hp": b_hp,
			"damage": 32.0,
			"aoe_damage": 58.0,
			"aoe_radius": 8.5,
			"aggro_range": 32.0,
			"respawn_sec": 180.0,
			"xp_reward": int(ddef.get("xp_reward", 3200)),
			"gold_reward": 450,
			"is_dungeon": true,
			"alive": true,
			"respawn_at": 0.0,
			"melee_cd": 0.0,
			"aoe_cd": 5.0,
			"pending_aoe_at": 0.0
		}
		_rpc_spawn_or_sync_boss.rpc(did, str(ddef["boss_name"]), str(ddef["name"]), style, false, bpos, 0.0, b_hp, b_hp, true)


func _server_respawn_all_bosses_now() -> void:
	for bid_var: Variant in _server_bosses.keys():
		var b: Dictionary = _server_bosses[bid_var] as Dictionary
		b["alive"] = true
		b["hp"] = b["max_hp"]
		b["pos"] = b["spawn_pos"]
		b["pending_aoe_at"] = 0.0
		_rpc_spawn_or_sync_boss.rpc(str(b["id"]), str(b["name"]), str(b["title"]), str(b["style"]), bool(b.get("is_supreme_dragon", false)), b["pos"] as Vector3, 0.0, float(b["hp"]), float(b["max_hp"]), true)


func _server_tick_bosses(dt: float) -> void:
	var now: float = Time.get_unix_time_from_system()
	for bid_var: Variant in _server_bosses.keys():
		var b: Dictionary = _server_bosses[bid_var] as Dictionary
		var is_sup: bool = bool(b.get("is_supreme_dragon", false))
		if not bool(b["alive"]):
			if now >= float(b["respawn_at"]):
				b["alive"] = true
				b["hp"] = b["max_hp"]
				b["pos"] = b["spawn_pos"]
				b["pending_aoe_at"] = 0.0
				_rpc_spawn_or_sync_boss.rpc(str(b["id"]), str(b["name"]), str(b["title"]), str(b["style"]), is_sup, b["pos"] as Vector3, 0.0, float(b["hp"]), float(b["max_hp"]), true)
				if not bool(b["is_dungeon"]):
					NetworkManager.broadcast_system_message("☠ JEFE DE MUNDO: %s ha reaparecido en (%d, %d)." % [str(b["name"]), int((b["pos"] as Vector3).x), int((b["pos"] as Vector3).z)], "#ff7744")
			continue

		var bpos: Vector3 = b["pos"] as Vector3
		var spawn_pos: Vector3 = b["spawn_pos"] as Vector3
		var aggro_r: float = float(b["aggro_range"])

		var pend_at: float = float(b["pending_aoe_at"])
		if pend_at > 0.0 and now >= pend_at:
			b["pending_aoe_at"] = 0.0
			var aoe_r: float = float(b["aoe_radius"])
			var aoe_dmg: float = float(b["aoe_damage"])
			for pid_var: Variant in _server_states.keys():
				var pid: int = int(pid_var)
				if server_get_player_position(pid).distance_to(bpos) <= aoe_r:
					_server_apply_damage_to_player(pid, 0, aoe_dmg, bpos)

		var nearest_pid: int = -1
		var nearest_dist: float = aggro_r
		for pid_var: Variant in _server_states.keys():
			var pid: int = int(pid_var)
			var ppos: Vector3 = server_get_player_position(pid)
			var d: float = ppos.distance_to(bpos)
			if d < nearest_dist:
				nearest_dist = d
				nearest_pid = pid

		b["melee_cd"] = maxf(0.0, float(b["melee_cd"]) - dt)
		b["aoe_cd"] = maxf(0.0, float(b["aoe_cd"]) - dt)

		if nearest_pid > 0:
			var tpos: Vector3 = server_get_player_position(nearest_pid)
			var flat_delta: Vector3 = Vector3(tpos.x - bpos.x, 0.0, tpos.z - bpos.z)
			if flat_delta.length() > 0.2:
				b["yaw"] = atan2(flat_delta.x, flat_delta.z)
			if flat_delta.length() > 4.8 and pend_at <= 0.0:
				var step: Vector3 = flat_delta.normalized() * (6.8 if is_sup else 5.2) * dt
				bpos.x += step.x
				bpos.z += step.z
				if not bool(b["is_dungeon"]):
					bpos.y = GameConfig.sample_terrain_height(bpos.x, bpos.z)
				b["pos"] = bpos
			if flat_delta.length() <= 6.5 and float(b["melee_cd"]) <= 0.0 and pend_at <= 0.0:
				b["melee_cd"] = 2.5
				_server_apply_damage_to_player(nearest_pid, 0, float(b["damage"]), bpos)
			if float(b["aoe_cd"]) <= 0.0 and pend_at <= 0.0:
				b["aoe_cd"] = 9.0
				b["pending_aoe_at"] = now + 1.8
				_rpc_boss_telegraph.rpc(str(b["id"]), float(b["aoe_radius"]), 1.8)
		elif bpos.distance_to(spawn_pos) > 2.5:
			var back: Vector3 = (spawn_pos - bpos).normalized() * 4.2 * dt
			bpos += back
			if not bool(b["is_dungeon"]):
				bpos.y = GameConfig.sample_terrain_height(bpos.x, bpos.z)
			b["pos"] = bpos

		_rpc_spawn_or_sync_boss.rpc(str(b["id"]), str(b["name"]), str(b["title"]), str(b["style"]), is_sup, b["pos"] as Vector3, float(b["yaw"]), float(b["hp"]), float(b["max_hp"]), true)


func _server_damage_bosses_in_radius(world_center: Vector3, radius: float, damage: float, attacker_pid: int, attacker_name: String) -> void:
	for bid_var: Variant in _server_bosses.keys():
		var b: Dictionary = _server_bosses[bid_var] as Dictionary
		if bool(b["alive"]) and (b["pos"] as Vector3).distance_to(world_center) <= radius:
			_server_damage_boss(str(bid_var), damage, attacker_pid, attacker_name)


func _server_damage_boss(boss_id: String, damage: float, attacker_pid: int, attacker_name: String) -> void:
	if not _server_bosses.has(boss_id):
		return
	var b: Dictionary = _server_bosses[boss_id] as Dictionary
	if not bool(b["alive"]):
		return
	var is_sup: bool = bool(b.get("is_supreme_dragon", false))
	b["hp"] = maxf(0.0, float(b["hp"]) - damage)
	if float(b["hp"]) <= 0.0:
		b["alive"] = false
		b["pending_aoe_at"] = 0.0
		b["respawn_at"] = Time.get_unix_time_from_system() + float(b["respawn_sec"])
		_rpc_spawn_or_sync_boss.rpc(boss_id, str(b["name"]), str(b["title"]), str(b["style"]), is_sup, b["pos"] as Vector3, float(b["yaw"]), 0.0, float(b["max_hp"]), false)
		_server_drop_boss_epic_loot(b, attacker_pid, attacker_name)
	else:
		_rpc_spawn_or_sync_boss.rpc(boss_id, str(b["name"]), str(b["title"]), str(b["style"]), is_sup, b["pos"] as Vector3, float(b["yaw"]), float(b["hp"]), float(b["max_hp"]), true)


func _server_drop_boss_epic_loot(b: Dictionary, slayer_pid: int, slayer_name: String) -> void:
	var drop_pos: Vector3 = b["pos"] as Vector3
	if not bool(b["is_dungeon"]):
		drop_pos.y = GameConfig.sample_terrain_height(drop_pos.x, drop_pos.z) + 0.1
	var is_sup: bool = bool(b.get("is_supreme_dragon", false))
	var epic_items: Dictionary = {
		"boss_blueprint": 1,
		"mythic_ingot": 4 if is_sup else 2,
		"arcane_gem": 4 if is_sup else 2,
		"dungeon_essence": 3 if bool(b["is_dungeon"]) else 2,
		"raw_meat": 4
	}
	if is_sup:
		epic_items["dragon_mount_stone"] = 1
	var gold: int = int(b.get("gold_reward", 350))
	server_spawn_world_loot_bag("Tesoro de %s" % str(b["name"]), drop_pos, gold, epic_items)
	if slayer_pid > 0:
		_server_grant_xp_with_party(slayer_pid, int(b.get("xp_reward", 2400)))
	var extra_msg: String = " ¡INCLUYE PIEDRA DE VÍNCULO DE DRAGÓN!" if is_sup else ""
	NetworkManager.broadcast_banner(
		"🐉 ¡JEFE DERROTADO: %s!" % str(b["name"]),
		"%s dio el golpe final. Cofre mítico en (%d, %d) con %d oro.%s" % [slayer_name, int(drop_pos.x), int(drop_pos.z), gold, extra_msg],
		"#ffe066"
	)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_or_sync_boss(boss_id: String, bname: String, btitle: String, bstyle: String, is_supreme_dragon: bool, world_pos: Vector3, yaw: float, hp: float, max_hp: float, alive: bool) -> void:
	if _bosses_container == null:
		return
	var wb: WorldBoss
	if boss_nodes.has(boss_id):
		wb = boss_nodes[boss_id] as WorldBoss
	else:
		if is_supreme_dragon:
			wb = DRAGON_BOSS_SCENE.instantiate() as WorldBoss
		else:
			wb = BOSS_SCENE.instantiate() as WorldBoss
		_bosses_container.add_child(wb)
		wb.setup(boss_id, bname, btitle, bstyle, max_hp, world_pos)
		boss_nodes[boss_id] = wb
	wb.apply_sync_state(world_pos, yaw, hp, max_hp, alive)


@rpc("authority", "call_local", "reliable")
func _rpc_boss_telegraph(boss_id: String, radius: float, windup_sec: float) -> void:
	if boss_nodes.has(boss_id):
		(boss_nodes[boss_id] as WorldBoss).trigger_aoe_telegraph(radius, windup_sec)


# --- 4-Player Complex Dungeon Portal Teleportation (Solo Bypass for Admins) ---

func request_use_dungeon_portal(dungeon_id: String, is_exit: bool) -> void:
	_rpc_use_dungeon_portal.rpc_id(1, dungeon_id, is_exit)


@rpc("any_peer", "call_local", "reliable")
func _rpc_use_dungeon_portal(dungeon_id: String, is_exit: bool) -> void:
	if not NetworkManager.is_server_running():
		return
	var sender_id: int = _get_sender_id()
	if not _server_states.has(sender_id):
		return
	var ddef: Dictionary = {}
	for d: Dictionary in GameConfig.DUNGEONS:
		if str(d["id"]) == dungeon_id:
			ddef = d
			break
	if ddef.is_empty():
		return
	var st: Dictionary = _server_states[sender_id] as Dictionary

	if not is_exit:
		var check: Dictionary = PartySystem.can_enter_complex_dungeon(sender_id, str(st.get("role", GameConfig.ROLE_PLAYER)))
		if not bool(check.get("ok", false)):
			NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Mazmorra", "Requisito de Grupo", str(check.get("error", "Se requiere un grupo de 4 jugadores.")), "#ffaa66")
			return
		# Auto-return dragon to backpack when entering underground dungeon
		if bool(st.get("is_mounted", false)):
			st["is_mounted"] = false
			st["has_dragon"] = false
			_rpc_despawn_dragon.rpc(sender_id)

	var dest: Vector3
	if is_exit:
		var exz: Vector2 = ddef["entrance_xz"] as Vector2
		dest = Vector3(exz.x + 3.5, GameConfig.sample_terrain_height(exz.x + 3.5, exz.y) + 1.2, exz.y)
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Mazmorra", "Sistema", "Regresaste al mundo abierto desde %s." % str(ddef["name"]), "#8fc7ff")
	else:
		var arena: Vector3 = ddef["arena_origin"] as Vector3
		dest = arena + Vector3(0.0, 1.2, 42.0)
		NetworkManager._rpc_receive_chat.rpc_id(sender_id, "Mazmorra", "Sistema", "Ingresaste a %s. Atravesá las 3 cámaras hasta la Sala del Jefe Final." % str(ddef["name"]), "#ffb84d")

	st["position"] = [dest.x, dest.y, dest.z]
	_rpc_teleport_player.rpc(sender_id, dest)
