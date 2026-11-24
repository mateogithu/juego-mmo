class_name PlayerController
extends CharacterBody3D

## Articulated 3D MMORPG player character with:
## - Elder Scrolls First-Person (hidden character mesh + animated weapon/hands viewmodel)
##   and Third-Person over-the-shoulder orbital camera (toggled via R3 / V / Mouse Wheel)
## - Full Gamepad + Keyboard/Mouse parallel controls (Left Stick move, Right Stick 360 look,
##   RT primary attack/spell, LT block/secondary quick-cast, LB/RB rotate quick abilities,
##   A jump, B dodge iframes, X dragon/rotate, Y interact, L3 sprint)
## - Infinite world & Floating Origin seamless support

var peer_id: int = 0
var is_local: bool = false
var username: String = ""
var role: String = GameConfig.ROLE_PLAYER
var class_id: String = "ARCANE_KNIGHT"
var philosophy: String = GameConfig.PHILOSOPHY_NEUTRAL
var armor_skin_id: String = "default_iron"
var dragon_skin_id: String = "crimson_wyrm"
var trail_id: String = "none"

# Live combat stats (authoritatively synced by WorldAuthority)
var max_hp: float = 120.0
var hp: float = 120.0
var max_mana: float = 100.0
var mana: float = 100.0
var max_stamina: float = 100.0
var stamina: float = 100.0
var shield_hp: float = 0.0
var has_combat_grace: bool = false
var is_divine_form: bool = false
var is_stealthed: bool = false
var is_blocking: bool = false
var is_dodging: bool = false
var is_mounted: bool = false
var mounted_dragon: DragonController = null

# Elder Scrolls Camera State
const FP_PIVOT_POS: Vector3 = Vector3(0.0, 1.66, -0.06)
const TP_SHOULDER_POS: Vector3 = Vector3(0.48, 1.68, 0.0)
const TP_MIN_DIST: float = 2.3
const TP_MAX_DIST: float = 9.5

var is_first_person: bool = false
var _tp_spring_length: float = 5.4
var _camera_yaw: float = 0.0
var _camera_pitch: float = -0.18
var _stick_look_smooth: Vector2 = Vector2.ZERO
var _sprint_toggled: bool = false

# Quick-rotated class ability slot (LB / RB on Gamepad)
var selected_ability_slot: int = 0
var _lt_hold_time: float = 0.0
var _lt_was_pressed: bool = false

# Cooldowns & combat timings
var ability_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _attack_cooldown: float = 0.0
var _attack_anim_timer: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _walk_phase: float = 0.0
var _snapshot_timer: float = 0.0

# Remote interpolation targets (local Floating Origin space)
var _net_pos: Vector3 = Vector3.ZERO
var _net_yaw: float = 0.0
var _net_anim_speed: float = 0.0
var _net_attacking: bool = false

@onready var visual_root: Node3D = $VisualRoot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var player_camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var nameplate: Label3D = $Nameplate
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _rig: Dictionary = {}
var _fp_root: Node3D = null
var _fp_rig: Dictionary = {}
var building_system: BuildingSystem = null


func setup_player(p_peer_id: int, p_local: bool, state: Dictionary) -> void:
	peer_id = p_peer_id
	is_local = p_local
	name = "Player_%d" % p_peer_id
	apply_full_state(state)
	if is_node_ready():
		_init_local_systems()


func _ready() -> void:
	add_to_group("players")
	collision_layer = GameConfig.LAYER_PLAYERS
	collision_mask = GameConfig.LAYER_TERRAIN | GameConfig.LAYER_BUILDINGS | GameConfig.LAYER_PLAYERS
	_net_pos = global_position
	_rebuild_visual()
	_init_local_systems()


func apply_floating_origin_shift(delta_vec: Vector3) -> void:
	global_position += delta_vec
	_net_pos += delta_vec


func _init_local_systems() -> void:
	if player_camera != null:
		player_camera.current = is_local and not is_mounted
		if is_local and _fp_root == null:
			_fp_root = Node3D.new()
			_fp_root.name = "FirstPersonViewmodel"
			player_camera.add_child(_fp_root)
			_rebuild_fp_viewmodel()
	if is_local and building_system == null:
		building_system = BuildingSystem.new()
		building_system.name = "BuildingSystem"
		add_child(building_system)
	_apply_camera_perspective(1.0)


