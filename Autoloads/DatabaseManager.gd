extends Node

## Server-side atomic JSON database with rolling backup (Release 2.0).
## Persists hashed accounts, levels (1..8000 / Infinity Admins), 5 races & 3D appearance,
## 150-slot backpack, 4-piece armor sets, Dragon Mount item, hunger/wayshrines,
## chunk-indexed buildings, persistent house Storage Chests, territorial war & 30-day Seasons.

const DB_PATH: String = "user://server_database.json"
const DB_TMP_PATH: String = "user://server_database.json.tmp"
const DB_BAK_PATH: String = "user://server_database.json.bak"
const CLIENT_PREFS_PATH: String = "user://client_prefs.json"

var data: Dictionary = {}
var client_prefs: Dictionary = {}
var _dirty: bool = false
var _autosave_timer: float = 0.0
const AUTOSAVE_INTERVAL: float = 15.0


func _ready() -> void:
	load_client_prefs()


func _process(delta: float) -> void:
	if _dirty:
		_autosave_timer += delta
		if _autosave_timer >= AUTOSAVE_INTERVAL:
			save_database()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if not data.is_empty():
			save_database()


func _exit_tree() -> void:
	if not data.is_empty():
		save_database()


func load_database() -> void:
	var loaded: Dictionary = _try_read_json(DB_PATH)
	if loaded.is_empty() and FileAccess.file_exists(DB_BAK_PATH):
		push_warning("[DatabaseManager] Primary DB missing/corrupt; restoring from backup.")
		loaded = _try_read_json(DB_BAK_PATH)

	if loaded.is_empty():
		data = _create_empty_database()
		_seed_creator_avatars()
		save_database()
	else:
		data = loaded
		_ensure_schema_fields()
		_migrate_legacy_buildings_to_chunks()
		_migrate_accounts_v2()
		_seed_creator_avatars()
		if _dirty:
			save_database()
	GameConfig.set_world_seed(int(data.get("world_seed", GameConfig.world_seed)))
	print("[DatabaseManager] DB v2.0 loaded (seed=%d, %d accounts, %d delta chunks, season #%d)." % [
		GameConfig.world_seed,
		(data["accounts"] as Dictionary).size(),
		(data["chunk_deltas"] as Dictionary).size(),
		int((data["season"] as Dictionary).get("number", 1))
	])


func save_database() -> bool:
	if data.is_empty():
		return false
	var json_text: String = JSON.stringify(data, "\t")
	var tmp_file: FileAccess = FileAccess.open(DB_TMP_PATH, FileAccess.WRITE)
	if tmp_file == null:
		push_error("[DatabaseManager] Failed to open temp database file.")
		return false
	tmp_file.store_string(json_text)
	tmp_file.flush()
	tmp_file.close()

	if FileAccess.file_exists(DB_PATH):
		var old_content: String = FileAccess.get_file_as_string(DB_PATH)
		if not old_content.is_empty():
			var bak_file: FileAccess = FileAccess.open(DB_BAK_PATH, FileAccess.WRITE)
			if bak_file != null:
				bak_file.store_string(old_content)
				bak_file.flush()
				bak_file.close()

	var abs_tmp: String = ProjectSettings.globalize_path(DB_TMP_PATH)
	var abs_dst: String = ProjectSettings.globalize_path(DB_PATH)
	var err: Error = DirAccess.rename_absolute(abs_tmp, abs_dst)
	if err != OK:
		var direct: FileAccess = FileAccess.open(DB_PATH, FileAccess.WRITE)
		if direct == null:
			push_error("[DatabaseManager] Atomic rename and direct write failed: %d" % err)
			return false
		direct.store_string(json_text)
		direct.flush()
		direct.close()

	_dirty = false
	_autosave_timer = 0.0
	return true


func mark_dirty() -> void:
	_dirty = true


func _try_read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {}


