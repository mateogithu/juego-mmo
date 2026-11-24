extends Node

## Server-side atomic JSON database with automatic backup, plus lightweight client preferences.
## Stores hashed user accounts, inventories, zero-P2W cosmetics, world structures,
## player kingdoms/guilds, market listings, player bounties, and persistent Gracia Combativa timers.

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


func _exit_tree() -> void:
	if _dirty and not data.is_empty():
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
		_seed_creator_avatars()
	GameConfig.set_world_seed(int(data.get("world_seed", GameConfig.world_seed)))
	print("[DatabaseManager] Database loaded (seed=%d, %d accounts, %d delta chunks, %d guilds)." % [
		GameConfig.world_seed,
		(data["accounts"] as Dictionary).size(),
		(data["chunk_deltas"] as Dictionary).size(),
		(data["guilds"] as Dictionary).size()
	])


func save_database() -> bool:
	if data.is_empty():
		return false
	var json_text: String = JSON.stringify(data, "\t")
	var tmp_file: FileAccess = FileAccess.open(DB_TMP_PATH, FileAccess.WRITE)
	if tmp_file == null:
		push_error("[DatabaseManager] Failed to open temp database file for writing.")
		return false
	tmp_file.store_string(json_text)
	tmp_file.flush()
	tmp_file.close()

	# Automatic rolling backup of previous valid database
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
		# Fallback direct write if rename across mounts is restricted
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
	return {
		"version": GameConfig.PROTOCOL_VERSION,
		"world_seed": GameConfig.world_seed,
		"next_building_id": 1,
		"next_loot_id": 1,
		"next_listing_id": 1,
		"next_bounty_id": 1,
		"accounts": {},
		"chunk_deltas": {},
		"guilds": {},
		"market_listings": [],
		"bounties": [],
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


func _seed_creator_avatars() -> void:
	var accounts: Dictionary = data["accounts"] as Dictionary
	if not accounts.has("avatarorden"):
		var res_o: Dictionary = register_account("AvatarOrden", "orden_creador", "ARCANE_KNIGHT", GameConfig.ROLE_AVATAR_ORDEN)
		if bool(res_o.get("ok", false)):
			var acc_o: Dictionary = accounts["avatarorden"] as Dictionary
			acc_o["philosophy"] = GameConfig.PHILOSOPHY_ORDER
			acc_o["crowns"] = 99999
			acc_o["gold"] = 50000
			var cos_o: Dictionary = acc_o["cosmetics"] as Dictionary
			cos_o["owned_armors"] = ["default_iron", "order_paladin_gold", "astral_silver", "royal_crimson", "chaos_obsidian"]
			cos_o["owned_dragons"] = ["crimson_wyrm", "celestial_white", "azure_drake", "emerald_ancient", "abyssal_black"]
			cos_o["owned_trails"] = ["none", "golden_order", "starlight_ribbon", "ember_sparks", "shadow_mist"]
			cos_o["equipped_armor"] = "order_paladin_gold"
			cos_o["equipped_dragon"] = "celestial_white"
			cos_o["equipped_trail"] = "golden_order"

	if not accounts.has("avatarcaos"):
		var res_c: Dictionary = register_account("AvatarCaos", "caos_creador", "PYROMANCER", GameConfig.ROLE_AVATAR_CAOS)
		if bool(res_c.get("ok", false)):
			var acc_c: Dictionary = accounts["avatarcaos"] as Dictionary
			acc_c["philosophy"] = GameConfig.PHILOSOPHY_CHAOS
			acc_c["crowns"] = 99999
			acc_c["gold"] = 50000
			var cos_c: Dictionary = acc_c["cosmetics"] as Dictionary
			cos_c["owned_armors"] = ["default_iron", "chaos_obsidian", "royal_crimson", "astral_silver", "order_paladin_gold"]
			cos_c["owned_dragons"] = ["crimson_wyrm", "abyssal_black", "azure_drake", "emerald_ancient", "celestial_white"]
			cos_c["owned_trails"] = ["none", "ember_sparks", "shadow_mist", "starlight_ribbon", "golden_order"]
			cos_c["equipped_armor"] = "chaos_obsidian"
			cos_c["equipped_dragon"] = "abyssal_black"
			cos_c["equipped_trail"] = "ember_sparks"


func _hash_password(password: String, salt: String) -> String:
	return (salt + "::" + password + "::cronicas_mmo_v1").sha256_text()


func _generate_salt(username: String) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return ("%s_%d_%d" % [username, Time.get_ticks_usec(), rng.randi()]).sha256_text().substr(0, 16)


func register_account(username: String, password: String, class_id: String, role: String = GameConfig.ROLE_PLAYER) -> Dictionary:
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
	var salt: String = _generate_salt(clean_user)
	var pw_hash: String = _hash_password(password, salt)
	var spawn_x: float = randf_range(-10.0, 10.0)
	var spawn_z: float = randf_range(-10.0, 10.0)
	var spawn_y: float = GameConfig.sample_terrain_height(spawn_x, spawn_z) + 1.5

	var profile: Dictionary = {
		"username": clean_user,
		"salt": salt,
		"password_hash": pw_hash,
		"role": role,
		"class_id": valid_class,
		"philosophy": GameConfig.PHILOSOPHY_NEUTRAL,
		"guild_id": "",
		"gold": 150,
		"crowns": 1000,
		"inventory": {
			"wood": 30,
			"stone": 30,
			"arcane_ore": 12,
			"health_potion": 3,
			"mana_potion": 2
		},
		"equipped_weapon": "",
		"equipped_armor_item": "",
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
	if _hash_password(password, salt) != expected:
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
	return copy


func update_player_position(username: String, pos: Vector3) -> void:
	var acc: Dictionary = get_account_mutable(username)
	if acc.is_empty():
		return
	acc["position"] = [pos.x, pos.y, pos.z]
	mark_dirty()


func add_item(username: String, item_id: String, qty: int) -> bool:
	if qty <= 0 or not GameConfig.ITEMS.has(item_id):
		return false
	var acc: Dictionary = get_account_mutable(username)
	if acc.is_empty():
		return false
	var inv: Dictionary = acc["inventory"] as Dictionary
	var current: int = int(inv.get(item_id, 0))
	inv[item_id] = current + qty
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
		var req: int = int(costs[item_id])
		if int(inv.get(str(item_id), 0)) < req:
			return false
	return true


func consume_items(username: String, costs: Dictionary) -> bool:
	if not has_items(username, costs):
		return false
	for item_id: Variant in costs.keys():
		remove_item(username, str(item_id), int(costs[item_id]))
	return true


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
		deltas[ckey] = {
			"buildings": [],
			"destroyed_ids": [],
			"loot_chests": []
		}
	return deltas[ckey] as Dictionary


func get_buildings() -> Array:
	var out: Array = []
	var deltas: Dictionary = data["chunk_deltas"] as Dictionary
	for ckey_var: Variant in deltas.keys():
		var bucket: Dictionary = deltas[ckey_var] as Dictionary
		var blist: Array = bucket.get("buildings", []) as Array
		for rec_var: Variant in blist:
			out.append(rec_var)
	return out


func get_chunk_buildings(coord: Vector2i) -> Array:
	var deltas: Dictionary = data["chunk_deltas"] as Dictionary
	var ckey: String = GameConfig.chunk_key(coord)
	if not deltas.has(ckey):
		return []
	return ((deltas[ckey] as Dictionary).get("buildings", []) as Array).duplicate(true)


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
		var llist: Array = bucket.get("loot_chests", []) as Array
		for rec_var: Variant in llist:
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


# --- Client-side local preferences (IntroLore first-account check & last login info) ---

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
