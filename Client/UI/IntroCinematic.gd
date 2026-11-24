class_name IntroCinematic
extends Node3D

## Real-time 3D opening cinematic for Crónicas del Orden y el Caos (Release 2.0).
## Renders a live stormy valley with 1K PBR peaks, storm rain, golden Order energy
## clashing against crimson Chaos fire, soaring real dragon.glb dragons, and
## completely transparent 4-Act subtitles (zero opaque panels).
## Main scene on F5; automatically skipped in headless --server mode.

static var enter_world_after: bool = false

var _cam_pivot: Node3D = null
var _camera: Camera3D = null
var _order_pillar: MeshInstance3D = null
var _chaos_pillar: MeshInstance3D = null
var _clash_orb: MeshInstance3D = null
var _clash_ring_a: MeshInstance3D = null
var _clash_ring_b: MeshInstance3D = null
var _lightning_light: DirectionalLight3D = null
var _dragons: Array[Node3D] = []

var _act_title_label: Label = null
var _subtitle_label: Label = null
var _progress_bar: ProgressBar = null
var _skip_btn: Button = null

var _elapsed: float = 0.0
var _act_index: int = 0
var _act_elapsed: float = 0.0
var _lightning_timer: float = 2.1
var _finished: bool = false


func _ready() -> void:
	# Dedicated headless server skips cinematic immediately and launches World.tscn
	if NetworkManager.is_dedicated_server_launch():
		var port: int = NetworkManager.get_launch_port()
		if NetworkManager.start_dedicated_server(port) == OK:
			get_tree().change_scene_to_file("res://Client/World/World.tscn")
		return

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_3d_stage()
	_build_transparent_hud()
	_apply_act(0)
	AudioSynth.play_thunder()