func apply_full_state(state: Dictionary) -> void:
	username = str(state.get("username", "Aventurero"))
	role = str(state.get("role", GameConfig.ROLE_PLAYER))
	var new_class: String = str(state.get("class_id", "ARCANE_KNIGHT"))
	philosophy = str(state.get("philosophy", GameConfig.PHILOSOPHY_NEUTRAL))
	var new_skin: String = str(state.get("armor_skin", "default_iron"))
	dragon_skin_id = str(state.get("dragon_skin", "crimson_wyrm"))
	trail_id = str(state.get("trail_id", "none"))
	max_hp = float(state.get("max_hp", 120.0))
	hp = float(state.get("hp", max_hp))
	max_mana = float(state.get("max_mana", 100.0))
	mana = float(state.get("mana", max_mana))
	max_stamina = float(state.get("max_stamina", 100.0))
	stamina = float(state.get("stamina", max_stamina))
	shield_hp = float(state.get("shield_hp", 0.0))
	has_combat_grace = bool(state.get("has_combat_grace", false))
	is_divine_form = bool(state.get("is_divine_form", false))
	is_stealthed = bool(state.get("is_stealthed", false))

	var pos_arr: Array = state.get("position", []) as Array
	if pos_arr.size() == 3:
		var wp: Vector3 = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		var lp: Vector3 = GameConfig.world_to_local(wp)
		global_position = lp
		_net_pos = lp

	var needs_rebuild: bool = (new_class != class_id or new_skin != armor_skin_id or _rig.is_empty())
	class_id = new_class
	armor_skin_id = new_skin
	if is_node_ready():
		if needs_rebuild:
			_rebuild_visual()
			_rebuild_fp_viewmodel()
		else:
			_apply_status_visuals()
		_update_nameplate()


func _rebuild_visual() -> void:
	if visual_root == null:
		return
	_rig = ProceduralMeshFactory.build_humanoid_rig(visual_root, class_id, armor_skin_id)
	_apply_status_visuals()
	_update_nameplate()


func _rebuild_fp_viewmodel() -> void:
	if not is_local or _fp_root == null:
		return
	_fp_rig = ProceduralMeshFactory.build_first_person_viewmodel(_fp_root, class_id, armor_skin_id)
	_apply_status_visuals()


func set_first_person(fp: bool) -> void:
	is_first_person = fp
	if is_mounted and mounted_dragon != null:
		mounted_dragon.set_first_person(fp)
	_apply_status_visuals()
	_apply_camera_perspective(1.0)


func toggle_camera_view() -> void:
	set_first_person(not is_first_person)
	AudioSynth.play_ui_click()


func _apply_camera_perspective(blend: float) -> void:
	if camera_pivot == null or spring_arm == null or not is_local:
		return
	var target_pivot: Vector3 = FP_PIVOT_POS if is_first_person else TP_SHOULDER_POS
	var target_len: float = 0.0 if is_first_person else _tp_spring_length
	camera_pivot.position = camera_pivot.position.lerp(target_pivot, blend)
	spring_arm.spring_length = lerpf(spring_arm.spring_length, target_len, blend)


func _apply_status_visuals() -> void:
	var hide_body_for_fp: bool = is_local and is_first_person

	var aura: MeshInstance3D = _rig.get("grace_aura", null) as MeshInstance3D
	if aura != null:
		aura.visible = (has_combat_grace or is_divine_form) and not hide_body_for_fp
		if is_divine_form:
			aura.material_override = ProceduralMeshFactory.make_grace_aura_material(role == GameConfig.ROLE_AVATAR_CAOS)
		elif has_combat_grace:
			aura.material_override = ProceduralMeshFactory.make_grace_aura_material(false)

	var crown: Node3D = _rig.get("divine_crown", null) as Node3D
	if crown != null:
		crown.visible = is_divine_form and not hide_body_for_fp

	var body_pivot: Node3D = _rig.get("body_pivot", null) as Node3D
	if body_pivot != null:
		var target_scale: float = 1.38 if is_divine_form else 1.0
		body_pivot.scale = Vector3.ONE * target_scale
		body_pivot.visible = (not hide_body_for_fp) and ((not is_stealthed) or is_local)

	if _fp_root != null:
		_fp_root.visible = is_local and is_first_person and not is_mounted


