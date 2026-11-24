class_name GameHUD
extends CanvasLayer

## Full MMORPG HUD (Release 2.0):
## - Safe Zone (Green) vs Open PvP Conquest (Red) zone pill + dramatic frontier crossing banner
## - Levels 1-8000 / Infinity badge, HP/Shield, Mana, Stamina, Hunger (Saciedad) bars
## - Corner Minimap + Interactive 5-Region World Map (M) with Wayshrine fast travel
## - 150-Slot Backpack + 4-Piece Armor Set tags + Campfire/Forge/Alchemy Crafting + 100% Player Market
## - Lockable 60-Slot Storage Chest modal + Direct P2P Trade + 4-Player Party HUD/Invite
## - Free Cosmetics for Creator Avatars + F1 Console (Disguised Novice Lv 1, Faction Grace, Season Reset)

var local_player: PlayerController = null
var _world_auth: WorldAuthority = null
var _grace_sched: CombatGraceScheduler = null

var _grace_state: Dictionary = {}
var _online_roster: Array[String] = []
var _active_panel: Control = null
var _banner_timer: float = 0.0

@onready var root_control: Control = $RootControl
var _grace_label: Label = null
var _zone_pill: PanelContainer = null
var _zone_pill_lbl: Label = null
var _minimap_canvas: Control = null
var _party_hud_lbl: Label = null
var _boss_bar_box: PanelContainer = null
var _boss_name_lbl: Label = null
var _boss_hp_bar: ProgressBar = null
var _boss_hp_lbl: Label = null
var _banner_box: PanelContainer = null
var _banner_title: Label = null
var _banner_body: Label = null
var _station_filter: String = ""

var _player_title: Label = null
var _hp_bar: ProgressBar = null
var _mana_bar: ProgressBar = null
var _stamina_bar: ProgressBar = null
var _hunger_bar: ProgressBar = null
var _hp_text: Label = null
var _mana_text: Label = null
var _stamina_text: Label = null
var _hunger_text: Label = null
var _dragon_status_lbl: Label = null
var _currency_lbl: Label = null
var _coords_lbl: Label = null
var _grace_badge: Label = null
var _crosshair_root: Control = null
var _ability_labels: Array[Label] = []
var _ability_panels: Array[PanelContainer] = []
var _slot_style_normal: StyleBoxFlat = null
var _slot_style_selected: StyleBoxFlat = null
var _chat_log: RichTextLabel = null
var _chat_input: LineEdit = null
var _build_bar: PanelContainer = null
var _build_info_lbl: Label = null

# Modal Panels
var _inv_panel: PanelContainer = null
var _inv_slots_lbl: Label = null
var _inv_list_box: VBoxContainer = null
var _craft_list_box: VBoxContainer = null
var _market_list_box: VBoxContainer = null
var _market_item_opt: OptionButton = null
var _market_qty_spin: SpinBox = null
var _market_price_spin: SpinBox = null
var _trade_target_in: LineEdit = null
var _trade_status_lbl: Label = null

var _chest_panel: PanelContainer = null
var _chest_title_lbl: Label = null
var _chest_bag_box: VBoxContainer = null
var _chest_box: VBoxContainer = null
var _open_chest_id: int = -1
var _open_chest_items: Dictionary = {}

var _world_map_ui: WorldMapUI = null

var _shop_panel: PanelContainer = null
var _shop_crowns_lbl: Label = null
var _shop_list_box: VBoxContainer = null

var _guilds_panel: PanelContainer = null
var _party_invite_in: LineEdit = null
var _party_list_lbl: Label = null
var _guild_name_in: LineEdit = null
var _guild_phil_opt: OptionButton = null
var _guild_manif_in: LineEdit = null
var _guild_list_box: VBoxContainer = null
var _bounty_target_in: LineEdit = null
var _bounty_gold_spin: SpinBox = null
var _bounty_reason_in: LineEdit = null
var _bounty_list_box: VBoxContainer = null

var _avatar_panel: PanelContainer = null
var _avatar_target_in: LineEdit = null
var _avatar_x_spin: SpinBox = null
var _avatar_z_spin: SpinBox = null
var _avatar_announce_in: LineEdit = null
var _avatar_roster_lbl: Label = null

var _pause_panel: PanelContainer = null
var _server_monitor_lbl: Label = null


func _ready() -> void:
	add_to_group("game_hud")
	_world_auth = get_tree().get_first_node_in_group("world_authority") as WorldAuthority
	_grace_sched = get_tree().get_first_node_in_group("combat_grace_scheduler") as CombatGraceScheduler

	if NetworkManager.is_dedicated_server():
		_build_dedicated_server_overlay()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	_build_hud_layout()
	_connect_signals()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if _grace_sched != null:
		_on_combat_grace_updated(_grace_sched.current_state)
	var my_id: int = multiplayer.get_unique_id()
	if _world_auth != null and _world_auth.player_nodes.has(my_id):
		_on_local_player_ready(_world_auth.player_nodes[my_id] as PlayerController)
	_refresh_all_panels()


func _connect_signals() -> void:
	if _world_auth != null:
		_world_auth.local_player_ready.connect(_on_local_player_ready)
		_world_auth.player_roster_updated.connect(_on_roster_updated)
	if _grace_sched != null:
		_grace_sched.combat_grace_updated.connect(_on_combat_grace_updated)
	NetworkManager.profile_updated.connect(_on_profile_updated)
	NetworkManager.chat_message_received.connect(_on_chat_received)
	NetworkManager.system_banner_received.connect(_on_banner_received)
	NetworkManager.social_data_updated.connect(_on_social_updated)
	NetworkManager.season_data_updated.connect(_on_season_updated)
	NetworkManager.party_updated.connect(_on_party_updated)
	NetworkManager.trade_updated.connect(_on_trade_updated)
	NetworkManager.chest_opened.connect(_on_chest_opened)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)


func _on_local_player_ready(pc: PlayerController) -> void:
	local_player = pc
	if not pc.zone_status_changed.is_connected(_on_zone_status_changed):
		pc.zone_status_changed.connect(_on_zone_status_changed)
	var wp: Vector3 = GameConfig.local_to_world(pc.global_position)
	_update_zone_pill(SafeZone.is_in_safe_zone(wp), SafeZone.get_safe_zone_name(wp))
	_update_ability_slot_names()
	_refresh_all_panels()


func _on_zone_status_changed(in_safe: bool, zname: String) -> void:
	_update_zone_pill(in_safe, zname)
	if in_safe:
		_on_banner_received("🛡️ HAS ENTRADO EN ZONA SEGURA", "%s — Combate PvP y robos 100%% bloqueados." % zname, "#66f2a2")
	else:
		_on_banner_received("⚔️ HAS ENTRADO EN ZONA PVP Y CONQUISTA", "¡Sin reglas ni piedad! Defendé tu botín y tu dragón con tu vida.", "#ff4a3a")


func _update_zone_pill(in_safe: bool, zname: String) -> void:
	if _zone_pill == null or _zone_pill_lbl == null:
		return
	if in_safe:
		_zone_pill.add_theme_stylebox_override("panel", _make_style(Color(0.06, 0.22, 0.12, 0.9), Color(0.32, 0.95, 0.52, 0.95)))
		_zone_pill_lbl.text = "🛡️ ZONA SEGURA: %s" % zname
		_zone_pill_lbl.add_theme_color_override("font_color", Color(0.65, 1.0, 0.78))
	else:
		_zone_pill.add_theme_stylebox_override("panel", _make_style(Color(0.24, 0.05, 0.05, 0.9), Color(1.0, 0.28, 0.22, 0.95)))
		_zone_pill_lbl.text = "⚔️ ZONA PVP Y CONQUISTA (BOTÍN TOTAL)"
		_zone_pill_lbl.add_theme_color_override("font_color", Color(1.0, 0.65, 0.6))


func _on_profile_updated(_profile: Dictionary) -> void:
	_refresh_all_panels()
	if _chest_panel != null and _chest_panel.visible:
		_refresh_chest_panel()


func _on_social_updated(_g: Dictionary, _l: Array, _b: Array) -> void:
	_refresh_guilds_panel()
	_refresh_inventory_panel()


func _on_season_updated(_s: Dictionary) -> void:
	if _world_map_ui != null and _world_map_ui.visible:
		_refresh_world_map()