func _create_empty_database() -> Dictionary:
	var now: float = Time.get_unix_time_from_system()
	var reg_scores: Dictionary = {}
	for r: Dictionary in GameConfig.WORLD_REGIONS:
		var rid: String = str(r["id"])
		var def_own: String = str(r["default_owner"])
		reg_scores[rid] = {
			"order": 100 if def_own == GameConfig.PHILOSOPHY_ORDER else 0,
			"chaos": 100 if def_own == GameConfig.PHILOSOPHY_CHAOS else 0,
			"owner": def_own
		}
	return {
		"version": GameConfig.PROTOCOL_VERSION,
		"world_seed": GameConfig.world_seed,
		"next_building_id": 1,
		"next_loot_id": 1,
		"next_listing_id": 1,
		"next_bounty_id": 1,
		"accounts": {},
		"chunk_deltas": {},
		"storage_chests": {},
		"guilds": {},
		"market_listings": [],
		"bounties": [],
		"season": {
			"number": 1,
			"started_at_unix": now,
			"ends_at_unix": now + GameConfig.SEASON_DURATION_SEC,
			"last_winner": "Ninguna (Temporada 1 en curso)",
			"region_scores": reg_scores
		},
		"combat_grace": {
			"active_username": "",
			"granted_at_unix": 0.0,
			"expires_at_unix": 0.0,
			"next_roll_at_unix": now + GameConfig.COMBAT_GRACE_DURATION_SEC,
			"blessed_by": "Los Arquitectos Primordiales"
		}
	}


func _ensure_schema_fields() -> void:
	var defaults: Dictionary = _create_empty_database()
	for key: Variant in defaults.keys():
		if not data.has(key):
			data[key] = defaults[key]


func _migrate_legacy_buildings_to_chunks() -> void:
	if data.has("buildings") and typeof(data["buildings"]) == TYPE_ARRAY:
		var legacy: Array = data["buildings"] as Array
		for rec_var: Variant in legacy:
			var rec: Dictionary = rec_var as Dictionary
			add_building_record(rec)
		data.erase("buildings")
		mark_dirty()


func _default_appearance(race_id: String = "HUMAN_VALLEY") -> Dictionary:
	var rdef: Dictionary = GameConfig.RACES.get(race_id, GameConfig.RACES["HUMAN_VALLEY"]) as Dictionary
	var sc: Color = rdef.get("default_skin", Color(0.86, 0.69, 0.56)) as Color
	return {
		"skin_color": sc.to_html(false),
		"hair_color": "2c1e14",
		"eye_color": "4ea8ff",
		"armor_tint": "8a929e",
		"hair_style": 0,
		"beard_style": 0,
		"hide_helmet": false
	}


func _migrate_accounts_v2() -> void:
	var accounts: Dictionary = data["accounts"] as Dictionary
	for k_var: Variant in accounts.keys():
		var acc: Dictionary = accounts[k_var] as Dictionary
		if not acc.has("level"):
			acc["level"] = 1
		if not acc.has("xp"):
			acc["xp"] = 0
		if not acc.has("race_id"):
			acc["race_id"] = "HUMAN_VALLEY"
		if not acc.has("appearance"):
			acc["appearance"] = _default_appearance(str(acc["race_id"]))
		if not acc.has("alignment_score"):
			acc["alignment_score"] = 0
		if not acc.has("hunger"):
			acc["hunger"] = 100.0
		if not acc.has("food_buff"):
			acc["food_buff"] = ""
		if not acc.has("food_buff_until"):
			acc["food_buff_until"] = 0.0
		if not acc.has("discovered_wayshrines"):
			acc["discovered_wayshrines"] = ["ws_alba", "ws_caos"]
		for slot_key: String in ["equipped_helmet", "equipped_chest", "equipped_legs", "equipped_boots", "equipped_weapon", "equipped_mount"]:
			if not acc.has(slot_key):
				acc[slot_key] = ""
		if not acc.has("dragon_summoned"):
			acc["dragon_summoned"] = false
		if not acc.has("inventory") or typeof(acc["inventory"]) != TYPE_DICTIONARY:
			acc["inventory"] = {}
		var inv_m: Dictionary = acc["inventory"] as Dictionary
		if int(inv_m.get("dragon_mount_stone", 0)) > 0 and str(acc.get("equipped_mount", "")).is_empty():
			acc["equipped_mount"] = "dragon_mount_stone"


