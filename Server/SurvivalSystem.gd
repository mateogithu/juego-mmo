class_name SurvivalSystem
extends RefCounted

## Hunger / Satiety survival tick and 15-minute cooked meal buffs.
## AvatarOrden & AvatarCaos remain permanently full (immune to starvation).


static func tick_player_hunger(acc: Dictionary, st: Dictionary, dt: float) -> float:
	if GameConfig.is_avatar_role(str(acc.get("role", ""))):
		acc["hunger"] = 100.0
		st["hunger"] = 100.0
		return 0.0

	var hunger: float = float(acc.get("hunger", 100.0))
	# Loses ~1.0 satiety every 15 seconds while active
	hunger = maxf(0.0, hunger - dt * 0.07)
	acc["hunger"] = hunger
	st["hunger"] = hunger
	if hunger <= 0.0:
		# Starvation drains HP until the player eats cooked food
		return 2.2 * dt
	return 0.0


static func eat_cooked_meal(acc: Dictionary, st: Dictionary, item_id: String) -> bool:
	if not GameConfig.ITEMS.has(item_id):
		return false
	var idef: Dictionary = GameConfig.ITEMS[item_id] as Dictionary
	if str(idef.get("type", "")) != "food":
		return false
	var restore: float = float(idef.get("hunger", 35.0))
	var new_h: float = minf(100.0, float(acc.get("hunger", 100.0)) + restore)
	acc["hunger"] = new_h
	st["hunger"] = new_h
	var buff_kind: String = str(idef.get("food_buff", ""))
	if not buff_kind.is_empty():
		var until: float = Time.get_unix_time_from_system() + GameConfig.COOKING_BUFF_DURATION_SEC
		acc["food_buff"] = buff_kind
		acc["food_buff_until"] = until
		st["food_buff"] = buff_kind
		st["food_buff_until"] = until
	DatabaseManager.mark_dirty()
	return true