func _on_party_updated(members: Array) -> void:
	if _party_hud_lbl != null:
		if members.is_empty():
			_party_hud_lbl.text = "Grupo (Tab): Solo (4 jug. para Mazmorras)"
		else:
			var parts: Array[String] = []
			for m_var: Variant in members:
				var m: Dictionary = m_var as Dictionary
				var badge: String = LevelingSystem.format_level_badge(int(m.get("level", 1)), str(m.get("role", GameConfig.ROLE_PLAYER)))
				parts.append("%s %s" % [badge, str(m.get("username", ""))])
			_party_hud_lbl.text = "Grupo (%d/4): %s" % [members.size(), ", ".join(parts)]
	if _party_list_lbl != null:
		_party_list_lbl.text = _party_hud_lbl.text if _party_hud_lbl != null else ""


func _on_trade_updated(sess: Dictionary) -> void:
	if _trade_status_lbl == null:
		return
	if sess.is_empty():
		_trade_status_lbl.text = "Trueque Directo: Sin sesión activa."
	else:
		_trade_status_lbl.text = "Trueque con %s / %s — Oro A:%d B:%d | Confirmado A:%s B:%s" % [
			str(sess.get("name_a", "")), str(sess.get("name_b", "")),
			int(sess.get("gold_a", 0)), int(sess.get("gold_b", 0)),
			"Sí" if bool(sess.get("confirm_a", false)) else "No",
			"Sí" if bool(sess.get("confirm_b", false)) else "No"
		]


func _on_chest_opened(building_id: int, owner_name: String, items: Dictionary) -> void:
	_open_chest_id = building_id
	_open_chest_items = items
	if _chest_title_lbl != null:
		_chest_title_lbl.text = "Cajón de Guardado de %s (%d / 60 espacios)" % [owner_name, items.size()]
	_refresh_chest_panel()
	_toggle_panel(_chest_panel)


func _on_roster_updated(names: PackedStringArray) -> void:
	_online_roster.clear()
	for n: String in names:
		_online_roster.append(n)
	if _avatar_roster_lbl != null:
		_avatar_roster_lbl.text = "Conectados (%d): %s" % [_online_roster.size(), ", ".join(_online_roster)]


func _on_combat_grace_updated(state: Dictionary) -> void:
	_grace_state = state


func _on_disconnected(_reason: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://Client/UI/MainMenu.tscn")


func _on_chat_received(sender: String, channel: String, text: String, color_hex: String) -> void:
	if _chat_log == null:
		return
	_chat_log.append_text("[color=%s][%s] %s:[/color] %s\n" % [color_hex, channel, sender, text])


func _on_banner_received(title: String, body: String, color_hex: String) -> void:
	if _banner_box == null:
		return
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", Color.html(color_hex))
	_banner_body.text = body
	_banner_box.visible = true
	_banner_timer = 7.5


func _unhandled_input(event: InputEvent) -> void:
	if NetworkManager.is_dedicated_server():
		return

	if _chat_input != null and _chat_input.has_focus():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
			_chat_input.release_focus()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo:
			if kev.keycode == KEY_ENTER or kev.keycode == KEY_KP_ENTER:
				if _active_panel == null and _chat_input != null:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					_chat_input.grab_focus()
					get_viewport().set_input_as_handled()
					return

	if _active_panel != null and event.is_action_pressed("ui_cancel"):
		_close_all_panels()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("pause_menu"):
		if _active_panel != null:
			_close_all_panels()
		else:
			_toggle_panel(_pause_panel)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_map"):
		open_world_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_inventory"):
		_station_filter = ""
		_toggle_panel(_inv_panel)
		_refresh_inventory_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_shop"):
		_toggle_panel(_shop_panel)
		_refresh_shop_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_guilds"):
		_toggle_panel(_guilds_panel)
		_refresh_guilds_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_avatar_console"):
		_toggle_panel(_avatar_panel)
		get_viewport().set_input_as_handled()


func open_world_map() -> void:
	if _world_map_ui == null:
		return
	if _active_panel == _world_map_ui:
		_close_all_panels()
	else:
		_refresh_world_map()
		_toggle_panel(_world_map_ui)


func _refresh_world_map() -> void:
	if _world_map_ui == null:
		return
	var wp: Vector3 = GameConfig.local_to_world(local_player.global_position) if local_player != null else Vector3.ZERO
	var discovered: Array = NetworkManager.local_profile.get("discovered_wayshrines", ["ws_alba", "ws_caos"]) as Array
	_world_map_ui.refresh_map(wp, NetworkManager.cached_season, discovered, true)


func open_trade_market() -> void:
	open_station_panel("shop_stall")


func open_station_panel(station_type: String) -> void:
	_station_filter = station_type
	if _inv_panel != null:
		_close_all_panels()
		_toggle_panel(_inv_panel)
		_refresh_inventory_panel()


func _focus_first_control(root: Node) -> bool:
	for child: Node in root.get_children():
		if child is Control:
			var ctrl: Control = child as Control
			if ctrl.visible and ctrl.focus_mode != Control.FOCUS_NONE:
				if (ctrl is Button and not (ctrl as Button).disabled) or ctrl is LineEdit or ctrl is OptionButton or ctrl is SpinBox:
					ctrl.grab_focus()
					return true
		if _focus_first_control(child):
			return true
	return false


func _toggle_panel(panel: Control) -> void:
	if panel == null:
		return
	var opening: bool = (_active_panel != panel)
	_close_all_panels()
	if opening:
		_active_panel = panel
		panel.visible = true
		if _crosshair_root != null:
			_crosshair_root.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		AudioSynth.play_ui_click()
		_focus_first_control.call_deferred(panel)


func _close_all_panels() -> void:
	for p: Control in [_inv_panel, _chest_panel, _world_map_ui, _shop_panel, _guilds_panel, _avatar_panel, _pause_panel]:
		if p != null:
			p.visible = false
	_active_panel = null
	if _crosshair_root != null:
		_crosshair_root.visible = true
	if _chat_input == null or not _chat_input.has_focus():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if NetworkManager.is_dedicated_server():
		if _server_monitor_lbl != null:
			var blessed: String = str(_grace_state.get("active_username", "Ninguno"))
			var online: Array[String] = NetworkManager.get_connected_usernames()
			_server_monitor_lbl.text = (
				"SERVIDOR DEDICADO ACTIVO — %s (v2.0)\n"
				+ "Jugadores Conectados: %d (%s)\n"
				+ "Gracia Combativa Hoy: %s\n"
				+ "Base de Datos: user://server_database.json"
			) % [GameConfig.GAME_TITLE, online.size(), ", ".join(online), blessed]
		return

	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0 and _banner_box != null:
			_banner_box.visible = false

	_update_combat_grace_banner()
	_update_boss_bar_ui()
	_update_player_vitals_ui()
	if _minimap_canvas != null:
		_minimap_canvas.queue_redraw()


func _update_boss_bar_ui() -> void:
	if _boss_bar_box == null or local_player == null:
		return
	var best_boss: WorldBoss = null
	var best_dist: float = 75.0
	for node: Node in get_tree().get_nodes_in_group("world_bosses"):
		var wb: WorldBoss = node as WorldBoss
		if not wb.is_alive:
			continue
		var d: float = local_player.global_position.distance_to(wb.global_position)
		if d < best_dist:
			best_dist = d
			best_boss = wb
	if best_boss == null:
		_boss_bar_box.visible = false
		return
	_boss_bar_box.visible = true
	_boss_name_lbl.text = "🐉 %s — %s" % [best_boss.boss_name, best_boss.boss_title]
	_boss_hp_bar.max_value = best_boss.max_hp
	_boss_hp_bar.value = best_boss.hp
	_boss_hp_lbl.text = "%d / %d HP" % [int(ceilf(best_boss.hp)), int(best_boss.max_hp)]


func _update_combat_grace_banner() -> void:
	if _grace_label == null:
		return
	var now: float = Time.get_unix_time_from_system()
	var active_user: String = str(_grace_state.get("active_username", ""))
	var expires_at: float = float(_grace_state.get("expires_at_unix", 0.0))
	var next_roll: float = float(_grace_state.get("next_roll_at_unix", 0.0))
	var s_num: int = int(NetworkManager.cached_season.get("season_number", 1))
	var s_days: int = SeasonResetSystem.get_days_remaining(NetworkManager.cached_season) if not NetworkManager.cached_season.is_empty() else 30
	if not active_user.is_empty() and now < expires_at:
		var rem: String = GameConfig.format_duration(expires_at - now)
		_grace_label.text = "★ GRACIA COMBATIVA (x2): %s (%s) | Temp. %d (%d d) ★" % [active_user, rem, s_num, s_days]
		_grace_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	else:
		var until: String = GameConfig.format_duration(maxf(0.0, next_roll - now))
		_grace_label.text = "Próximo Descenso: %s | Temporada %d (%d días restantes)" % [until, s_num, s_days]
		_grace_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.94))


