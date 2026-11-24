class_name ProceduralMeshFactory
extends RefCounted

## Builds articulated 3D humanoid rigs, animated dragons, medieval buildings,
## resource nodes, and loot chests purely from Godot 4 primitive meshes and shaders.

const SHADER_GRACE_AURA: Shader = preload("res://Client/Shaders/combat_grace_aura.gdshader")
const SHADER_DRAGON_FIRE: Shader = preload("res://Client/Shaders/dragon_fire.gdshader")


static func make_pbr_material(color: Color, roughness: float = 0.65, metallic: float = 0.0, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat


static func make_grace_aura_material(is_chaos: bool = false) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER_GRACE_AURA
	if is_chaos:
		mat.set_shader_parameter("primary_color", Color(1.0, 0.35, 0.14, 1.0))
		mat.set_shader_parameter("secondary_color", Color(1.0, 0.82, 0.35, 1.0))
	else:
		mat.set_shader_parameter("primary_color", Color(1.0, 0.86, 0.28, 1.0))
		mat.set_shader_parameter("secondary_color", Color(0.88, 0.96, 1.0, 1.0))
	return mat


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, node_name: String = "Box") -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _add_cylinder(parent: Node3D, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material, node_name: String = "Cyl", radial_segments: int = 10) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _add_sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, node_name: String = "Sphere", segments: int = 12) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(6, segments / 2)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func build_humanoid_rig(root: Node3D, class_id: String, armor_skin_id: String) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var skin: Dictionary = GameConfig.COSMETIC_ARMORS.get(armor_skin_id, GameConfig.COSMETIC_ARMORS["default_iron"]) as Dictionary
	var class_def: Dictionary = GameConfig.CLASSES.get(class_id, GameConfig.CLASSES["ARCANE_KNIGHT"]) as Dictionary
	var primary_mat: StandardMaterial3D = make_pbr_material(
		skin.get("primary", Color(0.5, 0.5, 0.55)) as Color,
		float(skin.get("roughness", 0.4)),
		float(skin.get("metallic", 0.65))
	)
	var secondary_mat: StandardMaterial3D = make_pbr_material(
		skin.get("secondary", Color(0.25, 0.22, 0.22)) as Color,
		0.72,
		0.2
	)
	var trim_mat: StandardMaterial3D = make_pbr_material(
		skin.get("trim", Color(0.8, 0.72, 0.42)) as Color,
		0.3,
		0.8
	)
	var accent: Color = class_def.get("accent_color", Color(0.3, 0.7, 1.0)) as Color
	var glow_mat: StandardMaterial3D = make_pbr_material(accent, 0.2, 0.2, accent, 1.8)
	var skin_mat: StandardMaterial3D = make_pbr_material(Color(0.84, 0.68, 0.56), 0.75, 0.0)

	var body_pivot: Node3D = Node3D.new()
	body_pivot.name = "BodyPivot"
	root.add_child(body_pivot)

	# Torso / Chestplate
	var torso: Node3D = Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0.0, 1.15, 0.0)
	body_pivot.add_child(torso)
	_add_box(torso, Vector3(0.54, 0.68, 0.34), Vector3(0.0, 0.0, 0.0), primary_mat, "Chestplate")
	_add_box(torso, Vector3(0.58, 0.14, 0.38), Vector3(0.0, -0.28, 0.0), trim_mat, "Belt")
	_add_box(torso, Vector3(0.22, 0.24, 0.05), Vector3(0.0, 0.06, -0.18), glow_mat, "ClassCrest")

	# Cape
	var cape: Node3D = Node3D.new()
	cape.name = "Cape"
	cape.position = Vector3(0.0, 0.28, 0.19)
	torso.add_child(cape)
	_add_box(cape, Vector3(0.52, 0.95, 0.05), Vector3(0.0, -0.46, 0.04), secondary_mat, "CapeCloth")

	# Head + Helmet
	var head: Node3D = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.52, 0.0)
	torso.add_child(head)
	_add_sphere(head, 0.2, Vector3(0.0, 0.05, 0.0), skin_mat, "Face")
	_add_box(head, Vector3(0.42, 0.36, 0.42), Vector3(0.0, 0.1, 0.02), primary_mat, "Helm")
	_add_box(head, Vector3(0.32, 0.07, 0.06), Vector3(0.0, 0.06, -0.21), glow_mat, "VisorGlow")

	# Divine Avatar Crown (hidden unless creator avatar activates divine descent)
	var divine_crown: Node3D = Node3D.new()
	divine_crown.name = "DivineCrown"
	divine_crown.position = Vector3(0.0, 0.42, 0.0)
	divine_crown.visible = false
	head.add_child(divine_crown)
	var crown_mat: StandardMaterial3D = make_pbr_material(Color(1.0, 0.88, 0.35), 0.15, 0.9, Color(1.0, 0.85, 0.3), 2.5)
	_add_cylinder(divine_crown, 0.34, 0.34, 0.06, Vector3.ZERO, crown_mat, "HaloRing", 16)
	_add_box(divine_crown, Vector3(0.08, 0.28, 0.08), Vector3(0.0, 0.14, -0.26), crown_mat, "CrownSpire")

	# Left & Right Arms with Pauldrons
	var arm_l: Node3D = Node3D.new()
	arm_l.name = "ArmL"
	arm_l.position = Vector3(-0.37, 0.24, 0.0)
	torso.add_child(arm_l)
	_add_sphere(arm_l, 0.15, Vector3(0.0, 0.04, 0.0), trim_mat, "PauldronL")
	_add_box(arm_l, Vector3(0.18, 0.56, 0.18), Vector3(0.0, -0.28, 0.0), primary_mat, "ArmMeshL")

	var arm_r: Node3D = Node3D.new()
	arm_r.name = "ArmR"
	arm_r.position = Vector3(0.37, 0.24, 0.0)
	torso.add_child(arm_r)
	_add_sphere(arm_r, 0.15, Vector3(0.0, 0.04, 0.0), trim_mat, "PauldronR")
	_add_box(arm_r, Vector3(0.18, 0.56, 0.18), Vector3(0.0, -0.28, 0.0), primary_mat, "ArmMeshR")

	# Class Weapon & Shield Attachments
	var weapon_pivot: Node3D = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.0, -0.54, -0.1)
	arm_r.add_child(weapon_pivot)

	var shield_pivot: Node3D = Node3D.new()
	shield_pivot.name = "ShieldPivot"
	shield_pivot.position = Vector3(-0.1, -0.45, -0.12)
	arm_l.add_child(shield_pivot)

	var weapon_style: String = str(class_def.get("weapon_style", "sword_shield"))
	var steel_mat: StandardMaterial3D = make_pbr_material(Color(0.76, 0.8, 0.86), 0.25, 0.9)
	if weapon_style == "sword_shield":
		_add_box(weapon_pivot, Vector3(0.08, 0.08, 0.26), Vector3(0.0, 0.0, -0.1), trim_mat, "Hilt")
		_add_box(weapon_pivot, Vector3(0.32, 0.06, 0.08), Vector3(0.0, 0.0, -0.22), trim_mat, "Crossguard")
		_add_box(weapon_pivot, Vector3(0.09, 0.04, 1.05), Vector3(0.0, 0.0, -0.76), steel_mat, "Blade")
		_add_box(weapon_pivot, Vector3(0.04, 0.05, 0.72), Vector3(0.0, 0.0, -0.72), glow_mat, "RunicEdge")
		_add_box(shield_pivot, Vector3(0.48, 0.68, 0.09), Vector3(0.0, 0.0, -0.08), primary_mat, "ShieldBody")
		_add_box(shield_pivot, Vector3(0.18, 0.24, 0.11), Vector3(0.0, 0.05, -0.08), glow_mat, "ShieldCore")
	elif weapon_style == "staff":
		_add_cylinder(weapon_pivot, 0.04, 0.045, 1.75, Vector3(0.0, 0.12, -0.18), secondary_mat, "StaffShaft")
		_add_sphere(weapon_pivot, 0.16, Vector3(0.0, 1.05, -0.18), glow_mat, "FlameOrb")
	elif weapon_style == "mace_shield":
		_add_cylinder(weapon_pivot, 0.04, 0.04, 0.85, Vector3(0.0, 0.0, -0.42), secondary_mat, "MaceHandle")
		_add_sphere(weapon_pivot, 0.18, Vector3(0.0, 0.0, -0.88), trim_mat, "MaceHead")
		_add_box(shield_pivot, Vector3(0.52, 0.76, 0.1), Vector3(0.0, 0.0, -0.08), trim_mat, "TowerShield")
		_add_box(shield_pivot, Vector3(0.12, 0.45, 0.12), Vector3(0.0, 0.0, -0.08), glow_mat, "HolyCrossV")
	elif weapon_style == "daggers":
		_add_box(weapon_pivot, Vector3(0.05, 0.04, 0.62), Vector3(0.0, 0.0, -0.36), steel_mat, "DaggerR")
		_add_box(weapon_pivot, Vector3(0.03, 0.05, 0.42), Vector3(0.0, 0.0, -0.36), glow_mat, "DaggerEdgeR")
		_add_box(shield_pivot, Vector3(0.05, 0.04, 0.62), Vector3(0.0, 0.0, -0.36), steel_mat, "DaggerL")
		_add_box(shield_pivot, Vector3(0.03, 0.05, 0.42), Vector3(0.0, 0.0, -0.36), glow_mat, "DaggerEdgeL")

	# Left & Right Legs
	var leg_l: Node3D = Node3D.new()
	leg_l.name = "LegL"
	leg_l.position = Vector3(-0.16, 0.78, 0.0)
	body_pivot.add_child(leg_l)
	_add_box(leg_l, Vector3(0.21, 0.76, 0.22), Vector3(0.0, -0.38, 0.0), secondary_mat, "LegMeshL")
	_add_box(leg_l, Vector3(0.23, 0.24, 0.26), Vector3(0.0, -0.66, -0.02), primary_mat, "BootL")

	var leg_r: Node3D = Node3D.new()
	leg_r.name = "LegR"
	leg_r.position = Vector3(0.16, 0.78, 0.0)
	body_pivot.add_child(leg_r)
	_add_box(leg_r, Vector3(0.21, 0.76, 0.22), Vector3(0.0, -0.38, 0.0), secondary_mat, "LegMeshR")
	_add_box(leg_r, Vector3(0.23, 0.24, 0.26), Vector3(0.0, -0.66, -0.02), primary_mat, "BootR")

	# Gracia Combativa Aura Shell (hidden until active)
	var grace_aura: MeshInstance3D = MeshInstance3D.new()
	grace_aura.name = "GraceAura"
	var aura_cap: CapsuleMesh = CapsuleMesh.new()
	aura_cap.radius = 0.68
	aura_cap.height = 2.25
	grace_aura.mesh = aura_cap
	grace_aura.position = Vector3(0.0, 1.05, 0.0)
	grace_aura.material_override = make_grace_aura_material(false)
	grace_aura.visible = false
	root.add_child(grace_aura)

	return {
		"body_pivot": body_pivot,
		"torso": torso,
		"head": head,
		"cape": cape,
		"arm_l": arm_l,
		"arm_r": arm_r,
		"leg_l": leg_l,
		"leg_r": leg_r,
		"weapon_pivot": weapon_pivot,
		"shield_pivot": shield_pivot,
		"divine_crown": divine_crown,
		"grace_aura": grace_aura
	}


