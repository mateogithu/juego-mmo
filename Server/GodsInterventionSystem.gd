class_name GodsInterventionSystem
extends RefCounted

## Handles automatic Population Balance Blessing ("Bendición de Equilibrio")
## when one faction significantly outnumbers the other, plus Disguised Novice Mode
## checks for AvatarOrden & AvatarCaos.

static var active_balance_faction: String = ""


static func evaluate_population_balance() -> Dictionary:
	var order_count: int = 0
	var chaos_count: int = 0
	for peer_var: Variant in NetworkManager.peer_to_username.keys():
		var acc: Dictionary = DatabaseManager.get_account_mutable(str(NetworkManager.peer_to_username[peer_var]))
		if acc.is_empty() or GameConfig.is_avatar_role(str(acc.get("role", ""))):
			continue
		var phil: String = str(acc.get("philosophy", GameConfig.PHILOSOPHY_NEUTRAL))
		if phil == GameConfig.PHILOSOPHY_ORDER:
			order_count += 1
		elif phil == GameConfig.PHILOSOPHY_CHAOS:
			chaos_count += 1

	var new_favored: String = ""
	if chaos_count >= 3 and order_count >= 1 and chaos_count >= order_count * 2:
		new_favored = GameConfig.PHILOSOPHY_ORDER
	elif order_count >= 3 and chaos_count >= 1 and order_count >= chaos_count * 2:
		new_favored = GameConfig.PHILOSOPHY_CHAOS

	var changed: bool = (new_favored != active_balance_faction)
	active_balance_faction = new_favored
	return {
		"changed": changed,
		"favored_faction": active_balance_faction,
		"order_count": order_count,
		"chaos_count": chaos_count
	}


static func get_balance_damage_mult(faction: String) -> float:
	if not active_balance_faction.is_empty() and faction == active_balance_faction:
		return 1.35
	return 1.0


static func get_balance_defense_mult(faction: String) -> float:
	if not active_balance_faction.is_empty() and faction == active_balance_faction:
		return 1.30
	return 1.0


static func get_balance_xp_mult(faction: String) -> float:
	if not active_balance_faction.is_empty() and faction == active_balance_faction:
		return 1.50
	return 1.0
