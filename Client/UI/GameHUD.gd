class_name GameHUD
extends CanvasLayer

## Full MMORPG HUD: Vitals (HP/Shield/Mana/Stamina), 4 Class Abilities, Global Gracia Combativa
## live countdown, Dragon Flight status, Chat, Building Menu (B), Inventory/Crafting/Market (I),
## Zero-P2W Cosmetic Shop (T), Kingdoms/Guilds & Player Bounties (Tab), and Creator Avatar Console (F1).

var local_player: PlayerController = null
var _world_auth: WorldAuthority = null
var _grace_sched: CombatGraceScheduler = null

var _grace_state: Dictionary = {}
var _online_roster: Array[String] = []
var _active_panel: Control = null
var _banner_timer: float = 0.0

# Core HUD widgets
@onready var root_control: Control = $RootControl
var _grace_label: Label = null
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
var _hp_text: Label = null
var _mana_text: Label = null
var _stamina_text: Label = null
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
var _inv_list_box: VBoxContainer = null
var _craft_list_box: VBoxContainer = null
var _market_list_box: VBoxContainer = null
var _market_item_opt: OptionButton = null
var _market_qty_spin: SpinBox = null
var _market_price_spin: SpinBox = null

var _shop_panel: PanelContainer = null
var _shop_crowns_lbl: Label = null
var _shop_list_box: VBoxContainer = null

var _guilds_panel: PanelContainer = null
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
	NetworkManager.disconnected_from_server.connect(_on_disconnected)


func _on_local_player_ready(pc: PlayerController) -> void:
	local_player = pc
	_update_ability_slot_names()
	_refresh_all_panels()


func _on_profile_updated(_profile: Dictionary) -> void:
	_refresh_all_panels()


func _on_social_updated(_g: Dictionary, _l: Array, _b: Array) -> void:
	_refresh_guilds_panel()
	_refresh_inventory_panel()


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
	elif event.is_action_pressed("toggle_inventory"):
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
	for p: Control in [_inv_panel, _shop_panel, _guilds_panel, _avatar_panel, _pause_panel]:
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
				"SERVIDOR DEDICADO ACTIVO — %s\n"
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


func _update_boss_bar_ui() -> void:
	if _boss_bar_box == null or local_player == null:
		return
	var best_boss: WorldBoss = null
	var best_dist: float = 65.0
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
	_boss_name_lbl.text = "☠ %s — %s ☠" % [best_boss.boss_name, best_boss.boss_title]
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
	if not active_user.is_empty() and now < expires_at:
		var rem: String = GameConfig.format_duration(expires_at - now)
		_grace_label.text = "★ GRACIA COMBATIVA (+100%% STATS): %s  |  Tiempo restante: %s ★" % [active_user, rem]
		_grace_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	else:
		var until: String = GameConfig.format_duration(maxf(0.0, next_roll - now))
		_grace_label.text = "Gracia Combativa: Ningún mortal bendecido aún  |  Próximo descenso solar: %s" % until
		_grace_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.94))