static func build_first_person_viewmodel(root: Node3D, class_id: String, armor_skin_id: String) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var skin: Dictionary = GameConfig.COSMETIC_ARMORS.get(armor_skin_id, GameConfig.COSMETIC_ARMORS["default_iron"]) as Dictionary
	var class_def: Dictionary = GameConfig.CLASSES.get(class_id, GameConfig.CLASSES["ARCANE_KNIGHT"]) as Dictionary
	var primary_mat: StandardMaterial3D = make_pbr_material(
		skin.get("primary", Color(0.5, 0.5, 0.55)) as Color,
		float(skin.get("roughness", 0.4)),
		float(skin.get("metallic", 0.65))
	)
	var secondary_mat: StandardMaterial3D = make_pbr_material(
		skin.get("secondary", Color(0.25, 0.22, 0.22)) as Color,
		0.72,
		0.2
	)
	var trim_mat: StandardMaterial3D = make_pbr_material(
		skin.get("trim", Color(0.8, 0.72, 0.42)) as Color,
		0.3,
		0.8
	)
	var accent: Color = class_def.get("accent_color", Color(0.3, 0.7, 1.0)) as Color
	var glow_mat: StandardMaterial3D = make_pbr_material(accent, 0.2, 0.2, accent, 2.2)
	var steel_mat: StandardMaterial3D = make_pbr_material(Color(0.78, 0.82, 0.88), 0.22, 0.9)

	var right_hand: Node3D = Node3D.new()
	right_hand.name = "FPRightHand"
	right_hand.position = Vector3(0.36, -0.3, -0.58)
	root.add_child(right_hand)
	_add_box(right_hand, Vector3(0.12, 0.12, 0.34), Vector3(0.0, -0.02, 0.14), primary_mat, "GauntletR")

	var left_hand: Node3D = Node3D.new()
	left_hand.name = "FPLeftHand"
	left_hand.position = Vector3(-0.38, -0.34, -0.55)
	root.add_child(left_hand)
	_add_box(left_hand, Vector3(0.12, 0.12, 0.34), Vector3(0.0, -0.02, 0.14), primary_mat, "GauntletL")

	var weapon_style: String = str(class_def.get("weapon_style", "sword_shield"))
	if weapon_style == "sword_shield":
		_add_box(right_hand, Vector3(0.05, 0.05, 0.2), Vector3(0.0, 0.04, -0.04), trim_mat, "FPHilt")
		_add_box(right_hand, Vector3(0.24, 0.05, 0.05), Vector3(0.0, 0.12, -0.08), trim_mat, "FPGuard")
		_add_box(right_hand, Vector3(0.06, 0.82, 0.03), Vector3(0.0, 0.52, -0.14), steel_mat, "FPBlade")
		_add_box(right_hand, Vector3(0.025, 0.58, 0.04), Vector3(0.0, 0.5, -0.14), glow_mat, "FPRune")
		_add_box(left_hand, Vector3(0.38, 0.48, 0.06), Vector3(-0.04, 0.1, -0.12), primary_mat, "FPShield")
		_add_box(left_hand, Vector3(0.12, 0.16, 0.08), Vector3(-0.04, 0.12, -0.12), glow_mat, "FPShieldCore")
	elif weapon_style == "staff":
		_add_cylinder(right_hand, 0.028, 0.032, 1.15, Vector3(0.0, 0.28, -0.14), secondary_mat, "FPStaff")
		_add_sphere(right_hand, 0.11, Vector3(0.0, 0.9, -0.14), glow_mat, "FPFireOrb")
		_add_sphere(left_hand, 0.08, Vector3(0.0, 0.08, -0.14), glow_mat, "FPMagicSpark")
	elif weapon_style == "mace_shield":
		_add_cylinder(right_hand, 0.026, 0.028, 0.65, Vector3(0.0, 0.26, -0.12), secondary_mat, "FPMaceShaft")
		_add_sphere(right_hand, 0.13, Vector3(0.0, 0.62, -0.12), trim_mat, "FPMaceHead")
		_add_box(left_hand, Vector3(0.4, 0.52, 0.07), Vector3(-0.04, 0.1, -0.12), trim_mat, "FPTowerShield")
		_add_box(left_hand, Vector3(0.09, 0.3, 0.09), Vector3(-0.04, 0.1, -0.12), glow_mat, "FPHolyCross")
	elif weapon_style == "daggers":
		_add_box(right_hand, Vector3(0.04, 0.44, 0.025), Vector3(0.0, 0.24, -0.14), steel_mat, "FPDaggerR")
		_add_box(right_hand, Vector3(0.02, 0.32, 0.03), Vector3(0.0, 0.24, -0.14), glow_mat, "FPDaggerEdgeR")
		_add_box(left_hand, Vector3(0.04, 0.44, 0.025), Vector3(0.0, 0.24, -0.14), steel_mat, "FPDaggerL")
		_add_box(left_hand, Vector3(0.02, 0.32, 0.03), Vector3(0.0, 0.24, -0.14), glow_mat, "FPDaggerEdgeL")

	return {
		"right_hand": right_hand,
		"left_hand": left_hand
	}


