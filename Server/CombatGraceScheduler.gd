class_name CombatGraceScheduler
extends Node

## Server-authoritative 24-hour real-time scheduler for the daily "Gracia Combativa" event.
## Picks 1 connected player completely at random (ignoring level and faction),
## doubles all their stats (+100%, x2.0 stacking over all buffs) for 24 exact hours,
## persists timestamps to disk, and syncs live state to every client.

signal combat_grace_updated(state: Dictionary)

var current_state: Dictionary = {
	"active_username": "",
	"granted_at_unix": 0.0,
	"expires_at_unix": 0.0,
	"next_roll_at_unix": 0.0,
	"blessed_by": "Los Arquitectos Primordiales"
}

var _tick_accum: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("combat_grace_scheduler")
	_rng.randomize()
	if NetworkManager.is_server_running():
		current_state = DatabaseManager.get_combat_grace_state().duplicate(true)
		var now: float = Time.get_unix_time_from_system()
		if float(current_state.get("next_roll_at_unix", 0.0)) <= 0.0:
			current_state["next_roll_at_unix"] = now + GameConfig.COMBAT_GRACE_DURATION_SEC
			DatabaseManager.set_combat_grace_state(current_state)
		_check_expiration(now)


func _process(delta: float) -> void:
	if not NetworkManager.is_server_running():
		return
	_tick_accum += delta
	if _tick_accum < 1.0:
		return
	_tick_accum = 0.0

	var now: float = Time.get_unix_time_from_system()
	_check_expiration(now)

	var next_roll: float = float(current_state.get("next_roll_at_unix", 0.0))
	if now >= next_roll:
		var online: Array[String] = NetworkManager.get_connected_usernames()
		if not online.is_empty():
			server_trigger_roll_now("Descenso Diario de los Avatares", "")


func _check_expiration(now: float) -> void:
	var active_user: String = str(current_state.get("active_username", ""))
	var expires_at: float = float(current_state.get("expires_at_unix", 0.0))
	if not active_user.is_empty() and expires_at > 0.0 and now >= expires_at:
		var old_user: String = active_user
		current_state["active_username"] = ""
		current_state["expires_at_unix"] = 0.0
		DatabaseManager.set_combat_grace_state(current_state)
		_notify_world_grace_change(old_user, "")
		broadcast_state()
		NetworkManager.broadcast_system_message("La Gracia Combativa sobre %s ha concluido tras 24 horas." % old_user, "#d8c88c")


func is_player_blessed(username: String) -> bool:
	var active_user: String = str(current_state.get("active_username", ""))
	if active_user.is_empty():
		return false
	var now: float = Time.get_unix_time_from_system()
	var expires_at: float = float(current_state.get("expires_at_unix", 0.0))
	return active_user.to_lower() == username.strip_edges().to_lower() and now < expires_at


func get_remaining_seconds() -> float:
	var active_user: String = str(current_state.get("active_username", ""))
	if active_user.is_empty():
		return 0.0
	var now: float = Time.get_unix_time_from_system()
	return maxf(0.0, float(current_state.get("expires_at_unix", 0.0)) - now)


func server_trigger_roll_now(triggered_by: String, forced_target_username: String = "") -> Dictionary:
	if not NetworkManager.is_server_running():
		return {"ok": false, "error": "Solo el servidor puede invocar la Gracia Combativa."}

	var online: Array[String] = NetworkManager.get_connected_usernames()
	if online.is_empty():
		return {"ok": false, "error": "No hay jugadores conectados para bendecir."}

	var chosen: String = ""
	if not forced_target_username.strip_edges().is_empty():
		var target_lower: String = forced_target_username.strip_edges().to_lower()
		for u: String in online:
			if u.to_lower() == target_lower:
				chosen = u
				break
		if chosen.is_empty():
			return {"ok": false, "error": "El jugador '%s' no está conectado." % forced_target_username}
	else:
		# Strictly uniform random across ALL connected players (no level or faction bias)
		var idx: int = _rng.randi_range(0, online.size() - 1)
		chosen = online[idx]

	var old_user: String = str(current_state.get("active_username", ""))
	var now: float = Time.get_unix_time_from_system()
	current_state = {
		"active_username": chosen,
		"granted_at_unix": now,
		"expires_at_unix": now + GameConfig.COMBAT_GRACE_DURATION_SEC,
		"next_roll_at_unix": now + GameConfig.COMBAT_GRACE_DURATION_SEC,
		"blessed_by": triggered_by
	}
	DatabaseManager.set_combat_grace_state(current_state)
	_notify_world_grace_change(old_user, chosen)
	broadcast_state()
	_rpc_play_grace_fanfare.rpc()

	NetworkManager.broadcast_banner(
		"¡DESCENSO DIVINO: GRACIA COMBATIVA!",
		"%s ha sido elegido por %s. Todas sus estadísticas se duplican (+100%%) durante 24 horas." % [chosen, triggered_by],
		"#ffe066"
	)
	NetworkManager.broadcast_system_message(
		"★ GRACIA COMBATIVA ★ %s recibe poder x2.0 durante 24h (otorgada por %s)." % [chosen, triggered_by],
		"#ffe066"
	)
	return {"ok": true, "chosen": chosen}


func sync_to_peer(peer_id: int) -> void:
	if not NetworkManager.is_server_running():
		return
	if peer_id == multiplayer.get_unique_id():
		combat_grace_updated.emit(current_state)
	else:
		_rpc_sync_state.rpc_id(peer_id, current_state)


func broadcast_state() -> void:
	if not NetworkManager.is_server_running():
		return
	_rpc_sync_state.rpc(current_state)


func _notify_world_grace_change(old_user: String, new_user: String) -> void:
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	if wa != null and wa.has_method("server_on_combat_grace_changed"):
		wa.call("server_on_combat_grace_changed", old_user, new_user)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_state(state: Dictionary) -> void:
	current_state = state
	combat_grace_updated.emit(current_state)


@rpc("authority", "call_local", "reliable")
func _rpc_play_grace_fanfare() -> void:
	AudioSynth.play_combat_grace_fanfare()