func _update_nameplate() -> void:
	if nameplate == null:
		return
	var prefix: String = ""
	if role == GameConfig.ROLE_AVATAR_ORDEN:
		prefix = "[AVATAR DEL ORDEN]\n"
		nameplate.modulate = Color(1.0, 0.88, 0.35)
	elif role == GameConfig.ROLE_AVATAR_CAOS:
		prefix = "[AVATAR DEL CAOS]\n"
		nameplate.modulate = Color(1.0, 0.35, 0.22)
	elif has_combat_grace:
		prefix = "★ GRACIA COMBATIVA (x2) ★\n"
		nameplate.modulate = Color(1.0, 0.92, 0.42)
	else:
		nameplate.modulate = Color(0.92, 0.96, 1.0)
	var class_name_str: String = str((GameConfig.CLASSES.get(class_id, {}) as Dictionary).get("name", class_id))
	nameplate.text = "%s%s [%s]\n%s | HP %d/%d" % [prefix, username, philosophy, class_name_str, int(ceilf(hp)), int(max_hp)]
	nameplate.visible = (not is_local) and (not is_stealthed)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if is_mounted and mounted_dragon != null:
			mounted_dragon.handle_mouse_motion(mm.relative)
		else:
			_camera_yaw -= mm.relative.x * 0.0032
			_camera_pitch = clampf(_camera_pitch - mm.relative.y * 0.0028, deg_to_rad(-72.0), deg_to_rad(68.0))
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed:
			if building_system != null and building_system.is_active:
				if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					building_system.rotate_ghost(15.0)
				elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					building_system.rotate_ghost(-15.0)
				elif mb.button_index == MOUSE_BUTTON_LEFT:
					building_system.try_place_current()
					return
			else:
				if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					_adjust_camera_zoom(-0.75)
				elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					_adjust_camera_zoom(0.75)


func _adjust_camera_zoom(delta_zoom: float) -> void:
	if is_mounted and mounted_dragon != null:
		mounted_dragon.adjust_zoom(delta_zoom)
		is_first_person = mounted_dragon.is_first_person
		_apply_status_visuals()
		return
	if is_first_person:
		if delta_zoom > 0.0:
			is_first_person = false
			_tp_spring_length = TP_MIN_DIST + 0.4
			_apply_status_visuals()
	else:
		_tp_spring_length = clampf(_tp_spring_length + delta_zoom, TP_MIN_DIST - 0.5, TP_MAX_DIST)
		if _tp_spring_length <= TP_MIN_DIST - 0.2:
			is_first_person = true
			_apply_status_visuals()


func _physics_process(delta: float) -> void:
	for i: int in range(ability_cooldowns.size()):
		if ability_cooldowns[i] > 0.0:
			ability_cooldowns[i] = maxf(0.0, ability_cooldowns[i] - delta)
	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _attack_anim_timer > 0.0:
		_attack_anim_timer = maxf(0.0, _attack_anim_timer - delta)

	if is_local:
		_process_local_controls(delta)
		_apply_camera_perspective(clampf(delta * 14.0, 0.0, 1.0))
	else:
		_process_remote_interpolation(delta)

	_animate_humanoid(delta)
	if is_local and is_first_person and not is_mounted:
		_animate_fp_viewmodel(delta)


func _process_gamepad_look(delta: float) -> void:
	var raw_look: Vector2 = Input.get_vector("cam_look_left", "cam_look_right", "cam_look_up", "cam_look_down")
	if raw_look.length() < 0.15:
		raw_look = Vector2.ZERO
	else:
		raw_look = raw_look.normalized() * pow(clampf((raw_look.length() - 0.15) / 0.85, 0.0, 1.0), 1.35)
	_stick_look_smooth = _stick_look_smooth.lerp(raw_look, clampf(delta * 14.0, 0.0, 1.0))
	if _stick_look_smooth.length_squared() > 0.0001:
		_camera_yaw -= _stick_look_smooth.x * 2.6 * delta
		_camera_pitch = clampf(_camera_pitch - _stick_look_smooth.y * 2.0 * delta, deg_to_rad(-72.0), deg_to_rad(68.0))


