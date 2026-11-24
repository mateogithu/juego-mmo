extends Node

## Authoritative Client-Server ENet networking manager (Release 2.0).
## Supports Dedicated Headless Server (--server), Local Host (Server + Client),
## Remote Client (IP:Port), 5 Classes & 5 Races, Appearance Editor,
## 100% Player Economy, 150-Slot Backpack, Storage Chests, 4-Player Parties,
## P2P Trade, Territorial Season State, and Free Cosmetics for Creator Avatars.

signal connection_status_changed(status_text: String)
signal auth_succeeded(profile: Dictionary, is_new_account: bool)
signal auth_failed(reason: String)
signal profile_updated(profile: Dictionary)
signal chat_message_received(sender: String, channel: String, text: String, color_hex: String)
signal system_banner_received(title: String, body: String, color_hex: String)
signal social_data_updated(guilds: Dictionary, listings: Array, bounties: Array)
signal season_data_updated(season_state: Dictionary)
signal party_updated(party_members: Array)
signal trade_updated(trade_session: Dictionary)
signal chest_opened(building_id: int, owner_name: String, items: Dictionary)
signal peer_authenticated(peer_id: int, profile: Dictionary)
signal peer_session_ended(peer_id: int, username: String)
signal disconnected_from_server(reason: String)

enum NetMode { NONE, DEDICATED_SERVER, HOST, CLIENT }

var mode: NetMode = NetMode.NONE
var local_profile: Dictionary = {}
var local_username: String = ""
var is_new_account_session: bool = false

# Server-only session tables
var peer_to_username: Dictionary = {} # int -> String (lowercase key)
var username_to_peer: Dictionary = {} # String (lowercase key) -> int

# Cached synced data on clients
var cached_guilds: Dictionary = {}
var cached_listings: Array = []
var cached_bounties: Array = []
var cached_season: Dictionary = {}
var cached_party: Array = []
var cached_trade: Dictionary = {}

# Pending client login credentials sent once connected_to_server fires
var _pending_auth: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_dedicated_server_launch() -> bool:
	var args: PackedStringArray = OS.get_cmdline_args()
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg == "--server":
			return true
	for arg: String in user_args:
		if arg == "--server":
			return true
	return DisplayServer.get_name() == "headless"


func get_launch_port() -> int:
	var all_args: Array[String] = []
	for a: String in OS.get_cmdline_args():
		all_args.append(a)
	for a: String in OS.get_cmdline_user_args():
		all_args.append(a)
	for arg: String in all_args:
		if arg.begins_with("--port="):
			var parsed: int = int(arg.substr(7))
			if parsed > 0 and parsed < 65536:
				return parsed
	return GameConfig.DEFAULT_PORT


func is_server_running() -> bool:
	return mode == NetMode.DEDICATED_SERVER or mode == NetMode.HOST


func is_dedicated_server() -> bool:
	return mode == NetMode.DEDICATED_SERVER


func start_dedicated_server(port: int = GameConfig.DEFAULT_PORT) -> Error:
	disconnect_session()
	DatabaseManager.load_database()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, GameConfig.MAX_CLIENTS)
	if err != OK:
		push_error("[NetworkManager] Cannot start dedicated server on port %d (err=%d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	mode = NetMode.DEDICATED_SERVER
	print("[NetworkManager] Dedicated Server listening on UDP port %d (max %d clients)." % [port, GameConfig.MAX_CLIENTS])
	connection_status_changed.emit("Servidor Dedicado activo en puerto %d" % port)
	return OK


func start_host(
	port: int,
	username: String,
	password: String,
	is_register: bool,
	class_id: String,
	cosmetics_choice: Dictionary,
	race_id: String = "HUMAN_VALLEY",
	appearance: Dictionary = {}
) -> Error:
	disconnect_session()
	DatabaseManager.load_database()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, GameConfig.MAX_CLIENTS)
	if err != OK:
		auth_failed.emit("No se pudo abrir el puerto %d (¿ya está en uso?)." % port)
		return err
	multiplayer.multiplayer_peer = peer
	mode = NetMode.HOST
	connection_status_changed.emit("Servidor Host iniciado en puerto %d" % port)

	var auth_res: Dictionary = _server_process_auth(1, username, password, is_register, class_id, cosmetics_choice, race_id, appearance)
	if not bool(auth_res.get("ok", false)):
		disconnect_session()
		auth_failed.emit(str(auth_res.get("error", "Error de autenticación")))
		return ERR_UNAUTHORIZED

	local_profile = auth_res["profile"] as Dictionary
	local_username = str(local_profile.get("username", ""))
	is_new_account_session = bool(auth_res.get("is_new", false))
	cached_guilds = DatabaseManager.get_guilds().duplicate(true)
	cached_listings = DatabaseManager.get_market_listings().duplicate(true)
	cached_bounties = DatabaseManager.get_bounties().duplicate(true)
	cached_season = DatabaseManager.get_season_state().duplicate(true)
	auth_succeeded.emit(local_profile, is_new_account_session)
	return OK


