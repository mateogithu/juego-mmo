class_name DragonController
extends CharacterBody3D

## Articulated Flying Dragon Mount with:
## - 5-state 3D flight physics (GROUNDED, TAKEOFF, FLYING, GLIDING, LANDING)
## - Elder Scrolls First-Person (Rider POV) & Third-Person over-the-shoulder orbital camera
## - Full Gamepad + Keyboard/Mouse controls (Left Stick steer, Right Stick 360 look,
##   RT Fire Breath aimed at crosshair, LT Air-Brake/Glide, A Ascend, B Descend, L3 Turbo, R3 Camera)
## - Floating Origin seamless infinite world support

enum FlightState { GROUNDED, TAKEOFF, FLYING, GLIDING, LANDING }

var owner_peer_id: int = 0
var is_local_controlled: bool = false
var is_mounted: bool = false
var is_first_person: bool = false
var flight_state: FlightState = FlightState.GROUNDED

var dragon_skin_id: String = "crimson_wyrm"
var trail_id: String = "none"
var has_combat_grace: bool = false
var is_breathing_fire: bool = false

const GROUND_SPEED: float = 12.0
const MIN_AIR_SPEED: float = 10.0
const CRUISE_AIR_SPEED: float = 25.0
const MAX_AIR_SPEED: float = 46.0
const GRAVITY: float = 22.0
const GLIDE_GRAVITY: float = 9.5

const FP_CAM_POS: Vector3 = Vector3(0.0, 3.2, -0.45)
const TP_CAM_POS: Vector3 = Vector3(0.75, 3.85, 0.0)
const TP_MIN_DIST: float = 5.5
const TP_MAX_DIST: float = 16.0

var air_speed: float = 16.0
var pitch_angle: float = 0.0
var roll_angle: float = 0.0
var yaw_angle: float = 0.0
var _cam_pitch: float = -0.14
var _cam_yaw_offset: float = 0.0
var _tp_spring_length: float = 11.5
var _stick_look_smooth: Vector2 = Vector2.ZERO
var _turbo_toggled: bool = false

var _takeoff_timer: float = 0.0
var _wing_phase: float = 0.0
var _flap_sound_timer: float = 0.0
var _breath_tick_timer: float = 0.0
var _breath_energy: float = 100.0

# Remote interpolation targets (local Floating Origin space)
var _net_target_pos: Vector3 = Vector3.ZERO
var _net_target_rot: Vector3 = Vector3.ZERO
var _net_target_state: int = FlightState.GROUNDED

@onready var visual_root: Node3D = $VisualRoot
@onready var rider_seat: Marker3D = $RiderSeat
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var mount_camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var _rig: Dictionary = {}
var _storm_light: OmniLight3D = null
var _storm_flash_timer: float = 0.0
var _last_dragon_anim: String = ""


func setup(p_owner_peer: int, p_skin: String, p_trail: String, p_grace: bool, local_spawn_pos: Vector3) -> void:
	owner_peer_id = p_owner_peer
	dragon_skin_id = p_skin
	trail_id = p_trail
	has_combat_grace = p_grace
	name = "Dragon_%d" % p_owner_peer
	global_position = local_spawn_pos
	_net_target_pos = local_spawn_pos
	if is_node_ready():
		_rebuild_visual()


func _ready() -> void:
	add_to_group("dragons")
	collision_layer = GameConfig.LAYER_DRAGONS
	collision_mask = GameConfig.LAYER_TERRAIN | GameConfig.LAYER_BUILDINGS
	_net_target_pos = global_position
	_storm_light = OmniLight3D.new()
	_storm_light.light_color = Color(0.65, 0.85, 1.0)
	_storm_light.omni_range = 42.0
	_storm_light.light_energy = 0.0
	_storm_light.position = Vector3(0.0, 6.0, 0.0)
	add_child(_storm_light)
	_rebuild_visual()
	_apply_camera_mode(1.0)