func _update_player_vitals_ui() -> void:
	if local_player == null:
		return
	var class_name_str: String = str((GameConfig.CLASSES.get(local_player.class_id, {}) as Dictionary).get("name", local_player.class_id))
	_player_title.text = "%s — %s [%s]" % [local_player.username, class_name_str, local_player.philosophy]
	_hp_bar.max_value = local_player.max_hp
	_hp_bar.value = local_player.hp
	var sh_str: String = " (+%d Escudo)" % int(local_player.shield_hp) if local_player.shield_hp > 1.0 else ""
	_hp_text.text = "HP: %d / %d%s" % [int(ceilf(local_player.hp)), int(local_player.max_hp), sh_str]

	_mana_bar.max_value = local_player.max_mana
	_mana_bar.value = local_player.mana
	_mana_text.text = "Maná: %d / %d" % [int(local_player.mana), int(local_player.max_mana)]

	_stamina_bar.max_value = local_player.max_stamina
	_stamina_bar.value = local_player.stamina
	_stamina_text.text = "Estamina: %d / %d" % [int(local_player.stamina), int(local_player.max_stamina)]

	var gold: int = int(NetworkManager.local_profile.get("gold", 0))
	var crowns: int = int(NetworkManager.local_profile.get("crowns", 0))
	_currency_lbl.text = "Oro: %d  |  Coronas Cosméticas: %d" % [gold, crowns]
	if _coords_lbl != null:
		var wp: Vector3 = GameConfig.local_to_world(local_player.global_position)
		var cc: Vector2i = GameConfig.world_to_chunk(wp)
		var cam_mode: String = "1ª Persona" if local_player.is_first_person else "3ª Persona"
		_coords_lbl.text = "Pos: (%d, %d) | Chunk (%d,%d) | Vista: %s (R3/V/Rueda)" % [int(wp.x), int(wp.z), cc.x, cc.y, cam_mode]
	_grace_badge.visible = local_player.has_combat_grace

	if local_player.is_mounted and local_player.mounted_dragon != null:
		var dc: DragonController = local_player.mounted_dragon
		_dragon_status_lbl.visible = true
		_dragon_status_lbl.text = "DRAGÓN: %s | Vel: %d m/s | RT/LMB: Fuego | LT/RMB: Planear | A/Esp: Subir | B/Ctrl: Bajar | L3/Shift: Turbo | X/G: Bajar" % [
			dc.get_flight_state_label(), int(dc.velocity.length())
		]
	else:
		_dragon_status_lbl.visible = false

	# Ability cooldown labels + active LB/RB selection highlight
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

	# Build bar visibility synced with local BuildingSystem
	if local_player.building_system != null and _build_bar != null:
		var bs: BuildingSystem = local_player.building_system
		_build_bar.visible = bs.is_active
		if bs.is_active:
			var spec: Dictionary = GameConfig.BUILD_PIECES.get(bs.selected_piece, {}) as Dictionary
			_build_info_lbl.text = "CONSTRUCCIÓN (B/D-Up salir) | %s (LB/RB o 1-6) | Snap (F/Back): %s | Rotar (R/X) | Colocar (LMB/RT)" % [
				str(spec.get("name", bs.selected_piece)),
				"ACTIVADO" if bs.snap_to_grid else "LIBRE"
			]


func _update_ability_slot_names() -> void:
	_update_player_vitals_ui()


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

	# 1. Top-Center Global Gracia Combativa Bar
	var top_bar: PanelContainer = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", dark_panel)
	top_bar.anchor_left = 0.2
	top_bar.anchor_right = 0.8
	top_bar.anchor_top = 0.0
	top_bar.offset_top = 10.0
	top_bar.offset_bottom = 48.0
	root_control.add_child(top_bar)
	_grace_label = Label.new()
	_grace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grace_label.text = "Gracia Combativa: sincronizando..."
	top_bar.add_child(_grace_label)

	# 1b. Live World Boss / Dungeon Boss Health Bar (visible within 65m of a Boss)
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

	# 2. Dramatic Global Event Banner (hidden by default)
	_banner_box = PanelContainer.new()
	_banner_box.add_theme_stylebox_override("panel", _make_style(Color(0.14, 0.09, 0.04, 0.92), Color(1.0, 0.85, 0.32, 0.95)))
	_banner_box.anchor_left = 0.22
	_banner_box.anchor_right = 0.78
	_banner_box.anchor_top = 0.0
	_banner_box.offset_top = 120.0
	_banner_box.offset_bottom = 192.0
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

	# 3. Elder Scrolls Style Center Reticle (Crosshair)
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

	# 4. Bottom-Left Vitals Card
	var vitals: PanelContainer = PanelContainer.new()
	vitals.add_theme_stylebox_override("panel", dark_panel)
	vitals.anchor_left = 0.0
	vitals.anchor_top = 1.0
	vitals.anchor_bottom = 1.0
	vitals.offset_left = 14.0
	vitals.offset_right = 356.0
	vitals.offset_top = -196.0
	vitals.offset_bottom = -14.0
	root_control.add_child(vitals)
	var vv: VBoxContainer = VBoxContainer.new()
	vv.add_theme_constant_override("separation", 4)
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

	_currency_lbl = Label.new()
	_currency_lbl.add_theme_font_size_override("font_size", 12)
	vv.add_child(_currency_lbl)
	_coords_lbl = Label.new()
	_coords_lbl.add_theme_font_size_override("font_size", 11)
	_coords_lbl.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92))
	vv.add_child(_coords_lbl)

	# 5. Bottom-Center Ability Hotbar + Dragon Flight Banner + Controls Legend
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
	controls_lbl.text = "LMB/RT: Atacar | RMB/LT: Bloq/Hechizo | LB/RB: Rotar | Q/B: Esquivar | G/X: Dragón | E/Y: Interactuar | R3/V/Rueda: 1ª/3ªP | D-Pad/B,I,Tab,T: Menús | F1: Avatar"
	bottom_center.add_child(controls_lbl)

	# 6. Build Mode Selection Bar (visible when B active)
	_build_bar = PanelContainer.new()
	_build_bar.add_theme_stylebox_override("panel", dark_panel)
	_build_bar.anchor_left = 0.18
	_build_bar.anchor_right = 0.82
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
	var piece_row: HBoxContainer = HBoxContainer.new()
	piece_row.alignment = BoxContainer.ALIGNMENT_CENTER
	piece_row.add_theme_constant_override("separation", 6)
	bbv.add_child(piece_row)
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
	_build_cosmetic_shop_modal(modal_panel)
	_build_guilds_bounties_modal(modal_panel)
	_build_avatar_console_modal(modal_panel)
	_build_pause_modal(modal_panel)