static func build_dragon_rig(root: Node3D, dragon_skin_id: String, trail_id: String) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var skin: Dictionary = GameConfig.COSMETIC_DRAGONS.get(dragon_skin_id, GameConfig.COSMETIC_DRAGONS["crimson_wyrm"]) as Dictionary
	var scale_mat: StandardMaterial3D = make_pbr_material(skin.get("scales", Color(0.68, 0.16, 0.14)) as Color, 0.42, 0.25)
	var belly_mat: StandardMaterial3D = make_pbr_material(skin.get("belly", Color(0.84, 0.66, 0.44)) as Color, 0.55, 0.1)
	var wing_mat: StandardMaterial3D = make_pbr_material(skin.get("wings", Color(0.45, 0.1, 0.1)) as Color, 0.6, 0.05)
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var horn_mat: StandardMaterial3D = make_pbr_material(Color(0.18, 0.16, 0.14), 0.35, 0.3)
	var eye_col: Color = skin.get("breath", Color(1.0, 0.5, 0.1)) as Color
	var eye_mat: StandardMaterial3D = make_pbr_material(eye_col, 0.1, 0.0, eye_col, 2.8)
	var saddle_mat: StandardMaterial3D = make_pbr_material(Color(0.28, 0.18, 0.1), 0.7, 0.15)

	var body: Node3D = Node3D.new()
	body.name = "DragonBody"
	root.add_child(body)

	# Main Torso + Belly + Saddle
	_add_box(body, Vector3(1.5, 1.15, 3.3), Vector3(0.0, 1.55, 0.0), scale_mat, "Torso")
	_add_box(body, Vector3(1.15, 0.42, 2.9), Vector3(0.0, 1.05, 0.05), belly_mat, "Belly")
	_add_box(body, Vector3(0.95, 0.24, 1.1), Vector3(0.0, 2.22, -0.15), saddle_mat, "RiderSaddle")
	# Dorsal Spines
	for i: int in range(4):
		_add_box(body, Vector3(0.14, 0.34, 0.36), Vector3(0.0, 2.25, -1.1 + float(i) * 0.72), horn_mat, "Spine_%d" % i)

	# Neck & Head (facing -Z forward)
	var neck: Node3D = Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0.0, 1.85, -1.55)
	body.add_child(neck)
	_add_box(neck, Vector3(0.75, 0.75, 1.45), Vector3(0.0, 0.25, -0.58), scale_mat, "NeckMesh")

	var head: Node3D = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.52, -1.3)
	neck.add_child(head)
	_add_box(head, Vector3(0.86, 0.62, 1.25), Vector3(0.0, 0.08, -0.45), scale_mat, "Skull")
	_add_box(head, Vector3(0.68, 0.26, 1.1), Vector3(0.0, -0.22, -0.45), belly_mat, "Jaw")
	_add_sphere(head, 0.11, Vector3(-0.38, 0.16, -0.62), eye_mat, "EyeL")
	_add_sphere(head, 0.11, Vector3(0.38, 0.16, -0.62), eye_mat, "EyeR")
	var horn_l: MeshInstance3D = _add_cylinder(head, 0.02, 0.12, 1.0, Vector3(-0.34, 0.48, 0.2), horn_mat, "HornL")
	horn_l.rotation_degrees = Vector3(55.0, 0.0, 18.0)
	var horn_r: MeshInstance3D = _add_cylinder(head, 0.02, 0.12, 1.0, Vector3(0.34, 0.48, 0.2), horn_mat, "HornR")
	horn_r.rotation_degrees = Vector3(55.0, 0.0, -18.0)

	# Fire Breath Cone (uses dragon_fire.gdshader)
	var breath_cone: MeshInstance3D = MeshInstance3D.new()
	breath_cone.name = "BreathCone"
	var cone_mesh: CylinderMesh = CylinderMesh.new()
	cone_mesh.top_radius = 0.25
	cone_mesh.bottom_radius = 2.6
	cone_mesh.height = 18.0
	cone_mesh.radial_segments = 12
	breath_cone.mesh = cone_mesh
	breath_cone.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	breath_cone.position = Vector3(0.0, -0.08, -10.0)
	var fire_mat: ShaderMaterial = ShaderMaterial.new()
	fire_mat.shader = SHADER_DRAGON_FIRE
	fire_mat.set_shader_parameter("flame_color", eye_col)
	fire_mat.set_shader_parameter("core_color", eye_col.lightened(0.65))
	breath_cone.material_override = fire_mat
	breath_cone.visible = false
	head.add_child(breath_cone)

	# Articulated Tail
	var tail_1: Node3D = Node3D.new()
	tail_1.name = "Tail1"
	tail_1.position = Vector3(0.0, 1.45, 1.65)
	body.add_child(tail_1)
	_add_box(tail_1, Vector3(0.66, 0.56, 2.0), Vector3(0.0, -0.05, 0.95), scale_mat, "TailSeg1")

	var tail_2: Node3D = Node3D.new()
	tail_2.name = "Tail2"
	tail_2.position = Vector3(0.0, -0.05, 1.95)
	tail_1.add_child(tail_2)
	_add_box(tail_2, Vector3(0.36, 0.3, 2.1), Vector3(0.0, 0.0, 1.0), scale_mat, "TailSeg2")
	_add_box(tail_2, Vector3(0.75, 0.1, 0.75), Vector3(0.0, 0.0, 2.1), horn_mat, "TailFin")

	# Legs
	for leg_pos: Vector3 in [
		Vector3(-0.75, 0.75, -0.95),
		Vector3(0.75, 0.75, -0.95),
		Vector3(-0.78, 0.75, 0.95),
		Vector3(0.78, 0.75, 0.95)
	]:
		_add_box(body, Vector3(0.38, 1.35, 0.44), leg_pos, scale_mat, "Leg")

	# Articulated Left & Right Wings (2 segments each for majestic flapping)
	var wing_l_root: Node3D = Node3D.new()
	wing_l_root.name = "WingLRoot"
	wing_l_root.position = Vector3(-0.72, 1.95, -0.35)
	body.add_child(wing_l_root)
	_add_box(wing_l_root, Vector3(2.8, 0.14, 0.26), Vector3(-1.4, 0.0, -0.4), scale_mat, "WingSparL1")
	_add_box(wing_l_root, Vector3(2.8, 0.05, 2.2), Vector3(-1.4, -0.02, 0.65), wing_mat, "WingMemL1")

	var wing_l_tip: Node3D = Node3D.new()
	wing_l_tip.name = "WingLTip"
	wing_l_tip.position = Vector3(-2.75, 0.0, -0.35)
	wing_l_root.add_child(wing_l_tip)
	_add_box(wing_l_tip, Vector3(3.1, 0.1, 0.2), Vector3(-1.55, 0.0, 0.0), scale_mat, "WingSparL2")
	_add_box(wing_l_tip, Vector3(3.0, 0.04, 1.9), Vector3(-1.5, -0.02, 0.95), wing_mat, "WingMemL2")

	var wing_r_root: Node3D = Node3D.new()
	wing_r_root.name = "WingRRoot"
	wing_r_root.position = Vector3(0.72, 1.95, -0.35)
	body.add_child(wing_r_root)
	_add_box(wing_r_root, Vector3(2.8, 0.14, 0.26), Vector3(1.4, 0.0, -0.4), scale_mat, "WingSparR1")
	_add_box(wing_r_root, Vector3(2.8, 0.05, 2.2), Vector3(1.4, -0.02, 0.65), wing_mat, "WingMemR1")

	var wing_r_tip: Node3D = Node3D.new()
	wing_r_tip.name = "WingRTip"
	wing_r_tip.position = Vector3(2.75, 0.0, -0.35)
	wing_r_root.add_child(wing_r_tip)
	_add_box(wing_r_tip, Vector3(3.1, 0.1, 0.2), Vector3(1.55, 0.0, 0.0), scale_mat, "WingSparR2")
	_add_box(wing_r_tip, Vector3(3.0, 0.04, 1.9), Vector3(1.5, -0.02, 0.95), wing_mat, "WingMemR2")

	# Cosmetic Flight Trail (CPUParticles3D - Vega 8 friendly!)
	var trail: CPUParticles3D = CPUParticles3D.new()
	trail.name = "CosmeticTrail"
	trail.position = Vector3(0.0, 1.5, 2.4)
	var trail_def: Dictionary = GameConfig.COSMETIC_TRAILS.get(trail_id, GameConfig.COSMETIC_TRAILS["none"]) as Dictionary
	var trail_color: Color = trail_def.get("color", Color(1, 1, 1, 0)) as Color
	trail.emitting = trail_id != "none" and trail_color.a > 0.05
	trail.amount = 24
	trail.lifetime = 0.85
	trail.direction = Vector3(0.0, 0.0, 1.0)
	trail.spread = 18.0
	trail.initial_velocity_min = 1.5
	trail.initial_velocity_max = 3.5
	trail.gravity = Vector3.ZERO
	var trail_mesh: SphereMesh = SphereMesh.new()
	trail_mesh.radius = 0.22
	trail_mesh.height = 0.44
	trail_mesh.radial_segments = 6
	trail_mesh.rings = 4
	trail.mesh = trail_mesh
	var trail_mat: StandardMaterial3D = make_pbr_material(trail_color, 0.2, 0.0, trail_color, 2.0)
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = trail_mat
	body.add_child(trail)

	# Gracia Combativa Aura on Dragon
	var grace_aura: MeshInstance3D = MeshInstance3D.new()
	grace_aura.name = "DragonGraceAura"
	var aura_sphere: SphereMesh = SphereMesh.new()
	aura_sphere.radius = 2.85
	aura_sphere.height = 3.6
	aura_sphere.radial_segments = 16
	aura_sphere.rings = 10
	grace_aura.mesh = aura_sphere
	grace_aura.position = Vector3(0.0, 1.65, -0.2)
	grace_aura.scale = Vector3(1.1, 0.75, 1.55)
	grace_aura.material_override = make_grace_aura_material(false)
	grace_aura.visible = false
	body.add_child(grace_aura)

	return {
		"body": body,
		"neck": neck,
		"head": head,
		"tail_1": tail_1,
		"tail_2": tail_2,
		"wing_l_root": wing_l_root,
		"wing_l_tip": wing_l_tip,
		"wing_r_root": wing_r_root,
		"wing_r_tip": wing_r_tip,
		"breath_cone": breath_cone,
		"trail": trail,
		"grace_aura": grace_aura
	}