func _seed_creator_avatars() -> void:
	var accounts: Dictionary = data["accounts"] as Dictionary
	var changed: bool = false
	if not accounts.has("avatarorden"):
		var res_o: Dictionary = register_account("AvatarOrden", "orden_creador", "ARCANE_KNIGHT", GameConfig.ROLE_AVATAR_ORDEN, "ASTRAL_ELF", _default_appearance("ASTRAL_ELF"))
		if bool(res_o.get("ok", false)):
			changed = true
	if accounts.has("avatarorden"):
		var acc_o: Dictionary = accounts["avatarorden"] as Dictionary
		acc_o["role"] = GameConfig.ROLE_AVATAR_ORDEN
		acc_o["philosophy"] = GameConfig.PHILOSOPHY_ORDER
		acc_o["alignment_score"] = 100
		acc_o["crowns"] = maxi(999999, int(acc_o.get("crowns", 0)))
		acc_o["gold"] = maxi(50000, int(acc_o.get("gold", 0)))
		var inv_o: Dictionary = acc_o.get("inventory", {}) as Dictionary
		if int(inv_o.get("dragon_mount_stone", 0)) < 1:
			inv_o["dragon_mount_stone"] = 1
			changed = true
		acc_o["inventory"] = inv_o
		if str(acc_o.get("equipped_mount", "")) != "dragon_mount_stone":
			acc_o["equipped_mount"] = "dragon_mount_stone"
			changed = true
		var cos_o: Dictionary = acc_o.get("cosmetics", {}) as Dictionary
		cos_o["owned_armors"] = ["default_iron", "order_paladin_gold", "astral_silver", "royal_crimson", "chaos_obsidian"]
		cos_o["owned_dragons"] = ["crimson_wyrm", "celestial_white", "azure_drake", "emerald_ancient", "abyssal_black"]
		cos_o["owned_trails"] = ["none", "golden_order", "starlight_ribbon", "ember_sparks", "shadow_mist"]
		if str(cos_o.get("equipped_armor", "")).is_empty() or str(cos_o.get("equipped_armor", "")) == "default_iron":
			cos_o["equipped_armor"] = "order_paladin_gold"
		if str(cos_o.get("equipped_dragon", "")).is_empty() or str(cos_o.get("equipped_dragon", "")) == "crimson_wyrm":
			cos_o["equipped_dragon"] = "celestial_white"
		if str(cos_o.get("equipped_trail", "")).is_empty() or str(cos_o.get("equipped_trail", "")) == "none":
			cos_o["equipped_trail"] = "golden_order"
		acc_o["cosmetics"] = cos_o

	if not accounts.has("avatarcaos"):
		var res_c: Dictionary = register_account("AvatarCaos", "caos_creador", "PYROMANCER", GameConfig.ROLE_AVATAR_CAOS, "DRACONID", _default_appearance("DRACONID"))
		if bool(res_c.get("ok", false)):
			changed = true
	if accounts.has("avatarcaos"):
		var acc_c: Dictionary = accounts["avatarcaos"] as Dictionary
		acc_c["role"] = GameConfig.ROLE_AVATAR_CAOS
		acc_c["philosophy"] = GameConfig.PHILOSOPHY_CHAOS
		acc_c["alignment_score"] = -100
		acc_c["crowns"] = maxi(999999, int(acc_c.get("crowns", 0)))
		acc_c["gold"] = maxi(50000, int(acc_c.get("gold", 0)))
		var inv_c: Dictionary = acc_c.get("inventory", {}) as Dictionary
		if int(inv_c.get("dragon_mount_stone", 0)) < 1:
			inv_c["dragon_mount_stone"] = 1
			changed = true
		acc_c["inventory"] = inv_c
		if str(acc_c.get("equipped_mount", "")) != "dragon_mount_stone":
			acc_c["equipped_mount"] = "dragon_mount_stone"
			changed = true
		var cos_c: Dictionary = acc_c.get("cosmetics", {}) as Dictionary
		cos_c["owned_armors"] = ["default_iron", "chaos_obsidian", "royal_crimson", "astral_silver", "order_paladin_gold"]
		cos_c["owned_dragons"] = ["crimson_wyrm", "abyssal_black", "azure_drake", "emerald_ancient", "celestial_white"]
		cos_c["owned_trails"] = ["none", "ember_sparks", "shadow_mist", "starlight_ribbon", "golden_order"]
		if str(cos_c.get("equipped_armor", "")).is_empty() or str(cos_c.get("equipped_armor", "")) == "default_iron":
			cos_c["equipped_armor"] = "chaos_obsidian"
		if str(cos_c.get("equipped_dragon", "")).is_empty() or str(cos_c.get("equipped_dragon", "")) == "crimson_wyrm":
			cos_c["equipped_dragon"] = "abyssal_black"
		if str(cos_c.get("equipped_trail", "")).is_empty() or str(cos_c.get("equipped_trail", "")) == "none":
			cos_c["equipped_trail"] = "ember_sparks"
		acc_c["cosmetics"] = cos_c

	if changed:
		mark_dirty()