func _update_player_vitals_ui() -> void:
	if local_player == null:
		return
	var class_name_str: String = str((GameConfig.CLASSES.get(local_player.class_id, {}) as Dictionary).get("name", local_player.class_id))
	var lvl_badge: String = LevelingSystem.format_level_badge(local_player.level, local_player.role, local_player.disguised_novice)
	_player_title.text = "%s %s — %s [%s]" % [lvl_badge, local_player.username, class_name_str, local_player.philosophy]

	_hp_bar.max_value = local_player.max_hp
	_hp_bar.value = local_player.hp
	var sh_str: String = " (+%d Escudo)" % int(local_player.shield_hp) if local_player.shield_hp > 1.0 else ""
	_hp_text.text = "HP: %d / %d%s" % [int(ceilf(local_player.hp)), int(local_player.max_hp), sh_str]

	var is_inf: bool = GameConfig.is_avatar_role(local_player.role) and not local_player.disguised_novice
	_mana_bar.max_value = local_player.max_mana
	_mana_bar.value = local_player.mana
	_mana_text.text = "Maná: ♾️ ILIMITADO" if is_inf else "Maná: %d / %d" % [int(local_player.mana), int(local_player.max_mana)]

	_stamina_bar.max_value = local_player.max_stamina
	_stamina_bar.value = local_player.stamina
	_stamina_text.text = "Estamina: ♾️ ILIMITADA" if is_inf else "Estamina: %d / %d" % [int(local_player.stamina), int(local_player.max_stamina)]

	_hunger_bar.max_value = 100.0
	_hunger_bar.value = local_player.hunger
	_hunger_text.text = "Saciedad: %d%%" % int(local_player.hunger)

	var gold: int = int(NetworkManager.local_profile.get("gold", 0))
	var crowns: int = int(NetworkManager.local_profile.get("crowns", 0))
	var used_slots: int = _count_local_backpack_slots()
	var slots_txt: String = "∞" if is_inf else "%d/%d" % [used_slots, GameConfig.BACKPACK_MAX_SLOTS]
	_currency_lbl.text = "Oro: %d | Coronas: %d | Mochila: %s" % [gold, crowns, slots_txt]

	if _coords_lbl != null:
		var wp: Vector3 = GameConfig.local_to_world(local_player.global_position)
		var cam_mode: String = "1ªP" if local_player.is_first_person else "3ªP"
		_coords_lbl.text = "Pos: (%d, %d) | Vista: %s | [M] Mapa | [G/X] Dragón" % [int(wp.x), int(wp.z), cam_mode]
	_grace_badge.visible = local_player.has_combat_grace

	if local_player.is_mounted and local_player.mounted_dragon != null:
		var dc: DragonController = local_player.mounted_dragon
		_dragon_status_lbl.visible = true
		_dragon_status_lbl.text = "🐉 DRAGÓN: %s | Vel: %d m/s | RT/LMB: Fuego | LT/RMB: Planear | A/Esp: Subir | B/Ctrl: Bajar | X/G: Guardar en Mochila" % [
			dc.get_flight_state_label(), int(dc.velocity.length())
		]
	else:
		_dragon_status_lbl.visible = false

	var class_def: Dictionary = GameConfig.CLASSES.get(local_player.class_id, {}) as Dictionary
	var abilities: Array = class_def.get("abilities", []) as Array
	for i: int in range(mini(4, _ability_labels.size())):
		var ab_name: String = str((abilities[i] as Dictionary).get("name", "Habilidad")) if i < abilities.size() else "-"
		var cd: float = local_player.ability_cooldowns[i]
		var is_sel: bool = (i == local_player.selected_ability_slot)
		if i < _ability_panels.size() and _slot_style_normal != null and _slot_style_selected != null:
			_ability_panels[i].add_theme_stylebox_override("panel", _slot_style_selected if is_sel else _slot_style_normal)
		var sel_tag: String = "★ " if is_sel else ""
		if cd > 0.05:
			_ability_labels[i].text = "%s[%d] %s\n(%.1fs)" % [sel_tag, i + 1, ab_name, cd]
			_ability_labels[i].add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
		else:
			_ability_labels[i].text = "%s[%d] %s\nLISTA" % [sel_tag, i + 1, ab_name]
			_ability_labels[i].add_theme_color_override("font_color", Color(1.0, 0.94, 0.55) if is_sel else Color(0.88, 0.9, 0.96))

	if local_player.building_system != null and _build_bar != null:
		var bs: BuildingSystem = local_player.building_system
		_build_bar.visible = bs.is_active
		if bs.is_active:
			var spec: Dictionary = GameConfig.BUILD_PIECES.get(bs.selected_piece, {}) as Dictionary
			_build_info_lbl.text = "CONSTRUCCIÓN (B salir) | %s (LB/RB o 1-9) | Snap (F): %s | Rotar (R) | Colocar (LMB/RT)" % [
				str(spec.get("name", bs.selected_piece)),
				"ACTIVADO" if bs.snap_to_grid else "LIBRE"
			]


func _count_local_backpack_slots() -> int:
	var inv: Dictionary = NetworkManager.local_profile.get("inventory", {}) as Dictionary
	var total: int = 0
	for q_var: Variant in inv.values():
		var q: int = int(q_var)
		if q > 0:
			total += 1
	return total


func _update_ability_slot_names() -> void:
	_update_player_vitals_ui()


func _draw_minimap() -> void:
	if _minimap_canvas == null or local_player == null:
		return
	var sz: Vector2 = _minimap_canvas.size
	var center: Vector2 = sz * 0.5
	var wp: Vector3 = GameConfig.local_to_world(local_player.global_position)
	_minimap_canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.09, 0.12, 0.92))
	var scale_px: float = 0.24 # 1m = 0.24px (~300m view)

	for sdef: Dictionary in GameConfig.SAFE_ZONES:
		var sc: Vector2 = sdef.get("center_xz", Vector2.ZERO) as Vector2
		var dp: Vector2 = Vector2(sc.x - wp.x, sc.y - wp.z) * scale_px + center
		if dp.x >= 0.0 and dp.x <= sz.x and dp.y >= 0.0 and dp.y <= sz.y:
			_minimap_canvas.draw_circle(dp, float(sdef.get("radius", 34.0)) * scale_px, Color(0.25, 0.85, 0.45, 0.3))

	for wdef: Dictionary in GameConfig.WAYSHRINES:
		var wxz: Vector2 = wdef.get("xz", Vector2.ZERO) as Vector2
		var dp: Vector2 = Vector2(wxz.x - wp.x, wxz.y - wp.z) * scale_px + center
		if dp.x >= 4.0 and dp.x <= sz.x - 4.0 and dp.y >= 4.0 and dp.y <= sz.y - 4.0:
			_minimap_canvas.draw_circle(dp, 3.0, Color(0.35, 0.9, 1.0))

	for bdef: Dictionary in GameConfig.WORLD_BOSSES:
		var bxz: Vector2 = bdef.get("spawn_xz", Vector2.ZERO) as Vector2
		var dp: Vector2 = Vector2(bxz.x - wp.x, bxz.y - wp.z) * scale_px + center
		if dp.x >= 4.0 and dp.x <= sz.x - 4.0 and dp.y >= 4.0 and dp.y <= sz.y - 4.0:
			_minimap_canvas.draw_circle(dp, 3.5, Color(1.0, 0.25, 0.22))

	_minimap_canvas.draw_circle(center, 4.0, Color(1.0, 1.0, 1.0))
	_minimap_canvas.draw_circle(center, 2.5, Color(0.2, 0.95, 0.45))


# --- Programmatic Styled HUD Construction ---

func _make_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	return sb


func _build_dedicated_server_overlay() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_style(Color(0.06, 0.08, 0.12, 0.95), Color(0.85, 0.7, 0.3, 0.9)))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 220)
	panel.position = Vector2(-310, -110)
	root_control.add_child(panel)
	_server_monitor_lbl = Label.new()
	_server_monitor_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_server_monitor_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_server_monitor_lbl.text = "Iniciando Servidor Dedicado..."
	panel.add_child(_server_monitor_lbl)