func _create_bar(parent: Control, fill_color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 22)
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
	lbl.add_theme_font_size_override("font_size", 12)
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

	return {"panel": panel, "vbox": vbox}


func _build_inventory_market_modal(style: StyleBoxFlat) -> void:
	var m: Dictionary = _make_centered_modal(style, "Inventario, Forja y Mercado de Jugadores (I)", 820.0, 500.0)
	_inv_panel = m["panel"] as PanelContainer
	var vbox: VBoxContainer = m["vbox"] as VBoxContainer
	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	vbox.add_child(cols)

	# Column 1: Inventory
	var c1: VBoxContainer = VBoxContainer.new()
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c1)
	var l1: Label = Label.new()
	l1.text = "Mochila (Saqueable al morir)"
	c1.add_child(l1)
	var s1: ScrollContainer = ScrollContainer.new()
	s1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c1.add_child(s1)
	_inv_list_box = VBoxContainer.new()
	_inv_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s1.add_child(_inv_list_box)

	# Column 2: Crafting
	var c2: VBoxContainer = VBoxContainer.new()
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c2)
	var l2: Label = Label.new()
	l2.text = "Forja / Crafteo"
	c2.add_child(l2)
	var s2: ScrollContainer = ScrollContainer.new()
	s2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c2.add_child(s2)
	_craft_list_box = VBoxContainer.new()
	_craft_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s2.add_child(_craft_list_box)

	# Column 3: Player Market
	var c3: VBoxContainer = VBoxContainer.new()
	c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(c3)
	var l3: Label = Label.new()
	l3.text = "Comercio entre Jugadores"
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
	list_btn.text = "Publicar Oferta"
	list_btn.pressed.connect(func() -> void:
		var idx: int = _market_item_opt.selected
		if idx >= 0:
			var iid: String = str(_market_item_opt.get_item_metadata(idx))
			NetworkManager.request_market_list(iid, int(_market_qty_spin.value), int(_market_price_spin.value))
	)
	c3.add_child(list_btn)
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
	note.text = "Todos los artículos son 100% visuales (armaduras, dragones y estelas) y nunca se pierden al morir."
	note.add_theme_color_override("font_color", Color(0.72, 0.92, 0.78))
	vbox.add_child(note)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_shop_list_box = VBoxContainer.new()
	_shop_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_shop_list_box)