func _process_local_controls(delta: float) -> void:
	var ui_captured: bool = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED

	if not ui_captured:
		# Elder Scrolls Camera Toggle (R3 or V)
		if Input.is_action_just_pressed("toggle_camera_view"):
			toggle_camera_view()

		# Build Mode toggle (B or D-Pad Up)
		if Input.is_action_just_pressed("toggle_build") and not is_mounted and building_system != null:
			building_system.toggle_build_mode()

		if building_system != null and building_system.is_active:
			if Input.is_action_just_pressed("rotate_build") or Input.is_action_just_pressed("toggle_dragon"):
				building_system.rotate_ghost(15.0)
			if Input.is_action_just_pressed("toggle_snap"):
				building_system.toggle_snap()
			if Input.is_action_just_pressed("ability_prev"):
				building_system.cycle_piece(-1)
			if Input.is_action_just_pressed("ability_next"):
				building_system.cycle_piece(1)
			if Input.is_action_just_pressed("attack_primary"):
				building_system.try_place_current()
			var piece_keys: Array[String] = ["wall", "gate", "tower", "altar_order", "altar_chaos", "trade_post"]
			for pk_idx: int in range(piece_keys.size()):
				if Input.is_physical_key_pressed(KEY_1 + pk_idx):
					building_system.select_piece(piece_keys[pk_idx])
		else:
			# Mount/Dismount Dragon (G or X/Square)
			if Input.is_action_just_pressed("toggle_dragon"):
				_request_toggle_dragon()
			# Rotate quick class abilities with Bumpers (LB / RB)
			if Input.is_action_just_pressed("ability_prev"):
				selected_ability_slot = posmod(selected_ability_slot - 1, 4)
				AudioSynth.play_ui_click()
			if Input.is_action_just_pressed("ability_next"):
				selected_ability_slot = posmod(selected_ability_slot + 1, 4)
				AudioSynth.play_ui_click()

		if Input.is_action_just_pressed("interact"):
			_try_interact()

	if is_mounted and mounted_dragon != null:
		global_position = mounted_dragon.rider_seat.global_position
		rotation = mounted_dragon.rotation
		velocity = mounted_dragon.velocity
		if collision_shape != null:
			collision_shape.disabled = true
	else:
		if collision_shape != null:
			collision_shape.disabled = false
		if not ui_captured:
			_process_gamepad_look(delta)
		_process_on_foot_movement(delta, ui_captured)

	if building_system != null and building_system.is_active and player_camera != null:
		building_system.update_preview(player_camera, global_position)

	_snapshot_timer += delta
	if _snapshot_timer >= GameConfig.SNAPSHOT_INTERVAL:
		_snapshot_timer = 0.0
		_send_transform_to_server()


