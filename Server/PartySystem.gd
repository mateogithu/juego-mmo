class_name PartySystem
extends RefCounted

## 4-player Party management: invites, friendly-fire prevention, shared XP,
## and 4-player Complex Dungeon entry validation (with Solo Test bypass for Admins).

static var _parties: Dictionary = {} # int party_id -> {id, leader_peer, members: Array[int]}
static var _peer_to_party: Dictionary = {} # int peer_id -> int party_id
static var _pending_invites: Dictionary = {} # int target_peer -> int party_id
static var _next_party_id: int = 1


static func get_party_id(peer_id: int) -> int:
	return int(_peer_to_party.get(peer_id, -1))


static func get_party_members(peer_id: int) -> Array[int]:
	var pid: int = get_party_id(peer_id)
	if pid <= 0 or not _parties.has(pid):
		return [peer_id]
	var raw: Array = (_parties[pid] as Dictionary).get("members", []) as Array
	var out: Array[int] = []
	for m: Variant in raw:
		out.append(int(m))
	return out


static func are_in_same_party(peer_a: int, peer_b: int) -> bool:
	if peer_a == peer_b:
		return true
	var pa: int = get_party_id(peer_a)
	var pb: int = get_party_id(peer_b)
	return pa > 0 and pa == pb


static func invite_player(leader_peer: int, target_peer: int) -> Dictionary:
	if leader_peer == target_peer:
		return {"ok": false, "error": "No podés invitarte a vos mismo."}
	var pid: int = get_party_id(leader_peer)
	if pid <= 0:
		pid = _next_party_id
		_next_party_id += 1
		_parties[pid] = {"id": pid, "leader_peer": leader_peer, "members": [leader_peer]}
		_peer_to_party[leader_peer] = pid
	var p: Dictionary = _parties[pid] as Dictionary
	var members: Array = p["members"] as Array
	if members.size() >= GameConfig.MAX_PARTY_SIZE:
		return {"ok": false, "error": "El grupo ya está completo (máximo %d jugadores)." % GameConfig.MAX_PARTY_SIZE}
	if members.has(target_peer):
		return {"ok": false, "error": "Ese jugador ya está en tu grupo."}
	_pending_invites[target_peer] = pid
	return {"ok": true, "party_id": pid}


static func accept_invite(peer_id: int) -> Dictionary:
	if not _pending_invites.has(peer_id):
		return {"ok": false, "error": "No tenés invitaciones de grupo pendientes."}
	var pid: int = int(_pending_invites[peer_id])
	_pending_invites.erase(peer_id)
	if not _parties.has(pid):
		return {"ok": false, "error": "El grupo ya no existe."}
	var p: Dictionary = _parties[pid] as Dictionary
	var members: Array = p["members"] as Array
	if members.size() >= GameConfig.MAX_PARTY_SIZE:
		return {"ok": false, "error": "El grupo ya alcanzó 4 jugadores."}
	leave_party(peer_id)
	members.append(peer_id)
	_peer_to_party[peer_id] = pid
	return {"ok": true, "party_id": pid}


static func leave_party(peer_id: int) -> void:
	var pid: int = get_party_id(peer_id)
	_peer_to_party.erase(peer_id)
	_pending_invites.erase(peer_id)
	if pid <= 0 or not _parties.has(pid):
		return
	var p: Dictionary = _parties[pid] as Dictionary
	var members: Array = p["members"] as Array
	members.erase(peer_id)
	if members.is_empty():
		_parties.erase(pid)
	elif int(p["leader_peer"]) == peer_id:
		p["leader_peer"] = int(members[0])


static func can_enter_complex_dungeon(peer_id: int, role: String) -> Dictionary:
	# Exclusive Solo / Test Mode for AvatarOrden & AvatarCaos
	if GameConfig.is_avatar_role(role):
		return {"ok": true, "solo_admin": true}
	var members: Array[int] = get_party_members(peer_id)
	if members.size() < GameConfig.DUNGEON_REQUIRED_PARTY:
		return {
			"ok": false,
			"error": "Esta mazmorra compleja exige un grupo (Party) de %d jugadores (actualmente: %d/%d)." % [
				GameConfig.DUNGEON_REQUIRED_PARTY,
				members.size(),
				GameConfig.DUNGEON_REQUIRED_PARTY
			]
		}
	return {"ok": true, "solo_admin": false}