func _build_guilds_bounties_modal(style: StyleBoxFlat) -> void:
	var m: Dictionary = _make_centered_modal(style, "Reinos, Filosofía y Contratos de Jugadores (Tab)", 780.0, 500.0)
	_guilds_panel = m["panel"] as PanelContainer
	var vbox: VBoxContainer = m["vbox"] as VBoxContainer

	# Personal Philosophy selector (100% voluntary, zero automatic karma)
	var phil_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(phil_row)
	var plbl: Label = Label.new()
	plbl.text = "Tu Estandarte Personal (libre, sin karma automático): "
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

	# Left: Kingdoms / Guilds
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

	# Right: Player-Funded Bounties / Contracts
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
	_bounty_reason_in.placeholder_text = "Motivo (ej: saqueó caravana del Orden)"
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
	var m: Dictionary = _make_centered_modal(style, "Consola de Avatar de Creador — Orden / Caos (F1)", 640.0, 470.0)
	_avatar_panel = m["panel"] as PanelContainer
	var vbox: VBoxContainer = m["vbox"] as VBoxContainer

	var role: String = str(NetworkManager.local_profile.get("role", GameConfig.ROLE_PLAYER))
	if not GameConfig.is_avatar_role(role):
		var denied: Label = Label.new()
		denied.text = "Acceso exclusivo para los Avatares de los Creadores (AVATAR_ORDEN y AVATAR_CAOS).\n\nPara probar esta consola, iniciá sesión con:\n• AvatarOrden / orden_creador\n• AvatarCaos / caos_creador"
		denied.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(denied)
		return

	_avatar_roster_lbl = Label.new()
	_avatar_roster_lbl.text = "Conectados: ..."
	_avatar_roster_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_avatar_roster_lbl)

	var divine_btn: Button = Button.new()
	divine_btn.text = "Activar / Desactivar Descenso Divino (Forma de Avatar + Corona + Inmortalidad)"
	divine_btn.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_toggle_divine_form()
	)
	vbox.add_child(divine_btn)

	# Instant Combat Grace Roll Button
	var grace_btn: Button = Button.new()
	grace_btn.text = "★ INVOCAR GRACIA COMBATIVA AHORA (1 Jugador al Azar, x2.0 por 24h) ★"
	grace_btn.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_trigger_grace("")
	)
	vbox.add_child(grace_btn)

	_avatar_target_in = LineEdit.new()
	_avatar_target_in.placeholder_text = "Nombre de jugador objetivo (opcional para acciones dirigidas)"
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
	b_favor.text = "Otorgar Favor Divino (+35% + Oro)"
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
	b_tp_c.text = "Teletransportar a Coordenadas"
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
	var b_day: Button = Button.new()
	b_day.text = "Invocar Día"
	b_day.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_world_command("set_day", "")
	)
	world_row.add_child(b_day)
	var b_night: Button = Button.new()
	b_night.text = "Invocar Noche"
	b_night.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_world_command("set_night", "")
	)
	world_row.add_child(b_night)
	var b_rep: Button = Button.new()
	b_rep.text = "Reparar Estructura"
	b_rep.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_world_command("repair_nearest", "")
	)
	world_row.add_child(b_rep)
	var b_boss: Button = Button.new()
	b_boss.text = "Reaparecer Jefes"
	b_boss.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_world_command("respawn_bosses", "")
	)
	world_row.add_child(b_boss)
	var b_kick: Button = Button.new()
	b_kick.text = "Expulsar Objetivo"
	b_kick.pressed.connect(func() -> void:
		if _world_auth != null:
			_world_auth.request_avatar_world_command("kick", _avatar_target_in.text)
	)
	world_row.add_child(b_kick)


func _build_pause_modal(style: StyleBoxFlat) -> void:
	var m: Dictionary = _make_centered_modal(style, "Menú de Pausa", 360.0, 230.0)
	_pause_panel = m["panel"] as PanelContainer
	var vbox: VBoxContainer = m["vbox"] as VBoxContainer
	var resume: Button = Button.new()
	resume.text = "Continuar Jugando"
	resume.pressed.connect(_close_all_panels)
	vbox.add_child(resume)

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