func connect_to_server(
	host: String,
	port: int,
	username: String,
	password: String,
	is_register: bool,
	class_id: String,
	cosmetics_choice: Dictionary,
	race_id: String = "HUMAN_VALLEY",
	appearance: Dictionary = {}
) -> Error:
	disconnect_session()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(host, port)
	if err != OK:
		auth_failed.emit("Error al iniciar cliente hacia %s:%d" % [host, port])
		return err
	multiplayer.multiplayer_peer = peer
	mode = NetMode.CLIENT
	_pending_auth = {
		"username": username,
		"password": password,
		"is_register": is_register,
		"class_id": class_id,
		"race_id": race_id,
		"appearance": appearance,
		"cosmetics": cosmetics_choice
	}
	connection_status_changed.emit("Conectando a %s:%d..." % [host, port])
	return OK


func disconnect_session() -> void:
	if is_server_running():
		DatabaseManager.save_database()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	mode = NetMode.NONE
	peer_to_username.clear()
	username_to_peer.clear()
	local_profile = {}
	local_username = ""
	cached_party.clear()
	cached_trade = {}
	_pending_auth = {}


func _on_peer_connected(peer_id: int) -> void:
	if is_server_running():
		print("[NetworkManager] Peer connected: %d (awaiting auth)" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if is_server_running():
		var prev_party: Array[int] = PartySystem.get_party_members(peer_id)
		PartySystem.leave_party(peer_id)
		for m_pid: int in prev_party:
			if m_pid != peer_id:
				_server_push_party_state(m_pid)
		var cancel_t: Dictionary = TradeSystem.cancel_trade(peer_id)
		if bool(cancel_t.get("ok", false)):
			var other_p: int = int(cancel_t.get("other", -1))
			if other_p > 0:
				_rpc_sync_trade.rpc_id(other_p, {})
		if peer_to_username.has(peer_id):
			var uname_key: String = str(peer_to_username[peer_id])
			var acc: Dictionary = DatabaseManager.get_account_mutable(uname_key)
			var display_name: String = str(acc.get("username", uname_key))
			peer_to_username.erase(peer_id)
			username_to_peer.erase(uname_key)
			peer_session_ended.emit(peer_id, display_name)
			broadcast_system_message("%s ha abandonado el mundo." % display_name)
			DatabaseManager.save_database()
		print("[NetworkManager] Peer disconnected: %d" % peer_id)


func _on_connected_to_server() -> void:
	connection_status_changed.emit("Conectado. Autenticando cuenta...")
	_rpc_request_auth.rpc_id(
		1,
		str(_pending_auth.get("username", "")),
		str(_pending_auth.get("password", "")),
		bool(_pending_auth.get("is_register", false)),
		str(_pending_auth.get("class_id", "ARCANE_KNIGHT")),
		_pending_auth.get("cosmetics", {}) as Dictionary,
		str(_pending_auth.get("race_id", "HUMAN_VALLEY")),
		_pending_auth.get("appearance", {}) as Dictionary
	)


func _on_connection_failed() -> void:
	disconnect_session()
	auth_failed.emit("No se pudo conectar al servidor. Revisá la IP, el puerto o iniciá un servidor Host.")


func _on_server_disconnected() -> void:
	disconnect_session()
	disconnected_from_server.emit("Se perdió la conexión con el servidor.")


func _get_sender_id() -> int:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender


func _server_process_auth(
	peer_id: int,
	username: String,
	password: String,
	is_register: bool,
	class_id: String,
	cosmetics_choice: Dictionary,
	race_id: String = "HUMAN_VALLEY",
	appearance: Dictionary = {}
) -> Dictionary:
	var key: String = username.strip_edges().to_lower()
	if username_to_peer.has(key):
		return {"ok": false, "error": "Esa cuenta ya está conectada en este servidor."}

	var res: Dictionary
	var is_new: bool = false
	if is_register:
		res = DatabaseManager.register_account(username, password, class_id, GameConfig.ROLE_PLAYER, race_id, appearance)
		is_new = bool(res.get("ok", false))
	else:
		res = DatabaseManager.authenticate_account(username, password)

	if not bool(res.get("ok", false)):
		return res

	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	var cosmetics_data: Dictionary = acc["cosmetics"] as Dictionary
	var chosen_armor: String = str(cosmetics_choice.get("equipped_armor", ""))
	if (cosmetics_data["owned_armors"] as Array).has(chosen_armor):
		cosmetics_data["equipped_armor"] = chosen_armor
	var chosen_dragon: String = str(cosmetics_choice.get("equipped_dragon", ""))
	if (cosmetics_data["owned_dragons"] as Array).has(chosen_dragon):
		cosmetics_data["equipped_dragon"] = chosen_dragon
	var chosen_trail: String = str(cosmetics_choice.get("equipped_trail", ""))
	if (cosmetics_data["owned_trails"] as Array).has(chosen_trail):
		cosmetics_data["equipped_trail"] = chosen_trail

	peer_to_username[peer_id] = key
	username_to_peer[key] = peer_id
	var sanitized: Dictionary = DatabaseManager.get_sanitized_profile(key)
	peer_authenticated.emit(peer_id, sanitized)
	return {"ok": true, "profile": sanitized, "is_new": is_new}


@rpc("any_peer", "reliable")
func _rpc_request_auth(
	username: String,
	password: String,
	is_register: bool,
	class_id: String,
	cosmetics_choice: Dictionary,
	race_id: String,
	appearance: Dictionary
) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var res: Dictionary = _server_process_auth(sender_id, username, password, is_register, class_id, cosmetics_choice, race_id, appearance)
	if not bool(res.get("ok", false)):
		_rpc_auth_response.rpc_id(sender_id, false, str(res.get("error", "Error")), {}, false)
		return
	var profile: Dictionary = res["profile"] as Dictionary
	_rpc_auth_response.rpc_id(sender_id, true, "OK", profile, bool(res.get("is_new", false)))
	_rpc_sync_social_data.rpc_id(
		sender_id,
		DatabaseManager.get_guilds(),
		DatabaseManager.get_market_listings(),
		DatabaseManager.get_bounties()
	)
	_rpc_sync_season_data.rpc_id(sender_id, DatabaseManager.get_season_state())
	broadcast_system_message("%s ha ingresado al mundo (%s)." % [
		str(profile.get("username", "")),
		str((GameConfig.CLASSES.get(str(profile.get("class_id", "ARCANE_KNIGHT")), {}) as Dictionary).get("name", "Aventurero"))
	])


@rpc("authority", "reliable")
func _rpc_auth_response(ok: bool, message: String, profile: Dictionary, is_new: bool) -> void:
	if not ok:
		disconnect_session()
		auth_failed.emit(message)
		return
	local_profile = profile
	local_username = str(profile.get("username", ""))
	is_new_account_session = is_new
	auth_succeeded.emit(profile, is_new)


func get_peer_username_key(peer_id: int) -> String:
	return str(peer_to_username.get(peer_id, ""))


func get_peer_profile(peer_id: int) -> Dictionary:
	var key: String = get_peer_username_key(peer_id)
	if key.is_empty():
		return {}
	return DatabaseManager.get_sanitized_profile(key)


func get_connected_usernames() -> Array[String]:
	var out: Array[String] = []
	for peer_id: Variant in peer_to_username.keys():
		var acc: Dictionary = DatabaseManager.get_account_mutable(str(peer_to_username[peer_id]))
		if not acc.is_empty():
			out.append(str(acc.get("username", "")))
	return out


func push_profile_to_peer(peer_id: int) -> void:
	if not is_server_running():
		return
	var profile: Dictionary = get_peer_profile(peer_id)
	if profile.is_empty():
		return
	if peer_id == multiplayer.get_unique_id():
		local_profile = profile
		profile_updated.emit(profile)
	else:
		_rpc_update_local_profile.rpc_id(peer_id, profile)


@rpc("authority", "reliable")
func _rpc_update_local_profile(profile: Dictionary) -> void:
	local_profile = profile
	profile_updated.emit(profile)


func broadcast_social_data() -> void:
	if not is_server_running():
		return
	var guilds: Dictionary = DatabaseManager.get_guilds()
	var listings: Array = DatabaseManager.get_market_listings()
	var bounties: Array = DatabaseManager.get_bounties()
	_rpc_sync_social_data.rpc(guilds, listings, bounties)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_social_data(guilds: Dictionary, listings: Array, bounties: Array) -> void:
	cached_guilds = guilds
	cached_listings = listings
	cached_bounties = bounties
	social_data_updated.emit(guilds, listings, bounties)


func broadcast_season_data() -> void:
	if not is_server_running():
		return
	_rpc_sync_season_data.rpc(DatabaseManager.get_season_state())


@rpc("authority", "call_local", "reliable")
func _rpc_sync_season_data(season_state: Dictionary) -> void:
	cached_season = season_state
	season_data_updated.emit(season_state)


# --- Appearance Editor (Existing Accounts) ---

func request_update_appearance(race_id: String, appearance: Dictionary) -> void:
	_rpc_update_appearance.rpc_id(1, race_id, appearance)


@rpc("any_peer", "call_local", "reliable")
func _rpc_update_appearance(race_id: String, appearance: Dictionary) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var key: String = get_peer_username_key(sender_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	if acc.is_empty():
		return
	if GameConfig.RACES.has(race_id):
		acc["race_id"] = race_id
	var cur_app: Dictionary = acc.get("appearance", {}) as Dictionary
	for ak: Variant in appearance.keys():
		cur_app[ak] = appearance[ak]
	acc["appearance"] = cur_app
	DatabaseManager.mark_dirty()
	DatabaseManager.save_database()
	push_profile_to_peer(sender_id)
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	if wa != null and wa.has_method("server_refresh_player_cosmetics"):
		wa.call("server_refresh_player_cosmetics", sender_id)


# --- Chat & Announcements ---

func send_chat(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return
	if trimmed.length() > 180:
		trimmed = trimmed.substr(0, 180)
	_rpc_send_chat.rpc_id(1, trimmed)


@rpc("any_peer", "call_local", "reliable")
func _rpc_send_chat(text: String) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = DatabaseManager.get_account_mutable(get_peer_username_key(sender_id))
	if acc.is_empty():
		return
	var uname: String = str(acc.get("username", "Viajero"))
	var role: String = str(acc.get("role", GameConfig.ROLE_PLAYER))
	var tag: String = "Global"
	var color_hex: String = "#e6edf7"
	# Check if creator avatar is disguised as Level-1 novice
	var disguised: bool = false
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	if wa != null and wa.has_method("server_is_peer_disguised"):
		disguised = bool(wa.call("server_is_peer_disguised", sender_id))
	if not disguised:
		if role == GameConfig.ROLE_AVATAR_ORDEN:
			tag = "♾️ AVATAR DEL ORDEN"
			color_hex = "#ffd866"
		elif role == GameConfig.ROLE_AVATAR_CAOS:
			tag = "♾️ AVATAR DEL CAOS"
			color_hex = "#ff5a3c"
	_rpc_receive_chat.rpc(uname, tag, text, color_hex)


func broadcast_system_message(text: String, color_hex: String = "#8fc7ff") -> void:
	if not is_server_running():
		return
	_rpc_receive_chat.rpc("Mundo", "Crónica", text, color_hex)


func broadcast_banner(title: String, body: String, color_hex: String = "#ffd866") -> void:
	if not is_server_running():
		return
	_rpc_receive_banner.rpc(title, body, color_hex)


@rpc("authority", "call_local", "reliable")
func _rpc_receive_chat(sender: String, channel: String, text: String, color_hex: String) -> void:
	chat_message_received.emit(sender, channel, text, color_hex)


@rpc("authority", "call_local", "reliable")
func _rpc_receive_banner(title: String, body: String, color_hex: String) -> void:
	system_banner_received.emit(title, body, color_hex)


# --- Zero Pay-to-Win Cosmetic Shop (Free for Creator Avatars) ---

func request_cosmetic_action(category: String, item_id: String, action: String) -> void:
	_rpc_cosmetic_action.rpc_id(1, category, item_id, action)


@rpc("any_peer", "call_local", "reliable")
func _rpc_cosmetic_action(category: String, item_id: String, action: String) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = DatabaseManager.get_account_mutable(get_peer_username_key(sender_id))
	if acc.is_empty():
		return
	var is_admin: bool = GameConfig.is_avatar_role(str(acc.get("role", "")))

	if action == "claim_crowns":
		acc["crowns"] = int(acc.get("crowns", 0)) + 500
		DatabaseManager.mark_dirty()
		push_profile_to_peer(sender_id)
		return

	var catalog: Dictionary = {}
	var owned_key: String = ""
	var equip_key: String = ""
	if category == "armor":
		catalog = GameConfig.COSMETIC_ARMORS
		owned_key = "owned_armors"
		equip_key = "equipped_armor"
	elif category == "dragon":
		catalog = GameConfig.COSMETIC_DRAGONS
		owned_key = "owned_dragons"
		equip_key = "equipped_dragon"
	elif category == "trail":
		catalog = GameConfig.COSMETIC_TRAILS
		owned_key = "owned_trails"
		equip_key = "equipped_trail"
	else:
		return

	if not catalog.has(item_id):
		return
	var cosmetics_data: Dictionary = acc["cosmetics"] as Dictionary
	var owned: Array = cosmetics_data[owned_key] as Array
	var item_def: Dictionary = catalog[item_id] as Dictionary

	if action == "buy":
		if not owned.has(item_id):
			var price: int = 0 if is_admin else int(item_def.get("price_crowns", 0))
			var crowns: int = int(acc.get("crowns", 0))
			if crowns < price:
				_rpc_receive_chat.rpc_id(sender_id, "Tienda", "Sistema", "Coronas insuficientes para este cosmético.", "#ff8888")
				return
			acc["crowns"] = crowns - price
			owned.append(item_id)
		cosmetics_data[equip_key] = item_id
	elif action == "equip":
		if owned.has(item_id) or is_admin:
			if not owned.has(item_id):
				owned.append(item_id)
			cosmetics_data[equip_key] = item_id

	DatabaseManager.mark_dirty()
	DatabaseManager.save_database()
	push_profile_to_peer(sender_id)
	var world_auth: Node = get_tree().get_first_node_in_group("world_authority")
	if world_auth != null and world_auth.has_method("server_refresh_player_cosmetics"):
		world_auth.call("server_refresh_player_cosmetics", sender_id)


# --- Crafting, 4-Piece Armor Sets, Consumables & Storage Chests ---

func request_craft(recipe_id: String) -> void:
	_rpc_craft_item.rpc_id(1, recipe_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_craft_item(recipe_id: String) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var key: String = get_peer_username_key(sender_id)
	if key.is_empty():
		return
	var res: Dictionary = CraftingSystem.craft_recipe(key, recipe_id)
	if not bool(res.get("ok", false)):
		_rpc_receive_chat.rpc_id(sender_id, "Forja", "Sistema", str(res.get("error", "No se pudo fabricar.")), "#ffaa66")
		return
	push_profile_to_peer(sender_id)
	_rpc_receive_chat.rpc_id(sender_id, "Forja", "Sistema", str(res.get("message", "Fabricado: %s" % recipe_id)), "#88f2a2")


func request_equip_or_use_item(item_id: String) -> void:
	_rpc_use_item.rpc_id(1, item_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_use_item(item_id: String) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var key: String = get_peer_username_key(sender_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	if acc.is_empty() or not GameConfig.ITEMS.has(item_id):
		return
	var inv: Dictionary = acc["inventory"] as Dictionary
	if int(inv.get(item_id, 0)) <= 0:
		return
	var item_def: Dictionary = GameConfig.ITEMS[item_id] as Dictionary
	var item_type: String = str(item_def.get("type", ""))
	if item_type == "weapon":
		acc["equipped_weapon"] = item_id
		DatabaseManager.mark_dirty()
		DatabaseManager.save_database()
		push_profile_to_peer(sender_id)
		_rpc_receive_chat.rpc_id(sender_id, "Equipo", "Mochila", "Equipaste %s (guardado en servidor)." % str(item_def.get("name", item_id)), "#88f2a2")
	elif item_type == "helmet" or item_type == "chest" or item_type == "legs" or item_type == "boots":
		var field: String = "equipped_%s" % item_type
		acc[field] = item_id
		DatabaseManager.mark_dirty()
		DatabaseManager.save_database()
		push_profile_to_peer(sender_id)
		_rpc_receive_chat.rpc_id(sender_id, "Equipo", "Mochila", "Equipaste %s (guardado en servidor)." % str(item_def.get("name", item_id)), "#88f2a2")
	elif item_type == "armor":
		var slot_name: String = str(item_def.get("slot", "chest"))
		var field: String = "equipped_%s" % slot_name
		acc[field] = item_id
		DatabaseManager.mark_dirty()
		DatabaseManager.save_database()
		push_profile_to_peer(sender_id)
	elif item_type == "mount":
		acc["equipped_mount"] = item_id
		DatabaseManager.mark_dirty()
		DatabaseManager.save_database()
		var wa_m: Node = get_tree().get_first_node_in_group("world_authority")
		if wa_m != null and wa_m.has_method("server_toggle_dragon_for_peer"):
			wa_m.call("server_toggle_dragon_for_peer", sender_id)
		push_profile_to_peer(sender_id)
		return
	elif item_type == "consumable" or item_type == "food":
		var world_auth: Node = get_tree().get_first_node_in_group("world_authority")
		if world_auth != null and world_auth.has_method("server_consume_item"):
			if bool(world_auth.call("server_consume_item", sender_id, item_id)):
				DatabaseManager.remove_item(key, item_id, 1)
				DatabaseManager.save_database()
				push_profile_to_peer(sender_id)
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	if wa != null and wa.has_method("server_recalculate_player_stats"):
		wa.call("server_recalculate_player_stats", sender_id)


func request_open_chest(building_id: int) -> void:
	_rpc_open_chest.rpc_id(1, building_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_open_chest(building_id: int) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var ba: Node = get_tree().get_first_node_in_group("building_authority")
	if ba == null or not ba.has_method("server_can_access_chest"):
		return
	var check: Dictionary = ba.call("server_can_access_chest", sender_id, building_id) as Dictionary
	if not bool(check.get("ok", false)):
		_rpc_receive_chat.rpc_id(sender_id, "Cajón", "Sistema", str(check.get("error", "Sin acceso.")), "#ffaa66")
		return
	var items: Dictionary = DatabaseManager.get_chest_inventory(building_id).duplicate(true)
	var owner_name: String = str(check.get("owner", ""))
	if sender_id == multiplayer.get_unique_id():
		chest_opened.emit(building_id, owner_name, items)
	else:
		_rpc_chest_opened.rpc_id(sender_id, building_id, owner_name, items)


@rpc("authority", "reliable")
func _rpc_chest_opened(building_id: int, owner_name: String, items: Dictionary) -> void:
	chest_opened.emit(building_id, owner_name, items)


func request_chest_transfer(building_id: int, item_id: String, qty: int, to_chest: bool) -> void:
	_rpc_chest_transfer.rpc_id(1, building_id, item_id, qty, to_chest)


@rpc("any_peer", "call_local", "reliable")
func _rpc_chest_transfer(building_id: int, item_id: String, qty: int, to_chest: bool) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var key: String = get_peer_username_key(sender_id)
	var ba: Node = get_tree().get_first_node_in_group("building_authority")
	if ba == null or not ba.has_method("server_can_access_chest"):
		return
	var check: Dictionary = ba.call("server_can_access_chest", sender_id, building_id) as Dictionary
	if not bool(check.get("ok", false)):
		return
	var res: Dictionary = InventorySystem.transfer_to_chest(key, building_id, item_id, qty) if to_chest else InventorySystem.transfer_from_chest(key, building_id, item_id, qty)
	if not bool(res.get("ok", false)):
		_rpc_receive_chat.rpc_id(sender_id, "Cajón", "Sistema", str(res.get("error", "Error de transferencia.")), "#ffaa66")
		return
	push_profile_to_peer(sender_id)
	var items: Dictionary = DatabaseManager.get_chest_inventory(building_id).duplicate(true)
	var owner_name: String = str(check.get("owner", ""))
	if sender_id == multiplayer.get_unique_id():
		chest_opened.emit(building_id, owner_name, items)
	else:
		_rpc_chest_opened.rpc_id(sender_id, building_id, owner_name, items)


# --- Kingdoms / Guilds, Alignment & 100% Player-Driven Economy ---

func request_guild_create(guild_name: String, philosophy: String, manifesto: String) -> void:
	_rpc_guild_create.rpc_id(1, guild_name, philosophy, manifesto)


@rpc("any_peer", "call_local", "reliable")
func _rpc_guild_create(guild_name: String, philosophy: String, manifesto: String) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var key: String = get_peer_username_key(sender_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	if acc.is_empty():
		return
	var clean_name: String = guild_name.strip_edges()
	if clean_name.length() < 3 or clean_name.length() > 28:
		_rpc_receive_chat.rpc_id(sender_id, "Reinos", "Sistema", "Nombre de Reino/Gremio inválido (3-28 caracteres).", "#ff8888")
		return
	var gid: String = clean_name.to_lower().replace(" ", "_")
	var guilds: Dictionary = DatabaseManager.get_guilds()
	if guilds.has(gid):
		_rpc_receive_chat.rpc_id(sender_id, "Reinos", "Sistema", "Ya existe un Reino/Gremio con ese nombre.", "#ff8888")
		return
	var valid_phil: String = philosophy if (philosophy == GameConfig.PHILOSOPHY_ORDER or philosophy == GameConfig.PHILOSOPHY_CHAOS) else GameConfig.PHILOSOPHY_NEUTRAL
	var uname: String = str(acc.get("username", ""))
	guilds[gid] = {
		"id": gid,
		"name": clean_name,
		"leader": uname,
		"philosophy": valid_phil,
		"manifesto": manifesto.strip_edges().substr(0, 140),
		"members": [uname]
	}
	acc["guild_id"] = gid
	acc["philosophy"] = valid_phil
	DatabaseManager.mark_dirty()
	DatabaseManager.save_database()
	push_profile_to_peer(sender_id)
	broadcast_social_data()
	broadcast_system_message("%s ha fundado el Reino/Gremio '%s' (%s)." % [uname, clean_name, valid_phil], "#ffd866")


func request_guild_join(gid: String) -> void:
	_rpc_guild_join.rpc_id(1, gid)


@rpc("any_peer", "call_local", "reliable")
func _rpc_guild_join(gid: String) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var key: String = get_peer_username_key(sender_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	if acc.is_empty():
		return
	var guilds: Dictionary = DatabaseManager.get_guilds()
	if not guilds.has(gid):
		return
	var uname: String = str(acc.get("username", ""))
	var old_gid: String = str(acc.get("guild_id", ""))
	if not old_gid.is_empty() and guilds.has(old_gid):
		var old_members: Array = (guilds[old_gid] as Dictionary)["members"] as Array
		old_members.erase(uname)
	var g: Dictionary = guilds[gid] as Dictionary
	var members: Array = g["members"] as Array
	if not members.has(uname):
		members.append(uname)
	acc["guild_id"] = gid
	acc["philosophy"] = str(g.get("philosophy", GameConfig.PHILOSOPHY_NEUTRAL))
	DatabaseManager.mark_dirty()
	DatabaseManager.save_database()
	push_profile_to_peer(sender_id)
	broadcast_social_data()
	broadcast_system_message("%s se unió a '%s'." % [uname, str(g.get("name", gid))])


func request_set_philosophy(philosophy: String) -> void:
	_rpc_set_philosophy.rpc_id(1, philosophy)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_philosophy(philosophy: String) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var acc: Dictionary = DatabaseManager.get_account_mutable(get_peer_username_key(sender_id))
	if acc.is_empty():
		return
	if philosophy != GameConfig.PHILOSOPHY_NEUTRAL and philosophy != GameConfig.PHILOSOPHY_ORDER and philosophy != GameConfig.PHILOSOPHY_CHAOS:
		return
	acc["philosophy"] = philosophy
	if philosophy == GameConfig.PHILOSOPHY_ORDER:
		acc["alignment_score"] = maxi(int(acc.get("alignment_score", 0)), 30)
	elif philosophy == GameConfig.PHILOSOPHY_CHAOS:
		acc["alignment_score"] = mini(int(acc.get("alignment_score", 0)), -30)
	else:
		acc["alignment_score"] = 0
	DatabaseManager.mark_dirty()
	push_profile_to_peer(sender_id)
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	if wa != null and wa.has_method("server_refresh_player_cosmetics"):
		wa.call("server_refresh_player_cosmetics", sender_id)


func request_market_list(item_id: String, qty: int, price_gold: int) -> void:
	_rpc_market_list.rpc_id(1, item_id, qty, price_gold)


@rpc("any_peer", "call_local", "reliable")
func _rpc_market_list(item_id: String, qty: int, price_gold: int) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var key: String = get_peer_username_key(sender_id)
	var res: Dictionary = PlayerEconomy.create_player_listing(key, item_id, qty, price_gold)
	if not bool(res.get("ok", false)):
		_rpc_receive_chat.rpc_id(sender_id, "Comercio", "Sistema", str(res.get("error", "Error al publicar.")), "#ff8888")
		return
	AlignmentSystem.apply_action(key, 5) # Trading favors Order
	push_profile_to_peer(sender_id)
	broadcast_social_data()
	_rpc_receive_chat.rpc_id(sender_id, "Comercio", "Sistema", "Oferta publicada en el Mercado de Jugadores.", "#88f2a2")


func request_market_buy(listing_id: int) -> void:
	_rpc_market_buy.rpc_id(1, listing_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_market_buy(listing_id: int) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var buyer_key: String = get_peer_username_key(sender_id)
	var res: Dictionary = PlayerEconomy.buy_player_listing(buyer_key, listing_id)
	if not bool(res.get("ok", false)):
		_rpc_receive_chat.rpc_id(sender_id, "Comercio", "Sistema", str(res.get("error", "No se pudo comprar.")), "#ff8888")
		return
	var seller_name: String = str(res.get("seller", ""))
	var price: int = int(res.get("price", 0))
	var seller_peer: int = int(username_to_peer.get(seller_name.to_lower(), -1))
	if seller_peer > 0:
		push_profile_to_peer(seller_peer)
		_rpc_receive_chat.rpc_id(seller_peer, "Comercio", "Sistema", "%s compró tu oferta por %d oro." % [buyer_key, price], "#88f2a2")
	push_profile_to_peer(sender_id)
	broadcast_social_data()
	_rpc_receive_chat.rpc_id(sender_id, "Comercio", "Sistema", "Compra completada por %d oro." % price, "#88f2a2")


func request_post_bounty(target_name: String, reward_gold: int, reason: String) -> void:
	_rpc_post_bounty.rpc_id(1, target_name, reward_gold, reason)


@rpc("any_peer", "call_local", "reliable")
func _rpc_post_bounty(target_name: String, reward_gold: int, reason: String) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var key: String = get_peer_username_key(sender_id)
	var acc: Dictionary = DatabaseManager.get_account_mutable(key)
	if acc.is_empty() or reward_gold < 10 or target_name.strip_edges().is_empty():
		return
	if int(acc.get("gold", 0)) < reward_gold:
		_rpc_receive_chat.rpc_id(sender_id, "Contratos", "Sistema", "No tenés suficiente oro para financiar este contrato.", "#ff8888")
		return
	acc["gold"] = int(acc.get("gold", 0)) - reward_gold
	var bid: int = int(DatabaseManager.data.get("next_bounty_id", 1))
	DatabaseManager.data["next_bounty_id"] = bid + 1
	DatabaseManager.get_bounties().append({
		"id": bid,
		"issuer": str(acc.get("username", "")),
		"target_name": target_name.strip_edges(),
		"reward_gold": reward_gold,
		"reason": reason.strip_edges().substr(0, 100)
	})
	DatabaseManager.mark_dirty()
	DatabaseManager.save_database()
	push_profile_to_peer(sender_id)
	broadcast_social_data()
	broadcast_system_message("Nuevo contrato de jugadores: %d oro por la cabeza de %s." % [reward_gold, target_name.strip_edges()], "#ffb84d")


# --- 4-Player Party System RPCs ---

func request_party_invite(target_username: String) -> void:
	_rpc_party_invite.rpc_id(1, target_username)


@rpc("any_peer", "call_local", "reliable")
func _rpc_party_invite(target_username: String) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var tkey: String = target_username.strip_edges().to_lower()
	if not username_to_peer.has(tkey):
		_rpc_receive_chat.rpc_id(sender_id, "Grupo", "Sistema", "Jugador no encontrado o desconectado.", "#ffaa66")
		return
	var target_pid: int = int(username_to_peer[tkey])
	if target_pid == sender_id:
		return
	var res: Dictionary = PartySystem.invite_player(sender_id, target_pid)
	if not bool(res.get("ok", false)):
		_rpc_receive_chat.rpc_id(sender_id, "Grupo", "Sistema", str(res.get("error", "")), "#ffaa66")
		return
	var leader_name: String = str(get_peer_profile(sender_id).get("username", "Jugador"))
	_rpc_receive_chat.rpc_id(target_pid, "Grupo", "Invitación", "%s te invitó a un Grupo (4 jugadores para Mazmorras). Aceptá en el panel de Grupo (Tab)." % leader_name, "#88f2a2")
	_rpc_receive_chat.rpc_id(sender_id, "Grupo", "Sistema", "Invitación enviada a %s." % target_username, "#8fc7ff")
	_server_push_party_state(sender_id)


func request_party_accept() -> void:
	_rpc_party_accept.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_party_accept() -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var res: Dictionary = PartySystem.accept_invite(sender_id)
	if not bool(res.get("ok", false)):
		_rpc_receive_chat.rpc_id(sender_id, "Grupo", "Sistema", str(res.get("error", "")), "#ffaa66")
		return
	var members: Array[int] = PartySystem.get_party_members(sender_id)
	for pid: int in members:
		_server_push_party_state(pid)
		_rpc_receive_chat.rpc_id(pid, "Grupo", "Sistema", "%s se unió al grupo (%d/4)." % [str(get_peer_profile(sender_id).get("username", "")), members.size()], "#88f2a2")


func request_party_leave() -> void:
	_rpc_party_leave.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_party_leave() -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var prev: Array[int] = PartySystem.get_party_members(sender_id)
	PartySystem.leave_party(sender_id)
	_server_push_party_state(sender_id)
	for pid: int in prev:
		if pid != sender_id:
			_server_push_party_state(pid)


func _server_push_party_state(peer_id: int) -> void:
	var members: Array[int] = PartySystem.get_party_members(peer_id)
	var payload: Array = []
	for pid: int in members:
		var prof: Dictionary = get_peer_profile(pid)
		if not prof.is_empty():
			payload.append({
				"peer_id": pid,
				"username": str(prof.get("username", "")),
				"class_id": str(prof.get("class_id", "ARCANE_KNIGHT")),
				"level": int(prof.get("level", 1)),
				"role": str(prof.get("role", GameConfig.ROLE_PLAYER))
			})
	if peer_id == multiplayer.get_unique_id():
		cached_party = payload
		party_updated.emit(payload)
	else:
		_rpc_sync_party.rpc_id(peer_id, payload)


@rpc("authority", "reliable")
func _rpc_sync_party(payload: Array) -> void:
	cached_party = payload
	party_updated.emit(payload)


# --- Direct Player-to-Player Trade RPCs ---

func request_trade_start(target_username: String) -> void:
	_rpc_trade_start.rpc_id(1, target_username)


@rpc("any_peer", "call_local", "reliable")
func _rpc_trade_start(target_username: String) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var tkey: String = target_username.strip_edges().to_lower()
	if not username_to_peer.has(tkey):
		_rpc_receive_chat.rpc_id(sender_id, "Trueque", "Sistema", "Jugador no encontrado.", "#ffaa66")
		return
	var target_pid: int = int(username_to_peer[tkey])
	if target_pid == sender_id:
		return
	var res: Dictionary = TradeSystem.start_trade(sender_id, target_pid)
	if not bool(res.get("ok", false)):
		_rpc_receive_chat.rpc_id(sender_id, "Trueque", "Sistema", str(res.get("error", "")), "#ffaa66")
		return
	_server_push_trade_session(res["session"] as Dictionary)


func request_trade_offer(gold: int, item_id: String, qty: int) -> void:
	_rpc_trade_offer.rpc_id(1, gold, item_id, qty)


@rpc("any_peer", "call_local", "reliable")
func _rpc_trade_offer(gold: int, item_id: String, qty: int) -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var res: Dictionary = TradeSystem.update_offer(sender_id, gold, item_id, qty)
	if bool(res.get("ok", false)):
		_server_push_trade_session(res["session"] as Dictionary)


func request_trade_confirm() -> void:
	_rpc_trade_confirm.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_trade_confirm() -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var sess: Dictionary = TradeSystem.get_session_for_peer(sender_id)
	if sess.is_empty():
		return
	var pa: int = int(sess["peer_a"])
	var pb: int = int(sess["peer_b"])
	var res: Dictionary = TradeSystem.confirm_trade(sender_id, get_peer_username_key(pa), get_peer_username_key(pb))
	if not bool(res.get("ok", false)):
		_rpc_receive_chat.rpc_id(sender_id, "Trueque", "Sistema", str(res.get("error", "Error")), "#ff8888")
		return
	if bool(res.get("completed", false)):
		push_profile_to_peer(pa)
		push_profile_to_peer(pb)
		_rpc_sync_trade.rpc_id(pa, {})
		_rpc_sync_trade.rpc_id(pb, {})
		_rpc_receive_chat.rpc_id(pa, "Trueque", "Sistema", "¡Intercambio completado!", "#88f2a2")
		_rpc_receive_chat.rpc_id(pb, "Trueque", "Sistema", "¡Intercambio completado!", "#88f2a2")
	else:
		_server_push_trade_session(res["session"] as Dictionary)


func request_trade_cancel() -> void:
	_rpc_trade_cancel.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_trade_cancel() -> void:
	if not is_server_running():
		return
	var sender_id: int = _get_sender_id()
	var res: Dictionary = TradeSystem.cancel_trade(sender_id)
	if bool(res.get("ok", false)):
		var other: int = int(res.get("other", -1))
		_rpc_sync_trade.rpc_id(sender_id, {})
		if other > 0:
			_rpc_sync_trade.rpc_id(other, {})


func _server_push_trade_session(sess: Dictionary) -> void:
	var pa: int = int(sess["peer_a"])
	var pb: int = int(sess["peer_b"])
	var packed: Dictionary = sess.duplicate(true)
	packed["name_a"] = str(get_peer_profile(pa).get("username", "Jugador A"))
	packed["name_b"] = str(get_peer_profile(pb).get("username", "Jugador B"))
	for pid: int in [pa, pb]:
		if pid == multiplayer.get_unique_id():
			cached_trade = packed
			trade_updated.emit(packed)
		else:
			_rpc_sync_trade.rpc_id(pid, packed)


@rpc("authority", "reliable")
func _rpc_sync_trade(sess: Dictionary) -> void:
	cached_trade = sess
	trade_updated.emit(sess)