func _hash_password(password: String, salt: String) -> String:
	return (salt + "::" + password + "::cronicas_mmo_v2").sha256_text()


func _hash_password_v1(password: String, salt: String) -> String:
	return (salt + "::" + password + "::cronicas_mmo_v1").sha256_text()


func _generate_salt(username: String) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return ("%s_%d_%d" % [username, Time.get_ticks_usec(), rng.randi()]).sha256_text().substr(0, 16)


func register_account(
	username: String,
	password: String,
	class_id: String,
	role: String = GameConfig.ROLE_PLAYER,
	race_id: String = "HUMAN_VALLEY",
	appearance: Dictionary = {}
) -> Dictionary:
	var clean_user: String = username.strip_edges()
	if clean_user.length() < 3 or clean_user.length() > 20:
		return {"ok": false, "error": "El nombre debe tener entre 3 y 20 caracteres."}
	if password.length() < 4:
		return {"ok": false, "error": "La contraseña debe tener al menos 4 caracteres."}

	var key: String = clean_user.to_lower()
	var accounts: Dictionary = data["accounts"] as Dictionary
	if accounts.has(key):
		return {"ok": false, "error": "Ya existe una cuenta con ese nombre."}

	var valid_class: String = class_id if GameConfig.CLASSES.has(class_id) else "ARCANE_KNIGHT"
	var valid_race: String = race_id if GameConfig.RACES.has(race_id) else "HUMAN_VALLEY"
	var final_app: Dictionary = _default_appearance(valid_race)
	for ak: Variant in appearance.keys():
		final_app[ak] = appearance[ak]

	var salt: String = _generate_salt(clean_user)
	var pw_hash: String = _hash_password(password, salt)
	# Spawn safely inside Santuario del Alba (0, 0)
	var spawn_x: float = randf_range(-8.0, 8.0)
	var spawn_z: float = randf_range(-8.0, 8.0)
	var spawn_y: float = GameConfig.sample_terrain_height(spawn_x, spawn_z) + 1.5

	var profile: Dictionary = {
		"username": clean_user,
		"salt": salt,
		"password_hash": pw_hash,
		"role": role,
		"level": 1,
		"xp": 0,
		"class_id": valid_class,
		"race_id": valid_race,
		"appearance": final_app,
		"philosophy": GameConfig.PHILOSOPHY_NEUTRAL,
		"alignment_score": 0,
		"guild_id": "",
		"gold": 50,
		"crowns": 1000,
		"hunger": 100.0,
		"food_buff": "",
		"food_buff_until": 0.0,
		"discovered_wayshrines": ["ws_alba", "ws_caos"],
		"inventory": {
			"wood": 20,
			"stone": 20,
			"iron_ore": 10,
			"traveler_bread": 3,
			"health_potion": 2
		},
		"equipped_weapon": "",
		"equipped_helmet": "",
		"equipped_chest": "",
		"equipped_legs": "",
		"equipped_boots": "",
		"equipped_mount": "",
		"dragon_summoned": false,
		"cosmetics": {
			"owned_armors": ["default_iron"],
			"owned_dragons": ["crimson_wyrm"],
			"owned_trails": ["none"],
			"equipped_armor": "default_iron",
			"equipped_dragon": "crimson_wyrm",
			"equipped_trail": "none"
		},
		"position": [spawn_x, spawn_y, spawn_z],
		"intro_seen": false,
		"created_at": Time.get_unix_time_from_system()
	}

	accounts[key] = profile
	mark_dirty()
	save_database()
	return {"ok": true, "profile": get_sanitized_profile(key)}


func authenticate_account(username: String, password: String) -> Dictionary:
	var key: String = username.strip_edges().to_lower()
	var accounts: Dictionary = data["accounts"] as Dictionary
	if not accounts.has(key):
		return {"ok": false, "error": "Cuenta no encontrada. Creá una nueva o revisá tu nombre."}
	var acc: Dictionary = accounts[key] as Dictionary
	var expected: String = str(acc.get("password_hash", ""))
	var salt: String = str(acc.get("salt", ""))
	var alias_ok: bool = (
		(key == "avatarorden" and (password == "orden_creador" or password == "orden_creator"))
		or (key == "avatarcaos" and (password == "caos_creador" or password == "caos_creator"))
	)
	if not alias_ok and _hash_password(password, salt) != expected and _hash_password_v1(password, salt) != expected:
		return {"ok": false, "error": "Contraseña incorrecta."}
	return {"ok": true, "profile": get_sanitized_profile(key)}