func _build_3d_stage() -> void:
	# Dramatic stormy twilight environment (100% Compatibility/Mobile safe)
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.07, 0.14)
	sky_mat.sky_horizon_color = Color(0.32, 0.18, 0.19)
	sky_mat.ground_bottom_color = Color(0.04, 0.05, 0.08)
	sky_mat.ground_horizon_color = Color(0.18, 0.13, 0.16)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.72
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.14, 0.22)
	env.fog_density = 0.0068
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env_node.environment = env
	add_child(env_node)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, 35.0, 0.0)
	sun.light_color = Color(0.95, 0.78, 0.62)
	sun.light_energy = 1.3
	add_child(sun)

	_lightning_light = DirectionalLight3D.new()
	_lightning_light.rotation_degrees = Vector3(-60.0, -40.0, 0.0)
	_lightning_light.light_color = Color(0.75, 0.88, 1.0)
	_lightning_light.light_energy = 0.0
	add_child(_lightning_light)

	# Sculpted 1K PBR valley floor with real terrain shader & elevation relief
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var grid_res: int = 32
	var half_span: float = 110.0
	var step: float = (half_span * 2.0) / float(grid_res)
	var stride: int = grid_res + 1
	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	verts.resize(stride * stride)
	uvs.resize(stride * stride)
	for gz: int in range(stride):
		for gx: int in range(stride):
			var wx: float = -half_span + float(gx) * step
			var wz: float = -half_span + float(gz) * step
			var radial: float = sqrt(wx * wx + wz * wz)
			var bowl: float = clampf((radial - 22.0) / 55.0, 0.0, 1.5)
			var ridge: float = sin(wx * 0.09) * cos(wz * 0.08) * 4.5 + bowl * bowl * 16.0
			var idx: int = gz * stride + gx
			verts[idx] = Vector3(wx, ridge - 1.5, wz)
			uvs[idx] = Vector2(float(gx) / float(grid_res), float(gz) / float(grid_res))
	for gz: int in range(grid_res):
		for gx: int in range(grid_res):
			var i00: int = gz * stride + gx
			var i10: int = i00 + 1
			var i01: int = i00 + stride
			var i11: int = i01 + 1
			st.set_uv(uvs[i00])
			st.add_vertex(verts[i00])
			st.set_uv(uvs[i10])
			st.add_vertex(verts[i10])
			st.set_uv(uvs[i11])
			st.add_vertex(verts[i11])
			st.set_uv(uvs[i00])
			st.add_vertex(verts[i00])
			st.set_uv(uvs[i11])
			st.add_vertex(verts[i11])
			st.set_uv(uvs[i01])
			st.add_vertex(verts[i01])
	st.index()
	st.generate_normals()
	var valley_mi: MeshInstance3D = MeshInstance3D.new()
	valley_mi.mesh = st.commit()
	valley_mi.material_override = TerrainChunk.get_terrain_material()
	add_child(valley_mi)

	# 1K PBR Mountain Peaks & Ancient Ruin Silhouettes around the valley
	var rock_mat: StandardMaterial3D = ProceduralMeshFactory.make_rock_pbr_material(Color(0.32, 0.34, 0.4), 0.18)
	for i: int in range(12):
		var angle: float = (float(i) / 12.0) * TAU
		var dist: float = 46.0 + float(i % 3) * 14.0
		var peak: MeshInstance3D = MeshInstance3D.new()
		var cm: CylinderMesh = CylinderMesh.new()
		cm.top_radius = 1.4
		cm.bottom_radius = 12.0 + float(i % 4) * 3.0
		cm.height = 20.0 + float(i % 3) * 10.0
		cm.radial_segments = 7
		peak.mesh = cm
		peak.position = Vector3(cos(angle) * dist, cm.height * 0.42, sin(angle) * dist)
		peak.material_override = rock_mat
		add_child(peak)

	# Storm Rain Streaks (lightweight CPUParticles3D for Radeon Vega 8)
	var rain: CPUParticles3D = CPUParticles3D.new()
	rain.name = "StormRain"
	rain.position = Vector3(0.0, 34.0, 0.0)
	rain.amount = 140
	rain.lifetime = 1.6
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(48.0, 2.0, 48.0)
	rain.direction = Vector3(0.18, -1.0, 0.1)
	rain.spread = 4.0
	rain.initial_velocity_min = 24.0
	rain.initial_velocity_max = 32.0
	rain.gravity = Vector3(0.0, -14.0, 0.0)
	var drop_mesh: CylinderMesh = CylinderMesh.new()
	drop_mesh.top_radius = 0.02
	drop_mesh.bottom_radius = 0.02
	drop_mesh.height = 1.35
	drop_mesh.radial_segments = 4
	rain.mesh = drop_mesh
	var rain_mat: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(Color(0.75, 0.86, 1.0, 0.42), 0.2, 0.0, Color(0.65, 0.8, 1.0), 0.7)
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain.material_override = rain_mat
	add_child(rain)

	# Golden Order energy beam (left)
	_order_pillar = MeshInstance3D.new()
	var om: CylinderMesh = CylinderMesh.new()
	om.top_radius = 1.3
	om.bottom_radius = 2.8
	om.height = 68.0
	_order_pillar.mesh = om
	_order_pillar.position = Vector3(-16.0, 26.0, 0.0)
	_order_pillar.rotation_degrees = Vector3(0.0, 0.0, -23.0)
	var omat: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(Color(1.0, 0.88, 0.42, 0.82), 0.15, 0.1, Color(1.0, 0.82, 0.28), 3.4)
	omat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_order_pillar.material_override = omat
	add_child(_order_pillar)

	var olight: OmniLight3D = OmniLight3D.new()
	olight.light_color = Color(1.0, 0.84, 0.35)
	olight.light_energy = 6.5
	olight.omni_range = 42.0
	olight.position = Vector3(-10.0, 12.0, 0.0)
	add_child(olight)

	# Crimson Chaos energy beam (right)
	_chaos_pillar = MeshInstance3D.new()
	var chm: CylinderMesh = CylinderMesh.new()
	chm.top_radius = 1.3
	chm.bottom_radius = 2.8
	chm.height = 68.0
	_chaos_pillar.mesh = chm
	_chaos_pillar.position = Vector3(16.0, 26.0, 0.0)
	_chaos_pillar.rotation_degrees = Vector3(0.0, 0.0, 23.0)
	var cmat: StandardMaterial3D = ProceduralMeshFactory.make_pbr_material(Color(1.0, 0.28, 0.14, 0.82), 0.15, 0.1, Color(1.0, 0.24, 0.08), 3.6)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_chaos_pillar.material_override = cmat
	add_child(_chaos_pillar)

	var clight: OmniLight3D = OmniLight3D.new()
	clight.light_color = Color(1.0, 0.3, 0.12)
	clight.light_energy = 6.5
	clight.omni_range = 42.0
	clight.position = Vector3(10.0, 12.0, 0.0)
	add_child(clight)

	# Central Clash Orb + Twin Energy Shockwave Rings where Order & Chaos collide
	_clash_orb = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 3.8
	sm.height = 7.6
	_clash_orb.mesh = sm
	_clash_orb.position = Vector3(0.0, 15.0, 0.0)
	_clash_orb.material_override = ProceduralMeshFactory.make_pbr_material(Color(1.0, 0.94, 0.76), 0.1, 0.0, Color(1.0, 0.76, 0.38), 4.4)
	add_child(_clash_orb)

	_clash_ring_a = MeshInstance3D.new()
	var tm_a: TorusMesh = TorusMesh.new()
	tm_a.inner_radius = 5.4
	tm_a.outer_radius = 6.1
	_clash_ring_a.mesh = tm_a
	_clash_ring_a.position = Vector3(0.0, 15.0, 0.0)
	_clash_ring_a.material_override = omat
	add_child(_clash_ring_a)

	_clash_ring_b = MeshInstance3D.new()
	var tm_b: TorusMesh = TorusMesh.new()
	tm_b.inner_radius = 6.8
	tm_b.outer_radius = 7.4
	_clash_ring_b.mesh = tm_b
	_clash_ring_b.position = Vector3(0.0, 15.0, 0.0)
	_clash_ring_b.material_override = cmat
	add_child(_clash_ring_b)

	# Three soaring real dragon.glb dragons crossing the stormy sky
	var skins: Array[String] = ["celestial_white", "abyssal_black", "crimson_wyrm"]
	for i: int in range(skins.size()):
		var d_holder: Node3D = Node3D.new()
		d_holder.name = "CinematicDragon_%d" % i
		var refs: Dictionary = ProceduralMeshFactory.build_dragon_rig(d_holder, skins[i], "ember_sparks" if i > 0 else "golden_order")
		d_holder.scale = Vector3.ONE * (1.35 if i < 2 else 1.1)
		var ap: AnimationPlayer = refs.get("anim_player", null) as AnimationPlayer
		if ap != null:
			var anim_name: String = "Dragon_Flying" if ap.has_animation("Dragon_Flying") else (ap.get_animation_list()[0] if ap.get_animation_list().size() > 0 else "")
			if not anim_name.is_empty():
				var anim: Animation = ap.get_animation(anim_name)
				if anim != null:
					anim.loop_mode = Animation.LOOP_LINEAR
				ap.speed_scale = 1.05 + float(i) * 0.12
				ap.play(anim_name)
		add_child(d_holder)
		_dragons.append(d_holder)

	# Cinematic orbiting camera
	_cam_pivot = Node3D.new()
	_cam_pivot.position = Vector3(0.0, 13.0, 0.0)
	add_child(_cam_pivot)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 8.5, 36.0)
	_camera.fov = 62.0
	_camera.far = 360.0
	_camera.current = true
	_cam_pivot.add_child(_camera)


