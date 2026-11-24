class_name WorldMapUI
extends PanelContainer

## Interactive 5-Region World Map modal (M key + MainMenu button).
## Shows Order vs Chaos territorial control, 30-day Season countdown,
## Safe Zones, Supreme Dragon Bosses, Dungeons, local player pin, and clickable Wayshrines.

signal wayshrine_teleport_requested(wayshrine_id: String)
signal map_closed()

const MAP_SPAN: float = 920.0 # World coordinates -460..+460 mapped onto canvas

var _map_canvas: Control = null
var _season_label: Label = null
var _region_info_label: RichTextLabel = null
var _wayshrine_list: VBoxContainer = null
var _player_world_pos: Vector3 = Vector3.ZERO
var _season_state: Dictionary = {}
var _discovered_wayshrines: Array = ["ws_alba", "ws_caos"]
var _can_teleport: bool = true


func _ready() -> void:
	visible = false
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(960.0, 620.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	style.border_color = Color(0.82, 0.68, 0.34, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", style)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	add_child(root_vbox)

	var header: HBoxContainer = HBoxContainer.new()
	root_vbox.add_child(header)

	var title: Label = Label.new()
	title.text = "🗺️ MAPA DEL MUNDO — GUERRA TERRITORIAL ORDEN VS. CAOS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.48))
	header.add_child(title)

	_season_label = Label.new()
	_season_label.text = "Temporada 1 — 30 días restantes"
	_season_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	header.add_child(_season_label)

	var close_btn: Button = Button.new()
	close_btn.text = "Cerrar [M / ESC]"
	close_btn.pressed.connect(func() -> void:
		visible = false
		map_closed.emit()
	)
	header.add_child(close_btn)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root_vbox.add_child(body)

	# Left: Custom drawn map canvas
	var map_frame: PanelContainer = PanelContainer.new()
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(map_frame)

	_map_canvas = Control.new()
	_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_canvas.draw.connect(_draw_world_map)
	map_frame.add_child(_map_canvas)

	# Right: Region dominance + Wayshrine fast travel list
	var side: VBoxContainer = VBoxContainer.new()
	side.custom_minimum_size = Vector2(310.0, 0.0)
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)

	var reg_hdr: Label = Label.new()
	reg_hdr.text = "Dominio de las 5 Regiones"
	reg_hdr.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45))
	side.add_child(reg_hdr)

	_region_info_label = RichTextLabel.new()
	_region_info_label.bbcode_enabled = true
	_region_info_label.custom_minimum_size = Vector2(0.0, 210.0)
	side.add_child(_region_info_label)

	var ws_hdr: Label = Label.new()
	ws_hdr.text = "⚡ Altares de Viaje Rápido (Wayshrines)"
	ws_hdr.add_theme_color_override("font_color", Color(0.55, 0.88, 1.0))
	side.add_child(ws_hdr)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)

	_wayshrine_list = VBoxContainer.new()
	_wayshrine_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wayshrine_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_wayshrine_list)


func refresh_map(player_pos: Vector3, season_state: Dictionary, discovered_ws: Array, allow_teleport: bool = true) -> void:
	_player_world_pos = player_pos
	_season_state = season_state
	_discovered_wayshrines = discovered_ws
	_can_teleport = allow_teleport

	var s_num: int = int(season_state.get("season_number", 1))
	var days_left: int = SeasonResetSystem.get_days_remaining(season_state) if not season_state.is_empty() else 30
	_season_label.text = "Temporada %d — %d días restantes" % [s_num, days_left]

	_rebuild_region_text()
	_rebuild_wayshrine_buttons()
	if _map_canvas != null:
		_map_canvas.queue_redraw()


func _rebuild_region_text() -> void:
	if _region_info_label == null:
		return
	var tc: Dictionary = _season_state.get("territory_control", {}) as Dictionary
	var lines: Array[String] = []
	for rdef: Dictionary in GameConfig.WORLD_REGIONS:
		var rid: String = str(rdef.get("id", ""))
		var rname: String = str(rdef.get("name", rid))
		var st: Dictionary = tc.get(rid, {"owner": str(rdef.get("default_owner", "Neutral")), "order_pts": 0, "chaos_pts": 0}) as Dictionary
		var owner_str: String = str(st.get("owner", "Neutral"))
		var col: String = "#b8c4d4"
		if owner_str == GameConfig.PHILOSOPHY_ORDER:
			col = "#ffd866"
		elif owner_str == GameConfig.PHILOSOPHY_CHAOS:
			col = "#ff6b4a"
		lines.append("[color=%s][b]%s[/b]: %s[/color] (Orden %d / Caos %d)" % [
			col, rname, owner_str, int(st.get("order_pts", 0)), int(st.get("chaos_pts", 0))
		])
	lines.append("\n[color=#88f2a2]● Zonas Seguras:[/color] Santuario del Alba (0,0) y Ciudadela del Caos (260,260)")
	lines.append("[color=#ff8888]● Jefes Dragón:[/color] Valle Dracónico (sueltan Piedra de Vínculo)")
	_region_info_label.text = "\n".join(lines)


func _rebuild_wayshrine_buttons() -> void:
	if _wayshrine_list == null:
		return
	for ch: Node in _wayshrine_list.get_children():
		ch.queue_free()
	for wdef: Dictionary in GameConfig.WAYSHRINES:
		var wid: String = str(wdef.get("id", ""))
		var wname: String = str(wdef.get("name", wid))
		var wpos: Vector2 = wdef.get("xz", Vector2.ZERO) as Vector2
		var known: bool = _discovered_wayshrines.has(wid) or bool(wdef.get("default_unlocked", false))
		var btn: Button = Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if known:
			btn.text = "✦ %s (%d, %d)" % [wname, int(wpos.x), int(wpos.y)]
			btn.disabled = not _can_teleport
			btn.pressed.connect(func() -> void:
				wayshrine_teleport_requested.emit(wid)
			)
		else:
			btn.text = "🔒 %s (Descubrir explorando)" % wname
			btn.disabled = true
		_wayshrine_list.add_child(btn)


