class_name InventorySystem
extends RefCounted

## Enforces the 150-slot personal backpack limit (unlimited for AvatarOrden & AvatarCaos)
## and handles secure item transfers between the player's backpack and persistent House Storage Chests.


static func transfer_to_chest(username: String, building_id: int, item_id: String, qty: int) -> Dictionary:
	if qty <= 0 or not GameConfig.ITEMS.has(item_id):
		return {"ok": false, "error": "Ítem o cantidad inválida."}
	var used_chest: int = DatabaseManager.get_chest_used_slots(building_id)
	if used_chest + qty > GameConfig.STORAGE_CHEST_SLOTS:
		return {"ok": false, "error": "El cajón está lleno (%d / %d espacios)." % [used_chest, GameConfig.STORAGE_CHEST_SLOTS]}
	if not DatabaseManager.remove_item(username, item_id, qty):
		return {"ok": false, "error": "No tenés esa cantidad en tu mochila."}
	var cinv: Dictionary = DatabaseManager.get_chest_inventory(building_id)
	cinv[item_id] = int(cinv.get(item_id, 0)) + qty
	DatabaseManager.mark_dirty()
	DatabaseManager.save_database()
	return {"ok": true, "chest_inv": cinv.duplicate(true)}


static func transfer_from_chest(username: String, building_id: int, item_id: String, qty: int) -> Dictionary:
	if qty <= 0 or not GameConfig.ITEMS.has(item_id):
		return {"ok": false, "error": "Ítem o cantidad inválida."}
	var cinv: Dictionary = DatabaseManager.get_chest_inventory(building_id)
	var cur: int = int(cinv.get(item_id, 0))
	if cur < qty:
		return {"ok": false, "error": "El cajón no tiene suficiente cantidad."}
	if not DatabaseManager.can_add_item(username, item_id, qty):
		return {"ok": false, "error": "Mochila llena (máximo %d espacios). Guardá o vendé ítems primero." % GameConfig.BACKPACK_MAX_SLOTS}
	var rem: int = cur - qty
	if rem <= 0:
		cinv.erase(item_id)
	else:
		cinv[item_id] = rem
	DatabaseManager.add_item(username, item_id, qty)
	DatabaseManager.save_database()
	return {"ok": true, "chest_inv": cinv.duplicate(true)}
