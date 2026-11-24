class_name SafeZone
extends RefCounted

## Handles the two indestructible capital Safe Zones:
## - Santuario del Alba (Bastión del Orden) at (0, 0)
## - Ciudadela del Caos (Santuario del Caos) at (260, 260)
## Blocks PvP damage, theft, and structure destruction inside either sanctuary.


static func get_safe_zone_at(world_pos: Vector3) -> Dictionary:
	# Underground dungeons are never safe zones
	if world_pos.y < -50.0:
		return {}
	var p2: Vector2 = Vector2(world_pos.x, world_pos.z)
	for sz: Dictionary in GameConfig.SAFE_ZONES:
		var center: Vector2 = sz["center_xz"] as Vector2
		var rad: float = float(sz["radius"])
		if p2.distance_to(center) <= rad:
			return sz
	return {}


static func is_in_safe_zone(world_pos: Vector3) -> bool:
	return not get_safe_zone_at(world_pos).is_empty()


static func get_safe_zone_name(world_pos: Vector3) -> String:
	var sz: Dictionary = get_safe_zone_at(world_pos)
	if sz.is_empty():
		return ""
	return str(sz.get("name", "Santuario"))
