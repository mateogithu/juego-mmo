class_name PlayerEconomy
extends RefCounted

## 100% Player-Driven Economy helper (ZERO infinite NPC gold faucets or NPC gear vendors).
## Currency enters circulation only by mining & minting Gold/Silver ore or claiming bounties/chests;
## all market prices are set exclusively by players on the Market Board.


static func create_player_listing(username: String, item_id: String, qty: int, price_gold: int) -> Dictionary:
	if qty <= 0 or price_gold <= 0 or not GameConfig.ITEMS.has(item_id):
		return {"ok": false, "error": "Oferta inválida."}
	if not DatabaseManager.remove_item(username, item_id, qty):
		return {"ok": false, "error": "No tenés suficiente cantidad en tu mochila."}
	var listing_id: int = int(DatabaseManager.data.get("next_listing_id", 1))
	DatabaseManager.data["next_listing_id"] = listing_id + 1
	DatabaseManager.get_market_listings().append({
		"id": listing_id,
		"seller": username,
		"item_id": item_id,
		"qty": qty,
		"price_gold": price_gold
	})
	DatabaseManager.mark_dirty()
	DatabaseManager.save_database()
	return {"ok": true, "id": listing_id}


static func buy_player_listing(buyer_username: String, listing_id: int) -> Dictionary:
	var buyer: Dictionary = DatabaseManager.get_account_mutable(buyer_username)
	if buyer.is_empty():
		return {"ok": false, "error": "Comprador inválido."}
	var listings: Array = DatabaseManager.get_market_listings()
	for i: int in range(listings.size()):
		var entry: Dictionary = listings[i] as Dictionary
		if int(entry.get("id", -1)) == listing_id:
			var iid: String = str(entry.get("item_id", ""))
			var qty: int = int(entry.get("qty", 1))
			var price: int = int(entry.get("price_gold", 0))
			if int(buyer.get("gold", 0)) < price:
				return {"ok": false, "error": "Monedas insuficientes."}
			if not DatabaseManager.can_add_item(buyer_username, iid, qty):
				return {"ok": false, "error": "Mochila llena (máx. 150 espacios)."}
			buyer["gold"] = int(buyer.get("gold", 0)) - price
			DatabaseManager.add_item(buyer_username, iid, qty)
			var seller_name: String = str(entry.get("seller", ""))
			var seller: Dictionary = DatabaseManager.get_account_mutable(seller_name)
			if not seller.is_empty():
				seller["gold"] = int(seller.get("gold", 0)) + price
			listings.remove_at(i)
			DatabaseManager.mark_dirty()
			DatabaseManager.save_database()
			return {"ok": true, "seller": seller_name, "price": price}
	return {"ok": false, "error": "La oferta ya fue vendida."}
