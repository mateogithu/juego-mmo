extends Node3D

## Real-time 3D opening cinematic for Crónicas del Orden y el Caos (Release 2.0).
## Renders a stormy valley with golden Order energy clashing against Chaos fire,
## soaring dragons using dragon.glb, and the official 4-Act subtitles.
## Automatically skipped in headless --server mode.

var _cam_pivot: Node3D = null
var _camera: Camera3D = null
var _order_pillar: MeshInstance3D = null
var _chaos_pillar: MeshInstance3D = null
var _clash_orb: MeshInstance3D = null
var _lightning_light: DirectionalLight3D = null
var _dragons: Array[Node3D] = []

var _act_title_label: Label = null
var _subtitle_label: Label = null
var _progress_bar: ProgressBar = null
var _skip_btn: Button = null
var _fade_rect: ColorRect = null

var _elapsed: float = 0.0
var _act_index: int = 0
var _act_elapsed: float = 0.0
var _lightning_timer: float = 2.4
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
	_build_hud()
	_apply_act(0)
	AudioSynth.play_thunder()


func _build_3d_stage() -> void:
	# Dramatic stormy twilight environment
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.07, 0.14)
	sky_mat.sky_horizon_color = Color(0.28, 0.16, 0.18)
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.07)
	sky_mat.ground_horizon_color = Color(0.18, 0.12, 0.14)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.fog_enabled = true
	env.fog_light_color = Color(0.18, 0.14, 0.22)
	env.fog_density = 0.0085
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env_node.environment = env
	add_child(env_node)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, 35.0, 0.0)
	sun.light_color = Color(0.95, 0.78, 0.62)
	sun.light_energy = 1.25
	add_child(sun)

	_lightning_light = DirectionalLight3D.new()
	_lightning_light.rotation_degrees = Vector3(-60.0, -40.0, 0.0)
	_lightning_light.light_color = Color(0.75, 0.88, 1.0)
	_lightning_light.light_energy = 0.0
	add_child(_lightning_light)

	# Sculpted dark valley floor + twin peaks
	var ground_mesh: PlaneMesh = PlaneMesh.new()
	ground_mesh.size = Vector2(220.0, 220.0)
	ground_mesh.subdivide_width = 24
	ground_mesh.subdivide_depth = 24
	var ground_mi: MeshInstance3D = MeshInstance3D.new()
	ground_mi.mesh = ground_mesh
	var gmat: StandardMaterial3D = ProceduralMeshFactory.make_stone_pbr_material(Color(0.24, 0.27, 0.30))
	gmat.uv1_scale = Vector3(14.0, 14.0, 1.0)
	ground_mi.material_override = gmat
	add_child(ground_mi)

	# Distant Sanctuary towers & Chaos ruins silhouettes
	for i: int in range(10):
		var angle: float = (float(i) / 10.0) * TAU
		var dist: float = 42.0 + (i % 3) * 14.0
		var peak: MeshInstance3D = MeshInstance3D.new()
		var cm: CylinderMesh = CylinderMesh.new()
		cm.top_radius = 1.6
		cm.bottom_radius = 11.0 + (i % 4) * 3.0
		cm.height = 18.0 + (i % 3) * 9.0
		cm.radial_segments = 7
		peak.mesh = cm
		peak.position = Vector3(cos(angle) * dist, cm.height * 0.45, sin(angle) * dist)
		peak.material_override = ProceduralMeshFactory.make_stone_pbr_material(Color(0.22, 0.24, 0.28))
		add_child(peak)

	# Golden Order energy beam (left)
	_order_pillar = MeshInstance3D.new()
	var om: CylinderMesh = CylinderMesh.new()
	om.top_radius = 1.4
	om.bottom_radius = 2.6
	om.height = 65.0
	_order_pillar.mesh = om
	_order_pillar.position = Vector3(-16.0, 26.0, 0.0)
	_order_pillar.rotation_degrees = Vector3(0.0, 0.0, -22.0)
	var omat: StandardMaterial3D = StandardMaterial3D.new()
	omat.albedo_color = Color(1.0, 0.88, 0.42, 0.82)
	omat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	omat.emission_enabled = true
	omat.emission = Color(1.0, 0.82, 0.28)
	omat.emission_energy_multiplier = 3.2
	_order_pillar.material_override = omat
	add_child(_order_pillar)

	var olight: OmniLight3D = OmniLight3D.new()
	olight.light_color = Color(1.0, 0.84, 0.35)
	olight.light_energy = 6.0
	olight.omni_range = 38.0
	olight.position = Vector3(-10.0, 12.0, 0.0)
	add_child(olight)

	# Crimson Chaos energy beam (right)
	_chaos_pillar = MeshInstance3D.new()
	var chm: CylinderMesh = CylinderMesh.new()
	chm.top_radius = 1.4
	chm.bottom_radius = 2.6
	chm.height = 65.0
	_chaos_pillar.mesh = chm
	_chaos_pillar.position = Vector3(16.0, 26.0, 0.0)
	_chaos_pillar.rotation_degrees = Vector3(0.0, 0.0, 22.0)
	var cmat: StandardMaterial3D = StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.28, 0.14, 0.82)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.24, 0.08)
	cmat.emission_energy_multiplier = 3.4
	_chaos_pillar.material_override = cmat
	add_child(_chaos_pillar)

	var clight: OmniLight3D = OmniLight3D.new()
	clight.light_color = Color(1.0, 0.3, 0.12)
	clight.light_energy = 6.0
	clight.omni_range = 38.0
	clight.position = Vector3(10.0, 12.0, 0.0)
	add_child(clight)

	# Central Clash Orb where Order & Chaos collide
	_clash_orb = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 3.6
	sm.height = 7.2
	_clash_orb.mesh = sm
	_clash_orb.position = Vector3(0.0, 15.0, 0.0)
	var clash_mat: StandardMaterial3D = StandardMaterial3D.new()
	clash_mat.albedo_color = Color(1.0, 0.92, 0.72)
	clash_mat.emission_enabled = true
	clash_mat.emission = Color(1.0, 0.72, 0.36)
	clash_mat.emission_energy_multiplier = 4.2
	_clash_orb.material_override = clash_mat
	add_child(_clash_orb)

	# Two soaring real dragon.glb dragons circling the clash
	var skins: Array[String] = ["celestial_white", "abyssal_black"]
	for i: int in range(2):
		var d_holder: Node3D = Node3D.new()
		d_holder.name = "CinematicDragon_%d" % i
		var refs: Dictionary = ProceduralMeshFactory.build_dragon_rig(d_holder, skins[i], "ember_sparks")
		d_holder.scale = Vector3(1.25, 1.25, 1.25)
		var ap: AnimationPlayer = refs.get("anim_player", null) as AnimationPlayer
		if ap != null:
			var anim_name: String = "Dragon_Flying" if ap.has_animation("Dragon_Flying") else (ap.get_animation_list()[0] if ap.get_animation_list().size() > 0 else "")
			if not anim_name.is_empty():
				var anim: Animation = ap.get_animation(anim_name)
				if anim != null:
					anim.loop_mode = Animation.LOOP_LINEAR
				ap.play(anim_name)
		add_child(d_holder)
		_dragons.append(d_holder)

	# Cinematic orbiting camera
	_cam_pivot = Node3D.new()
	_cam_pivot.position = Vector3(0.0, 12.0, 0.0)
	add_child(_cam_pivot)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 8.0, 34.0)
	_camera.fov = 62.0
	_camera.current = true
	_cam_pivot.add_child(_camera)