func _process_on_foot_movement(delta: float, ui_captured: bool) -> void:
	if camera_pivot != null:
		camera_pivot.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)

	var class_def: Dictionary = GameConfig.CLASSES.get(class_id, GameConfig.CLASSES["ARCANE_KNIGHT"]) as Dictionary
	var base_speed: float = float(class_def.get("move_speed", 6.5))
	if has_combat_grace:
		base_speed *= 1.3
	if is_stealthed:
		base_speed *= 1.25
	if is_divine_form:
		base_speed *= 1.4

	var input_vec: Vector2 = Vector2.ZERO if ui_captured else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis: Basis = Basis(Vector3.UP, _camera_yaw)
	var move_dir: Vector3 = (cam_basis * Vector3(input_vec.x, 0.0, input_vec.y))
	if move_dir.length() > 1.0:
		move_dir = move_dir.normalized()

	# L3 click toggles sprint on gamepad; Shift holds sprint on keyboard
	if (not ui_captured) and Input.is_action_just_pressed("sprint") and Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK):
		_sprint_toggled = not _sprint_toggled
	if input_vec.length() < 0.15:
		_sprint_toggled = false

	# Dodge Roll with temporary iframes (Q / Alt / B-Circle)
	if not ui_captured and Input.is_action_just_pressed("dodge") and not is_dodging and stamina >= 22.0:
		is_dodging = true
		_dodge_timer = 0.42
		_dodge_dir = move_dir.normalized() if move_dir.length() > 0.1 else -Vector3(sin(_camera_yaw), 0.0, cos(_camera_yaw))
		AudioSynth.play_dodge()
		var wa: Node = get_tree().get_first_node_in_group("world_authority")
		if wa != null and wa.has_method("request_dodge"):
			wa.call("request_dodge")

	if is_dodging:
		_dodge_timer -= delta
		velocity.x = _dodge_dir.x * base_speed * 2.15
		velocity.z = _dodge_dir.z * base_speed * 2.15
		if _dodge_timer <= 0.0:
			is_dodging = false
	else:
		# LT/L2 or RMB: Hold = Directional Block; Quick Tap (<0.22s) = Cast Quick-Selected Class Ability!
		var block_btn: bool = (not ui_captured) and Input.is_action_pressed("block_secondary") and (building_system == null or not building_system.is_active)
		if block_btn:
			_lt_hold_time += delta
			_lt_was_pressed = true
		elif _lt_was_pressed:
			if _lt_hold_time < 0.22 and not is_dodging:
				_perform_ability(selected_ability_slot)
			_lt_hold_time = 0.0
			_lt_was_pressed = false

		var wants_block: bool = block_btn and stamina > 4.0
		if wants_block != is_blocking:
			is_blocking = wants_block
			var wa_blk: Node = get_tree().get_first_node_in_group("world_authority")
			if wa_blk != null and wa_blk.has_method("request_set_blocking"):
				wa_blk.call("request_set_blocking", is_blocking)

		var speed: float = base_speed
		if is_blocking:
			speed *= 0.52
		elif not ui_captured and (Input.is_action_pressed("sprint") or _sprint_toggled) and stamina > 5.0 and move_dir.length() > 0.1:
			speed *= 1.45

		velocity.x = lerpf(velocity.x, move_dir.x * speed, clampf(delta * 10.0, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, move_dir.z * speed, clampf(delta * 10.0, 0.0, 1.0))

		if is_first_person or is_blocking:
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, _camera_yaw, clampf(delta * 18.0, 0.0, 1.0))
		elif move_dir.length() > 0.08:
			var desired_yaw: float = atan2(-move_dir.x, -move_dir.z)
			visual_root.rotation.y = lerp_angle(visual_root.rotation.y, desired_yaw, clampf(delta * 12.0, 0.0, 1.0))

	if not is_on_floor():
		velocity.y -= 24.0 * delta
	elif not ui_captured and Input.is_action_just_pressed("jump"):
		velocity.y = 9.2

	move_and_slide()
	var wp: Vector3 = GameConfig.local_to_world(global_position)
	var min_ground: float = GameConfig.sample_terrain_height(wp.x, wp.z)
	if global_position.y < min_ground - 0.5:
		global_position.y = min_ground + 0.15
		velocity.y = maxf(0.0, velocity.y)

	# Combat inputs (aimed straight at center Crosshair!)
	if not ui_captured and (building_system == null or not building_system.is_active):
		if Input.is_action_just_pressed("attack_primary") and _attack_cooldown <= 0.0 and not is_dodging:
			_perform_primary_attack()
		for slot: int in range(4):
			if Input.is_action_just_pressed("ability_%d" % (slot + 1)):
				selected_ability_slot = slot
				_perform_ability(slot)


func _get_crosshair_aim_dir() -> Vector3:
	if player_camera == null:
		return -visual_root.global_transform.basis.z
	var cam_origin: Vector3 = player_camera.global_position
	var cam_fwd: Vector3 = -player_camera.global_transform.basis.z
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cam_origin, cam_origin + cam_fwd * 80.0)
	query.collision_mask = GameConfig.LAYER_TERRAIN | GameConfig.LAYER_PLAYERS | GameConfig.LAYER_BUILDINGS
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	var launch_local: Vector3 = global_position + Vector3(0.0, 1.35, 0.0)
	if not hit.is_empty():
		var target_pt: Vector3 = hit["position"] as Vector3
		var d: Vector3 = target_pt - launch_local
		if d.length() > 0.5:
			return d.normalized()
	return cam_fwd.normalized()