static func build_structure_visual(root: Node3D, piece_type: String, is_ghost: bool = false, valid_ghost: bool = true) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var spec: Dictionary = GameConfig.BUILD_PIECES.get(piece_type, GameConfig.BUILD_PIECES["wall"]) as Dictionary
	var base_col: Color = spec.get("color", Color(0.55, 0.55, 0.58)) as Color
	var stone_mat: StandardMaterial3D = make_pbr_material(base_col, 0.85, 0.05)
	var wood_mat: StandardMaterial3D = make_pbr_material(Color(0.42, 0.28, 0.16), 0.8, 0.0)
	var trim_mat: StandardMaterial3D = make_pbr_material(Color(0.32, 0.34, 0.38), 0.6, 0.4)

	if is_ghost:
		var gcol: Color = Color(0.25, 0.9, 0.45, 0.48) if valid_ghost else Color(0.95, 0.22, 0.22, 0.48)
		stone_mat = make_pbr_material(gcol, 0.4, 0.0, gcol, 0.8)
		stone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wood_mat = stone_mat
		trim_mat = stone_mat

	var door_pivot: Node3D = null
	var sigil_node: Node3D = null

	if piece_type == "wall":
		_add_box(root, Vector3(6.0, 4.2, 1.3), Vector3(0.0, 2.1, 0.0), stone_mat, "WallBody")
		for i: int in range(4):
			_add_box(root, Vector3(1.0, 0.65, 1.35), Vector3(-2.25 + float(i) * 1.5, 4.5, 0.0), stone_mat, "Merlon_%d" % i)
		_add_box(root, Vector3(0.5, 2.2, 1.7), Vector3(-2.6, 1.1, 0.0), trim_mat, "ButtressL")
		_add_box(root, Vector3(0.5, 2.2, 1.7), Vector3(2.6, 1.1, 0.0), trim_mat, "ButtressR")

	elif piece_type == "gate":
		_add_box(root, Vector3(1.4, 4.8, 1.5), Vector3(-2.3, 2.4, 0.0), stone_mat, "PillarL")
		_add_box(root, Vector3(1.4, 4.8, 1.5), Vector3(2.3, 2.4, 0.0), stone_mat, "PillarR")
		_add_box(root, Vector3(6.0, 1.1, 1.6), Vector3(0.0, 4.55, 0.0), stone_mat, "ArchTop")
		door_pivot = Node3D.new()
		door_pivot.name = "DoorPivot"
		door_pivot.position = Vector3(-1.55, 0.0, 0.0)
		root.add_child(door_pivot)
		_add_box(door_pivot, Vector3(3.1, 3.9, 0.28), Vector3(1.55, 1.95, 0.0), wood_mat, "GateDoor")
		_add_box(door_pivot, Vector3(3.15, 0.22, 0.34), Vector3(1.55, 1.1, 0.0), trim_mat, "IronBand1")
		_add_box(door_pivot, Vector3(3.15, 0.22, 0.34), Vector3(1.55, 2.8, 0.0), trim_mat, "IronBand2")

	elif piece_type == "tower":
		_add_box(root, Vector3(3.8, 8.2, 3.8), Vector3(0.0, 4.1, 0.0), stone_mat, "TowerShaft")
		_add_box(root, Vector3(4.5, 0.6, 4.5), Vector3(0.0, 8.4, 0.0), trim_mat, "TowerDeck")
		for corner: Vector3 in [Vector3(-1.9, 9.0, -1.9), Vector3(1.9, 9.0, -1.9), Vector3(-1.9, 9.0, 1.9), Vector3(1.9, 9.0, 1.9)]:
			_add_box(root, Vector3(0.7, 0.85, 0.7), corner, stone_mat, "CornerParapet")
		var beacon_mat: StandardMaterial3D = make_pbr_material(Color(1.0, 0.72, 0.22), 0.2, 0.0, Color(1.0, 0.6, 0.12), 2.5) if not is_ghost else stone_mat
		_add_sphere(root, 0.38, Vector3(0.0, 9.1, 0.0), beacon_mat, "WatchBeacon")

	elif piece_type == "altar_order" or piece_type == "altar_chaos":
		var is_order: bool = piece_type == "altar_order"
		var sigil_col: Color = Color(1.0, 0.86, 0.35) if is_order else Color(1.0, 0.25, 0.14)
		var sigil_mat: StandardMaterial3D = make_pbr_material(sigil_col, 0.15, 0.5, sigil_col, 2.4) if not is_ghost else stone_mat
		_add_cylinder(root, 1.8, 2.1, 0.5, Vector3(0.0, 0.25, 0.0), stone_mat, "DaisBase", 8)
		_add_cylinder(root, 1.2, 1.4, 0.5, Vector3(0.0, 0.75, 0.0), trim_mat, "DaisMid", 8)
		_add_box(root, Vector3(0.8, 1.6, 0.8), Vector3(0.0, 1.75, 0.0), stone_mat, "Pillar")
		sigil_node = Node3D.new()
		sigil_node.name = "SigilPivot"
		sigil_node.position = Vector3(0.0, 3.15, 0.0)
		root.add_child(sigil_node)
		var crystal: MeshInstance3D = _add_box(sigil_node, Vector3(0.62, 0.62, 0.62), Vector3.ZERO, sigil_mat, "SigilCrystal")
		crystal.rotation_degrees = Vector3(45.0, 45.0, 0.0)

	elif piece_type == "trade_post":
		_add_box(root, Vector3(4.4, 0.25, 3.2), Vector3(0.0, 0.12, 0.0), stone_mat, "Floor")
		_add_box(root, Vector3(3.8, 1.1, 0.9), Vector3(0.0, 0.75, -0.7), wood_mat, "Counter")
		for post_pos: Vector3 in [Vector3(-1.9, 1.7, -1.3), Vector3(1.9, 1.7, -1.3), Vector3(-1.9, 1.7, 1.3), Vector3(1.9, 1.7, 1.3)]:
			_add_box(root, Vector3(0.22, 3.2, 0.22), post_pos, wood_mat, "Post")
		var awning_mat: StandardMaterial3D = make_pbr_material(Color(0.78, 0.22, 0.18), 0.7, 0.0) if not is_ghost else stone_mat
		var awning: MeshInstance3D = _add_box(root, Vector3(4.6, 0.18, 3.6), Vector3(0.0, 3.35, 0.0), awning_mat, "Awning")
		awning.rotation_degrees = Vector3(8.0, 0.0, 0.0)
		_add_box(root, Vector3(0.75, 0.75, 0.75), Vector3(-1.2, 0.62, 0.7), wood_mat, "Crate1")
		_add_box(root, Vector3(0.65, 0.65, 0.65), Vector3(1.1, 0.57, 0.6), wood_mat, "Crate2")

	return {"door_pivot": door_pivot, "sigil_node": sigil_node}


