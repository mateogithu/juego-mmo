class_name LevelingSystem
extends RefCounted

## Player progression from Level 1 to Level 8,000 (with Infinity symbol for AvatarOrden & AvatarCaos).


static func xp_for_next_level(current_level: int) -> int:
	var lv: int = clampi(current_level, 1, GameConfig.MAX_PLAYER_LEVEL)
	return int(100.0 + pow(float(lv), 1.35) * 18.0)


static func grant_xp(username: String, raw_xp: int) -> Dictionary:
	var acc: Dictionary = DatabaseManager.get_account_mutable(username)
	if acc.is_empty():
		return {"leveled_up": false, "level": 1}
	if GameConfig.is_avatar_role(str(acc.get("role", ""))):
		return {"leveled_up": false, "level": 0}

	var phil: String = str(acc.get("philosophy", GameConfig.PHILOSOPHY_NEUTRAL))
	var mult: float = GodsInterventionSystem.get_balance_xp_mult(phil)
	var gained: int = maxi(1, int(roundf(float(raw_xp) * mult)))
	var lv: int = clampi(int(acc.get("level", 1)), 1, GameConfig.MAX_PLAYER_LEVEL)
	var xp: int = int(acc.get("xp", 0)) + gained
	var leveled: bool = false

	while lv < GameConfig.MAX_PLAYER_LEVEL:
		var req: int = xp_for_next_level(lv)
		if xp >= req:
			xp -= req
			lv += 1
			leveled = true
		else:
			break

	acc["level"] = lv
	acc["xp"] = xp
	DatabaseManager.mark_dirty()
	return {"leveled_up": leveled, "level": lv, "gained_xp": gained}


static func get_level_stat_multiplier(level: int, role: String) -> float:
	if GameConfig.is_avatar_role(role):
		return 10.0
	var lv: float = float(clampi(level, 1, GameConfig.MAX_PLAYER_LEVEL))
	# Smooth progressive scaling across 1..8000 (Lv 1 = 1.0x, Lv 100 = 1.8x, Lv 8000 = 9.0x)
	return 1.0 + sqrt(lv - 1.0) * 0.089


static func format_level_badge(level: int, role: String, disguised_novice: bool = false) -> String:
	if GameConfig.is_avatar_role(role) and not disguised_novice:
		return "♾️"
	if disguised_novice:
		return "Nv. 1"
	return "Nv. %d" % clampi(level, 1, GameConfig.MAX_PLAYER_LEVEL)