func _refresh_inventory_panel() -> void:
	if _inv_list_box == null:
		return
	_clear_box(_inv_list_box)
	var inv: Dictionary = NetworkManager.local_profile.get("inventory", {}) as Dictionary
	var eq_w: String = str(NetworkManager.local_profile.get("equipped_weapon", ""))
	var eq_a: String = str(NetworkManager.local_profile.get("equipped_armor_item", ""))
	for item_var: Variant in inv.keys():
		var iid: String = str(item_var)
		var qty: int = int(inv[iid])
		if qty <= 0 or not GameConfig.ITEMS.has(iid):
			continue
		var idef: Dictionary = GameConfig.ITEMS[iid] as Dictionary
		var row: HBoxContainer = HBoxContainer.new()
		_inv_list_box.add_child(row)
		var lbl: Label = Label.new()
		var eq_tag: String = " [EQ]" if (iid == eq_w or iid == eq_a) else ""
		lbl.text = "%s x%d%s" % [str(idef["name"]), qty, eq_tag]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var itype: String = str(idef.get("type", ""))
		if itype != "resource":
			var btn: Button = Button.new()
			btn.text = "Usar" if itype == "consumable" else "Equipar"
			btn.pressed.connect(func() -> void: NetworkManager.request_equip_or_use_item(iid))
			row.add_child(btn)

	_clear_box(_craft_list_box)
	for rkey_var: Variant in GameConfig.CRAFT_RECIPES.keys():
		var rkey: String = str(rkey_var)
		var rec: Dictionary = GameConfig.CRAFT_RECIPES[rkey] as Dictionary
		var st_tag: String = str(rec.get("station", "forge"))
		var idef: Dictionary = GameConfig.ITEMS[rkey] as Dictionary
		var cost_parts: Array[String] = []
		var cost: Dictionary = rec["cost"] as Dictionary
		for ckey_var: Variant in cost.keys():
			cost_parts.append("%s:%d" % [str((GameConfig.ITEMS[str(ckey_var)] as Dictionary)["name"]), int(cost[ckey_var])])
		var prefix: String = "[Alq] " if st_tag == "alchemy" else "[Forja] "
		var btn: Button = Button.new()
		btn.text = "%s%s (%s)" % [prefix, str(idef["name"]), ", ".join(cost_parts)]
		btn.pressed.connect(func() -> void: NetworkManager.request_craft(rkey))
		_craft_list_box.add_child(btn)

	_clear_box(_market_list_box)
	var merch_hdr: Label = Label.new()
	merch_hdr.text = "— Tienda del Asentamiento (Oro) —"
	merch_hdr.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	_market_list_box.add_child(merch_hdr)
	for m_idx: int in range(GameConfig.MERCHANT_STOCK.size()):
		var offer: Dictionary = GameConfig.MERCHANT_STOCK[m_idx]
		var iid: String = str(offer["item_id"])
		var iname: String = str((GameConfig.ITEMS.get(iid, {}) as Dictionary).get("name", iid))
		var mbtn: Button = Button.new()
		mbtn.text = "Comprar %s x%d (%d oro)" % [iname, int(offer["qty"]), int(offer["price_gold"])]
		var captured_idx: int = m_idx
		mbtn.pressed.connect(func() -> void: NetworkManager.request_merchant_buy(captured_idx))
		_market_list_box.add_child(mbtn)

	var p_hdr: Label = Label.new()
	p_hdr.text = "— Mercado de Jugadores —"
	p_hdr.add_theme_color_override("font_color", Color(0.72, 0.9, 1.0))
	_market_list_box.add_child(p_hdr)
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
	var crowns: int = int(NetworkManager.local_profile.get("crowns", 0))
	_shop_crowns_lbl.text = "Tus Coronas Cosméticas: %d" % crowns
	_clear_box(_shop_list_box)
	var cos: Dictionary = NetworkManager.local_profile.get("cosmetics", {}) as Dictionary

	_add_shop_category("ARMADURAS COSMÉTICAS", "armor", GameConfig.COSMETIC_ARMORS, cos.get("owned_armors", []) as Array, str(cos.get("equipped_armor", "")))
	_add_shop_category("SKINS DE DRAGÓN", "dragon", GameConfig.COSMETIC_DRAGONS, cos.get("owned_dragons", []) as Array, str(cos.get("equipped_dragon", "")))
	_add_shop_category("ESTELAS DE VUELO DE DRAGÓN", "trail", GameConfig.COSMETIC_TRAILS, cos.get("owned_trails", []) as Array, str(cos.get("equipped_trail", "")))


func _add_shop_category(header_text: String, cat: String, catalog: Dictionary, owned: Array, equipped: String) -> void:
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
		elif owned.has(item_id):
			btn.text = "Equipar"
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