func trigger_summon_storm() -> void:
	_storm_flash_timer = 1.25
	if _storm_light != null:
		_storm_light.light_energy = 9.0
	AudioSynth.play_thunder()
	AudioSynth.play_dragon_roar()


func apply_floating_origin_shift(delta_vec: Vector3) -> void:
	global_position += delta_vec
	_net_target_pos += delta_vec


func _rebuild_visual() -> void:
	_rig = ProceduralMeshFactory.build_dragon_rig(visual_root, dragon_skin_id, trail_id)
	_last_dragon_anim = ""
	set_combat_grace(has_combat_grace)


func apply_cosmetics(p_skin: String, p_trail: String) -> void:
	if dragon_skin_id == p_skin and trail_id == p_trail:
		return
	dragon_skin_id = p_skin
	trail_id = p_trail
	if is_node_ready():
		_rebuild_visual()


func set_combat_grace(active: bool) -> void:
	has_combat_grace = active
	var aura: MeshInstance3D = _rig.get("grace_aura", null) as MeshInstance3D
	if aura != null:
		aura.visible = active


func set_first_person(fp: bool) -> void:
	is_first_person = fp
	if is_node_ready():
		_apply_camera_mode(1.0)


func toggle_camera_view() -> void:
	set_first_person(not is_first_person)


func adjust_zoom(delta_zoom: float) -> void:
	if is_first_person:
		if delta_zoom > 0.0:
			is_first_person = false
			_tp_spring_length = TP_MIN_DIST + 0.5
	else:
		_tp_spring_length = clampf(_tp_spring_length + delta_zoom, TP_MIN_DIST - 0.5, TP_MAX_DIST)
		if _tp_spring_length <= TP_MIN_DIST - 0.25:
			is_first_person = true


func set_mounted(mounted: bool, local_control: bool) -> void:
	is_mounted = mounted
	is_local_controlled = local_control
	if mount_camera != null:
		mount_camera.current = mounted and local_control
	if mounted:
		yaw_angle = rotation.y
		_cam_yaw_offset = 0.0
		_turbo_toggled = false
		if local_control:
			AudioSynth.play_dragon_roar()
	else:
		is_breathing_fire = false
		_set_breath_visual(false)
		if flight_state != FlightState.GROUNDED:
			flight_state = FlightState.LANDING


func handle_mouse_motion(rel: Vector2) -> void:
	if not is_mounted or not is_local_controlled:
		return
	_apply_look_delta(rel.x * 0.0032, rel.y * 0.0028)


func _apply_look_delta(dx: float, dy: float) -> void:
	yaw_angle -= dx
	if flight_state == FlightState.FLYING or flight_state == FlightState.GLIDING:
		pitch_angle = clampf(pitch_angle - dy * 0.72, deg_to_rad(-55.0), deg_to_rad(50.0))
	_cam_pitch = clampf(_cam_pitch - dy, deg_to_rad(-48.0), deg_to_rad(42.0))


func _apply_camera_mode(blend: float) -> void:
	if camera_pivot == null or spring_arm == null:
		return
	var target_pos: Vector3 = FP_CAM_POS if is_first_person else TP_CAM_POS
	var target_len: float = 0.0 if is_first_person else _tp_spring_length
	camera_pivot.position = camera_pivot.position.lerp(target_pos, blend)
	spring_arm.spring_length = lerpf(spring_arm.spring_length, target_len, blend)
	camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw_offset, 0.0)
	# Dynamic flight FOV (72 deg grounded -> up to 92 deg at turbo air speed)
	if mount_camera != null:
		var spd_ratio: float = clampf((air_speed - MIN_AIR_SPEED) / maxf(1.0, MAX_AIR_SPEED - MIN_AIR_SPEED), 0.0, 1.0) if flight_state != FlightState.GROUNDED else 0.0
		var target_fov: float = lerpf(72.0, 92.0, spd_ratio)
		mount_camera.fov = lerpf(mount_camera.fov, target_fov, clampf(blend * 0.5, 0.05, 1.0))