func _build_hud() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	add_child(canvas)

	# Letterbox bars
	var top_bar: ColorRect = ColorRect.new()
	top_bar.color = Color(0.02, 0.02, 0.04, 0.92)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 66.0
	canvas.add_child(top_bar)

	var brand: Label = Label.new()
	brand.text = "CRÓNICAS DEL ORDEN Y EL CAOS — RELEASE 2.0"
	brand.position = Vector2(24.0, 18.0)
	brand.add_theme_font_size_override("font_size", 18)
	brand.add_theme_color_override("font_color", Color(0.98, 0.84, 0.45))
	top_bar.add_child(brand)

	_skip_btn = Button.new()
	_skip_btn.text = "Saltar [ESC]"
	_skip_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_btn.offset_left = -168.0
	_skip_btn.offset_top = 14.0
	_skip_btn.offset_right = -20.0
	_skip_btn.offset_bottom = 52.0
	_skip_btn.pressed.connect(_finish_cinematic)
	top_bar.add_child(_skip_btn)
	_skip_btn.grab_focus()

	var bottom_bar: ColorRect = ColorRect.new()
	bottom_bar.color = Color(0.02, 0.02, 0.04, 0.90)
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_top = -172.0
	canvas.add_child(bottom_bar)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 80.0
	vbox.offset_right = -80.0
	vbox.offset_top = 16.0
	vbox.offset_bottom = -16.0
	vbox.add_theme_constant_override("separation", 10)
	bottom_bar.add_child(vbox)

	_act_title_label = Label.new()
	_act_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_act_title_label.add_theme_font_size_override("font_size", 22)
	_act_title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	vbox.add_child(_act_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	vbox.add_child(_subtitle_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0.0, 6.0)
	_progress_bar.max_value = 100.0
	vbox.add_child(_progress_bar)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_fade_rect)


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
		if k.pressed and (k.keycode == KEY_ESCAPE or k.keycode == KEY_SPACE or k.keycode == KEY_ENTER):
			if k.keycode == KEY_ESCAPE:
				_finish_cinematic()
			else:
				_apply_act(_act_index + 1)


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	_act_elapsed += delta

	# Orbit camera smoothly
	if _cam_pivot != null and _camera != null:
		_cam_pivot.rotation.y = _elapsed * 0.18
		_camera.position.y = 7.5 + sin(_elapsed * 0.45) * 3.0
		_camera.look_at(Vector3(0.0, 14.5, 0.0), Vector3.UP)

	# Pulse Order vs Chaos clash orb
	if _clash_orb != null:
		var pulse: float = 1.0 + sin(_elapsed * 4.5) * 0.16
		_clash_orb.scale = Vector3(pulse, pulse, pulse)

	# Soar dragons on opposite ellipses
	for i: int in range(_dragons.size()):
		var d: Node3D = _dragons[i]
		var dir: float = 1.0 if i == 0 else -1.0
		var a: float = _elapsed * (0.55 + float(i) * 0.12) * dir + float(i) * PI
		var r: float = 22.0 + float(i) * 6.0
		var next_a: float = a + 0.08 * dir
		var pos: Vector3 = Vector3(cos(a) * r, 16.0 + sin(_elapsed * 1.4 + float(i)) * 4.2, sin(a) * r)
		var look_pos: Vector3 = Vector3(cos(next_a) * r, 16.0 + sin((_elapsed + 0.12) * 1.4 + float(i)) * 4.2, sin(next_a) * r)
		d.position = pos
		if pos.distance_squared_to(look_pos) > 0.01:
			d.look_at(look_pos, Vector3.UP)

	# Periodic storm lightning flash
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = randf_range(3.2, 5.8)
		_lightning_light.light_energy = 4.5
		AudioSynth.play_thunder()
	elif _lightning_light != null and _lightning_light.light_energy > 0.01:
		_lightning_light.light_energy = lerpf(_lightning_light.light_energy, 0.0, clampf(delta * 9.0, 0.0, 1.0))

	# Advance act timer
	if _act_index < GameConfig.INTRO_CINEMATIC_ACTS.size():
		var dur: float = float(GameConfig.INTRO_CINEMATIC_ACTS[_act_index].get("duration", 7.0))
		var total_pct: float = ((float(_act_index) + clampf(_act_elapsed / dur, 0.0, 1.0)) / float(GameConfig.INTRO_CINEMATIC_ACTS.size())) * 100.0
		_progress_bar.value = total_pct
		if _act_elapsed >= dur:
			_apply_act(_act_index + 1)


func _finish_cinematic() -> void:
	if _finished:
		return
	_finished = true
	AudioSynth.play_ui_click()
	get_tree().change_scene_to_file("res://Client/UI/MainMenu.tscn")