func _build_hud_layout() -> void:
	var dark_panel: StyleBoxFlat = _make_style(Color(0.06, 0.08, 0.13, 0.86), Color(0.75, 0.6, 0.28, 0.75))
	var modal_panel: StyleBoxFlat = _make_style(Color(0.07, 0.09, 0.15, 0.96), Color(0.9, 0.74, 0.32, 0.9))
	_slot_style_normal = dark_panel
	_slot_style_selected = _make_style(Color(0.14, 0.12, 0.06, 0.92), Color(1.0, 0.86, 0.3, 1.0))

	# 0. Top-Left SafeZone / PvP Pill + Party HUD
	var tl_vbox: VBoxContainer = VBoxContainer.new()
	tl_vbox.position = Vector2(14.0, 10.0)
	tl_vbox.custom_minimum_size = Vector2(300.0, 0.0)
	root_control.add_child(tl_vbox)

	_zone_pill = PanelContainer.new()
	_zone_pill.add_theme_stylebox_override("panel", _make_style(Color(0.06, 0.22, 0.12, 0.9), Color(0.32, 0.95, 0.52, 0.95)))
	tl_vbox.add_child(_zone_pill)
	_zone_pill_lbl = Label.new()
	_zone_pill_lbl.text = "🛡️ ZONA SEGURA: Santuario del Alba"
	_zone_pill_lbl.add_theme_font_size_override("font_size", 12)
	_zone_pill.add_child(_zone_pill_lbl)

	var party_pill: PanelContainer = PanelContainer.new()
	party_pill.add_theme_stylebox_override("panel", dark_panel)
	tl_vbox.add_child(party_pill)
	_party_hud_lbl = Label.new()
	_party_hud_lbl.text = "Grupo (Tab): Solo (4 jug. para Mazmorras)"
	_party_hud_lbl.add_theme_font_size_override("font_size", 11)
	party_pill.add_child(_party_hud_lbl)

	# 0b. Top-Right Corner Minimap
	var mm_panel: PanelContainer = PanelContainer.new()
	mm_panel.add_theme_stylebox_override("panel", dark_panel)
	mm_panel.anchor_left = 1.0
	mm_panel.anchor_right = 1.0
	mm_panel.anchor_top = 0.0
	mm_panel.offset_left = -168.0
	mm_panel.offset_right = -14.0
	mm_panel.offset_top = 10.0
	mm_panel.offset_bottom = 176.0
	root_control.add_child(mm_panel)
	var mm_vb: VBoxContainer = VBoxContainer.new()
	mm_panel.add_child(mm_vb)
	var mm_title: Label = Label.new()
	mm_title.text = "Minimapa [M: Mundo]"
	mm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mm_title.add_theme_font_size_override("font_size", 11)
	mm_vb.add_child(mm_title)
	_minimap_canvas = Control.new()
	_minimap_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_minimap_canvas.draw.connect(_draw_minimap)
	mm_vb.add_child(_minimap_canvas)

	# 1. Top-Center Global Gracia Combativa + Season Bar
	var top_bar: PanelContainer = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", dark_panel)
	top_bar.anchor_left = 0.25
	top_bar.anchor_right = 0.75
	top_bar.anchor_top = 0.0
	top_bar.offset_top = 10.0
	top_bar.offset_bottom = 48.0
	root_control.add_child(top_bar)
	_grace_label = Label.new()
	_grace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grace_label.text = "Gracia Combativa: sincronizando..."
	top_bar.add_child(_grace_label)

	# 1b. Live World Boss / Supreme Dragon Boss Health Bar
	_boss_bar_box = PanelContainer.new()
	_boss_bar_box.add_theme_stylebox_override("panel", _make_style(Color(0.14, 0.05, 0.05, 0.9), Color(0.95, 0.3, 0.22, 0.95)))
	_boss_bar_box.anchor_left = 0.24
	_boss_bar_box.anchor_right = 0.76
	_boss_bar_box.anchor_top = 0.0
	_boss_bar_box.offset_top = 56.0
	_boss_bar_box.offset_bottom = 114.0
	_boss_bar_box.visible = false
	root_control.add_child(_boss_bar_box)
	var boss_vb: VBoxContainer = VBoxContainer.new()
	boss_vb.add_theme_constant_override("separation", 3)
	_boss_bar_box.add_child(boss_vb)
	_boss_name_lbl = Label.new()
	_boss_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.42))
	boss_vb.add_child(_boss_name_lbl)
	_boss_hp_bar = _create_bar(boss_vb, Color(0.86, 0.16, 0.14))
	_boss_hp_lbl = _attach_bar_label(_boss_hp_bar)

	# 2. Dramatic Global Event Banner
	_banner_box = PanelContainer.new()
	_banner_box.add_theme_stylebox_override("panel", _make_style(Color(0.14, 0.09, 0.04, 0.92), Color(1.0, 0.85, 0.32, 0.95)))
	_banner_box.anchor_left = 0.22
	_banner_box.anchor_right = 0.78
	_banner_box.anchor_top = 0.0
	_banner_box.offset_top = 120.0
	_banner_box.offset_bottom = 196.0
	_banner_box.visible = false
	root_control.add_child(_banner_box)
	var bvb: VBoxContainer = VBoxContainer.new()
	_banner_box.add_child(bvb)
	_banner_title = Label.new()
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_font_size_override("font_size", 20)
	bvb.add_child(_banner_title)
	_banner_body = Label.new()
	_banner_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_body.autowrap_mode = TextServer.AUTOWRAP_WORD
	bvb.add_child(_banner_body)

	# 3. Elder Scrolls Center Reticle
	_crosshair_root = Control.new()
	_crosshair_root.anchor_left = 0.5
	_crosshair_root.anchor_top = 0.5
	_crosshair_root.anchor_right = 0.5
	_crosshair_root.anchor_bottom = 0.5
	_crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(_crosshair_root)
	var reticle_col: Color = Color(1.0, 0.94, 0.76, 0.85)
	for rect_def: Array in [
		[Vector2(-1.5, -1.5), Vector2(3, 3)],
		[Vector2(-12, -1), Vector2(6, 2)],
		[Vector2(6, -1), Vector2(6, 2)],
		[Vector2(-1, -12), Vector2(2, 6)],
		[Vector2(-1, 6), Vector2(2, 6)]
	]:
		var tick: ColorRect = ColorRect.new()
		tick.color = reticle_col
		tick.position = rect_def[0] as Vector2
		tick.size = rect_def[1] as Vector2
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair_root.add_child(tick)

	# 4. Bottom-Left Vitals Card (HP, Mana, Stamina, Hunger)
	var vitals: PanelContainer = PanelContainer.new()
	vitals.add_theme_stylebox_override("panel", dark_panel)
	vitals.anchor_left = 0.0
	vitals.anchor_top = 1.0
	vitals.anchor_bottom = 1.0
	vitals.offset_left = 14.0
	vitals.offset_right = 368.0
	vitals.offset_top = -224.0
	vitals.offset_bottom = -14.0
	root_control.add_child(vitals)
	var vv: VBoxContainer = VBoxContainer.new()
	vv.add_theme_constant_override("separation", 3)
	vitals.add_child(vv)
	_player_title = Label.new()
	_player_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	vv.add_child(_player_title)
	_grace_badge = Label.new()
	_grace_badge.text = "★ POSEÉS LA GRACIA COMBATIVA (ESTADÍSTICAS x2.0) ★"
	_grace_badge.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_grace_badge.add_theme_font_size_override("font_size", 11)
	_grace_badge.visible = false
	vv.add_child(_grace_badge)

	_hp_bar = _create_bar(vv, Color(0.78, 0.16, 0.16))
	_hp_text = _attach_bar_label(_hp_bar)
	_mana_bar = _create_bar(vv, Color(0.16, 0.44, 0.86))
	_mana_text = _attach_bar_label(_mana_bar)
	_stamina_bar = _create_bar(vv, Color(0.2, 0.68, 0.34))
	_stamina_text = _attach_bar_label(_stamina_bar)
	_hunger_bar = _create_bar(vv, Color(0.84, 0.54, 0.16))
	_hunger_text = _attach_bar_label(_hunger_bar)

	_currency_lbl = Label.new()
	_currency_lbl.add_theme_font_size_override("font_size", 12)
	vv.add_child(_currency_lbl)
	_coords_lbl = Label.new()
	_coords_lbl.add_theme_font_size_override("font_size", 11)
	_coords_lbl.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92))
	vv.add_child(_coords_lbl)

	# 5. Bottom-Center Ability Hotbar + Dragon Flight Banner
	var bottom_center: VBoxContainer = VBoxContainer.new()
	bottom_center.anchor_left = 0.28
	bottom_center.anchor_right = 0.72
	bottom_center.anchor_top = 1.0
	bottom_center.anchor_bottom = 1.0
	bottom_center.offset_top = -126.0
	bottom_center.offset_bottom = -12.0
	bottom_center.alignment = BoxContainer.ALIGNMENT_END
	root_control.add_child(bottom_center)

	_dragon_status_lbl = Label.new()
	_dragon_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dragon_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.3))
	_dragon_status_lbl.visible = false
	bottom_center.add_child(_dragon_status_lbl)

	var ab_row: HBoxContainer = HBoxContainer.new()
	ab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ab_row.add_theme_constant_override("separation", 8)
	bottom_center.add_child(ab_row)
	_ability_panels.clear()
	_ability_labels.clear()
	for i: int in range(4):
		var slot: PanelContainer = PanelContainer.new()
		slot.add_theme_stylebox_override("panel", _slot_style_selected if i == 0 else _slot_style_normal)
		slot.custom_minimum_size = Vector2(126, 54)
		ab_row.add_child(slot)
		var lbl: Label = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.text = "[%d]" % (i + 1)
		slot.add_child(lbl)
		_ability_panels.append(slot)
		_ability_labels.append(lbl)

	var controls_lbl: Label = Label.new()
	controls_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_lbl.add_theme_font_size_override("font_size", 11)
	controls_lbl.add_theme_color_override("font_color", Color(0.76, 0.82, 0.9))
	controls_lbl.text = "LMB/RT: Atacar | RMB/LT: Bloq | Q/B: Esquivar | G/X: Dragón | E/Y: Interactuar | M: Mapa | B: Casas | I: Mochila | Tab: Grupo/Reinos | T: Tienda | F1: Avatar"
	bottom_center.add_child(controls_lbl)

	# 6. Build Mode Selection Bar
	_build_bar = PanelContainer.new()
	_build_bar.add_theme_stylebox_override("panel", dark_panel)
	_build_bar.anchor_left = 0.1
	_build_bar.anchor_right = 0.9
	_build_bar.anchor_top = 1.0
	_build_bar.anchor_bottom = 1.0
	_build_bar.offset_top = -226.0
	_build_bar.offset_bottom = -134.0
	_build_bar.visible = false
	root_control.add_child(_build_bar)
	var bbv: VBoxContainer = VBoxContainer.new()
	_build_bar.add_child(bbv)
	_build_info_lbl = Label.new()
	_build_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_info_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.72))
	bbv.add_child(_build_info_lbl)
	var piece_scroll: ScrollContainer = ScrollContainer.new()
	piece_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bbv.add_child(piece_scroll)
	var piece_row: HBoxContainer = HBoxContainer.new()
	piece_row.alignment = BoxContainer.ALIGNMENT_CENTER
	piece_row.add_theme_constant_override("separation", 5)
	piece_scroll.add_child(piece_row)
	var piece_idx: int = 1
	for pkey_var: Variant in GameConfig.BUILD_PIECES.keys():
		var pkey: String = str(pkey_var)
		var spec: Dictionary = GameConfig.BUILD_PIECES[pkey] as Dictionary
		var btn: Button = Button.new()
		btn.text = "[%d] %s" % [piece_idx, str(spec["name"])]
		piece_idx += 1
		btn.pressed.connect(func() -> void:
			if local_player != null and local_player.building_system != null:
				local_player.building_system.select_piece(pkey)
		)
		piece_row.add_child(btn)

	# 7. Bottom-Right Chat Box
	var chat_panel: PanelContainer = PanelContainer.new()
	chat_panel.add_theme_stylebox_override("panel", dark_panel)
	chat_panel.anchor_left = 1.0
	chat_panel.anchor_right = 1.0
	chat_panel.anchor_top = 1.0
	chat_panel.anchor_bottom = 1.0
	chat_panel.offset_left = -356.0
	chat_panel.offset_right = -14.0
	chat_panel.offset_top = -210.0
	chat_panel.offset_bottom = -14.0
	root_control.add_child(chat_panel)
	var cv: VBoxContainer = VBoxContainer.new()
	chat_panel.add_child(cv)
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_font_size_override("normal_font_size", 12)
	cv.add_child(_chat_log)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Enter para escribir en el chat..."
	_chat_input.text_submitted.connect(_on_chat_submitted)
	cv.add_child(_chat_input)

	# 8. Modal Windows
	_build_inventory_market_modal(modal_panel)
	_build_storage_chest_modal(modal_panel)
	_build_world_map_modal()
	_build_cosmetic_shop_modal(modal_panel)
	_build_guilds_bounties_modal(modal_panel)
	_build_avatar_console_modal(modal_panel)
	_build_pause_modal(modal_panel)


