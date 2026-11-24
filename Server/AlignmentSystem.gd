class_name AlignmentSystem
extends RefCounted

## Dynamic Order / Chaos alignment driven strictly by player actions in the world
## (ZERO NPC guards):
## - Order (+): building structures/cities, healing/aiding allies, defeating bosses.
## - Chaos (-): sieging/destroying structures, PvP kills, looting tombs.


static func apply_action(username: String, delta_score: int) -> String:
	var acc: Dictionary = DatabaseManager.get_account_mutable(username)
	if acc.is_empty() or GameConfig.is_avatar_role(str(acc.get("role", ""))):
		return str(acc.get("philosophy", GameConfig.PHILOSOPHY_NEUTRAL))
	var score: int = clampi(int(acc.get("alignment_score", 0)) + delta_score, -100, 100)
	acc["alignment_score"] = score
	var new_phil: String = GameConfig.PHILOSOPHY_NEUTRAL
	if score >= 20:
		new_phil = GameConfig.PHILOSOPHY_ORDER
	elif score <= -20:
		new_phil = GameConfig.PHILOSOPHY_CHAOS
	acc["philosophy"] = new_phil
	DatabaseManager.mark_dirty()
	return new_phil