static func build_resource_visual(root: Node3D, resource_type: String) -> void:
	for child: Node in root.get_children():
		child.queue_free()

	if resource_type == "wood":
		var bark_mat: StandardMaterial3D = make_pbr_material(Color(0.32, 0.21, 0.13), 0.9, 0.0)
		var leaf_mat: StandardMaterial3D = make_pbr_material(Color(0.16, 0.36, 0.17), 0.82, 0.0)
		_add_cylinder(root, 0.22, 0.35, 3.0, Vector3(0.0, 1.5, 0.0), bark_mat, "Trunk", 7)
		_add_cylinder(root, 0.05, 1.7, 2.8, Vector3(0.0, 3.6, 0.0), leaf_mat, "Foliage1", 8)
		_add_cylinder(root, 0.05, 1.3, 2.3, Vector3(0.0, 5.1, 0.0), leaf_mat, "Foliage2", 8)
	elif resource_type == "stone":
		var rock_mat: StandardMaterial3D = make_pbr_material(Color(0.46, 0.47, 0.5), 0.88, 0.05)
		var b1: MeshInstance3D = _add_box(root, Vector3(1.8, 1.25, 1.6), Vector3(0.0, 0.55, 0.0), rock_mat, "Boulder1")
		b1.rotation_degrees = Vector3(12.0, 24.0, -8.0)
		var b2: MeshInstance3D = _add_box(root, Vector3(1.1, 0.9, 1.2), Vector3(0.85, 0.4, 0.45), rock_mat, "Boulder2")
		b2.rotation_degrees = Vector3(-15.0, 48.0, 14.0)
	else:
		# arcane_ore
		var rock_mat: StandardMaterial3D = make_pbr_material(Color(0.24, 0.24, 0.3), 0.8, 0.1)
		var crystal_mat: StandardMaterial3D = make_pbr_material(Color(0.32, 0.78, 1.0), 0.15, 0.3, Color(0.24, 0.68, 1.0), 2.2)
		_add_box(root, Vector3(1.5, 0.7, 1.5), Vector3(0.0, 0.3, 0.0), rock_mat, "OreBase")
		var c1: MeshInstance3D = _add_cylinder(root, 0.04, 0.28, 1.9, Vector3(0.0, 1.1, 0.0), crystal_mat, "Crystal1", 6)
		c1.rotation_degrees = Vector3(8.0, 0.0, -10.0)
		var c2: MeshInstance3D = _add_cylinder(root, 0.03, 0.2, 1.4, Vector3(0.45, 0.85, 0.25), crystal_mat, "Crystal2", 6)
		c2.rotation_degrees = Vector3(-14.0, 15.0, 22.0)
		var c3: MeshInstance3D = _add_cylinder(root, 0.03, 0.2, 1.3, Vector3(-0.42, 0.8, -0.2), crystal_mat, "Crystal3", 6)
		c3.rotation_degrees = Vector3(18.0, -20.0, -20.0)