func _build_transparent_hud() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)

	# Completely transparent top overlay (zero opaque blue/black boxes!)
	var top_overlay: Control = Control.new()
	top_overlay.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_overlay.offset_bottom = 70.0
	top_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.add_child(top_overlay)

	var brand: Label = Label.new()
	brand.text = "CRÓNICAS DEL ORDEN Y EL CAOS — RELEASE 2.0"
	brand.position = Vector2(26.0, 18.0)
	brand.add_theme_font_size_override("font_size", 19)
	brand.add_theme_color_override("font_color", Color(1.0, 0.88, 0.48))
	brand.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	brand.add_theme_constant_override("outline_size", 5)
	top_overlay.add_child(brand)

	_skip_btn = Button.new()
	_skip_btn.text = "Saltar [ESC]"
	_skip_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_btn.offset_left = -168.0
	_skip_btn.offset_top = 14.0
	_skip_btn.offset_right = -20.0
	_skip_btn.offset_bottom = 52.0
	var btn_style: StyleBoxFlat = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.05, 0.05, 0.08, 0.42)
	btn_style.border_color = Color(0.95, 0.78, 0.34, 0.85)
	btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(6)
	_skip_btn.add_theme_stylebox_override("normal", btn_style)
	_skip_btn.pressed.connect(_finish_cinematic)
	top_overlay.add_child(_skip_btn)
	_skip_btn.grab_focus()

	# Transparent floating bottom subtitle strip (lets the live 3D valley & dragons shine through!)
	var bottom_panel: PanelContainer = PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left = 72.0
	bottom_panel.offset_right = -72.0
	bottom_panel.offset_top = -174.0
	bottom_panel.offset_bottom = -18.0
	bottom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub_style: StyleBoxFlat = StyleBoxFlat.new()
	sub_style.bg_color = Color(0.0, 0.0, 0.0, 0.24)
	sub_style.border_color = Color(0.95, 0.78, 0.34, 0.32)
	sub_style.set_border_width_all(1)
	sub_style.set_corner_radius_all(10)
	sub_style.set_content_margin_all(14)
	bottom_panel.add_theme_stylebox_override("panel", sub_style)
	canvas.add_child(bottom_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	bottom_panel.add_child(vbox)

	_act_title_label = Label.new()
	_act_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_act_title_label.add_theme_font_size_override("font_size", 23)
	_act_title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	_act_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_act_title_label.add_theme_constant_override("outline_size", 5)
	vbox.add_child(_act_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_font_size_override("font_size", 19)
	_subtitle_label.add_theme_color_override("font_color", Color(0.98, 0.98, 1.0))
	_subtitle_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_subtitle_label.add_theme_constant_override("outline_size", 5)
	vbox.add_child(_subtitle_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0.0, 5.0)
	_progress_bar.max_value = 100.0
	var pb_bg: StyleBoxFlat = StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	var pb_fill: StyleBoxFlat = StyleBoxFlat.new()
	pb_fill.bg_color = Color(1.0, 0.82, 0.34, 0.9)
	_progress_bar.add_theme_stylebox_override("background", pb_bg)
	_progress_bar.add_theme_stylebox_override("fill", pb_fill)
	vbox.add_child(_progress_bar)


func _apply_act(idx: int) -> void:
	if idx >= GameConfig.INTRO_CINEMATIC_ACTS.size():
		_finish_cinematic()
		return
	_act_index = idx
	_act_elapsed = 0.0
	var act: Dictionary = GameConfig.INTRO_CINEMATIC_ACTS[idx]
	_act_title_label.text = str(act.get("act", ""))
	_subtitle_label.text = "\"%s\"" % str(act.get("text", ""))
	if idx == 1:
		AudioSynth.play_dragon_roar()
	elif idx == 2:
		AudioSynth.play_combat_grace_fanfare()


func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		_finish_cinematic()
	elif event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ESCAPE or k.keycode == KEY_SPACE or k.keycode == KEY_ENTER):
			if k.keycode == KEY_ESCAPE:
				_finish_cinematic()
			else:
				_apply_act(_act_index + 1)


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	_act_elapsed += delta

	# Orbit camera smoothly around the Order vs Chaos clash
	if _cam_pivot != null and _camera != null:
		_cam_pivot.rotation.y = _elapsed * 0.16
		_camera.position.y = 8.0 + sin(_elapsed * 0.42) * 3.4
		_camera.look_at(Vector3(0.0, 14.5, 0.0), Vector3.UP)

	# Pulse Order vs Chaos clash orb and spin shockwave rings
	if _clash_orb != null:
		var pulse: float = 1.0 + sin(_elapsed * 4.5) * 0.18
		_clash_orb.scale = Vector3(pulse, pulse, pulse)
	if _clash_ring_a != null:
		_clash_ring_a.rotation = Vector3(_elapsed * 0.9, _elapsed * 0.6, 0.4)
	if _clash_ring_b != null:
		_clash_ring_b.rotation = Vector3(-_elapsed * 0.7, _elapsed * 1.1, -0.5)

	# Soar real dragon.glb dragons across the stormy sky
	for i: int in range(_dragons.size()):
		var d: Node3D = _dragons[i]
		var dir: float = 1.0 if (i % 2 == 0) else -1.0
		var a: float = _elapsed * (0.52 + float(i) * 0.11) * dir + float(i) * 2.1
		var rx: float = 22.0 + float(i) * 7.5
		var rz: float = 19.0 + float(i) * 6.0
		var next_a: float = a + 0.08 * dir
		var base_y: float = 17.0 + float(i) * 3.2
		var pos: Vector3 = Vector3(cos(a) * rx, base_y + sin(_elapsed * 1.3 + float(i)) * 3.8, sin(a) * rz)
		var look_pos: Vector3 = Vector3(cos(next_a) * rx, base_y + sin((_elapsed + 0.12) * 1.3 + float(i)) * 3.8, sin(next_a) * rz)
		d.position = pos
		if pos.distance_squared_to(look_pos) > 0.01:
			d.look_at(look_pos, Vector3.UP)

	# Periodic storm lightning flash
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = randf_range(2.8, 5.2)
		_lightning_light.light_energy = 5.2
		AudioSynth.play_thunder()
	elif _lightning_light != null and _lightning_light.light_energy > 0.01:
		_lightning_light.light_energy = lerpf(_lightning_light.light_energy, 0.0, clampf(delta * 8.5, 0.0, 1.0))

	# Advance 4-act subtitles
	if _act_index < GameConfig.INTRO_CINEMATIC_ACTS.size():
		var dur: float = float(GameConfig.INTRO_CINEMATIC_ACTS[_act_index].get("duration", 7.5))
		var total_pct: float = ((float(_act_index) + clampf(_act_elapsed / dur, 0.0, 1.0)) / float(GameConfig.INTRO_CINEMATIC_ACTS.size())) * 100.0
		_progress_bar.value = total_pct
		if _act_elapsed >= dur:
			_apply_act(_act_index + 1)


func _finish_cinematic() -> void:
	if _finished:
		return
	_finished = true
	var go_world: bool = enter_world_after
	enter_world_after = false
	AudioSynth.play_ui_click()
	if go_world:
		get_tree().change_scene_to_file("res://Client/World/World.tscn")
	else:
		get_tree().change_scene_to_file("res://Client/UI/MainMenu.tscn")