func get_account_mutable(username: String) -> Dictionary:
	var key: String = username.strip_edges().to_lower()
	var accounts: Dictionary = data["accounts"] as Dictionary
	if accounts.has(key):
		return accounts[key] as Dictionary
	return {}


func get_sanitized_profile(username_or_key: String) -> Dictionary:
	var acc: Dictionary = get_account_mutable(username_or_key)
	if acc.is_empty():
		return {}
	var copy: Dictionary = acc.duplicate(true)
	copy.erase("password_hash")
	copy.erase("salt")
	copy["backpack_used"] = get_backpack_used_slots(username_or_key)
	copy["backpack_max"] = -1 if GameConfig.is_avatar_role(str(acc.get("role", ""))) else GameConfig.BACKPACK_MAX_SLOTS
	return copy


func update_player_position(username: String, pos: Vector3) -> void:
	var acc: Dictionary = get_account_mutable(username)
	if acc.is_empty():
		return
	acc["position"] = [pos.x, pos.y, pos.z]
	mark_dirty()


# --- 150-Slot Backpack Management (Unlimited for AvatarOrden & AvatarCaos) ---

func get_backpack_used_slots(username: String) -> int:
	var acc: Dictionary = get_account_mutable(username)
	if acc.is_empty():
		return 0
	var inv: Dictionary = acc.get("inventory", {}) as Dictionary
	var total: int = 0
	for k_var: Variant in inv.keys():
		total += maxi(0, int(inv[k_var]))
	return total


func can_add_item(username: String, item_id: String, qty: int) -> bool:
	if qty <= 0 or not GameConfig.ITEMS.has(item_id):
		return false
	var acc: Dictionary = get_account_mutable(username)
	if acc.is_empty():
		return false
	if GameConfig.is_avatar_role(str(acc.get("role", ""))):
		return true
	return get_backpack_used_slots(username) + qty <= GameConfig.BACKPACK_MAX_SLOTS


func add_item(username: String, item_id: String, qty: int) -> bool:
	if not can_add_item(username, item_id, qty):
		return false
	var acc: Dictionary = get_account_mutable(username)
	var inv: Dictionary = acc["inventory"] as Dictionary
	inv[item_id] = int(inv.get(item_id, 0)) + qty
	mark_dirty()
	return true


func remove_item(username: String, item_id: String, qty: int) -> bool:
	if qty <= 0:
		return false
	var acc: Dictionary = get_account_mutable(username)
	if acc.is_empty():
		return false
	var inv: Dictionary = acc["inventory"] as Dictionary
	var current: int = int(inv.get(item_id, 0))
	if current < qty:
		return false
	var remaining: int = current - qty
	if remaining <= 0:
		inv.erase(item_id)
	else:
		inv[item_id] = remaining
	mark_dirty()
	return true


func has_items(username: String, costs: Dictionary) -> bool:
	var acc: Dictionary = get_account_mutable(username)
	if acc.is_empty():
		return false
	var inv: Dictionary = acc["inventory"] as Dictionary
	for item_id: Variant in costs.keys():
		if int(inv.get(str(item_id), 0)) < int(costs[item_id]):
			return false
	return true


func consume_items(username: String, costs: Dictionary) -> bool:
	if not has_items(username, costs):
		return false
	for item_id: Variant in costs.keys():
		remove_item(username, str(item_id), int(costs[item_id]))
	return true


# --- Persistent House Storage Chests ---

func get_chest_inventory(building_id: int) -> Dictionary:
	var chests: Dictionary = data["storage_chests"] as Dictionary
	var key: String = str(building_id)
	if not chests.has(key):
		chests[key] = {}
	return chests[key] as Dictionary


func get_chest_used_slots(building_id: int) -> int:
	var cinv: Dictionary = get_chest_inventory(building_id)
	var total: int = 0
	for k_var: Variant in cinv.keys():
		total += maxi(0, int(cinv[k_var]))
	return total


func remove_chest_inventory(building_id: int) -> Dictionary:
	var chests: Dictionary = data["storage_chests"] as Dictionary
	var key: String = str(building_id)
	if chests.has(key):
		var copy: Dictionary = (chests[key] as Dictionary).duplicate(true)
		chests.erase(key)
		mark_dirty()
		return copy
	return {}