func _create_bar(parent: Control, fill_color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 20)
	bar.show_percentage = false
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	bg.set_corner_radius_all(4)
	var fg: StyleBoxFlat = StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	parent.add_child(bar)
	return bar


func _attach_bar_label(bar: ProgressBar) -> Label:
	var lbl: Label = Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	bar.add_child(lbl)
	return lbl


func _make_centered_modal(style: StyleBoxFlat, title_text: String, width: float, height: float) -> Dictionary:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	panel.visible = false
	root_control.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var header: HBoxContainer = HBoxContainer.new()
	vbox.add_child(header)
	var title: Label = Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.38))
	header.add_child(title)
	var close_btn: Button = Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_close_all_panels)
	header.add_child(close_btn)

	return {"panel": panel, "vbox": vbox, "title": title}


func _build_world_map_modal() -> void:
	_world_map_ui = WorldMapUI.new()
	_world_map_ui.anchor_left = 0.5
	_world_map_ui.anchor_right = 0.5
	_world_map_ui.anchor_top = 0.5
	_world_map_ui.anchor_bottom = 0.5
	_world_map_ui.offset_left = -480.0
	_world_map_ui.offset_right = 480.0
	_world_map_ui.offset_top = -310.0
	_world_map_ui.offset_bottom = 310.0
	_world_map_ui.map_closed.connect(_close_all_panels)
	_world_map_ui.wayshrine_teleport_requested.connect(func(wid: String) -> void:
		if _world_auth != null:
			_world_auth.request_wayshrine_teleport(wid)
		_close_all_panels()
	)
	root_control.add_child(_world_map_ui)


func _build_storage_chest_modal(style: StyleBoxFlat) -> void:
	var m: Dictionary = _make_centered_modal(style, "Cajón de Guardado Privado (60 espacios)", 720.0, 460.0)
	_chest_panel = m["panel"] as PanelContainer
	_chest_title_lbl = m["title"] as Label
	var vbox: VBoxContainer = m["vbox"] as VBoxContainer
	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	vbox.add_child(cols)

	var c1: VBoxContainer = VBoxContainer.new()
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c1)
	var l1: Label = Label.new()
	l1.text = "Tu Mochila (Guardar en Cajón →)"
	c1.add_child(l1)
	var s1: ScrollContainer = ScrollContainer.new()
	s1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c1.add_child(s1)
	_chest_bag_box = VBoxContainer.new()
	_chest_bag_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s1.add_child(_chest_bag_box)

	var c2: VBoxContainer = VBoxContainer.new()
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c2)
	var l2: Label = Label.new()
	l2.text = "Contenido del Cajón (← Retirar)"
	c2.add_child(l2)
	var s2: ScrollContainer = ScrollContainer.new()
	s2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c2.add_child(s2)
	_chest_box = VBoxContainer.new()
	_chest_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s2.add_child(_chest_box)