func _world_to_canvas(wx: float, wz: float, rect_size: Vector2) -> Vector2:
	var nx: float = clampf((wx + MAP_SPAN * 0.5) / MAP_SPAN, 0.04, 0.96)
	var nz: float = clampf((wz + MAP_SPAN * 0.5) / MAP_SPAN, 0.04, 0.96)
	return Vector2(nx * rect_size.x, nz * rect_size.y)


func _draw_world_map() -> void:
	if _map_canvas == null:
		return
	var sz: Vector2 = _map_canvas.size
	if sz.x < 10.0 or sz.y < 10.0:
		return
	_map_canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.11, 0.14))
	for g: int in range(1, 8):
		var gx: float = sz.x * (float(g) / 8.0)
		var gy: float = sz.y * (float(g) / 8.0)
		_map_canvas.draw_line(Vector2(gx, 0.0), Vector2(gx, sz.y), Color(0.2, 0.25, 0.3, 0.28), 1.0)
		_map_canvas.draw_line(Vector2(0.0, gy), Vector2(sz.x, gy), Color(0.2, 0.25, 0.3, 0.28), 1.0)

	var tc: Dictionary = _season_state.get("territory_control", {}) as Dictionary
	var font: Font = ThemeDB.fallback_font

	for rdef: Dictionary in GameConfig.WORLD_REGIONS:
		var rid: String = str(rdef.get("id", ""))
		var center_v2: Vector2 = rdef.get("center_xz", Vector2.ZERO) as Vector2
		var cpos: Vector2 = _world_to_canvas(center_v2.x, center_v2.y, sz)
		var rad_px: float = (float(rdef.get("radius", 150.0)) / MAP_SPAN) * minf(sz.x, sz.y)
		var base_col: Color = rdef.get("color", Color(0.4, 0.5, 0.4)) as Color
		var st: Dictionary = tc.get(rid, {}) as Dictionary
		var owner_str: String = str(st.get("owner", str(rdef.get("default_owner", "Neutral"))))
		var ring_col: Color = base_col
		if owner_str == GameConfig.PHILOSOPHY_ORDER:
			ring_col = Color(1.0, 0.85, 0.32)
		elif owner_str == GameConfig.PHILOSOPHY_CHAOS:
			ring_col = Color(1.0, 0.32, 0.18)
		_map_canvas.draw_circle(cpos, rad_px, Color(base_col.r, base_col.g, base_col.b, 0.22))
		_map_canvas.draw_arc(cpos, rad_px, 0.0, TAU, 36, ring_col, 2.2)
		_map_canvas.draw_string(font, cpos + Vector2(-58.0, -rad_px * 0.35), str(rdef.get("name", rid)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.96, 0.98))

	for sdef: Dictionary in GameConfig.SAFE_ZONES:
		var sc: Vector2 = sdef.get("center_xz", Vector2.ZERO) as Vector2
		var p: Vector2 = _world_to_canvas(sc.x, sc.y, sz)
		var s_col: Color = Color(0.98, 0.84, 0.36) if str(sdef.get("faction", "")) == GameConfig.PHILOSOPHY_ORDER else Color(0.98, 0.34, 0.22)
		_map_canvas.draw_circle(p, 11.0, Color(s_col.r, s_col.g, s_col.b, 0.45))
		_map_canvas.draw_arc(p, 11.0, 0.0, TAU, 20, Color(0.35, 1.0, 0.55), 2.2)

	for bdef: Dictionary in GameConfig.WORLD_BOSSES:
		var bp: Vector2 = bdef.get("spawn_xz", Vector2.ZERO) as Vector2
		var p: Vector2 = _world_to_canvas(bp.x, bp.y, sz)
		var col: Color = Color(1.0, 0.25, 0.25) if bool(bdef.get("is_supreme_dragon", false)) else Color(1.0, 0.65, 0.25)
		_map_canvas.draw_circle(p, 5.5, col)

	for ddef: Dictionary in GameConfig.DUNGEONS:
		var dp: Vector2 = ddef.get("entrance_xz", Vector2.ZERO) as Vector2
		var p: Vector2 = _world_to_canvas(dp.x, dp.y, sz)
		_map_canvas.draw_rect(Rect2(p - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color(0.75, 0.42, 1.0))

	for wdef: Dictionary in GameConfig.WAYSHRINES:
		var wid: String = str(wdef.get("id", ""))
		var wp: Vector2 = wdef.get("xz", Vector2.ZERO) as Vector2
		var p: Vector2 = _world_to_canvas(wp.x, wp.y, sz)
		var known: bool = _discovered_wayshrines.has(wid) or bool(wdef.get("default_unlocked", false))
		_map_canvas.draw_circle(p, 4.5, Color(0.35, 0.9, 1.0) if known else Color(0.45, 0.48, 0.52))

	var pp: Vector2 = _world_to_canvas(_player_world_pos.x, _player_world_pos.z, sz)
	_map_canvas.draw_circle(pp, 6.0, Color(1.0, 1.0, 1.0))
	_map_canvas.draw_circle(pp, 3.8, Color(0.18, 0.95, 0.42))