func _perform_primary_attack() -> void:
	_attack_cooldown = 0.52
	_attack_anim_timer = 0.35
	visual_root.rotation.y = _camera_yaw
	var aim_dir: Vector3 = _get_crosshair_aim_dir()
	AudioSynth.play_sword_hit()
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	if wa != null and wa.has_method("request_primary_attack"):
		var world_origin: Vector3 = GameConfig.local_to_world(global_position + Vector3(0.0, 1.35, 0.0))
		wa.call("request_primary_attack", world_origin, aim_dir)


func _perform_ability(slot: int) -> void:
	if slot < 0 or slot >= 4 or ability_cooldowns[slot] > 0.0:
		return
	var class_def: Dictionary = GameConfig.CLASSES.get(class_id, {}) as Dictionary
	var abilities: Array = class_def.get("abilities", []) as Array
	if slot >= abilities.size():
		return
	var ab: Dictionary = abilities[slot] as Dictionary
	if mana < float(ab.get("cost_mana", 0.0)) or stamina < float(ab.get("cost_stamina", 0.0)):
		return
	ability_cooldowns[slot] = float(ab.get("cooldown", 4.0))
	_attack_anim_timer = 0.35
	visual_root.rotation.y = _camera_yaw
	var aim_dir: Vector3 = _get_crosshair_aim_dir()
	var ab_type: String = str(ab.get("type", "projectile"))
	if ab_type == "heal" or ab_type == "shield" or ab_type == "buff":
		AudioSynth.play_heal()
	elif ab_type == "dash":
		AudioSynth.play_dodge()
		var dash_vec: Vector3 = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized() * float(ab.get("dash_dist", 9.0))
		global_position += dash_vec * 0.65
		var dwp: Vector3 = GameConfig.local_to_world(global_position)
		global_position.y = maxf(global_position.y, GameConfig.sample_terrain_height(dwp.x, dwp.z) + 0.2)
	else:
		AudioSynth.play_fireball()
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	if wa != null and wa.has_method("request_cast_ability"):
		var world_origin: Vector3 = GameConfig.local_to_world(global_position + Vector3(0.0, 1.35, 0.0))
		wa.call("request_cast_ability", slot, world_origin, aim_dir)


func _request_toggle_dragon() -> void:
	if building_system != null and building_system.is_active:
		building_system.set_build_mode(false)
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	if wa != null and wa.has_method("request_toggle_dragon"):
		wa.call("request_toggle_dragon")


func _try_interact() -> void:
	var best_dist: float = 5.5
	var nearest_loot: LootCorpse = null
	for node: Node in get_tree().get_nodes_in_group("loot_corpses"):
		var lc: LootCorpse = node as LootCorpse
		var d: float = global_position.distance_to(lc.global_position)
		if d < best_dist:
			best_dist = d
			nearest_loot = lc
	if nearest_loot != null:
		var wa: Node = get_tree().get_first_node_in_group("world_authority")
		if wa != null and wa.has_method("request_loot_corpse"):
			wa.call("request_loot_corpse", nearest_loot.loot_id)
			AudioSynth.play_ui_click()
		return

	best_dist = 5.5
	var nearest_build: BuildPiece = null
	for node: Node in get_tree().get_nodes_in_group("buildings"):
		var bp: BuildPiece = node as BuildPiece
		if bp.piece_type == "gate" or bp.piece_type == "trade_post":
			var d: float = global_position.distance_to(bp.global_position)
			if d < best_dist:
				best_dist = d
				nearest_build = bp
	if nearest_build != null:
		if nearest_build.piece_type == "gate":
			var ba: Node = get_tree().get_first_node_in_group("building_authority")
			if ba != null and ba.has_method("request_toggle_gate"):
				ba.call("request_toggle_gate", nearest_build.building_id)
				AudioSynth.play_build_place()
		elif nearest_build.piece_type == "trade_post":
			var hud: Node = get_tree().get_first_node_in_group("game_hud")
			if hud != null and hud.has_method("open_trade_market"):
				hud.call("open_trade_market")
		return

	best_dist = 5.8
	var nearest_res: ResourceNode = null
	for node: Node in get_tree().get_nodes_in_group("resource_nodes"):
		var rn: ResourceNode = node as ResourceNode
		if rn.is_depleted:
			continue
		var d: float = global_position.distance_to(rn.global_position)
		if d < best_dist:
			best_dist = d
			nearest_res = rn
	if nearest_res != null:
		_attack_anim_timer = 0.25
		AudioSynth.play_sword_hit()
		var wa_res: Node = get_tree().get_first_node_in_group("world_authority")
		if wa_res != null and wa_res.has_method("request_gather_resource"):
			wa_res.call("request_gather_resource", nearest_res.resource_key)


