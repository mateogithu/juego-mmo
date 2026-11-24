class_name TerritoryWarSystem
extends RefCounted

## Asymmetric Territorial War across the 5 world regions:
## - Order expands borders by constructing cities, walls, towers, houses, and altars.
## - Chaos conquers regions by besieging/destroying Order structures and raiding defenders.


static func record_structure_built(world_pos: Vector3, piece_type: String, builder_faction: String) -> void:
	var reg_id: String = GameConfig.get_region_id_at(world_pos)
	var season: Dictionary = DatabaseManager.get_season_state()
	var scores: Dictionary = season.get("region_scores", {}) as Dictionary
	if not scores.has(reg_id):
		scores[reg_id] = {"order": 0, "chaos": 0, "owner": GameConfig.PHILOSOPHY_NEUTRAL}
	var entry: Dictionary = scores[reg_id] as Dictionary
	var spec: Dictionary = GameConfig.BUILD_PIECES.get(piece_type, {}) as Dictionary
	var pts: int = int(spec.get("territory_pts", 10))
	if piece_type == "altar_chaos" or builder_faction == GameConfig.PHILOSOPHY_CHAOS:
		entry["chaos"] = int(entry.get("chaos", 0)) + pts
	else:
		entry["order"] = int(entry.get("order", 0)) + pts
	_recompute_region_owner(entry)
	DatabaseManager.mark_dirty()


static func record_structure_destroyed(world_pos: Vector3, piece_type: String, attacker_faction: String) -> void:
	var reg_id: String = GameConfig.get_region_id_at(world_pos)
	var season: Dictionary = DatabaseManager.get_season_state()
	var scores: Dictionary = season.get("region_scores", {}) as Dictionary
	if not scores.has(reg_id):
		return
	var entry: Dictionary = scores[reg_id] as Dictionary
	var spec: Dictionary = GameConfig.BUILD_PIECES.get(piece_type, {}) as Dictionary
	var pts: int = int(spec.get("territory_pts", 12))
	entry["order"] = maxi(0, int(entry.get("order", 0)) - pts)
	if attacker_faction == GameConfig.PHILOSOPHY_CHAOS or piece_type != "altar_chaos":
		entry["chaos"] = int(entry.get("chaos", 0)) + int(pts * 1.4)
	_recompute_region_owner(entry)
	DatabaseManager.mark_dirty()


static func _recompute_region_owner(entry: Dictionary) -> void:
	var o: int = int(entry.get("order", 0))
	var c: int = int(entry.get("chaos", 0))
	if o >= c + 25:
		entry["owner"] = GameConfig.PHILOSOPHY_ORDER
	elif c >= o + 25:
		entry["owner"] = GameConfig.PHILOSOPHY_CHAOS
	else:
		entry["owner"] = GameConfig.PHILOSOPHY_NEUTRAL


static func compute_leading_faction() -> String:
	var season: Dictionary = DatabaseManager.get_season_state()
	var scores: Dictionary = season.get("region_scores", {}) as Dictionary
	var order_regions: int = 0
	var chaos_regions: int = 0
	for rid_var: Variant in scores.keys():
		var own: String = str((scores[rid_var] as Dictionary).get("owner", ""))
		if own == GameConfig.PHILOSOPHY_ORDER:
			order_regions += 1
		elif own == GameConfig.PHILOSOPHY_CHAOS:
			chaos_regions += 1
	if order_regions > chaos_regions:
		return GameConfig.PHILOSOPHY_ORDER
	if chaos_regions > order_regions:
		return GameConfig.PHILOSOPHY_CHAOS
	return GameConfig.PHILOSOPHY_NEUTRAL