func _build_inventory_market_modal(style: StyleBoxFlat) -> void:
	var m: Dictionary = _make_centered_modal(style, "Mochila (150), Forja/Cocina y Economía 100% Jugadores (I)", 900.0, 540.0)
	_inv_panel = m["panel"] as PanelContainer
	var vbox: VBoxContainer = m["vbox"] as VBoxContainer
	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	vbox.add_child(cols)

	# Column 1: 150-Slot Backpack
	var c1: VBoxContainer = VBoxContainer.new()
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c1)
	_inv_slots_lbl = Label.new()
	_inv_slots_lbl.text = "Mochila (0 / 150 espacios)"
	c1.add_child(_inv_slots_lbl)
	var s1: ScrollContainer = ScrollContainer.new()
	s1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c1.add_child(s1)
	_inv_list_box = VBoxContainer.new()
	_inv_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s1.add_child(_inv_list_box)

	# Column 2: Crafting (Forge / Alchemy / Campfire Cooking)
	var c2: VBoxContainer = VBoxContainer.new()
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c2)
	var l2: Label = Label.new()
	l2.text = "Forja Elemental, Alquimia y Cocina"
	c2.add_child(l2)
	var s2: ScrollContainer = ScrollContainer.new()
	s2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c2.add_child(s2)
	_craft_list_box = VBoxContainer.new()
	_craft_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s2.add_child(_craft_list_box)

	# Column 3: 100% Player Market + Direct P2P Trade
	var c3: VBoxContainer = VBoxContainer.new()
	c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c3)
	var l3: Label = Label.new()
	l3.text = "Economía 100% de Jugadores (Sin NPCs)"
	c3.add_child(l3)
	_market_item_opt = OptionButton.new()
	for ikey_var: Variant in GameConfig.ITEMS.keys():
		var ikey: String = str(ikey_var)
		_market_item_opt.add_item(str((GameConfig.ITEMS[ikey] as Dictionary)["name"]))
		_market_item_opt.set_item_metadata(_market_item_opt.item_count - 1, ikey)
	c3.add_child(_market_item_opt)
	var sell_row: HBoxContainer = HBoxContainer.new()
	c3.add_child(sell_row)
	_market_qty_spin = SpinBox.new()
	_market_qty_spin.min_value = 1
	_market_qty_spin.max_value = 99
	_market_qty_spin.value = 1
	_market_qty_spin.prefix = "Cant:"
	sell_row.add_child(_market_qty_spin)
	_market_price_spin = SpinBox.new()
	_market_price_spin.min_value = 1
	_market_price_spin.max_value = 99999
	_market_price_spin.value = 25
	_market_price_spin.prefix = "Oro:"
	sell_row.add_child(_market_price_spin)
	var list_btn: Button = Button.new()
	list_btn.text = "Publicar Oferta de Jugador"
	list_btn.pressed.connect(func() -> void:
		var idx: int = _market_item_opt.selected
		if idx >= 0:
			var iid: String = str(_market_item_opt.get_item_metadata(idx))
			NetworkManager.request_market_list(iid, int(_market_qty_spin.value), int(_market_price_spin.value))
	)
	c3.add_child(list_btn)

	# Direct P2P Trade bar
	var trade_row: HBoxContainer = HBoxContainer.new()
	c3.add_child(trade_row)
	_trade_target_in = LineEdit.new()
	_trade_target_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trade_target_in.placeholder_text = "Jugador para Trueque P2P"
	trade_row.add_child(_trade_target_in)
	var tr_btn: Button = Button.new()
	tr_btn.text = "Trueque"
	tr_btn.pressed.connect(func() -> void: NetworkManager.request_trade_start(_trade_target_in.text))
	trade_row.add_child(tr_btn)
	var tr_ok: Button = Button.new()
	tr_ok.text = "Confirmar"
	tr_ok.pressed.connect(func() -> void:
		var idx: int = _market_item_opt.selected
		var iid: String = str(_market_item_opt.get_item_metadata(idx)) if idx >= 0 else ""
		NetworkManager.request_trade_offer(int(_market_price_spin.value), iid, int(_market_qty_spin.value))
		NetworkManager.request_trade_confirm()
	)
	trade_row.add_child(tr_ok)
	_trade_status_lbl = Label.new()
	_trade_status_lbl.text = "Trueque Directo: Sin sesión activa."
	_trade_status_lbl.add_theme_font_size_override("font_size", 11)
	c3.add_child(_trade_status_lbl)

	var s3: ScrollContainer = ScrollContainer.new()
	s3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c3.add_child(s3)
	_market_list_box = VBoxContainer.new()
	_market_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s3.add_child(_market_list_box)


func _build_cosmetic_shop_modal(style: StyleBoxFlat) -> void:
	var m: Dictionary = _make_centered_modal(style, "Tienda Cosmética — 0% Pay-to-Win (T)", 680.0, 480.0)
	_shop_panel = m["panel"] as PanelContainer
	var vbox: VBoxContainer = m["vbox"] as VBoxContainer
	var top: HBoxContainer = HBoxContainer.new()
	vbox.add_child(top)
	_shop_crowns_lbl = Label.new()
	_shop_crowns_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_shop_crowns_lbl)
	var claim_btn: Button = Button.new()
	claim_btn.text = "+500 Coronas (Paquete Prueba)"
	claim_btn.pressed.connect(func() -> void: NetworkManager.request_cosmetic_action("", "", "claim_crowns"))
	top.add_child(claim_btn)

	var note: Label = Label.new()
	note.text = "100% visual (0% estadísticas). Gratis para Avatares ♾️. Nunca se pierden al morir ni al reiniciar temporada."
	note.add_theme_color_override("font_color", Color(0.72, 0.92, 0.78))
	vbox.add_child(note)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_shop_list_box = VBoxContainer.new()
	_shop_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shop_list_box)


func _build_guilds_bounties_modal(style: StyleBoxFlat) -> void:
	var m: Dictionary = _make_centered_modal(style, "Grupo (4 Jug.), Reinos, Alineación y Contratos (Tab)", 820.0, 540.0)
	_guilds_panel = m["panel"] as PanelContainer
	var vbox: VBoxContainer = m["vbox"] as VBoxContainer

	# 4-Player Party bar
	var party_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(party_row)
	_party_invite_in = LineEdit.new()
	_party_invite_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_invite_in.placeholder_text = "Invitar jugador a Grupo (4 jugadores para Mazmorras)"
	party_row.add_child(_party_invite_in)
	var p_inv_btn: Button = Button.new()
	p_inv_btn.text = "Invitar al Grupo"
	p_inv_btn.pressed.connect(func() -> void:
		NetworkManager.request_party_invite(_party_invite_in.text)
		_party_invite_in.clear()
	)
	party_row.add_child(p_inv_btn)
	var p_acc_btn: Button = Button.new()
	p_acc_btn.text = "Aceptar Invitación"
	p_acc_btn.pressed.connect(func() -> void: NetworkManager.request_party_accept())
	party_row.add_child(p_acc_btn)
	var p_leave_btn: Button = Button.new()
	p_leave_btn.text = "Salir del Grupo"
	p_leave_btn.pressed.connect(func() -> void: NetworkManager.request_party_leave())
	party_row.add_child(p_leave_btn)

	_party_list_lbl = Label.new()
	_party_list_lbl.text = "Grupo: Solo"
	_party_list_lbl.add_theme_color_override("font_color", Color(0.68, 0.92, 1.0))
	vbox.add_child(_party_list_lbl)

	var phil_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(phil_row)
	var plbl: Label = Label.new()
	plbl.text = "Alineación / Estandarte: "
	phil_row.add_child(plbl)
	for phil: String in [GameConfig.PHILOSOPHY_NEUTRAL, GameConfig.PHILOSOPHY_ORDER, GameConfig.PHILOSOPHY_CHAOS]:
		var pb: Button = Button.new()
		pb.text = phil
		pb.pressed.connect(func() -> void: NetworkManager.request_set_philosophy(phil))
		phil_row.add_child(pb)

	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	vbox.add_child(cols)

	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var gl: Label = Label.new()
	gl.text = "Fundar o Unirse a un Reino / Gremio"
	left.add_child(gl)
	_guild_name_in = LineEdit.new()
	_guild_name_in.placeholder_text = "Nombre del Reino / Horda"
	left.add_child(_guild_name_in)
	_guild_phil_opt = OptionButton.new()
	_guild_phil_opt.add_item(GameConfig.PHILOSOPHY_ORDER)
	_guild_phil_opt.add_item(GameConfig.PHILOSOPHY_CHAOS)
	_guild_phil_opt.add_item(GameConfig.PHILOSOPHY_NEUTRAL)
	left.add_child(_guild_phil_opt)
	_guild_manif_in = LineEdit.new()
	_guild_manif_in.placeholder_text = "Leyes / Manifiesto del Reino..."
	left.add_child(_guild_manif_in)
	var create_g_btn: Button = Button.new()
	create_g_btn.text = "Fundar Reino / Gremio"
	create_g_btn.pressed.connect(func() -> void:
		var chosen_p: String = _guild_phil_opt.get_item_text(_guild_phil_opt.selected)
		NetworkManager.request_guild_create(_guild_name_in.text, chosen_p, _guild_manif_in.text)
		_guild_name_in.clear()
		_guild_manif_in.clear()
	)
	left.add_child(create_g_btn)
	var gs: ScrollContainer = ScrollContainer.new()
	gs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(gs)
	_guild_list_box = VBoxContainer.new()
	_guild_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gs.add_child(_guild_list_box)

	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var bl: Label = Label.new()
	bl.text = "Contratos / Recompensas (Justicia de Jugadores)"
	right.add_child(bl)
	_bounty_target_in = LineEdit.new()
	_bounty_target_in.placeholder_text = "Nombre del objetivo"
	right.add_child(_bounty_target_in)
	_bounty_gold_spin = SpinBox.new()
	_bounty_gold_spin.min_value = 10
	_bounty_gold_spin.max_value = 50000
	_bounty_gold_spin.value = 50
	_bounty_gold_spin.prefix = "Recompensa Oro: "
	right.add_child(_bounty_gold_spin)
	_bounty_reason_in = LineEdit.new()
	_bounty_reason_in.placeholder_text = "Motivo..."
	right.add_child(_bounty_reason_in)
	var post_b_btn: Button = Button.new()
	post_b_btn.text = "Publicar Contrato"
	post_b_btn.pressed.connect(func() -> void:
		NetworkManager.request_post_bounty(_bounty_target_in.text, int(_bounty_gold_spin.value), _bounty_reason_in.text)
		_bounty_target_in.clear()
		_bounty_reason_in.clear()
	)
	right.add_child(post_b_btn)
	var bs: ScrollContainer = ScrollContainer.new()
	bs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(bs)
	_bounty_list_box = VBoxContainer.new()
	_bounty_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bs.add_child(_bounty_list_box)