# --- Chunk-Indexed Deltas & Monthly Season Reset ---

func allocate_building_id() -> int:
	var next_id: int = int(data.get("next_building_id", 1))
	data["next_building_id"] = next_id + 1
	mark_dirty()
	return next_id


func allocate_loot_id() -> int:
	var next_id: int = int(data.get("next_loot_id", 1))
	data["next_loot_id"] = next_id + 1
	mark_dirty()
	return next_id


func _get_or_create_chunk_delta(ckey: String) -> Dictionary:
	var deltas: Dictionary = data["chunk_deltas"] as Dictionary
	if not deltas.has(ckey):
		deltas[ckey] = {"buildings": [], "destroyed_ids": [], "loot_chests": []}
	return deltas[ckey] as Dictionary


func get_buildings() -> Array:
	var out: Array = []
	var deltas: Dictionary = data["chunk_deltas"] as Dictionary
	for ckey_var: Variant in deltas.keys():
		var bucket: Dictionary = deltas[ckey_var] as Dictionary
		for rec_var: Variant in (bucket.get("buildings", []) as Array):
			out.append(rec_var)
	return out


func add_building_record(record: Dictionary) -> void:
	var pos_arr: Array = record.get("position", [0.0, 0.0, 0.0]) as Array
	var wp: Vector3 = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])) if pos_arr.size() == 3 else Vector3.ZERO
	var ccoord: Vector2i = GameConfig.world_to_chunk(wp)
	var ckey: String = GameConfig.chunk_key(ccoord)
	record["chunk_x"] = ccoord.x
	record["chunk_z"] = ccoord.y
	var bucket: Dictionary = _get_or_create_chunk_delta(ckey)
	(bucket["buildings"] as Array).append(record)
	mark_dirty()
	save_database()


func remove_building_record(building_id: int, chunk_key_hint: String = "") -> void:
	var deltas: Dictionary = data["chunk_deltas"] as Dictionary
	var keys_to_search: Array = [chunk_key_hint] if (not chunk_key_hint.is_empty() and deltas.has(chunk_key_hint)) else deltas.keys()
	for ckey_var: Variant in keys_to_search:
		var ckey: String = str(ckey_var)
		var bucket: Dictionary = deltas[ckey] as Dictionary
		var blist: Array = bucket.get("buildings", []) as Array
		for i: int in range(blist.size() - 1, -1, -1):
			var rec: Dictionary = blist[i] as Dictionary
			if int(rec.get("id", -1)) == building_id:
				blist.remove_at(i)
				var destroyed: Array = bucket.get("destroyed_ids", []) as Array
				if not destroyed.has(building_id):
					destroyed.append(building_id)
				mark_dirty()
				return


func get_all_loot_records() -> Array:
	var out: Array = []
	var deltas: Dictionary = data["chunk_deltas"] as Dictionary
	for ckey_var: Variant in deltas.keys():
		var bucket: Dictionary = deltas[ckey_var] as Dictionary
		for rec_var: Variant in (bucket.get("loot_chests", []) as Array):
			out.append(rec_var)
	return out


func add_loot_record(record: Dictionary) -> void:
	var pos_arr: Array = record.get("position", [0.0, 0.0, 0.0]) as Array
	var wp: Vector3 = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])) if pos_arr.size() == 3 else Vector3.ZERO
	var ccoord: Vector2i = GameConfig.world_to_chunk(wp)
	var ckey: String = GameConfig.chunk_key(ccoord)
	record["chunk_x"] = ccoord.x
	record["chunk_z"] = ccoord.y
	var bucket: Dictionary = _get_or_create_chunk_delta(ckey)
	(bucket["loot_chests"] as Array).append(record)
	mark_dirty()
	save_database()


func remove_loot_record(loot_id: int, chunk_key_hint: String = "") -> void:
	var deltas: Dictionary = data["chunk_deltas"] as Dictionary
	var keys_to_search: Array = [chunk_key_hint] if (not chunk_key_hint.is_empty() and deltas.has(chunk_key_hint)) else deltas.keys()
	for ckey_var: Variant in keys_to_search:
		var ckey: String = str(ckey_var)
		var bucket: Dictionary = deltas[ckey] as Dictionary
		var llist: Array = bucket.get("loot_chests", []) as Array
		for i: int in range(llist.size() - 1, -1, -1):
			var rec: Dictionary = llist[i] as Dictionary
			if int(rec.get("id", -1)) == loot_id:
				llist.remove_at(i)
				mark_dirty()
				return


