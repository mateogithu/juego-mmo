class_name SeasonResetSystem
extends RefCounted

## Monthly 30-day Territorial War Season manager.
## At the end of each 30-day cycle, proclaims the winning faction, awards cosmetic crowns,
## and resets ONLY territorial structures & region control — preserving ALL player levels,
## 150-slot backpacks, equipment, gold, cosmetics, and Dragon Mounts!


static func check_monthly_reset(building_auth: Node) -> bool:
	if not NetworkManager.is_server_running():
		return false
	var season: Dictionary = DatabaseManager.get_season_state()
	var now: float = Time.get_unix_time_from_system()
	if now >= float(season.get("ends_at_unix", now + 100.0)):
		execute_season_reset(building_auth)
		return true
	return false


static func execute_season_reset(building_auth: Node) -> String:
	var winner: String = TerritoryWarSystem.compute_leading_faction()
	var old_num: int = int(DatabaseManager.get_season_state().get("number", 1))
	DatabaseManager.reset_territorial_map_for_new_season(winner)
	if building_auth != null and building_auth.has_method("server_clear_all_buildings_for_season"):
		building_auth.call("server_clear_all_buildings_for_season")
	NetworkManager.broadcast_banner(
		"¡FIN DE TEMPORADA #%d — VICTORIA: %s!" % [old_num, winner.to_upper()],
		"Los Dioses han reiniciado el mapa territorial para una nueva guerra. Tu nivel, mochila, equipo y dragones permanecen intactos (+500 Coronas a los vencedores).",
		"#ffe066"
	)
	for peer_var: Variant in NetworkManager.peer_to_username.keys():
		NetworkManager.push_profile_to_peer(int(peer_var))
	return winner


static func get_days_remaining(season_state: Dictionary) -> int:
	var now: float = Time.get_unix_time_from_system()
	var rem: float = maxf(0.0, float(season_state.get("ends_at_unix", now)) - now)
	return int(ceilf(rem / 86400.0))
