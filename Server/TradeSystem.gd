class_name TradeSystem
extends RefCounted

## Secure Dual-Confirmation Player-to-Player (P2P) Direct Trade sessions.
## Both players place items/coins and must explicitly confirm before atomic transfer.

static var _sessions: Dictionary = {} # int trade_id -> session dict
static var _peer_trade: Dictionary = {} # int peer_id -> int trade_id
static var _next_id: int = 1


static func start_trade(peer_a: int, peer_b: int) -> Dictionary:
	if peer_a == peer_b:
		return {"ok": false, "error": "No podés comerciar con vos mismo."}
	if _peer_trade.has(peer_a) or _peer_trade.has(peer_b):
		return {"ok": false, "error": "Uno de los jugadores ya está en un intercambio."}
	var tid: int = _next_id
	_next_id += 1
	_sessions[tid] = {
		"id": tid,
		"peer_a": peer_a,
		"peer_b": peer_b,
		"offer_a": {"gold": 0, "items": {}},
		"offer_b": {"gold": 0, "items": {}},
		"confirm_a": false,
		"confirm_b": false
	}
	_peer_trade[peer_a] = tid
	_peer_trade[peer_b] = tid
	return {"ok": true, "session": _sessions[tid]}


static func get_session_for_peer(peer_id: int) -> Dictionary:
	var tid: int = int(_peer_trade.get(peer_id, -1))
	if tid <= 0 or not _sessions.has(tid):
		return {}
	return _sessions[tid] as Dictionary


static func update_offer(peer_id: int, gold: int, item_id: String, qty: int) -> Dictionary:
	var sess: Dictionary = get_session_for_peer(peer_id)
	if sess.is_empty():
		return {"ok": false, "error": "Sin sesión de intercambio."}
	var is_a: bool = (int(sess["peer_a"]) == peer_id)
	var offer: Dictionary = (sess["offer_a"] if is_a else sess["offer_b"]) as Dictionary
	offer["gold"] = maxi(0, gold)
	if not item_id.is_empty() and GameConfig.ITEMS.has(item_id):
		var items: Dictionary = offer["items"] as Dictionary
		if qty <= 0:
			items.erase(item_id)
		else:
			items[item_id] = qty
	# Reset confirmations whenever either side modifies the offer
	sess["confirm_a"] = false
	sess["confirm_b"] = false
	return {"ok": true, "session": sess}


static func confirm_trade(peer_id: int, user_a: String, user_b: String) -> Dictionary:
	var sess: Dictionary = get_session_for_peer(peer_id)
	if sess.is_empty():
		return {"ok": false, "error": "Sin sesión de intercambio."}
	if int(sess["peer_a"]) == peer_id:
		sess["confirm_a"] = true
	else:
		sess["confirm_b"] = true

	if not (bool(sess["confirm_a"]) and bool(sess["confirm_b"])):
		return {"ok": true, "completed": false, "session": sess}

	# Atomic dual-validation & transfer
	var acc_a: Dictionary = DatabaseManager.get_account_mutable(user_a)
	var acc_b: Dictionary = DatabaseManager.get_account_mutable(user_b)
	var oa: Dictionary = sess["offer_a"] as Dictionary
	var ob: Dictionary = sess["offer_b"] as Dictionary
	var ga: int = int(oa["gold"])
	var gb: int = int(ob["gold"])
	var ia: Dictionary = oa["items"] as Dictionary
	var ib: Dictionary = ob["items"] as Dictionary

	if int(acc_a.get("gold", 0)) < ga or int(acc_b.get("gold", 0)) < gb:
		cancel_trade(peer_id)
		return {"ok": false, "error": "Oro insuficiente para completar el intercambio."}
	if not DatabaseManager.has_items(user_a, ia) or not DatabaseManager.has_items(user_b, ib):
		cancel_trade(peer_id)
		return {"ok": false, "error": "Ítems insuficientes para completar el intercambio."}

	acc_a["gold"] = int(acc_a["gold"]) - ga + gb
	acc_b["gold"] = int(acc_b["gold"]) - gb + ga
	DatabaseManager.consume_items(user_a, ia)
	DatabaseManager.consume_items(user_b, ib)
	for iid_var: Variant in ib.keys():
		DatabaseManager.add_item(user_a, str(iid_var), int(ib[iid_var]))
	for iid_var: Variant in ia.keys():
		DatabaseManager.add_item(user_b, str(iid_var), int(ia[iid_var]))
	DatabaseManager.save_database()
	cancel_trade(peer_id)
	return {"ok": true, "completed": true}


static func cancel_trade(peer_id: int) -> Dictionary:
	var sess: Dictionary = get_session_for_peer(peer_id)
	if sess.is_empty():
		return {}
	var tid: int = int(sess["id"])
	_peer_trade.erase(int(sess["peer_a"]))
	_peer_trade.erase(int(sess["peer_b"]))
	_sessions.erase(tid)
	return sess