func _physics_process(delta: float) -> void:
	if _storm_flash_timer > 0.0:
		_storm_flash_timer = maxf(0.0, _storm_flash_timer - delta)
		if _storm_light != null:
			_storm_light.light_energy = lerpf(_storm_light.light_energy, 0.0, clampf(delta * 5.5, 0.0, 1.0))

	if is_local_controlled and is_mounted:
		_process_gamepad_look(delta)
		_process_local_flight(delta)
		_apply_camera_mode(clampf(delta * 12.0, 0.0, 1.0))
	elif NetworkManager.is_server_running() and not is_mounted:
		var wp: Vector3 = GameConfig.local_to_world(global_position)
		var gy: float = GameConfig.sample_terrain_height(wp.x, wp.z)
		global_position.y = lerpf(global_position.y, gy + 0.1, delta * 3.0)
		flight_state = FlightState.GROUNDED
	else:
		global_position = global_position.lerp(_net_target_pos, clampf(delta * 12.0, 0.0, 1.0))
		rotation.x = lerp_angle(rotation.x, _net_target_rot.x, clampf(delta * 10.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _net_target_rot.y, clampf(delta * 10.0, 0.0, 1.0))
		rotation.z = lerp_angle(rotation.z, _net_target_rot.z, clampf(delta * 10.0, 0.0, 1.0))
		flight_state = _net_target_state as FlightState

	_animate_dragon(delta)


func _process_gamepad_look(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var raw_look: Vector2 = Input.get_vector("cam_look_left", "cam_look_right", "cam_look_up", "cam_look_down")
	if raw_look.length() < 0.15:
		raw_look = Vector2.ZERO
	else:
		raw_look = raw_look.normalized() * pow(clampf((raw_look.length() - 0.15) / 0.85, 0.0, 1.0), 1.35)
	_stick_look_smooth = _stick_look_smooth.lerp(raw_look, clampf(delta * 14.0, 0.0, 1.0))
	if _stick_look_smooth.length_squared() > 0.0001:
		_apply_look_delta(_stick_look_smooth.x * 2.5 * delta, _stick_look_smooth.y * 1.9 * delta)


func _process_local_flight(delta: float) -> void:
	var ui_open: bool = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	var move_fwd: float = 0.0 if ui_open else Input.get_axis("move_back", "move_forward")
	var steer_x: float = 0.0 if ui_open else Input.get_axis("move_left", "move_right")
	var thrust_up: bool = (not ui_open) and Input.is_action_pressed("jump")
	var descend_held: bool = (not ui_open) and Input.is_action_pressed("descend")
	var air_brake_glide: bool = (not ui_open) and Input.is_action_pressed("block_secondary")

	if (not ui_open) and Input.is_action_just_pressed("sprint") and Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK):
		_turbo_toggled = not _turbo_toggled
	var boost_held: bool = (not ui_open) and (Input.is_action_pressed("sprint") or _turbo_toggled)
	if move_fwd < -0.2 or air_brake_glide:
		_turbo_toggled = false

	var grace_speed_mult: float = 1.25 if has_combat_grace else 1.0
	var world_pos: Vector3 = GameConfig.local_to_world(global_position)
	var ground_y: float = GameConfig.sample_terrain_height(world_pos.x, world_pos.z)
	var altitude: float = world_pos.y - ground_y

	yaw_angle -= steer_x * 1.7 * delta
	var target_roll: float = clampf(-steer_x * 0.52, -0.55, 0.55) if flight_state != FlightState.GROUNDED else 0.0
	roll_angle = lerpf(roll_angle, target_roll, delta * 5.0)

	match flight_state:
		FlightState.GROUNDED:
			pitch_angle = lerpf(pitch_angle, 0.0, delta * 6.0)
			var forward_xz: Vector3 = Vector3(-sin(yaw_angle), 0.0, -cos(yaw_angle))
			var g_mult: float = 1.45 if boost_held else 1.0
			velocity.x = forward_xz.x * move_fwd * GROUND_SPEED * g_mult * grace_speed_mult
			velocity.z = forward_xz.z * move_fwd * GROUND_SPEED * g_mult * grace_speed_mult
			if not is_on_floor() and altitude > 0.35:
				velocity.y -= GRAVITY * delta
			else:
				velocity.y = 0.0
			if (not ui_open) and Input.is_action_just_pressed("jump"):
				flight_state = FlightState.TAKEOFF
				_takeoff_timer = 0.55
				air_speed = CRUISE_AIR_SPEED * 0.78
				velocity.y = 14.5
				AudioSynth.play_dragon_roar()
				AudioSynth.play_wing_flap()

		FlightState.TAKEOFF:
			_takeoff_timer -= delta
			pitch_angle = lerpf(pitch_angle, deg_to_rad(18.0), delta * 5.0)
			var forward_takeoff: Vector3 = Vector3(-sin(yaw_angle), 0.42, -cos(yaw_angle)).normalized()
			velocity = forward_takeoff * (CRUISE_AIR_SPEED * 0.85 * grace_speed_mult)
			if _takeoff_timer <= 0.0:
				flight_state = FlightState.FLYING

		FlightState.FLYING:
			if thrust_up:
				pitch_angle = clampf(pitch_angle + 0.9 * delta, deg_to_rad(-55.0), deg_to_rad(45.0))
			elif descend_held:
				pitch_angle = clampf(pitch_angle - 1.15 * delta, deg_to_rad(-55.0), deg_to_rad(45.0))

			var target_speed: float = MAX_AIR_SPEED if boost_held else (CRUISE_AIR_SPEED if (move_fwd >= 0.0 or thrust_up) else MIN_AIR_SPEED)
			if air_brake_glide:
				target_speed = MIN_AIR_SPEED * 0.85
			target_speed *= grace_speed_mult
			air_speed = lerpf(air_speed, target_speed, delta * 2.8)
			air_speed = clampf(air_speed - sin(pitch_angle) * 14.0 * delta, MIN_AIR_SPEED * 0.7, MAX_AIR_SPEED * grace_speed_mult)

			var dir: Vector3 = Basis.from_euler(Vector3(pitch_angle, yaw_angle, 0.0)) * Vector3.FORWARD
			velocity = dir * air_speed
			if thrust_up:
				velocity.y += 5.8

			if air_brake_glide and altitude > 3.5:
				flight_state = FlightState.GLIDING
			elif not thrust_up and not boost_held and move_fwd <= 0.05 and altitude > 5.0:
				flight_state = FlightState.GLIDING
			elif descend_held and altitude < 4.5:
				flight_state = FlightState.LANDING

		FlightState.GLIDING:
			if (thrust_up or boost_held or move_fwd > 0.25) and not air_brake_glide:
				flight_state = FlightState.FLYING
			elif descend_held and altitude < 4.5:
				flight_state = FlightState.LANDING
			else:
				var drag: float = 7.5 if air_brake_glide else 0.8
				air_speed = clampf(air_speed - sin(pitch_angle) * 18.0 * delta - drag * delta, MIN_AIR_SPEED * 0.65, MAX_AIR_SPEED * grace_speed_mult)
				var glide_dir: Vector3 = Basis.from_euler(Vector3(pitch_angle, yaw_angle, 0.0)) * Vector3.FORWARD
				velocity = glide_dir * air_speed + Vector3(0.0, -GLIDE_GRAVITY * (0.18 if air_brake_glide else 0.26), 0.0)
				if altitude < 2.2:
					flight_state = FlightState.LANDING

		FlightState.LANDING:
			pitch_angle = lerpf(pitch_angle, 0.0, delta * 6.0)
			roll_angle = lerpf(roll_angle, 0.0, delta * 6.0)
			air_speed = lerpf(air_speed, 6.0, delta * 4.0)
			var land_fwd: Vector3 = Vector3(-sin(yaw_angle), 0.0, -cos(yaw_angle))
			velocity = Vector3(land_fwd.x * air_speed * 0.4, -7.5, land_fwd.z * air_speed * 0.4)
			if altitude <= 0.65 or is_on_floor():
				global_position.y = ground_y + 0.1
				velocity = Vector3.ZERO
				flight_state = FlightState.GROUNDED

	global_position.y = clampf(global_position.y, maxf(ground_y + 0.05, GameConfig.WATER_LEVEL + 1.0), 240.0)
	rotation = Vector3(pitch_angle, yaw_angle, roll_angle)
	move_and_slide()

	var wants_breath: bool = (not ui_open) and Input.is_action_pressed("attack_primary")
	if wants_breath and _breath_energy > 8.0:
		if not is_breathing_fire:
			AudioSynth.play_dragon_roar()
		is_breathing_fire = true
		_breath_energy = maxf(0.0, _breath_energy - 28.0 * delta)
		_breath_tick_timer += delta
		if _breath_tick_timer >= 0.25:
			_breath_tick_timer = 0.0
			_fire_breath_server_tick()
	else:
		is_breathing_fire = false
		_breath_energy = minf(100.0, _breath_energy + 20.0 * delta)

	_set_breath_visual(is_breathing_fire)


func _fire_breath_server_tick() -> void:
	var head: Node3D = _rig.get("head", null) as Node3D
	var local_origin: Vector3 = head.global_position if head != null else global_position + Vector3(0.0, 2.0, 0.0)
	var aim_dir: Vector3 = -global_transform.basis.z
	if mount_camera != null:
		aim_dir = -mount_camera.global_transform.basis.z
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	if wa != null and wa.has_method("request_dragon_breath"):
		wa.call("request_dragon_breath", GameConfig.local_to_world(local_origin), aim_dir.normalized())


func _set_breath_visual(active: bool) -> void:
	var cone: MeshInstance3D = _rig.get("breath_cone", null) as MeshInstance3D
	if cone != null:
		cone.visible = active


func apply_network_snapshot(local_pos: Vector3, rot: Vector3, state_int: int, breathing: bool, grace: bool) -> void:
	if is_local_controlled:
		return
	_net_target_pos = local_pos
	_net_target_rot = rot
	_net_target_state = state_int
	is_breathing_fire = breathing
	_set_breath_visual(breathing)
	if has_combat_grace != grace:
		set_combat_grace(grace)


func get_flight_state_label() -> String:
	var cam_tag: String = "1ªP" if is_first_person else "3ªP"
	var state_str: String = "En Tierra"
	match flight_state:
		FlightState.GROUNDED:
			state_str = "En Tierra"
		FlightState.TAKEOFF:
			state_str = "Despegando"
		FlightState.FLYING:
			state_str = "Volando"
		FlightState.GLIDING:
			state_str = "Planeando"
		FlightState.LANDING:
			state_str = "Aterrizando"
	return "%s (%s)" % [state_str, cam_tag]


func _animate_dragon(delta: float) -> void:
	# Drive real dragon.glb AnimationPlayer when present
	var ap: AnimationPlayer = _rig.get("anim_player", null) as AnimationPlayer
	if ap != null:
		var target_anim: String = "Dragon_Hit" if is_breathing_fire and ap.has_animation("Dragon_Hit") else "Dragon_Flying"
		if ap.has_animation(target_anim):
			var speed_scale: float = 0.45 if flight_state == FlightState.GROUNDED else (0.65 if flight_state == FlightState.GLIDING else 1.25)
			ap.speed_scale = speed_scale
			if _last_dragon_anim != target_anim or not ap.is_playing():
				var anim_res: Animation = ap.get_animation(target_anim)
				if anim_res != null:
					anim_res.loop_mode = Animation.LOOP_LINEAR
				ap.play(target_anim, 0.15)
				_last_dragon_anim = target_anim
		if is_local_controlled and (flight_state == FlightState.FLYING or flight_state == FlightState.TAKEOFF):
			_flap_sound_timer += delta
			if _flap_sound_timer >= 0.65:
				_flap_sound_timer = 0.0
				AudioSynth.play_wing_flap()
		return

	# Procedural fallback wing/tail animation
	var wl_root: Node3D = _rig.get("wing_l_root", null) as Node3D
	var wl_tip: Node3D = _rig.get("wing_l_tip", null) as Node3D
	var wr_root: Node3D = _rig.get("wing_r_root", null) as Node3D
	var wr_tip: Node3D = _rig.get("wing_r_tip", null) as Node3D
	var tail_1: Node3D = _rig.get("tail_1", null) as Node3D
	var tail_2: Node3D = _rig.get("tail_2", null) as Node3D
	var neck: Node3D = _rig.get("neck", null) as Node3D

	if wl_root == null or wr_root == null:
		return

	var flap_freq: float = 0.0
	var flap_amp: float = 0.0
	match flight_state:
		FlightState.GROUNDED:
			_wing_phase += delta * 1.4
			wl_root.rotation_degrees = Vector3(12.0, -25.0, 28.0 + sin(_wing_phase) * 3.0)
			wr_root.rotation_degrees = Vector3(12.0, 25.0, -28.0 - sin(_wing_phase) * 3.0)
			wl_tip.rotation_degrees = Vector3(0.0, 0.0, -45.0)
			wr_tip.rotation_degrees = Vector3(0.0, 0.0, 45.0)
		FlightState.TAKEOFF:
			flap_freq = 10.5
			flap_amp = 48.0
		FlightState.FLYING:
			flap_freq = 6.2 + clampf(air_speed / 35.0, 0.0, 1.0) * 2.5
			flap_amp = 38.0
		FlightState.GLIDING:
			flap_freq = 1.6
			flap_amp = 6.0
		FlightState.LANDING:
			flap_freq = 8.0
			flap_amp = 34.0

	if flight_state != FlightState.GROUNDED:
		_wing_phase += delta * flap_freq
		var beat: float = sin(_wing_phase)
		var lag_beat: float = sin(_wing_phase - 0.65)
		wl_root.rotation_degrees = Vector3(0.0, 0.0, beat * flap_amp)
		wr_root.rotation_degrees = Vector3(0.0, 0.0, -beat * flap_amp)
		wl_tip.rotation_degrees = Vector3(0.0, 0.0, lag_beat * flap_amp * 0.65)
		wr_tip.rotation_degrees = Vector3(0.0, 0.0, -lag_beat * flap_amp * 0.65)
		if is_local_controlled and (flight_state == FlightState.FLYING or flight_state == FlightState.TAKEOFF):
			_flap_sound_timer += delta
			if _flap_sound_timer >= maxf(0.45, TAU / maxf(flap_freq, 1.0)):
				_flap_sound_timer = 0.0
				AudioSynth.play_wing_flap()

	if tail_1 != null and tail_2 != null:
		tail_1.rotation_degrees.y = sin(_wing_phase * 0.6) * 14.0
		tail_2.rotation_degrees.y = sin(_wing_phase * 0.6 - 0.8) * 18.0
	if neck != null:
		neck.rotation_degrees.x = sin(_wing_phase * 0.5) * 4.0 + (6.0 if is_breathing_fire else 0.0)
	var jaw: Node3D = _rig.get("jaw", null) as Node3D
	if jaw != null:
		var target_jaw_x: float = 34.0 if is_breathing_fire else 0.0
		jaw.rotation_degrees.x = lerpf(jaw.rotation_degrees.x, target_jaw_x, clampf(delta * 12.0, 0.0, 1.0))
