class_name CraftingSystem
extends RefCounted

## Handles 4-piece Armor Set passives (Heavy, Medium, Light), Elemental Weapon traits
## (Fire, Lightning, Ice), Coin Minting from mined Gold/Silver ore, and Survival Cooking.


static func evaluate_gear_bonuses(profile: Dictionary) -> Dictionary:
	var out: Dictionary = {
		"hp_bonus": 0.0,
		"atk_bonus": 0.0,
		"spell_bonus": 0.0,
		"def_bonus": 0.0,
		"hp_mult": 1.0,
		"mitigation_mult": 1.0,
		"move_speed_mult": 1.0,
		"crit_chance": 0.05,
		"stamina_cost_mult": 1.0,
		"mana_cost_mult": 1.0,
		"mana_regen_mult": 1.0,
		"spell_power_mult": 1.0,
		"heal_mult": 1.0,
		"weapon_element": "none",
		"full_set_line": "",
		"has_full_dungeon_set": false
	}

	var line_counts: Dictionary = {"heavy": 0, "medium": 0, "light": 0}
	for slot_key: String in ["equipped_helmet", "equipped_chest", "equipped_legs", "equipped_boots", "equipped_weapon"]:
		var iid: String = str(profile.get(slot_key, ""))
		if iid.is_empty() or not GameConfig.ITEMS.has(iid):
			continue
		var idef: Dictionary = GameConfig.ITEMS[iid] as Dictionary
		out["hp_bonus"] = float(out["hp_bonus"]) + float(idef.get("hp_bonus", 0.0))
		out["atk_bonus"] = float(out["atk_bonus"]) + float(idef.get("atk_bonus", 0.0))
		out["spell_bonus"] = float(out["spell_bonus"]) + float(idef.get("spell_bonus", 0.0))
		out["def_bonus"] = float(out["def_bonus"]) + float(idef.get("def_bonus", 0.0))
		if idef.has("heal_bonus"):
			out["heal_mult"] = float(out["heal_mult"]) + float(idef["heal_bonus"])
		if slot_key == "equipped_weapon":
			out["weapon_element"] = str(idef.get("element", "none"))
		elif idef.has("armor_line"):
			var ln: String = str(idef["armor_line"])
			if line_counts.has(ln):
				line_counts[ln] = int(line_counts[ln]) + 1

	# 4-Piece Full Set Passives
	if int(line_counts["heavy"]) >= 4:
		out["full_set_line"] = "heavy"
		out["has_full_dungeon_set"] = true
		out["hp_mult"] = 1.25
		out["mitigation_mult"] = 0.80 # +20% physical mitigation
	elif int(line_counts["medium"]) >= 4:
		out["full_set_line"] = "medium"
		out["has_full_dungeon_set"] = true
		out["move_speed_mult"] = 1.20
		out["crit_chance"] = 0.23 # +18% crit
		out["stamina_cost_mult"] = 0.85
	elif int(line_counts["light"]) >= 4:
		out["full_set_line"] = "light"
		out["has_full_dungeon_set"] = true
		out["spell_power_mult"] = 1.30
		out["heal_mult"] = float(out["heal_mult"]) + 0.30
		out["mana_regen_mult"] = 1.25
		out["mana_cost_mult"] = 0.80

	return out


static func get_element_damage_multiplier(element: String) -> float:
	if element == "fire":
		return 1.32
	if element == "lightning":
		return 1.15
	if element == "ice":
		return 0.95
	return 1.0


static func get_element_cost_multiplier(element: String) -> float:
	if element == "fire":
		return 1.35 # High Mana/Stamina consumption for pure Fire damage
	if element == "lightning":
		return 1.0
	if element == "ice":
		return 0.9
	return 1.0


static func craft_recipe(username: String, recipe_id: String) -> Dictionary:
	if not GameConfig.CRAFT_RECIPES.has(recipe_id):
		return {"ok": false, "error": "Receta desconocida."}
	var acc: Dictionary = DatabaseManager.get_account_mutable(username)
	if acc.is_empty():
		return {"ok": false, "error": "Cuenta inválida."}

	var rec: Dictionary = GameConfig.CRAFT_RECIPES[recipe_id] as Dictionary
	var cost: Dictionary = rec["cost"] as Dictionary
	if not DatabaseManager.has_items(username, cost):
		return {"ok": false, "error": "Te faltan materiales para fabricar/cocinar esto."}

	# Coin Minting (player-driven gold economy from mined gold/silver ore!)
	if rec.has("mint_gold"):
		DatabaseManager.consume_items(username, cost)
		var minted: int = int(rec["mint_gold"])
		acc["gold"] = int(acc.get("gold", 0)) + minted
		DatabaseManager.mark_dirty()
		DatabaseManager.save_database()
		return {"ok": true, "message": "Acuñaste %d Monedas del Reino a partir de mineral fundido." % minted}

	var out_qty: int = int(rec.get("output_qty", 1))
	# Check backpack space (accounting for consumed items freeing slots)
	var consumed_slots: int = 0
	for k_var: Variant in cost.keys():
		consumed_slots += int(cost[k_var])
	var is_admin: bool = GameConfig.is_avatar_role(str(acc.get("role", "")))
	if not is_admin and DatabaseManager.get_backpack_used_slots(username) - consumed_slots + out_qty > GameConfig.BACKPACK_MAX_SLOTS:
		return {"ok": false, "error": "Mochila llena (150 espacios). Guardá ítems en un Cajón de tu casa."}

	DatabaseManager.consume_items(username, cost)
	DatabaseManager.add_item(username, recipe_id, out_qty)
	DatabaseManager.save_database()
	var iname: String = str((GameConfig.ITEMS.get(recipe_id, {}) as Dictionary).get("name", recipe_id))
	return {"ok": true, "message": "Fabricaste: %s x%d" % [iname, out_qty]}