func _build_avatar_console_modal(style: StyleBoxFlat) -> void:
	var m: Dictionary = _make_centered_modal(style, "Consola de Avatar Primordial ♾️ — Orden / Caos (F1)", 680.0, 540.0)
	_avatar_panel = m["panel"] as PanelContainer
	var vbox: VBoxContainer = m["vbox"] as VBoxContainer

	var role: String = str(NetworkManager.local_profile.get("role", GameConfig.ROLE_PLAYER))
	if not GameConfig.is_avatar_role(role):
		var denied: Label = Label.new()
		denied.text = "Acceso exclusivo para los Avatares de los Creadores (AVATAR_ORDEN y AVATAR_CAOS).\n\nIniciá sesión con:\n• AvatarOrden / orden_creador\n• AvatarCaos / caos_creador"
		denied.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(denied)
		return

	_avatar_roster_lbl = Label.new()
	_avatar_roster_lbl.text = "Conectados: ..."
	_avatar_roster_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_avatar_roster_lbl)

	# Disguised Level-1 Novice & Divine Form buttons
	var form_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(form_row)
	var novice_btn: Button = Button.new()
	novice_btn.text = "🎭 Encarnar como Novato (Nivel 1) / Revelar ♾️"
	novice_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	novice_btn.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_toggle_disguised_novice()
	)
	form_row.add_child(novice_btn)

	var divine_btn: Button = Button.new()
	divine_btn.text = "👑 Forma Divina (Inmortal)"
	divine_btn.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_toggle_divine_form()
	)
	form_row.add_child(divine_btn)

	# Faction-Wide Grace + Daily Random Grace
	var grace_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(grace_row)
	var grace_btn: Button = Button.new()
	grace_btn.text = "★ Gracia Diaria al Azar (x2, 24h)"
	grace_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grace_btn.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_trigger_grace("")
	)
	grace_row.add_child(grace_btn)

	var fgrace_btn: Button = Button.new()
	fgrace_btn.text = "⚡ Gracia Combativa a Toda mi Facción"
	fgrace_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fgrace_btn.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_grant_faction_grace()
	)
	grace_row.add_child(fgrace_btn)

	_avatar_target_in = LineEdit.new()
	_avatar_target_in.placeholder_text = "Nombre de jugador objetivo (opcional)"
	vbox.add_child(_avatar_target_in)

	var target_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(target_row)
	var b_grace_t: Button = Button.new()
	b_grace_t.text = "Dar Gracia al Objetivo"
	b_grace_t.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_trigger_grace(_avatar_target_in.text)
	)
	target_row.add_child(b_grace_t)
	var b_favor: Button = Button.new()
	b_favor.text = "Favor Divino (+35% + Oro)"
	b_favor.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_grant_favor(_avatar_target_in.text)
	)
	target_row.add_child(b_favor)
	var b_tp_p: Button = Button.new()
	b_tp_p.text = "TP al Jugador"
	b_tp_p.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_teleport(_avatar_target_in.text, Vector3.ZERO)
	)
	target_row.add_child(b_tp_p)

	var tp_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(tp_row)
	_avatar_x_spin = SpinBox.new()
	_avatar_x_spin.min_value = -100000
	_avatar_x_spin.max_value = 100000
	_avatar_x_spin.prefix = "X:"
	tp_row.add_child(_avatar_x_spin)
	_avatar_z_spin = SpinBox.new()
	_avatar_z_spin.min_value = -100000
	_avatar_z_spin.max_value = 100000
	_avatar_z_spin.prefix = "Z:"
	tp_row.add_child(_avatar_z_spin)
	var b_tp_c: Button = Button.new()
	b_tp_c.text = "TP a Coordenadas"
	b_tp_c.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_teleport("", Vector3(_avatar_x_spin.value, 25.0, _avatar_z_spin.value))
	)
	tp_row.add_child(b_tp_c)

	var ann_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(ann_row)
	_avatar_announce_in = LineEdit.new()
	_avatar_announce_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_avatar_announce_in.placeholder_text = "Mensaje divino para todo el servidor..."
	ann_row.add_child(_avatar_announce_in)
	var b_ann: Button = Button.new()
	b_ann.text = "Anunciar"
	b_ann.pressed.connect(func() -> void:
		if _world_auth != null and not _avatar_announce_in.text.strip_edges().is_empty():
			_world_auth.request_avatar_world_command("announce", _avatar_announce_in.text)
			_avatar_announce_in.clear()
	)
	ann_row.add_child(b_ann)

	var world_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(world_row)
	for pair: Array in [
		["Día", "set_day"],
		["Noche", "set_night"],
		["Reparar", "repair_nearest"],
		["Reaparecer Jefes", "respawn_bosses"],
		["🔄 Reiniciar Temporada", "season_reset"],
		["Expulsar", "kick"]
	]:
		var btn: Button = Button.new()
		btn.text = str(pair[0])
		var cmd_id: String = str(pair[1])
		btn.pressed.connect(func() -> void:
			if _world_auth != null:
				_world_auth.request_avatar_world_command(cmd_id, _avatar_target_in.text if cmd_id == "kick" else "")
		)
		world_row.add_child(btn)


func _build_pause_modal(style: StyleBoxFlat) -> void:
	var m: Dictionary = _make_centered_modal(style, "Menú de Pausa", 360.0, 260.0)
	_pause_panel = m["panel"] as PanelContainer
	var vbox: VBoxContainer = m["vbox"] as VBoxContainer
	var resume: Button = Button.new()
	resume.text = "Continuar Jugando"
	resume.pressed.connect(_close_all_panels)
	vbox.add_child(resume)

	var map_btn: Button = Button.new()
	map_btn.text = "🗺️ Abrir Mapa del Mundo (M)"
	map_btn.pressed.connect(open_world_map)
	vbox.add_child(map_btn)

	var lore_btn: Button = Button.new()
	lore_btn.text = "Leer Mitología en el Chat"
	lore_btn.pressed.connect(func() -> void:
		_on_chat_received("Crónicas", "Mitología", GameConfig.OFFICIAL_LORE_CHAPTERS[0], "#ffe066")
		_close_all_panels()
	)
	vbox.add_child(lore_btn)

	var leave: Button = Button.new()
	leave.text = "Desconectar y Volver al Menú Principal"
	leave.pressed.connect(func() -> void:
		NetworkManager.disconnect_session()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://Client/UI/MainMenu.tscn")
	)
	vbox.add_child(leave)


func _on_chat_submitted(text: String) -> void:
	NetworkManager.send_chat(text)
	_chat_input.clear()
	_chat_input.release_focus()
	if _active_panel == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_all_panels() -> void:
	_refresh_inventory_panel()
	_refresh_shop_panel()
	_refresh_guilds_panel()


func _clear_box(box: VBoxContainer) -> void:
	if box == null:
		return
	for c: Node in box.get_children():
		c.queue_free()


func _refresh_chest_panel() -> void:
	if _chest_bag_box == null or _chest_box == null:
		return
	_clear_box(_chest_bag_box)
	var inv: Dictionary = NetworkManager.local_profile.get("inventory", {}) as Dictionary
	for item_var: Variant in inv.keys():
		var iid: String = str(item_var)
		var qty: int = int(inv[iid])
		if qty <= 0 or not GameConfig.ITEMS.has(iid):
			continue
		var iname: String = str((GameConfig.ITEMS[iid] as Dictionary).get("name", iid))
		var btn: Button = Button.new()
		btn.text = "%s x%d  → Guardar" % [iname, qty]
		btn.pressed.connect(func() -> void: NetworkManager.request_chest_transfer(_open_chest_id, iid, 1, true))
		_chest_bag_box.add_child(btn)

	_clear_box(_chest_box)
	for item_var: Variant in _open_chest_items.keys():
		var iid: String = str(item_var)
		var qty: int = int(_open_chest_items[iid])
		if qty <= 0 or not GameConfig.ITEMS.has(iid):
			continue
		var iname: String = str((GameConfig.ITEMS[iid] as Dictionary).get("name", iid))
		var btn: Button = Button.new()
		btn.text = "← Retirar  %s x%d" % [iname, qty]
		btn.pressed.connect(func() -> void: NetworkManager.request_chest_transfer(_open_chest_id, iid, 1, false))
		_chest_box.add_child(btn)