static func build_loot_chest_visual(root: Node3D) -> void:
	for child: Node in root.get_children():
		child.queue_free()
	var wood_mat: StandardMaterial3D = make_pbr_material(Color(0.38, 0.22, 0.12), 0.75, 0.05)
	var gold_mat: StandardMaterial3D = make_pbr_material(Color(0.95, 0.78, 0.24), 0.28, 0.85, Color(0.95, 0.75, 0.2), 0.6)
	_add_box(root, Vector3(1.05, 0.62, 0.72), Vector3(0.0, 0.31, 0.0), wood_mat, "ChestBase")
	_add_box(root, Vector3(1.1, 0.12, 0.76), Vector3(0.0, 0.62, 0.0), gold_mat, "ChestTrim")
	_add_box(root, Vector3(0.16, 0.22, 0.08), Vector3(0.0, 0.45, -0.38), gold_mat, "ChestLock")
	# Vertical beam marker so loot corpses are easy to spot after PvP kills
	var beam_mat: StandardMaterial3D = make_pbr_material(Color(1.0, 0.82, 0.32, 0.35), 0.2, 0.0, Color(1.0, 0.8, 0.25), 1.4)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add_cylinder(root, 0.12, 0.18, 3.2, Vector3(0.0, 2.0, 0.0), beam_mat, "LootBeacon", 8)