func _send_transform_to_server() -> void:
	var wa: Node = get_tree().get_first_node_in_group("world_authority")
	if wa == null or not wa.has_method("send_client_transform"):
		return
	var p_world: Vector3 = GameConfig.local_to_world(global_position)
	var d_world: Vector3 = GameConfig.local_to_world(mounted_dragon.global_position) if (is_mounted and mounted_dragon != null) else Vector3.ZERO
	var d_rot: Vector3 = mounted_dragon.rotation if (is_mounted and mounted_dragon != null) else Vector3.ZERO
	var d_state: int = int(mounted_dragon.flight_state) if (is_mounted and mounted_dragon != null) else 0
	var d_breath: bool = mounted_dragon.is_breathing_fire if (is_mounted and mounted_dragon != null) else false
	wa.call(
		"send_client_transform",
		p_world,
		visual_root.rotation.y,
		Vector2(velocity.x, velocity.z).length(),
		_attack_anim_timer > 0.0,
		is_blocking,
		is_dodging,
		is_mounted,
		d_world,
		d_rot,
		d_state,
		d_breath
	)


func apply_remote_transform(local_pos: Vector3, yaw: float, anim_speed: float, attacking: bool, blocking: bool, dodging: bool) -> void:
	if is_local:
		return
	_net_pos = local_pos
	_net_yaw = yaw
	_net_anim_speed = anim_speed
	_net_attacking = attacking
	is_blocking = blocking
	is_dodging = dodging


func _process_remote_interpolation(delta: float) -> void:
	if is_mounted and mounted_dragon != null:
		global_position = mounted_dragon.rider_seat.global_position
		visual_root.rotation.y = mounted_dragon.rotation.y
	else:
		global_position = global_position.lerp(_net_pos, clampf(delta * 14.0, 0.0, 1.0))
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, _net_yaw, clampf(delta * 14.0, 0.0, 1.0))


func set_mounted_dragon(dragon: DragonController) -> void:
	mounted_dragon = dragon
	is_mounted = dragon != null
	if is_local and player_camera != null:
		player_camera.current = not is_mounted
	_apply_status_visuals()


func _animate_fp_viewmodel(delta: float) -> void:
	var rh: Node3D = _fp_rig.get("right_hand", null) as Node3D
	var lh: Node3D = _fp_rig.get("left_hand", null) as Node3D
	if rh == null or lh == null:
		return

	var speed: float = Vector2(velocity.x, velocity.z).length()
	var bob_y: float = sin(_walk_phase * 2.0) * 0.018 if speed > 0.4 else sin(Time.get_ticks_msec() * 0.003) * 0.006
	var bob_x: float = cos(_walk_phase) * 0.012 if speed > 0.4 else 0.0

	var rh_target_pos: Vector3 = Vector3(0.36 + bob_x, -0.3 + bob_y, -0.58)
	var rh_target_rot: Vector3 = Vector3.ZERO
	if _attack_anim_timer > 0.0:
		var t: float = sin((_attack_anim_timer / 0.35) * PI)
		rh_target_pos += Vector3(-0.16 * t, 0.08 * t, -0.22 * t)
		rh_target_rot = Vector3(-52.0 * t, 28.0 * t, 32.0 * t)

	var lh_target_pos: Vector3 = Vector3(-0.38 - bob_x, -0.34 + bob_y, -0.55)
	var lh_target_rot: Vector3 = Vector3.ZERO
	if is_blocking:
		lh_target_pos = Vector3(-0.14, -0.14, -0.46)
		lh_target_rot = Vector3(8.0, 24.0, -12.0)

	rh.position = rh.position.lerp(rh_target_pos, clampf(delta * 18.0, 0.0, 1.0))
	rh.rotation_degrees = rh.rotation_degrees.lerp(rh_target_rot, clampf(delta * 18.0, 0.0, 1.0))
	lh.position = lh.position.lerp(lh_target_pos, clampf(delta * 16.0, 0.0, 1.0))
	lh.rotation_degrees = lh.rotation_degrees.lerp(lh_target_rot, clampf(delta * 16.0, 0.0, 1.0))