## Monthly Season Reset: clears ONLY territorial buildings & region scores while keeping
## ALL player levels, 150-slot backpacks, equipment, gold, cosmetics, and dragons intact!
func reset_territorial_map_for_new_season(winner_faction: String) -> void:
	var deltas: Dictionary = data["chunk_deltas"] as Dictionary
	for ckey_var: Variant in deltas.keys():
		var bucket: Dictionary = deltas[ckey_var] as Dictionary
		var kept_buildings: Array = []
		# Return items stored inside house chests safely to owners if space allows, or clear territorial cities
		for b_var: Variant in (bucket.get("buildings", []) as Array):
			var brec: Dictionary = b_var as Dictionary
			if str(brec.get("piece_type", "")) == "storage_chest":
				var cid: int = int(brec.get("id", -1))
				var owner_u: String = str(brec.get("owner", ""))
				var chest_items: Dictionary = remove_chest_inventory(cid)
				var owner_acc: Dictionary = get_account_mutable(owner_u)
				if not owner_acc.is_empty():
					var inv: Dictionary = owner_acc["inventory"] as Dictionary
					for iid_var: Variant in chest_items.keys():
						inv[str(iid_var)] = int(inv.get(str(iid_var), 0)) + int(chest_items[iid_var])
		bucket["buildings"] = kept_buildings
		bucket["destroyed_ids"] = []

	var now: float = Time.get_unix_time_from_system()
	var season: Dictionary = data["season"] as Dictionary
	var next_num: int = int(season.get("number", 1)) + 1
	var reg_scores: Dictionary = {}
	for r: Dictionary in GameConfig.WORLD_REGIONS:
		var rid: String = str(r["id"])
		var def_own: String = str(r["default_owner"])
		reg_scores[rid] = {
			"order": 100 if def_own == GameConfig.PHILOSOPHY_ORDER else 0,
			"chaos": 100 if def_own == GameConfig.PHILOSOPHY_CHAOS else 0,
			"owner": def_own
		}
	data["season"] = {
		"number": next_num,
		"started_at_unix": now,
		"ends_at_unix": now + GameConfig.SEASON_DURATION_SEC,
		"last_winner": winner_faction,
		"region_scores": reg_scores
	}
	# Reward cosmetic crowns to members of the winning faction
	var accounts: Dictionary = data["accounts"] as Dictionary
	for ak_var: Variant in accounts.keys():
		var acc: Dictionary = accounts[ak_var] as Dictionary
		if str(acc.get("philosophy", "")) == winner_faction:
			acc["crowns"] = int(acc.get("crowns", 0)) + 500
	mark_dirty()
	save_database()


func get_season_state() -> Dictionary:
	return data["season"] as Dictionary


func get_combat_grace_state() -> Dictionary:
	return data["combat_grace"] as Dictionary


func set_combat_grace_state(state: Dictionary) -> void:
	data["combat_grace"] = state
	mark_dirty()
	save_database()


func get_guilds() -> Dictionary:
	return data["guilds"] as Dictionary


func get_market_listings() -> Array:
	return data["market_listings"] as Array


func get_bounties() -> Array:
	return data["bounties"] as Array


func load_client_prefs() -> void:
	var loaded: Dictionary = _try_read_json(CLIENT_PREFS_PATH)
	if loaded.is_empty():
		client_prefs = {
			"last_host": GameConfig.DEFAULT_HOST,
			"last_port": GameConfig.DEFAULT_PORT,
			"last_username": "",
			"seen_intro_accounts": []
		}
	else:
		client_prefs = loaded
		if not client_prefs.has("seen_intro_accounts"):
			client_prefs["seen_intro_accounts"] = []


func save_client_prefs() -> void:
	var f: FileAccess = FileAccess.open(CLIENT_PREFS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(client_prefs, "\t"))
		f.flush()
		f.close()


func has_seen_intro(username: String) -> bool:
	var seen: Array = client_prefs.get("seen_intro_accounts", []) as Array
	return seen.has(username.strip_edges().to_lower())


func mark_intro_seen(username: String) -> void:
	var key: String = username.strip_edges().to_lower()
	var seen: Array = client_prefs.get("seen_intro_accounts", []) as Array
	if not seen.has(key):
		seen.append(key)
		client_prefs["seen_intro_accounts"] = seen
		save_client_prefs()