func _refresh_inventory_panel() -> void:
	if _inv_list_box == null:
		return
	_clear_box(_inv_list_box)
	var is_admin: bool = GameConfig.is_avatar_role(str(NetworkManager.local_profile.get("role", "")))
	var used_slots: int = _count_local_backpack_slots()
	if _inv_slots_lbl != null:
		_inv_slots_lbl.text = "Mochila (%s espacios — Saqueable en PvP)" % ("♾️" if is_admin else "%d / %d" % [used_slots, GameConfig.BACKPACK_MAX_SLOTS])

	var inv: Dictionary = NetworkManager.local_profile.get("inventory", {}) as Dictionary
	var eq_slots: Array[String] = [
		str(NetworkManager.local_profile.get("equipped_weapon", "")),
		str(NetworkManager.local_profile.get("equipped_helmet", "")),
		str(NetworkManager.local_profile.get("equipped_chest", "")),
		str(NetworkManager.local_profile.get("equipped_legs", "")),
		str(NetworkManager.local_profile.get("equipped_boots", ""))
	]
	for item_var: Variant in inv.keys():
		var iid: String = str(item_var)
		var qty: int = int(inv[iid])
		if qty <= 0 or not GameConfig.ITEMS.has(iid):
			continue
		var idef: Dictionary = GameConfig.ITEMS[iid] as Dictionary
		var row: HBoxContainer = HBoxContainer.new()
		_inv_list_box.add_child(row)
		var lbl: Label = Label.new()
		var eq_tag: String = " [EQ]" if eq_slots.has(iid) else ""
		lbl.text = "%s x%d%s" % [str(idef["name"]), qty, eq_tag]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var itype: String = str(idef.get("type", ""))
		if itype == "weapon" or itype == "armor" or itype == "consumable" or itype == "food":
			var btn: Button = Button.new()
			btn.text = "Comer" if itype == "food" else ("Usar" if itype == "consumable" else "Equipar")
			btn.pressed.connect(func() -> void: NetworkManager.request_equip_or_use_item(iid))
			row.add_child(btn)

	_clear_box(_craft_list_box)
	for rkey_var: Variant in GameConfig.CRAFT_RECIPES.keys():
		var rkey: String = str(rkey_var)
		var rec: Dictionary = GameConfig.CRAFT_RECIPES[rkey] as Dictionary
		var st_tag: String = str(rec.get("station", "forge"))
		if not _station_filter.is_empty() and _station_filter != "shop_stall" and st_tag != _station_filter:
			continue
		var idef: Dictionary = GameConfig.ITEMS[rkey] as Dictionary
		var cost_parts: Array[String] = []
		var cost: Dictionary = rec["cost"] as Dictionary
		for ckey_var: Variant in cost.keys():
			cost_parts.append("%s:%d" % [str((GameConfig.ITEMS[str(ckey_var)] as Dictionary)["name"]), int(cost[ckey_var])])
		var prefix: String = "[Cocina] " if st_tag == "campfire" else ("[Alq] " if st_tag == "alchemy" else "[Forja] ")
		var btn: Button = Button.new()
		btn.text = "%s%s (%s)" % [prefix, str(idef["name"]), ", ".join(cost_parts)]
		btn.pressed.connect(func() -> void: NetworkManager.request_craft(rkey))
		_craft_list_box.add_child(btn)

	# 100% Player-Driven Market (Zero NPC vendors!)
	_clear_box(_market_list_box)
	var p_hdr: Label = Label.new()
	p_hdr.text = "— Ofertas Publicadas por Jugadores —"
	p_hdr.add_theme_color_override("font_color", Color(0.72, 0.9, 1.0))
	_market_list_box.add_child(p_hdr)
	if NetworkManager.cached_listings.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Sin ofertas activas. ¡Publicá tus materiales o equipo forjado arriba!"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_market_list_box.add_child(empty_lbl)
	for entry_var: Variant in NetworkManager.cached_listings:
		var entry: Dictionary = entry_var as Dictionary
		var lid: int = int(entry.get("id", -1))
		var iid: String = str(entry.get("item_id", ""))
		var iname: String = str((GameConfig.ITEMS.get(iid, {}) as Dictionary).get("name", iid))
		var btn: Button = Button.new()
		btn.text = "Comprar %s x%d (%d oro) — %s" % [iname, int(entry.get("qty", 1)), int(entry.get("price_gold", 0)), str(entry.get("seller", ""))]
		btn.pressed.connect(func() -> void: NetworkManager.request_market_buy(lid))
		_market_list_box.add_child(btn)


func _refresh_shop_panel() -> void:
	if _shop_list_box == null:
		return
	var is_admin: bool = GameConfig.is_avatar_role(str(NetworkManager.local_profile.get("role", "")))
	var crowns: int = int(NetworkManager.local_profile.get("crowns", 0))
	_shop_crowns_lbl.text = "Tus Coronas: ♾️ (Todo Gratis para Avatar)" if is_admin else "Tus Coronas Cosméticas: %d" % crowns
	_clear_box(_shop_list_box)
	var cos: Dictionary = NetworkManager.local_profile.get("cosmetics", {}) as Dictionary

	_add_shop_category("ARMADURAS COSMÉTICAS", "armor", GameConfig.COSMETIC_ARMORS, cos.get("owned_armors", []) as Array, str(cos.get("equipped_armor", "")), is_admin)
	_add_shop_category("SKINS DE DRAGÓN", "dragon", GameConfig.COSMETIC_DRAGONS, cos.get("owned_dragons", []) as Array, str(cos.get("equipped_dragon", "")), is_admin)
	_add_shop_category("ESTELAS DE VUELO DE DRAGÓN", "trail", GameConfig.COSMETIC_TRAILS, cos.get("owned_trails", []) as Array, str(cos.get("equipped_trail", "")), is_admin)


func _add_shop_category(header_text: String, cat: String, catalog: Dictionary, owned: Array, equipped: String, is_admin: bool) -> void:
	var h: Label = Label.new()
	h.text = "— " + header_text + " —"
	h.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	_shop_list_box.add_child(h)
	for id_var: Variant in catalog.keys():
		var item_id: String = str(id_var)
		var spec: Dictionary = catalog[item_id] as Dictionary
		var row: HBoxContainer = HBoxContainer.new()
		_shop_list_box.add_child(row)
		var lbl: Label = Label.new()
		lbl.text = str(spec["name"])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn: Button = Button.new()
		if item_id == equipped:
			btn.text = "Equipado"
			btn.disabled = true
		elif owned.has(item_id) or is_admin:
			btn.text = "Equipar (Gratis ♾️)" if is_admin else "Equipar"
			btn.pressed.connect(func() -> void: NetworkManager.request_cosmetic_action(cat, item_id, "equip"))
		else:
			btn.text = "Comprar (%d Coronas)" % int(spec["price_crowns"])
			btn.pressed.connect(func() -> void: NetworkManager.request_cosmetic_action(cat, item_id, "buy"))
		row.add_child(btn)


func _refresh_guilds_panel() -> void:
	if _guild_list_box == null:
		return
	_clear_box(_guild_list_box)
	for gid_var: Variant in NetworkManager.cached_guilds.keys():
		var gid: String = str(gid_var)
		var g: Dictionary = NetworkManager.cached_guilds[gid] as Dictionary
		var row: HBoxContainer = HBoxContainer.new()
		_guild_list_box.add_child(row)
		var lbl: Label = Label.new()
		var members: Array = g.get("members", []) as Array
		lbl.text = "%s [%s] (%d miembros)\n\"%s\"" % [str(g.get("name", gid)), str(g.get("philosophy", "")), members.size(), str(g.get("manifesto", ""))]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(lbl)
		var jbtn: Button = Button.new()
		jbtn.text = "Unirse"
		jbtn.pressed.connect(func() -> void: NetworkManager.request_guild_join(gid))
		row.add_child(jbtn)

	_clear_box(_bounty_list_box)
	for b_var: Variant in NetworkManager.cached_bounties:
		var b: Dictionary = b_var as Dictionary
		var lbl: Label = Label.new()
		lbl.text = "Objetivo: %s — %d Oro\nPublicado por %s: %s" % [
			str(b.get("target_name", "")),
			int(b.get("reward_gold", 0)),
			str(b.get("issuer", "")),
			str(b.get("reason", ""))
		]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_bounty_list_box.add_child(lbl)