func _animate_humanoid(delta: float) -> void:
	var leg_l: Node3D = _rig.get("leg_l", null) as Node3D
	var leg_r: Node3D = _rig.get("leg_r", null) as Node3D
	var arm_l: Node3D = _rig.get("arm_l", null) as Node3D
	var arm_r: Node3D = _rig.get("arm_r", null) as Node3D
	var torso: Node3D = _rig.get("torso", null) as Node3D
	var cape: Node3D = _rig.get("cape", null) as Node3D
	var body_pivot: Node3D = _rig.get("body_pivot", null) as Node3D

	if leg_l == null or arm_r == null or body_pivot == null:
		return

	var horiz_speed: float = Vector2(velocity.x, velocity.z).length() if is_local else _net_anim_speed
	var attacking: bool = (_attack_anim_timer > 0.0) if is_local else _net_attacking

	if is_mounted:
		leg_l.rotation_degrees = Vector3(-55.0, 0.0, -24.0)
		leg_r.rotation_degrees = Vector3(-55.0, 0.0, 24.0)
		arm_l.rotation_degrees = Vector3(-35.0, 0.0, 0.0)
		arm_r.rotation_degrees = Vector3(-35.0, 0.0, 0.0)
		body_pivot.rotation_degrees.x = 0.0
		if cape != null:
			cape.rotation_degrees.x = 32.0 + sin(Time.get_ticks_msec() * 0.01) * 8.0
		return

	if is_dodging:
		body_pivot.rotation_degrees.x = lerpf(body_pivot.rotation_degrees.x, -42.0, delta * 18.0)
	else:
		body_pivot.rotation_degrees.x = lerpf(body_pivot.rotation_degrees.x, 0.0, delta * 12.0)

	if horiz_speed > 0.35:
		_walk_phase += delta * clampf(horiz_speed * 1.45, 5.0, 14.0)
		var swing: float = sin(_walk_phase) * 34.0
		leg_l.rotation_degrees = Vector3(swing, 0.0, 0.0)
		leg_r.rotation_degrees = Vector3(-swing, 0.0, 0.0)
		if not attacking and not is_blocking:
			arm_l.rotation_degrees = Vector3(-swing * 0.7, 0.0, 0.0)
			arm_r.rotation_degrees = Vector3(swing * 0.7, 0.0, 0.0)
		if cape != null:
			cape.rotation_degrees.x = clampf(horiz_speed * 3.8, 8.0, 42.0) + sin(_walk_phase * 2.0) * 5.0
	else:
		leg_l.rotation_degrees = leg_l.rotation_degrees.lerp(Vector3.ZERO, delta * 10.0)
		leg_r.rotation_degrees = leg_r.rotation_degrees.lerp(Vector3.ZERO, delta * 10.0)
		if not attacking and not is_blocking:
			arm_l.rotation_degrees = arm_l.rotation_degrees.lerp(Vector3.ZERO, delta * 10.0)
			arm_r.rotation_degrees = arm_r.rotation_degrees.lerp(Vector3.ZERO, delta * 10.0)
		if cape != null:
			cape.rotation_degrees.x = lerpf(cape.rotation_degrees.x, 4.0, delta * 6.0)

	if is_blocking:
		arm_l.rotation_degrees = Vector3(-72.0, 35.0, 0.0)
	if attacking:
		var slash_t: float = sin((_attack_anim_timer / 0.35) * PI) if is_local else 1.0
		arm_r.rotation_degrees = Vector3(-115.0 * slash_t, -25.0 * slash_t, 0.0)
		if torso != null:
			torso.rotation_degrees.y = 18.0 * slash_t
	elif torso != null:
		torso.rotation_degrees.y = lerpf(torso.rotation_degrees.y, 0.0, delta * 10.0)
