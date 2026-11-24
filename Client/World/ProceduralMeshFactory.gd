class_name ProceduralMeshFactory
extends RefCounted

## Sculpted organic 3D mesh & PBR material factory (Release 1.1 Visual Overhaul).
## - ZERO BoxMesh on Dragons or Character bodies/limbs: uses lofted SurfaceTool ArrayMeshes,
##   CapsuleMesh, tapered CylinderMesh, SphereMesh, TorusMesh, and PrismMesh.
## - Automatic .glb loader for res://Assets/Models/player_*.glb and dragon.glb.
## - Character visual root oriented with ModelOrient rotation.y = PI (+Z glTF standard -> -Z forward).

const SHADER_GRACE_AURA: Shader = preload("res://Client/Shaders/combat_grace_aura.gdshader")
const SHADER_DRAGON_FIRE: Shader = preload("res://Client/Shaders/dragon_fire.gdshader")
const TEX_STONE_ALBEDO: Texture2D = preload("res://Assets/Textures/stone_albedo.jpg")
const TEX_STONE_NORMAL: Texture2D = preload("res://Assets/Textures/stone_normal.jpg")
const TEX_STONE_ROUGH: Texture2D = preload("res://Assets/Textures/stone_roughness.jpg")


static func make_stone_pbr_material(tint: Color = Color(0.95, 0.95, 0.95)) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = TEX_STONE_ALBEDO
	mat.normal_enabled = true
	mat.normal_texture = TEX_STONE_NORMAL
	mat.roughness_texture = TEX_STONE_ROUGH
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	return mat


static func _find_child_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for c: Node in node.get_children():
		var found: Node = _find_child_of_type(c, type_name)
		if found != null:
			return found
	return null


static func make_pbr_material(
	color: Color,
	roughness: float = 0.55,
	metallic: float = 0.0,
	emission: Color = Color(0, 0, 0),
	emission_energy: float = 0.0
) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat


static func make_wing_membrane_material(wing_color: Color, backlight_color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = wing_color
	mat.roughness = 0.52
	mat.metallic = 0.04
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.backlight_enabled = true
	mat.backlight = backlight_color
	mat.subsurf_scatter_enabled = true
	mat.subsurf_scatter_strength = 0.55
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


# --- Smooth Primitive & Lofted SurfaceTool Helpers ---

static func _add_capsule(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, node_name: String = "Cap", rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0 + 0.02)
	mesh.radial_segments = 14
	mesh.rings = 6
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _add_cylinder(parent: Node3D, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material, node_name: String = "Cyl", radial_segments: int = 14, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = 2
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _add_sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, node_name: String = "Sphere", scale_vec: Vector3 = Vector3.ONE, segments: int = 16) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(8, segments / 2)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale_vec
	parent.add_child(mi)
	return mi


static func _add_torus(parent: Node3D, inner_r: float, outer_r: float, pos: Vector3, mat: Material, node_name: String = "Torus", rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	var mesh: TorusMesh = TorusMesh.new()
	mesh.inner_radius = inner_r
	mesh.outer_radius = outer_r
	mesh.rings = 18
	mesh.ring_segments = 10
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _add_prism(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, node_name: String = "Prism", rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	var mesh: PrismMesh = PrismMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, node_name: String = "Box", rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## Lofts an organic smooth-shaded tube mesh from elliptical cross-section rings:
## Each ring dict: {"pos": Vector3, "rx": float, "ry": float}
static func make_lofted_tube_mesh(rings: Array, radial_segs: int = 14) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)

	var ring_verts: Array = []
	var ring_count: int = rings.size()
	for r_idx: int in range(ring_count):
		var r: Dictionary = rings[r_idx] as Dictionary
		var p: Vector3 = r["pos"] as Vector3
		var rx: float = float(r["rx"])
		var ry: float = float(r["ry"])

		var tangent: Vector3
		if r_idx == 0 and ring_count > 1:
			tangent = ((rings[1] as Dictionary)["pos"] as Vector3 - p).normalized()
		elif r_idx == ring_count - 1 and ring_count > 1:
			tangent = (p - (rings[r_idx - 1] as Dictionary)["pos"] as Vector3).normalized()
		else:
			tangent = ((rings[r_idx + 1] as Dictionary)["pos"] as Vector3 - (rings[r_idx - 1] as Dictionary)["pos"] as Vector3).normalized()
		if tangent.length_squared() < 0.001:
			tangent = Vector3.FORWARD

		var up_ref: Vector3 = Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.94 else Vector3.RIGHT
		var side: Vector3 = tangent.cross(up_ref).normalized()
		var up: Vector3 = side.cross(tangent).normalized()

		var pts: Array[Vector3] = []
		for s: int in range(radial_segs + 1):
			var ang: float = (float(s) / float(radial_segs)) * TAU
			var pt: Vector3 = p + side * (cos(ang) * rx) + up * (sin(ang) * ry)
			pts.append(pt)
		ring_verts.append(pts)

	for r_idx: int in range(ring_count - 1):
		var cur: Array = ring_verts[r_idx] as Array
		var nxt: Array = ring_verts[r_idx + 1] as Array
		var v0: float = float(r_idx) / float(maxi(1, ring_count - 1))
		var v1: float = float(r_idx + 1) / float(maxi(1, ring_count - 1))
		for s: int in range(radial_segs):
			var u0: float = float(s) / float(radial_segs)
			var u1: float = float(s + 1) / float(radial_segs)
			var a: Vector3 = cur[s] as Vector3
			var b: Vector3 = cur[s + 1] as Vector3
			var c: Vector3 = nxt[s + 1] as Vector3
			var d: Vector3 = nxt[s] as Vector3
			st.set_uv(Vector2(u0, v0))
			st.add_vertex(a)
			st.set_uv(Vector2(u1, v0))
			st.add_vertex(b)
			st.set_uv(Vector2(u1, v1))
			st.add_vertex(c)

			st.set_uv(Vector2(u0, v0))
			st.add_vertex(a)
			st.set_uv(Vector2(u1, v1))
			st.add_vertex(c)
			st.set_uv(Vector2(u0, v1))
			st.add_vertex(d)

	st.index()
	st.generate_normals()
	return st.commit()


static func _add_lofted(parent: Node3D, rings: Array, mat: Material, node_name: String, segs: int = 14) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = make_lofted_tube_mesh(rings, segs)
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Curved multi-ribbed organic dragon wing membrane mesh (zero boxes)
static func _make_wing_membrane_mesh(p_root: Vector3, p_elbow: Vector3, p_tips: Array[Vector3], p_body_attach: Vector3) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)

	# Build scalloped triangular fan segments between elbow/root and trailing wing finger tips
	var chain: Array[Vector3] = []
	for pt: Vector3 in p_tips:
		chain.append(pt)
	chain.append(p_body_attach)

	for i: int in range(chain.size() - 1):
		var a: Vector3 = chain[i]
		var b: Vector3 = chain[i + 1]
		var mid: Vector3 = (a + b) * 0.5 + (p_elbow - (a + b) * 0.5) * 0.16 + Vector3(0.0, 0.14, 0.0)
		var hub: Vector3 = p_elbow if i < p_tips.size() - 1 else p_root
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(hub)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(a)
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(mid)

		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(hub)
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(mid)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(b)

	# Connect leading edge between root and elbow
	if not p_tips.is_empty():
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(p_root)
		st.set_uv(Vector2(0.5, 0.0))
		st.add_vertex(p_elbow)
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(p_body_attach)

	st.index()
	st.generate_normals()
	return st.commit()


static func _make_curved_cape_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var rows: int = 6
	var cols: int = 5
	var grid: Array[Vector3] = []
	for r: int in range(rows + 1):
		var vt: float = float(r) / float(rows)
		var y: float = -vt * 1.02
		var half_w: float = lerpf(0.24, 0.42, vt)
		var z_curve: float = -0.04 - vt * 0.16 - sin(vt * PI) * 0.05
		for c: int in range(cols + 1):
			var ut: float = float(c) / float(cols)
			var x: float = lerpf(-half_w, half_w, ut)
			var fold: float = sin(ut * PI * 3.0) * 0.025 * vt
			grid.append(Vector3(x, y, z_curve + fold))
	var stride: int = cols + 1
	for r: int in range(rows):
		for c: int in range(cols):
			var i00: int = r * stride + c
			var i10: int = i00 + 1
			var i01: int = i00 + stride
			var i11: int = i01 + 1
			st.add_vertex(grid[i00])
			st.add_vertex(grid[i10])
			st.add_vertex(grid[i11])
			st.add_vertex(grid[i00])
			st.add_vertex(grid[i11])
			st.add_vertex(grid[i01])
	st.index()
	st.generate_normals()
	return st.commit()


static func _make_heraldic_shield_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var center_front: Vector3 = Vector3(0.0, 0.04, 0.11)
	var center_back: Vector3 = Vector3(0.0, 0.04, -0.04)
	var rim: Array[Vector3] = [
		Vector3(0.0, 0.36, 0.04),
		Vector3(0.26, 0.3, 0.0),
		Vector3(0.24, -0.02, 0.0),
		Vector3(0.14, -0.26, 0.02),
		Vector3(0.0, -0.4, 0.04),
		Vector3(-0.14, -0.26, 0.02),
		Vector3(-0.24, -0.02, 0.0),
		Vector3(-0.26, 0.3, 0.0)
	]
	for i: int in range(rim.size()):
		var a: Vector3 = rim[i]
		var b: Vector3 = rim[(i + 1) % rim.size()]
		st.add_vertex(center_front)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(center_back)
		st.add_vertex(b)
		st.add_vertex(a)
	st.index()
	st.generate_normals()
	return st.commit()


static func _try_load_external_glb(res_path: String) -> Node3D:
	if not ResourceLoader.exists(res_path):
		return null
	var packed: PackedScene = load(res_path) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	if inst is Node3D:
		return inst as Node3D
	inst.queue_free()
	return null


# --- Sculpted Stylized Medieval Characters (+ Auto .glb Loader) ---

static func build_humanoid_rig(root: Node3D, class_id: String, armor_skin_id: String, race_id: String = "HUMAN_VALLEY", appearance: Dictionary = {}) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var skin: Dictionary = GameConfig.COSMETIC_ARMORS.get(armor_skin_id, GameConfig.COSMETIC_ARMORS["default_iron"]) as Dictionary
	var class_def: Dictionary = GameConfig.CLASSES.get(class_id, GameConfig.CLASSES["ARCANE_KNIGHT"]) as Dictionary
	var race_def: Dictionary = GameConfig.RACES.get(race_id, GameConfig.RACES["HUMAN_VALLEY"]) as Dictionary
	var race_scale_y: float = float(race_def.get("scale_y", 1.0))

	var primary_mat: StandardMaterial3D = make_pbr_material(
		skin.get("primary", Color(0.5, 0.52, 0.58)) as Color,
		float(skin.get("roughness", 0.36)),
		float(skin.get("metallic", 0.72))
	)
	var secondary_mat: StandardMaterial3D = make_pbr_material(
		skin.get("secondary", Color(0.22, 0.19, 0.2)) as Color,
		0.76,
		0.15
	)
	secondary_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var trim_mat: StandardMaterial3D = make_pbr_material(
		skin.get("trim", Color(0.86, 0.74, 0.38)) as Color,
		0.25,
		0.88
	)
	var accent: Color = class_def.get("accent_color", Color(0.3, 0.7, 1.0)) as Color
	var glow_mat: StandardMaterial3D = make_pbr_material(accent, 0.15, 0.1, accent, 2.4)
	var skin_hex: String = str(appearance.get("skin_color", ""))
	var skin_col: Color = Color.html(skin_hex) if skin_hex.length() >= 6 else (race_def.get("default_skin", Color(0.84, 0.68, 0.56)) as Color)
	var skin_mat: StandardMaterial3D = make_pbr_material(skin_col, 0.72, 0.0)
	var steel_mat: StandardMaterial3D = make_pbr_material(Color(0.82, 0.86, 0.92), 0.2, 0.94)

	# ModelOrient rotated PI so +Z glTF/sculpted front ALWAYS faces -Z (away from 3rd-person camera)
	var body_pivot: Node3D = Node3D.new()
	body_pivot.name = "BodyPivot"
	body_pivot.rotation.y = PI
	body_pivot.scale = Vector3(1.0, race_scale_y, 1.0)
	root.add_child(body_pivot)

	# Automatic real CC0 .glb loader with Skeleton3D + AnimationPlayer (procedural kept as fallback)
	var glb_map: Dictionary = {
		"ARCANE_KNIGHT": "res://Assets/Models/player_knight.glb",
		"PYROMANCER": "res://Assets/Models/player_mage.glb",
		"WAR_CLERIC": "res://Assets/Models/player_cleric.glb",
		"SHADOW_ASSASSIN": "res://Assets/Models/player_rogue.glb",
		"VALLEY_HUNTER": "res://Assets/Models/player_ranger.glb"
	}
	var custom_glb: Node3D = _try_load_external_glb(str(glb_map.get(class_id, "")))
	if custom_glb != null:
		custom_glb.name = "ExternalGLB"
		custom_glb.scale = Vector3.ONE * 0.86
		body_pivot.add_child(custom_glb)
		var ap: AnimationPlayer = _find_child_of_type(custom_glb, "AnimationPlayer") as AnimationPlayer
		var skel: Skeleton3D = _find_child_of_type(custom_glb, "Skeleton3D") as Skeleton3D
		if ap != null and ap.has_animation("Idle"):
			var idle_anim: Animation = ap.get_animation("Idle")
			if idle_anim != null:
				idle_anim.loop_mode = Animation.LOOP_LINEAR
			ap.play("Idle")
		var divine_crown_glb: Node3D = Node3D.new()
		divine_crown_glb.name = "DivineCrown"
		divine_crown_glb.position = Vector3(0.0, 2.28, 0.0)
		divine_crown_glb.visible = false
		body_pivot.add_child(divine_crown_glb)
		var crown_mat_g: StandardMaterial3D = make_pbr_material(Color(1.0, 0.88, 0.35), 0.15, 0.92, Color(1.0, 0.85, 0.3), 2.8)
		_add_torus(divine_crown_glb, 0.28, 0.35, Vector3.ZERO, crown_mat_g, "DivineHalo")
		var aura_glb: MeshInstance3D = _build_humanoid_grace_aura(root)
		return {
			"body_pivot": body_pivot,
			"torso": custom_glb,
			"head": custom_glb,
			"anim_player": ap,
			"skeleton": skel,
			"cape": null,
			"arm_l": null,
			"arm_r": null,
			"leg_l": null,
			"leg_r": null,
			"weapon_pivot": null,
			"shield_pivot": null,
			"divine_crown": divine_crown_glb,
			"grace_aura": aura_glb
		}

	# Anatomical Sculpted Humanoid (Front = +Z inside BodyPivot, rotated PI -> -Z in World!)
	var torso: Node3D = Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0.0, 1.14, 0.0)
	body_pivot.add_child(torso)

	# Sculpted lofted anatomical cuirass / jerkin / mage robe (zero boxes!)
	if class_id == "PYROMANCER":
		# Flowing conical wizard robe with pleated lower skirt
		var robe_rings: Array = [
			{"pos": Vector3(0.0, -0.96, 0.0), "rx": 0.44, "ry": 0.4},
			{"pos": Vector3(0.0, -0.58, 0.0), "rx": 0.34, "ry": 0.3},
			{"pos": Vector3(0.0, -0.24, 0.0), "rx": 0.21, "ry": 0.18},
			{"pos": Vector3(0.0, 0.14, 0.02), "rx": 0.26, "ry": 0.2},
			{"pos": Vector3(0.0, 0.34, 0.0), "rx": 0.23, "ry": 0.17}
		]
		_add_lofted(torso, robe_rings, secondary_mat, "MageRobe", 16)
		_add_torus(torso, 0.16, 0.23, Vector3(0.0, -0.22, 0.0), trim_mat, "RobeSash")
		# Floating runic shoulder rings
		_add_torus(torso, 0.11, 0.15, Vector3(-0.38, 0.34, 0.0), glow_mat, "RuneHaloL", Vector3(24.0, 0.0, 28.0))
		_add_torus(torso, 0.11, 0.15, Vector3(0.38, 0.34, 0.0), glow_mat, "RuneHaloR", Vector3(24.0, 0.0, -28.0))
	else:
		# Sculpted athletic medieval cuirass / leather vest
		var chest_rings: Array = [
			{"pos": Vector3(0.0, -0.32, 0.0), "rx": 0.21, "ry": 0.16},
			{"pos": Vector3(0.0, -0.1, 0.01), "rx": 0.23, "ry": 0.18},
			{"pos": Vector3(0.0, 0.14, 0.03), "rx": 0.3, "ry": 0.22},
			{"pos": Vector3(0.0, 0.34, 0.01), "rx": 0.25, "ry": 0.17}
		]
		var chest_mat: Material = secondary_mat if class_id == "SHADOW_ASSASSIN" else primary_mat
		_add_lofted(torso, chest_rings, chest_mat, "SculptedCuirass", 16)
		_add_torus(torso, 0.18, 0.24, Vector3(0.0, -0.26, 0.0), trim_mat, "WaistBelt")
		_add_sphere(torso, 0.08, Vector3(0.0, 0.14, 0.22), glow_mat, "ClassGem", Vector3(1.1, 1.3, 0.45))
		if class_id == "WAR_CLERIC":
			# Sculpted golden tabard front
			_add_cylinder(torso, 0.18, 0.25, 0.56, Vector3(0.0, -0.5, 0.04), trim_mat, "Tabard", 12)
		elif class_id == "SHADOW_ASSASSIN":
			# Crossed leather bandolier sash
			_add_torus(torso, 0.21, 0.25, Vector3(0.0, 0.02, 0.01), trim_mat, "Bandolier", Vector3(0.0, 0.0, 48.0))

	# Flowing sculpted cloth cape on back (-Z in local BodyPivot, which faces camera in world!)
	var cape: Node3D = Node3D.new()
	cape.name = "Cape"
	cape.position = Vector3(0.0, 0.3, -0.16)
	torso.add_child(cape)
	var cape_mi: MeshInstance3D = MeshInstance3D.new()
	cape_mi.name = "CapeCloth"
	cape_mi.mesh = _make_curved_cape_mesh()
	cape_mi.material_override = secondary_mat
	cape.add_child(cape_mi)

	# Neck & Sculpted Head / Helmet / Wizard Hat / Rogue Cowl
	_add_cylinder(torso, 0.08, 0.1, 0.16, Vector3(0.0, 0.39, 0.0), skin_mat, "Neck", 12)
	var head: Node3D = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.54, 0.0)
	torso.add_child(head)
	_add_sphere(head, 0.18, Vector3(0.0, 0.02, 0.0), skin_mat, "HeadBase", Vector3(0.92, 1.05, 0.96))

	if class_id == "PYROMANCER":
		# Pointed medieval wizard hat with curved brim & glowing band
		_add_cylinder(head, 0.38, 0.42, 0.04, Vector3(0.0, 0.14, 0.0), secondary_mat, "HatBrim", 18)
		_add_torus(head, 0.16, 0.2, Vector3(0.0, 0.17, 0.0), glow_mat, "HatBand")
		_add_cylinder(head, 0.02, 0.19, 0.52, Vector3(0.0, 0.42, -0.06), secondary_mat, "HatCone", 14, Vector3(-16.0, 0.0, 0.0))
	elif class_id == "SHADOW_ASSASSIN":
		# Fitted sculpted hood + shadow face mask + glowing eyes
		_add_sphere(head, 0.22, Vector3(0.0, 0.05, -0.02), secondary_mat, "RogueHood", Vector3(0.98, 1.12, 1.08))
		_add_sphere(head, 0.035, Vector3(-0.07, 0.05, 0.17), glow_mat, "EyeL")
		_add_sphere(head, 0.035, Vector3(0.07, 0.05, 0.17), glow_mat, "EyeR")
	else:
		# Sculpted domed knight/paladin helm with curved visor & crest plume
		_add_sphere(head, 0.215, Vector3(0.0, 0.05, 0.0), primary_mat, "KnightHelm", Vector3(0.95, 1.08, 1.04))
		_add_torus(head, 0.15, 0.19, Vector3(0.0, 0.05, 0.04), trim_mat, "VisorRim", Vector3(90.0, 0.0, 0.0))
		_add_capsule(head, 0.03, 0.16, Vector3(0.0, 0.06, 0.19), glow_mat, "VisorGlow", Vector3(0.0, 0.0, 90.0))
		_add_capsule(head, 0.045, 0.26, Vector3(0.0, 0.27, -0.04), trim_mat, "HelmCrest", Vector3(72.0, 0.0, 0.0))

	# Divine Avatar Crown
	var divine_crown: Node3D = Node3D.new()
	divine_crown.name = "DivineCrown"
	divine_crown.position = Vector3(0.0, 0.48, 0.0)
	divine_crown.visible = false
	head.add_child(divine_crown)
	var crown_mat: StandardMaterial3D = make_pbr_material(Color(1.0, 0.88, 0.35), 0.15, 0.92, Color(1.0, 0.85, 0.3), 2.8)
	_add_torus(divine_crown, 0.26, 0.32, Vector3.ZERO, crown_mat, "DivineHalo")
	_add_cylinder(divine_crown, 0.01, 0.06, 0.28, Vector3(0.0, 0.16, 0.22), crown_mat, "CrownSpire", 8)

	# Sculpted Curved Arms & Domed Pauldrons (Zero Boxes!)
	var arm_l: Node3D = Node3D.new()
	arm_l.name = "ArmL"
	arm_l.position = Vector3(0.35, 0.25, 0.0)
	torso.add_child(arm_l)
	_add_sphere(arm_l, 0.15, Vector3(0.02, 0.04, 0.0), trim_mat, "PauldronL", Vector3(1.15, 0.88, 1.05))
	_add_capsule(arm_l, 0.085, 0.56, Vector3(0.0, -0.26, 0.0), primary_mat, "ArmCapL")

	var arm_r: Node3D = Node3D.new()
	arm_r.name = "ArmR"
	arm_r.position = Vector3(-0.35, 0.25, 0.0)
	torso.add_child(arm_r)
	_add_sphere(arm_r, 0.15, Vector3(-0.02, 0.04, 0.0), trim_mat, "PauldronR", Vector3(1.15, 0.88, 1.05))
	_add_capsule(arm_r, 0.085, 0.56, Vector3(0.0, -0.26, 0.0), primary_mat, "ArmCapR")

	# Detailed Medieval Class Weapons (pointing +Z inside BodyPivot -> -Z world forward!)
	var weapon_pivot: Node3D = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	weapon_pivot.position = Vector3(0.0, -0.52, 0.1)
	arm_r.add_child(weapon_pivot)

	var shield_pivot: Node3D = Node3D.new()
	shield_pivot.name = "ShieldPivot"
	shield_pivot.position = Vector3(0.08, -0.44, 0.12)
	arm_l.add_child(shield_pivot)

	var weapon_style: String = str(class_def.get("weapon_style", "sword_shield"))
	if weapon_style == "sword_shield":
		_add_cylinder(weapon_pivot, 0.032, 0.032, 0.26, Vector3(0.0, 0.0, 0.1), trim_mat, "Hilt", 10, Vector3(90.0, 0.0, 0.0))
		_add_sphere(weapon_pivot, 0.055, Vector3(0.0, 0.0, -0.04), trim_mat, "Pommel")
		_add_capsule(weapon_pivot, 0.035, 0.34, Vector3(0.0, 0.0, 0.22), trim_mat, "Crossguard", Vector3(0.0, 0.0, 90.0))
		# Beveled tapered longsword blade using PrismMesh
		_add_prism(weapon_pivot, Vector3(0.09, 1.05, 0.035), Vector3(0.0, 0.0, 0.76), steel_mat, "BeveledBlade", Vector3(90.0, 0.0, 0.0))
		_add_capsule(weapon_pivot, 0.018, 0.68, Vector3(0.0, 0.0, 0.68), glow_mat, "RunicEdge", Vector3(90.0, 0.0, 0.0))
		# Curved heraldic shield
		var sh_mi: MeshInstance3D = MeshInstance3D.new()
		sh_mi.name = "HeraldicShield"
		sh_mi.mesh = _make_heraldic_shield_mesh()
		sh_mi.material_override = primary_mat
		sh_mi.position = Vector3(0.04, 0.0, 0.06)
		shield_pivot.add_child(sh_mi)
		_add_sphere(shield_pivot, 0.09, Vector3(0.04, 0.04, 0.16), glow_mat, "ShieldCrest", Vector3(1.0, 1.2, 0.45))
	elif weapon_style == "staff":
		_add_cylinder(weapon_pivot, 0.032, 0.044, 1.85, Vector3(0.0, 0.18, 0.14), secondary_mat, "GnarledStaff", 10)
		_add_torus(weapon_pivot, 0.14, 0.18, Vector3(0.0, 1.15, 0.14), trim_mat, "StaffCradle", Vector3(90.0, 0.0, 0.0))
		_add_sphere(weapon_pivot, 0.13, Vector3(0.0, 1.15, 0.14), glow_mat, "ArcaneCrystal")
		_add_sphere(shield_pivot, 0.11, Vector3(0.0, -0.05, 0.12), glow_mat, "HandArcaneAura")
	elif weapon_style == "mace_shield":
		_add_cylinder(weapon_pivot, 0.034, 0.038, 0.92, Vector3(0.0, 0.0, 0.44), secondary_mat, "MaceShaft", 10, Vector3(90.0, 0.0, 0.0))
		_add_sphere(weapon_pivot, 0.15, Vector3(0.0, 0.0, 0.92), trim_mat, "MaceHead")
		_add_torus(weapon_pivot, 0.14, 0.18, Vector3(0.0, 0.0, 0.92), glow_mat, "MaceHalo")
		var sh_cleric: MeshInstance3D = MeshInstance3D.new()
		sh_cleric.name = "SanctifiedShield"
		sh_cleric.mesh = _make_heraldic_shield_mesh()
		sh_cleric.material_override = trim_mat
		sh_cleric.scale = Vector3(1.12, 1.16, 1.0)
		shield_pivot.add_child(sh_cleric)
		_add_capsule(shield_pivot, 0.035, 0.4, Vector3(0.0, 0.02, 0.14), glow_mat, "HolyEmblem")
	elif weapon_style == "daggers":
		_add_prism(weapon_pivot, Vector3(0.06, 0.62, 0.025), Vector3(0.0, 0.0, 0.36), steel_mat, "DaggerR", Vector3(90.0, 0.0, 0.0))
		_add_capsule(weapon_pivot, 0.015, 0.38, Vector3(0.0, 0.0, 0.34), glow_mat, "DaggerGlowR", Vector3(90.0, 0.0, 0.0))
		_add_prism(shield_pivot, Vector3(0.06, 0.62, 0.025), Vector3(0.0, 0.0, 0.36), steel_mat, "DaggerL", Vector3(90.0, 0.0, 0.0))
		_add_capsule(shield_pivot, 0.015, 0.38, Vector3(0.0, 0.0, 0.34), glow_mat, "DaggerGlowL", Vector3(90.0, 0.0, 0.0))

	# Sculpted Legs & Tapered Greaves (Zero Boxes!)
	var leg_l: Node3D = Node3D.new()
	leg_l.name = "LegL"
	leg_l.position = Vector3(0.15, 0.78, 0.0)
	body_pivot.add_child(leg_l)
	_add_capsule(leg_l, 0.095, 0.68, Vector3(0.0, -0.34, 0.0), secondary_mat, "LegCapL")
	_add_cylinder(leg_l, 0.11, 0.095, 0.34, Vector3(0.0, -0.58, 0.02), primary_mat, "GreaveL", 12)

	var leg_r: Node3D = Node3D.new()
	leg_r.name = "LegR"
	leg_r.position = Vector3(-0.15, 0.78, 0.0)
	body_pivot.add_child(leg_r)
	_add_capsule(leg_r, 0.095, 0.68, Vector3(0.0, -0.34, 0.0), secondary_mat, "LegCapR")
	_add_cylinder(leg_r, 0.11, 0.095, 0.34, Vector3(0.0, -0.58, 0.02), primary_mat, "GreaveR", 12)

	var grace_aura: MeshInstance3D = _build_humanoid_grace_aura(root)
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


static func _build_humanoid_grace_aura(root: Node3D) -> MeshInstance3D:
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
	return grace_aura


static func build_first_person_viewmodel(root: Node3D, class_id: String, armor_skin_id: String) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var skin: Dictionary = GameConfig.COSMETIC_ARMORS.get(armor_skin_id, GameConfig.COSMETIC_ARMORS["default_iron"]) as Dictionary
	var class_def: Dictionary = GameConfig.CLASSES.get(class_id, GameConfig.CLASSES["ARCANE_KNIGHT"]) as Dictionary
	var primary_mat: StandardMaterial3D = make_pbr_material(skin.get("primary", Color(0.5, 0.5, 0.55)) as Color, 0.35, 0.72)
	var secondary_mat: StandardMaterial3D = make_pbr_material(skin.get("secondary", Color(0.25, 0.22, 0.22)) as Color, 0.72, 0.2)
	var trim_mat: StandardMaterial3D = make_pbr_material(skin.get("trim", Color(0.85, 0.75, 0.4)) as Color, 0.25, 0.88)
	var accent: Color = class_def.get("accent_color", Color(0.3, 0.7, 1.0)) as Color
	var glow_mat: StandardMaterial3D = make_pbr_material(accent, 0.15, 0.1, accent, 2.4)
	var steel_mat: StandardMaterial3D = make_pbr_material(Color(0.82, 0.86, 0.92), 0.2, 0.94)

	var right_hand: Node3D = Node3D.new()
	right_hand.name = "FPRightHand"
	right_hand.position = Vector3(0.36, -0.3, -0.58)
	root.add_child(right_hand)
	_add_capsule(right_hand, 0.065, 0.36, Vector3(0.0, -0.03, 0.14), primary_mat, "GauntletR", Vector3(90.0, 0.0, 0.0))

	var left_hand: Node3D = Node3D.new()
	left_hand.name = "FPLeftHand"
	left_hand.position = Vector3(-0.38, -0.34, -0.55)
	root.add_child(left_hand)
	_add_capsule(left_hand, 0.065, 0.36, Vector3(0.0, -0.03, 0.14), primary_mat, "GauntletL", Vector3(90.0, 0.0, 0.0))

	var weapon_style: String = str(class_def.get("weapon_style", "sword_shield"))
	if weapon_style == "sword_shield":
		_add_cylinder(right_hand, 0.025, 0.025, 0.2, Vector3(0.0, 0.04, -0.04), trim_mat, "FPHilt")
		_add_capsule(right_hand, 0.026, 0.24, Vector3(0.0, 0.12, -0.08), trim_mat, "FPGuard", Vector3(0.0, 0.0, 90.0))
		_add_prism(right_hand, Vector3(0.065, 0.82, 0.028), Vector3(0.0, 0.52, -0.12), steel_mat, "FPBlade")
		_add_capsule(right_hand, 0.014, 0.52, Vector3(0.0, 0.5, -0.12), glow_mat, "FPRune")
		var sh: MeshInstance3D = MeshInstance3D.new()
		sh.mesh = _make_heraldic_shield_mesh()
		sh.material_override = primary_mat
		sh.position = Vector3(-0.02, 0.1, -0.14)
		sh.rotation_degrees = Vector3(0.0, 155.0, 0.0)
		sh.scale = Vector3(0.82, 0.82, 0.82)
		left_hand.add_child(sh)
	elif weapon_style == "staff":
		_add_cylinder(right_hand, 0.026, 0.034, 1.15, Vector3(0.0, 0.28, -0.14), secondary_mat, "FPStaff")
		_add_torus(right_hand, 0.1, 0.13, Vector3(0.0, 0.9, -0.14), trim_mat, "FPCradle", Vector3(90.0, 0.0, 0.0))
		_add_sphere(right_hand, 0.095, Vector3(0.0, 0.9, -0.14), glow_mat, "FPFireOrb")
		_add_sphere(left_hand, 0.08, Vector3(0.0, 0.08, -0.14), glow_mat, "FPMagicSpark")
	elif weapon_style == "mace_shield":
		_add_cylinder(right_hand, 0.026, 0.03, 0.65, Vector3(0.0, 0.26, -0.12), secondary_mat, "FPMaceShaft")
		_add_sphere(right_hand, 0.12, Vector3(0.0, 0.62, -0.12), trim_mat, "FPMaceHead")
		_add_torus(right_hand, 0.11, 0.14, Vector3(0.0, 0.62, -0.12), glow_mat, "FPMaceHalo")
		var sh_c: MeshInstance3D = MeshInstance3D.new()
		sh_c.mesh = _make_heraldic_shield_mesh()
		sh_c.material_override = trim_mat
		sh_c.position = Vector3(-0.02, 0.1, -0.14)
		sh_c.rotation_degrees = Vector3(0.0, 155.0, 0.0)
		sh_c.scale = Vector3(0.86, 0.86, 0.86)
		left_hand.add_child(sh_c)
	elif weapon_style == "daggers":
		_add_prism(right_hand, Vector3(0.048, 0.46, 0.022), Vector3(0.0, 0.24, -0.14), steel_mat, "FPDaggerR")
		_add_capsule(right_hand, 0.012, 0.3, Vector3(0.0, 0.24, -0.14), glow_mat, "FPDaggerEdgeR")
		_add_prism(left_hand, Vector3(0.048, 0.46, 0.022), Vector3(0.0, 0.24, -0.14), steel_mat, "FPDaggerL")
		_add_capsule(left_hand, 0.012, 0.3, Vector3(0.0, 0.24, -0.14), glow_mat, "FPDaggerEdgeL")

	return {"right_hand": right_hand, "left_hand": left_hand}


# --- Sculpted Organic High-Detail Dragon (ZERO BoxMesh + Subsurface Wings + Auto .glb) ---

static func build_dragon_rig(root: Node3D, dragon_skin_id: String, trail_id: String) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var skin: Dictionary = GameConfig.COSMETIC_DRAGONS.get(dragon_skin_id, GameConfig.COSMETIC_DRAGONS["crimson_wyrm"]) as Dictionary
	var scale_col: Color = skin.get("scales", Color(0.68, 0.16, 0.14)) as Color
	var belly_col: Color = skin.get("belly", Color(0.84, 0.66, 0.44)) as Color
	var wing_col: Color = skin.get("wings", Color(0.45, 0.1, 0.1)) as Color
	var breath_col: Color = skin.get("breath", Color(1.0, 0.45, 0.12)) as Color

	var scale_mat: StandardMaterial3D = make_pbr_material(scale_col, 0.34, 0.38)
	var belly_mat: StandardMaterial3D = make_pbr_material(belly_col, 0.48, 0.18)
	var wing_mat: StandardMaterial3D = make_wing_membrane_material(wing_col, breath_col.lerp(Color(1.0, 0.65, 0.28), 0.5))
	var horn_mat: StandardMaterial3D = make_pbr_material(Color(0.16, 0.14, 0.12), 0.28, 0.35)
	var eye_mat: StandardMaterial3D = make_pbr_material(breath_col, 0.1, 0.0, breath_col, 3.2)
	var saddle_mat: StandardMaterial3D = make_pbr_material(Color(0.28, 0.16, 0.09), 0.62, 0.18)

	var body: Node3D = Node3D.new()
	body.name = "DragonBody"
	root.add_child(body)

	# Auto-load real rigged dragon.glb (Quaternius CC0) oriented -Z with AnimationPlayer & Skeleton3D
	var custom_dragon: Node3D = _try_load_external_glb("res://Assets/Models/dragon.glb")
	if custom_dragon != null:
		custom_dragon.name = "ExternalDragonGLB"
		custom_dragon.rotation.y = PI
		custom_dragon.scale = Vector3.ONE * 1.45
		body.add_child(custom_dragon)
		var dap: AnimationPlayer = _find_child_of_type(custom_dragon, "AnimationPlayer") as AnimationPlayer
		var dskel: Skeleton3D = _find_child_of_type(custom_dragon, "Skeleton3D") as Skeleton3D
		if dap != null and dap.has_animation("Dragon_Flying"):
			var fa: Animation = dap.get_animation("Dragon_Flying")
			if fa != null:
				fa.loop_mode = Animation.LOOP_LINEAR
			dap.play("Dragon_Flying")
		var cone_glb: MeshInstance3D = _make_dragon_breath_cone(body, breath_col, Vector3(0.0, 2.3, -11.5))
		var aura_glb: MeshInstance3D = _make_dragon_grace_aura(body)
		return {
			"body": body, "neck": custom_dragon, "head": custom_dragon, "jaw": null,
			"anim_player": dap, "skeleton": dskel,
			"tail_1": null, "tail_2": null, "wing_l_root": null, "wing_l_tip": null,
			"wing_r_root": null, "wing_r_tip": null, "breath_cone": cone_glb,
			"trail": null, "grace_aura": aura_glb
		}

	# 1. Sculpted Aerodynamic Muscular Torso (Lofted curved elliptical cross-sections, facing -Z)
	var torso_rings: Array = [
		{"pos": Vector3(0.0, 1.38, 1.95), "rx": 0.44, "ry": 0.38},
		{"pos": Vector3(0.0, 1.56, 1.15), "rx": 0.72, "ry": 0.6},
		{"pos": Vector3(0.0, 1.62, 0.25), "rx": 0.82, "ry": 0.68},
		{"pos": Vector3(0.0, 1.72, -0.75), "rx": 0.94, "ry": 0.78},
		{"pos": Vector3(0.0, 1.68, -1.65), "rx": 0.62, "ry": 0.56}
	]
	_add_lofted(body, torso_rings, scale_mat, "SculptedTorso", 16)

	# Plated armored belly keel
	var belly_rings: Array = [
		{"pos": Vector3(0.0, 1.12, 1.45), "rx": 0.34, "ry": 0.16},
		{"pos": Vector3(0.0, 1.02, 0.2), "rx": 0.58, "ry": 0.22},
		{"pos": Vector3(0.0, 1.06, -0.85), "rx": 0.64, "ry": 0.24},
		{"pos": Vector3(0.0, 1.24, -1.55), "rx": 0.36, "ry": 0.16}
	]
	_add_lofted(body, belly_rings, belly_mat, "ArmoredBelly", 12)

	# Curved Leather Saddle
	_add_sphere(body, 0.55, Vector3(0.0, 2.28, -0.22), saddle_mat, "RiderSaddle", Vector3(1.0, 0.34, 1.25))

	# Swept Dorsal Spines along the back
	for i: int in range(6):
		var z_p: float = -1.25 + float(i) * 0.56
		var y_p: float = 2.42 - absf(z_p + 0.3) * 0.12
		_add_prism(body, Vector3(0.12, 0.42, 0.32), Vector3(0.0, y_p, z_p), horn_mat, "DorsalSpine_%d" % i, Vector3(-24.0, 0.0, 0.0))

	# 2. Long S-Curved Articulated Neck (facing -Z)
	var neck: Node3D = Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0.0, 1.72, -1.55)
	body.add_child(neck)
	var neck_rings: Array = [
		{"pos": Vector3(0.0, -0.05, 0.12), "rx": 0.54, "ry": 0.48},
		{"pos": Vector3(0.0, 0.12, -0.55), "rx": 0.44, "ry": 0.4},
		{"pos": Vector3(0.0, 0.48, -1.15), "rx": 0.38, "ry": 0.35},
		{"pos": Vector3(0.0, 0.82, -1.68), "rx": 0.34, "ry": 0.32}
	]
	_add_lofted(neck, neck_rings, scale_mat, "SCurvedNeck", 14)

	# 3. Sculpted Draconic Head + Articulated Opening Lower Jaw + Swept Curved Horns
	var head: Node3D = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.86, -1.72)
	neck.add_child(head)

	var skull_rings: Array = [
		{"pos": Vector3(0.0, 0.06, 0.18), "rx": 0.42, "ry": 0.34},
		{"pos": Vector3(0.0, 0.1, -0.32), "rx": 0.38, "ry": 0.3},
		{"pos": Vector3(0.0, 0.04, -0.95), "rx": 0.26, "ry": 0.2},
		{"pos": Vector3(0.0, -0.02, -1.48), "rx": 0.14, "ry": 0.11}
	]
	_add_lofted(head, skull_rings, scale_mat, "DragonSkull", 14)

	# Articulated Lower Jaw (rotates open when breathing fire!)
	var jaw: Node3D = Node3D.new()
	jaw.name = "Jaw"
	jaw.position = Vector3(0.0, -0.1, -0.15)
	head.add_child(jaw)
	var jaw_rings: Array = [
		{"pos": Vector3(0.0, 0.0, 0.1), "rx": 0.32, "ry": 0.14},
		{"pos": Vector3(0.0, -0.06, -0.58), "rx": 0.22, "ry": 0.11},
		{"pos": Vector3(0.0, -0.05, -1.22), "rx": 0.11, "ry": 0.08}
	]
	_add_lofted(jaw, jaw_rings, belly_mat, "LowerJaw", 12)

	# Glowing Emissive Eyes + Brow Ridges
	_add_sphere(head, 0.09, Vector3(-0.31, 0.14, -0.45), eye_mat, "EyeL", Vector3(0.85, 0.72, 1.3))
	_add_sphere(head, 0.09, Vector3(0.31, 0.14, -0.45), eye_mat, "EyeR", Vector3(0.85, 0.72, 1.3))
	_add_capsule(head, 0.06, 0.42, Vector3(-0.3, 0.23, -0.52), horn_mat, "BrowL", Vector3(82.0, 0.0, 12.0))
	_add_capsule(head, 0.06, 0.42, Vector3(0.3, 0.23, -0.52), horn_mat, "BrowR", Vector3(82.0, 0.0, -12.0))

	# Sweeping Curved Horns (lofted splines!)
	for side_sign: float in [-1.0, 1.0]:
		var horn_rings: Array = [
			{"pos": Vector3(side_sign * 0.26, 0.24, 0.04), "rx": 0.11, "ry": 0.11},
			{"pos": Vector3(side_sign * 0.42, 0.48, 0.56), "rx": 0.08, "ry": 0.08},
			{"pos": Vector3(side_sign * 0.52, 0.68, 1.18), "rx": 0.05, "ry": 0.05},
			{"pos": Vector3(side_sign * 0.5, 0.74, 1.65), "rx": 0.015, "ry": 0.015}
		]
		_add_lofted(head, horn_rings, horn_mat, "Horn_%s" % ("L" if side_sign < 0.0 else "R"), 10)

	# Fire Breath Cone attached to head
	var breath_cone: MeshInstance3D = _make_dragon_breath_cone(head, breath_col, Vector3(0.0, -0.06, -10.2))

	# 4. Sinuous Articulated Tail + Spearhead Caudal Fin
	var tail_1: Node3D = Node3D.new()
	tail_1.name = "Tail1"
	tail_1.position = Vector3(0.0, 1.38, 1.9)
	body.add_child(tail_1)
	var t1_rings: Array = [
		{"pos": Vector3(0.0, 0.0, 0.0), "rx": 0.42, "ry": 0.36},
		{"pos": Vector3(0.0, -0.06, 1.1), "rx": 0.3, "ry": 0.26},
		{"pos": Vector3(0.0, -0.1, 2.2), "rx": 0.21, "ry": 0.18}
	]
	_add_lofted(tail_1, t1_rings, scale_mat, "TailSeg1", 12)

	var tail_2: Node3D = Node3D.new()
	tail_2.name = "Tail2"
	tail_2.position = Vector3(0.0, -0.1, 2.15)
	tail_1.add_child(tail_2)
	var t2_rings: Array = [
		{"pos": Vector3(0.0, 0.0, 0.0), "rx": 0.2, "ry": 0.17},
		{"pos": Vector3(0.0, 0.02, 1.25), "rx": 0.12, "ry": 0.11},
		{"pos": Vector3(0.0, 0.06, 2.45), "rx": 0.04, "ry": 0.04}
	]
	_add_lofted(tail_2, t2_rings, scale_mat, "TailSeg2", 10)
	_add_prism(tail_2, Vector3(0.95, 1.15, 0.08), Vector3(0.0, 0.06, 2.65), horn_mat, "TailSpearFin", Vector3(90.0, 0.0, 0.0))

	# 5. Muscular Dragon Legs with Curved Claws (Zero Boxes!)
	for leg_def: Array in [
		[Vector3(-0.78, 1.22, -0.95), -1.0],
		[Vector3(0.78, 1.22, -0.95), 1.0],
		[Vector3(-0.74, 1.22, 0.95), -1.0],
		[Vector3(0.74, 1.22, 0.95), 1.0]
	]:
		var lp: Vector3 = leg_def[0] as Vector3
		var leg_root: Node3D = Node3D.new()
		leg_root.position = lp
		body.add_child(leg_root)
		_add_capsule(leg_root, 0.24, 0.85, Vector3(0.0, -0.28, 0.08), scale_mat, "Thigh", Vector3(22.0, 0.0, 0.0))
		_add_capsule(leg_root, 0.16, 0.78, Vector3(0.0, -0.82, -0.06), scale_mat, "Shin", Vector3(-18.0, 0.0, 0.0))
		# 3 curved talons per foot
		for ci: int in range(-1, 2):
			_add_prism(leg_root, Vector3(0.08, 0.34, 0.08), Vector3(float(ci) * 0.13, -1.16, -0.32), horn_mat, "Talon_%d" % ci, Vector3(-72.0, float(ci) * 16.0, 0.0))

	# 6. Articulated Bat/Wyvern Wings with Visible Wing Bones & Translucent Backlit Membrane
	var wing_l_root: Node3D = Node3D.new()
	wing_l_root.name = "WingLRoot"
	wing_l_root.position = Vector3(-0.75, 2.02, -0.45)
	body.add_child(wing_l_root)
	var wing_l_tip: Node3D = _build_wyvern_wing(wing_l_root, -1.0, scale_mat, horn_mat, wing_mat)

	var wing_r_root: Node3D = Node3D.new()
	wing_r_root.name = "WingRRoot"
	wing_r_root.position = Vector3(0.75, 2.02, -0.45)
	body.add_child(wing_r_root)
	var wing_r_tip: Node3D = _build_wyvern_wing(wing_r_root, 1.0, scale_mat, horn_mat, wing_mat)

	# Cosmetic Flight Trail
	var trail: CPUParticles3D = CPUParticles3D.new()
	trail.name = "CosmeticTrail"
	trail.position = Vector3(0.0, 1.5, 2.6)
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
	var trail_mat: StandardMaterial3D = make_pbr_material(trail_color, 0.2, 0.0, trail_color, 2.2)
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = trail_mat
	body.add_child(trail)

	var grace_aura: MeshInstance3D = _make_dragon_grace_aura(body)
	return {
		"body": body,
		"neck": neck,
		"head": head,
		"jaw": jaw,
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


static func _build_wyvern_wing(root: Node3D, s: float, bone_mat: Material, claw_mat: Material, mem_mat: Material) -> Node3D:
	# Inner wing arm (Humerus + Radius)
	var p_root: Vector3 = Vector3.ZERO
	var p_elbow: Vector3 = Vector3(s * 2.55, 0.25, -0.45)
	var p_attach: Vector3 = Vector3(s * 0.1, -0.35, 2.0)

	_add_lofted(root, [
		{"pos": p_root, "rx": 0.18, "ry": 0.16},
		{"pos": p_elbow * 0.5 + Vector3(0.0, 0.08, 0.0), "rx": 0.14, "ry": 0.12},
		{"pos": p_elbow, "rx": 0.13, "ry": 0.11}
	], bone_mat, "Humerus", 10)

	# Wing wrist claw
	_add_prism(root, Vector3(0.14, 0.42, 0.14), p_elbow + Vector3(0.0, 0.12, -0.26), claw_mat, "WingClaw", Vector3(-68.0, 0.0, 0.0))

	# Inner membrane connecting arm to dragon flank
	var inner_mem: MeshInstance3D = MeshInstance3D.new()
	inner_mem.name = "InnerMembrane"
	inner_mem.mesh = _make_wing_membrane_mesh(p_root, p_elbow, [Vector3(s * 1.9, -0.1, 1.95)], p_attach)
	inner_mem.material_override = mem_mat
	root.add_child(inner_mem)

	# Outer articulated wing hand (3 long bat phalanges + translucent scalloped membrane)
	var tip_pivot: Node3D = Node3D.new()
	tip_pivot.name = "WingTip"
	tip_pivot.position = p_elbow
	root.add_child(tip_pivot)

	var f1: Vector3 = Vector3(s * 3.7, 0.15, -0.25)
	var f2: Vector3 = Vector3(s * 3.15, -0.1, 1.35)
	var f3: Vector3 = Vector3(s * 1.65, -0.22, 2.45)
	var f4: Vector3 = Vector3(-s * 0.65, -0.35, 2.35)

	for finger_end: Vector3 in [f1, f2, f3]:
		_add_lofted(tip_pivot, [
			{"pos": Vector3.ZERO, "rx": 0.09, "ry": 0.08},
			{"pos": finger_end * 0.55, "rx": 0.055, "ry": 0.05},
			{"pos": finger_end, "rx": 0.02, "ry": 0.02}
		], bone_mat, "Phalanx", 8)

	var outer_mem: MeshInstance3D = MeshInstance3D.new()
	outer_mem.name = "OuterMembrane"
	outer_mem.mesh = _make_wing_membrane_mesh(Vector3.ZERO, Vector3.ZERO, [f1, f2, f3], f4)
	outer_mem.material_override = mem_mat
	tip_pivot.add_child(outer_mem)
	return tip_pivot


static func _make_dragon_breath_cone(parent: Node3D, breath_col: Color, pos: Vector3) -> MeshInstance3D:
	var breath_cone: MeshInstance3D = MeshInstance3D.new()
	breath_cone.name = "BreathCone"
	var cone_mesh: CylinderMesh = CylinderMesh.new()
	cone_mesh.top_radius = 0.28
	cone_mesh.bottom_radius = 2.8
	cone_mesh.height = 18.5
	cone_mesh.radial_segments = 14
	breath_cone.mesh = cone_mesh
	breath_cone.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	breath_cone.position = pos
	var fire_mat: ShaderMaterial = ShaderMaterial.new()
	fire_mat.shader = SHADER_DRAGON_FIRE
	fire_mat.set_shader_parameter("flame_color", breath_col)
	fire_mat.set_shader_parameter("core_color", breath_col.lightened(0.65))
	breath_cone.material_override = fire_mat
	breath_cone.visible = false
	parent.add_child(breath_cone)
	return breath_cone


static func _make_dragon_grace_aura(parent: Node3D) -> MeshInstance3D:
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
	parent.add_child(grace_aura)
	return grace_aura


# --- Colossal Sculpted World Bosses ---

static func build_world_boss_rig(root: Node3D, style: String) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var body: Node3D = Node3D.new()
	body.name = "BossBody"
	root.add_child(body)

	if style == "wyrm":
		var drig: Dictionary = build_dragon_rig(body, "abyssal_black", "ember_sparks")
		body.scale = Vector3.ONE * 1.85
		return {"body": body, "dragon_rig": drig}

	var is_order: bool = (style == "seraphim")
	var armor_mat: StandardMaterial3D = make_pbr_material(
		Color(0.92, 0.8, 0.36) if is_order else Color(0.14, 0.1, 0.16),
		0.25 if is_order else 0.38,
		0.88 if is_order else 0.65
	)
	var glow_col: Color = Color(1.0, 0.92, 0.42) if is_order else Color(1.0, 0.28, 0.08)
	var glow_mat: StandardMaterial3D = make_pbr_material(glow_col, 0.15, 0.1, glow_col, 3.0)

	# Towering sculpted titan torso
	var titan_rings: Array = [
		{"pos": Vector3(0.0, 1.8, 0.0), "rx": 0.85, "ry": 0.65},
		{"pos": Vector3(0.0, 3.0, 0.05), "rx": 1.35, "ry": 0.95},
		{"pos": Vector3(0.0, 4.1, 0.0), "rx": 1.1, "ry": 0.75}
	]
	_add_lofted(body, titan_rings, armor_mat, "TitanTorso", 16)
	_add_sphere(body, 0.55, Vector3(0.0, 3.1, 0.88), glow_mat, "TitanCore", Vector3(1.1, 1.3, 0.4))
	_add_sphere(body, 0.62, Vector3(0.0, 4.75, 0.0), armor_mat, "TitanHead")
	_add_torus(body, 0.72, 0.86, Vector3(0.0, 5.4, 0.0), glow_mat, "BossCrown")
	_add_capsule(body, 0.42, 1.9, Vector3(-0.7, 0.95, 0.0), armor_mat, "LegL")
	_add_capsule(body, 0.42, 1.9, Vector3(0.7, 0.95, 0.0), armor_mat, "LegR")

	var arm_r: Node3D = Node3D.new()
	arm_r.name = "BossArmR"
	arm_r.position = Vector3(1.55, 3.6, 0.0)
	body.add_child(arm_r)
	_add_sphere(arm_r, 0.65, Vector3.ZERO, glow_mat if is_order else armor_mat, "PauldronR")
	_add_capsule(arm_r, 0.36, 1.9, Vector3(0.0, -0.95, 0.0), armor_mat, "ArmCapR")
	_add_prism(arm_r, Vector3(0.42, 3.6, 0.22), Vector3(0.0, -1.8, 1.4), glow_mat, "ColossalWeapon", Vector3(85.0, 0.0, 0.0))

	var arm_l: Node3D = Node3D.new()
	arm_l.name = "BossArmL"
	arm_l.position = Vector3(-1.55, 3.6, 0.0)
	body.add_child(arm_l)
	_add_sphere(arm_l, 0.65, Vector3.ZERO, glow_mat if is_order else armor_mat, "PauldronL")
	_add_capsule(arm_l, 0.36, 1.9, Vector3(0.0, -0.95, 0.0), armor_mat, "ArmCapL")

	if is_order:
		# Sweeping radiant wings for Seraphim Colossus
		for s: float in [-1.0, 1.0]:
			_add_prism(body, Vector3(2.8, 4.2, 0.14), Vector3(s * 2.1, 3.9, -0.7), glow_mat, "SeraphWing_%d" % int(s), Vector3(15.0, 0.0, s * -28.0))
	else:
		# Jagged obsidian horns for Chaos Behemoth
		for s: float in [-1.0, 1.0]:
			_add_prism(body, Vector3(0.35, 1.5, 0.35), Vector3(s * 0.7, 5.4, 0.0), glow_mat, "ChaosHorn_%d" % int(s), Vector3(-15.0, 0.0, s * -32.0))

	return {"body": body, "arm_r": arm_r, "arm_l": arm_l}


# --- Sculpted Medieval Stations (Blacksmith Forge, Alchemy Bench, Shop Stall) ---

static func build_station_visual(root: Node3D, station_type: String) -> void:
	for child: Node in root.get_children():
		child.queue_free()
	var stone_mat: StandardMaterial3D = make_pbr_material(Color(0.44, 0.44, 0.48), 0.85, 0.05)
	var wood_mat: StandardMaterial3D = make_pbr_material(Color(0.4, 0.25, 0.14), 0.78, 0.0)
	var iron_mat: StandardMaterial3D = make_pbr_material(Color(0.24, 0.26, 0.3), 0.35, 0.85)
	var fire_mat: StandardMaterial3D = make_pbr_material(Color(1.0, 0.46, 0.12), 0.2, 0.0, Color(1.0, 0.42, 0.08), 3.0)

	if station_type == "forge":
		_add_cylinder(root, 1.35, 1.55, 1.2, Vector3(-0.8, 0.6, -0.4), make_stone_pbr_material(), "ForgeHearth", 10)
		_add_cylinder(root, 0.65, 1.05, 1.9, Vector3(-0.8, 2.1, -0.5), make_stone_pbr_material(), "Chimney", 8)
		_add_sphere(root, 0.72, Vector3(-0.8, 1.28, -0.25), fire_mat, "Embers", Vector3(1.1, 0.45, 1.0))
		_add_cylinder(root, 0.42, 0.5, 0.55, Vector3(1.0, 0.28, 0.4), wood_mat, "AnvilStump", 12)
		_add_cylinder(root, 0.24, 0.34, 0.35, Vector3(1.0, 0.72, 0.4), iron_mat, "AnvilWaist", 10)
		_add_capsule(root, 0.2, 0.95, Vector3(1.0, 0.98, 0.4), iron_mat, "AnvilHorn", Vector3(0.0, 0.0, 90.0))
	elif station_type == "campfire":
		# Stone-ringed cooking campfire with suspended stew pot
		_add_torus(root, 0.75, 1.05, Vector3(0.0, 0.14, 0.0), stone_mat, "FireRing")
		_add_sphere(root, 0.48, Vector3(0.0, 0.36, 0.0), fire_mat, "CampFlames", Vector3(1.0, 1.35, 1.0))
		_add_cylinder(root, 0.06, 0.07, 1.9, Vector3(-0.85, 0.9, 0.0), wood_mat, "TripodL", 8, Vector3(0.0, 0.0, -18.0))
		_add_cylinder(root, 0.06, 0.07, 1.9, Vector3(0.85, 0.9, 0.0), wood_mat, "TripodR", 8, Vector3(0.0, 0.0, 18.0))
		_add_sphere(root, 0.44, Vector3(0.0, 0.92, 0.0), iron_mat, "CookingPot", Vector3(1.0, 0.78, 1.0))
	elif station_type == "alchemy":
		var emerald_mat: StandardMaterial3D = make_pbr_material(Color(0.24, 0.95, 0.55), 0.12, 0.1, Color(0.2, 0.9, 0.48), 2.5)
		var arcane_mat: StandardMaterial3D = make_pbr_material(Color(0.45, 0.68, 1.0), 0.12, 0.1, Color(0.38, 0.62, 1.0), 2.5)
		_add_cylinder(root, 1.25, 1.15, 0.16, Vector3(0.0, 0.95, 0.0), wood_mat, "AlchemyTableTop", 12)
		_add_cylinder(root, 0.22, 0.36, 0.92, Vector3(0.0, 0.46, 0.0), wood_mat, "TablePedestal", 10)
		_add_sphere(root, 0.22, Vector3(-0.45, 1.22, 0.15), emerald_mat, "FlaskGreen")
		_add_sphere(root, 0.18, Vector3(0.42, 1.18, -0.2), arcane_mat, "FlaskBlue")
		_add_torus(root, 0.32, 0.38, Vector3(0.0, 1.45, 0.0), arcane_mat, "AlchemyRing")
	else:
		var canopy_mat: StandardMaterial3D = make_pbr_material(Color(0.74, 0.2, 0.16), 0.72, 0.0)
		canopy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_add_cylinder(root, 2.2, 2.35, 0.22, Vector3(0.0, 0.11, 0.0), make_stone_pbr_material(), "StallDeck", 12)
		for p: Vector3 in [Vector3(-1.6, 1.6, -1.0), Vector3(1.6, 1.6, -1.0), Vector3(-1.6, 1.6, 1.0), Vector3(1.6, 1.6, 1.0)]:
			_add_cylinder(root, 0.1, 0.12, 3.1, p, wood_mat, "Post", 8)
		_add_cylinder(root, 0.1, 2.6, 1.1, Vector3(0.0, 3.55, 0.0), canopy_mat, "PavilionCanopy", 8)
		_add_cylinder(root, 0.42, 0.38, 0.85, Vector3(-1.0, 0.55, 0.5), wood_mat, "Barrel1", 12)
		_add_cylinder(root, 0.36, 0.34, 0.75, Vector3(1.05, 0.5, 0.4), wood_mat, "Barrel2", 12)
		_add_sphere(root, 0.22, Vector3(0.0, 2.65, 1.05), fire_mat, "ShopLantern")


# --- Sculpted Dungeon Entrance Portal ---

static func build_dungeon_portal_visual(root: Node3D, theme: String) -> Node3D:
	for child: Node in root.get_children():
		child.queue_free()
	var is_order: bool = (theme == "order")
	var stone_mat: StandardMaterial3D = make_stone_pbr_material(Color(0.72, 0.75, 0.82))
	var portal_col: Color = Color(0.35, 0.82, 1.0) if is_order else Color(1.0, 0.26, 0.12)
	var portal_mat: StandardMaterial3D = make_pbr_material(portal_col, 0.1, 0.1, portal_col, 3.0)
	portal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	portal_mat.albedo_color.a = 0.78

	_add_cylinder(root, 2.8, 3.2, 0.45, Vector3(0.0, 0.22, 0.0), stone_mat, "PortalSteps", 10)
	_add_cylinder(root, 0.52, 0.72, 4.6, Vector3(-2.1, 2.4, 0.0), stone_mat, "MonolithL", 8)
	_add_cylinder(root, 0.52, 0.72, 4.6, Vector3(2.1, 2.4, 0.0), stone_mat, "MonolithR", 8)
	_add_torus(root, 1.9, 2.45, Vector3(0.0, 3.2, 0.0), stone_mat, "StoneArch", Vector3(90.0, 0.0, 0.0))

	var vortex: Node3D = Node3D.new()
	vortex.name = "PortalVortex"
	vortex.position = Vector3(0.0, 2.6, 0.0)
	root.add_child(vortex)
	_add_torus(vortex, 1.45, 1.72, Vector3.ZERO, portal_mat, "RuneRing", Vector3(90.0, 0.0, 0.0))
	_add_sphere(vortex, 1.55, Vector3.ZERO, portal_mat, "PortalCore", Vector3(1.0, 1.25, 0.16))
	return vortex


# --- Player Buildings (Walls, Gates, Towers, Houses, Storage Chests, Altars, Trade Posts) ---

static func build_structure_visual(root: Node3D, piece_type: String, is_ghost: bool = false, valid_ghost: bool = true) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var spec: Dictionary = GameConfig.BUILD_PIECES.get(piece_type, GameConfig.BUILD_PIECES["wall"]) as Dictionary
	var base_col: Color = spec.get("color", Color(0.55, 0.55, 0.58)) as Color
	var stone_mat: StandardMaterial3D = make_stone_pbr_material(base_col.lightened(0.35))
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
		_add_cylinder(root, 0.52, 0.68, 4.5, Vector3(-2.85, 2.25, 0.0), trim_mat, "EndTurretL", 10)
		_add_cylinder(root, 0.52, 0.68, 4.5, Vector3(2.85, 2.25, 0.0), trim_mat, "EndTurretR", 10)
	elif piece_type == "gate" or piece_type == "house_door":
		var h_tall: float = 4.8 if piece_type == "gate" else 3.8
		_add_cylinder(root, 0.65, 0.8, h_tall, Vector3(-2.3, h_tall * 0.5, 0.0), stone_mat, "PillarL", 10)
		_add_cylinder(root, 0.65, 0.8, h_tall, Vector3(2.3, h_tall * 0.5, 0.0), stone_mat, "PillarR", 10)
		_add_box(root, Vector3(5.6, 0.8, 1.1), Vector3(0.0, h_tall - 0.3, 0.0), stone_mat, "ArchTop")
		door_pivot = Node3D.new()
		door_pivot.name = "DoorPivot"
		door_pivot.position = Vector3(-1.55, 0.0, 0.0)
		root.add_child(door_pivot)
		_add_box(door_pivot, Vector3(3.1, h_tall - 0.7, 0.26), Vector3(1.55, (h_tall - 0.7) * 0.5, 0.0), wood_mat, "GateDoor")
		_add_box(door_pivot, Vector3(3.15, 0.2, 0.32), Vector3(1.55, 1.1, 0.0), trim_mat, "IronBand1")
	elif piece_type == "house_foundation":
		_add_box(root, Vector3(6.0, 0.7, 6.0), Vector3(0.0, 0.35, 0.0), stone_mat, "FoundationSlab")
	elif piece_type == "house_wall":
		_add_box(root, Vector3(6.0, 3.8, 0.55), Vector3(0.0, 1.9, 0.0), wood_mat, "HouseTimberWall")
		_add_box(root, Vector3(6.0, 0.9, 0.62), Vector3(0.0, 0.45, 0.0), stone_mat, "HouseStoneBase")
	elif piece_type == "house_roof":
		_add_prism(root, Vector3(6.4, 2.2, 6.4), Vector3(0.0, 1.1, 0.0), wood_mat, "PitchedRoof")
	elif piece_type == "storage_chest":
		build_loot_chest_visual(root)
	elif piece_type == "tower":
		_add_cylinder(root, 2.15, 2.55, 8.2, Vector3(0.0, 4.1, 0.0), stone_mat, "RoundTower", 14)
		_add_cylinder(root, 2.65, 2.35, 0.8, Vector3(0.0, 8.4, 0.0), trim_mat, "TowerParapet", 14)
		var roof_mat: StandardMaterial3D = make_pbr_material(Color(0.24, 0.28, 0.42), 0.65, 0.1) if not is_ghost else stone_mat
		_add_cylinder(root, 0.1, 2.85, 2.8, Vector3(0.0, 10.2, 0.0), roof_mat, "ConicalRoof", 14)
		var beacon_mat: StandardMaterial3D = make_pbr_material(Color(1.0, 0.72, 0.22), 0.2, 0.0, Color(1.0, 0.6, 0.12), 2.5) if not is_ghost else stone_mat
		_add_sphere(root, 0.42, Vector3(0.0, 11.75, 0.0), beacon_mat, "WatchBeacon")
	elif piece_type == "altar_order" or piece_type == "altar_chaos":
		var is_order: bool = piece_type == "altar_order"
		var sigil_col: Color = Color(1.0, 0.86, 0.35) if is_order else Color(1.0, 0.25, 0.14)
		var sigil_mat: StandardMaterial3D = make_pbr_material(sigil_col, 0.15, 0.5, sigil_col, 2.6) if not is_ghost else stone_mat
		_add_cylinder(root, 1.8, 2.15, 0.5, Vector3(0.0, 0.25, 0.0), stone_mat, "DaisBase", 12)
		_add_cylinder(root, 1.2, 1.45, 0.5, Vector3(0.0, 0.75, 0.0), trim_mat, "DaisMid", 12)
		_add_cylinder(root, 0.48, 0.62, 1.65, Vector3(0.0, 1.75, 0.0), stone_mat, "Pillar", 10)
		sigil_node = Node3D.new()
		sigil_node.name = "SigilPivot"
		sigil_node.position = Vector3(0.0, 3.25, 0.0)
		root.add_child(sigil_node)
		_add_torus(sigil_node, 0.52, 0.64, Vector3.ZERO, sigil_mat, "SigilRing", Vector3(45.0, 0.0, 0.0))
		_add_sphere(sigil_node, 0.34, Vector3.ZERO, sigil_mat, "SigilOrb")
	elif piece_type == "trade_post":
		build_station_visual(root, "shop_stall")

	return {"door_pivot": door_pivot, "sigil_node": sigil_node}


# --- Sculpted Gatherable Resource Nodes ---

static func build_resource_visual(root: Node3D, resource_type: String) -> void:
	for child: Node in root.get_children():
		child.queue_free()

	if resource_type == "wood":
		var bark_mat: StandardMaterial3D = make_pbr_material(Color(0.32, 0.21, 0.13), 0.9, 0.0)
		var leaf_mat: StandardMaterial3D = make_pbr_material(Color(0.16, 0.38, 0.16), 0.82, 0.0)
		_add_cylinder(root, 0.22, 0.42, 3.1, Vector3(0.0, 1.55, 0.0), bark_mat, "Trunk", 9)
		_add_sphere(root, 1.55, Vector3(0.0, 3.6, 0.0), leaf_mat, "Crown1", Vector3(1.1, 0.85, 1.1), 10)
		_add_sphere(root, 1.15, Vector3(0.85, 3.2, 0.4), leaf_mat, "Crown2", Vector3(1.0, 0.85, 1.0), 10)
		_add_sphere(root, 1.05, Vector3(-0.7, 4.4, -0.3), leaf_mat, "Crown3", Vector3(1.0, 0.85, 1.0), 10)
	elif resource_type == "iron_ore" or resource_type == "silver_ore" or resource_type == "gold_ore":
		var rock_mat: StandardMaterial3D = make_pbr_material(Color(0.34, 0.35, 0.38), 0.82, 0.25)
		var vein_col: Color = Color(0.68, 0.72, 0.78)
		var emit_e: float = 0.0
		if resource_type == "silver_ore":
			vein_col = Color(0.84, 0.9, 1.0)
			emit_e = 0.8
		elif resource_type == "gold_ore":
			vein_col = Color(1.0, 0.82, 0.26)
			emit_e = 1.4
		var ore_mat: StandardMaterial3D = make_pbr_material(vein_col, 0.22, 0.92, vein_col, emit_e)
		_add_sphere(root, 1.05, Vector3(0.0, 0.65, 0.0), rock_mat, "OreRock", Vector3(1.25, 0.85, 1.1), 10)
		_add_prism(root, Vector3(0.45, 0.85, 0.45), Vector3(0.35, 1.0, 0.2), ore_mat, "Vein1", Vector3(16.0, 25.0, -18.0))
		_add_prism(root, Vector3(0.38, 0.72, 0.38), Vector3(-0.42, 0.9, -0.18), ore_mat, "Vein2", Vector3(-18.0, -30.0, 22.0))
	elif resource_type == "raw_meat":
		var crate_mat: StandardMaterial3D = make_pbr_material(Color(0.58, 0.22, 0.18), 0.72, 0.05)
		var bone_mat: StandardMaterial3D = make_pbr_material(Color(0.92, 0.88, 0.78), 0.65, 0.0)
		_add_sphere(root, 0.62, Vector3(0.0, 0.55, 0.0), crate_mat, "GameRoast", Vector3(1.3, 0.75, 0.95), 10)
		_add_cylinder(root, 0.12, 0.12, 1.25, Vector3(0.0, 0.55, 0.0), bone_mat, "Bone", 8, Vector3(0.0, 0.0, 90.0))
	elif resource_type == "alchemy_herb":
		var stem_mat: StandardMaterial3D = make_pbr_material(Color(0.16, 0.48, 0.22), 0.75, 0.0)
		var bloom_mat: StandardMaterial3D = make_pbr_material(Color(0.35, 1.0, 0.68), 0.2, 0.0, Color(0.28, 0.95, 0.62), 2.4)
		for i: int in range(5):
			var ang: float = (float(i) / 5.0) * TAU
			var sx: float = cos(ang) * 0.42
			var sz: float = sin(ang) * 0.42
			_add_capsule(root, 0.07, 0.85, Vector3(sx, 0.42, sz), stem_mat, "Stem_%d" % i, Vector3(sin(ang) * 18.0, 0.0, -cos(ang) * 18.0))
			_add_sphere(root, 0.16, Vector3(sx * 1.25, 0.88, sz * 1.25), bloom_mat, "Bloom_%d" % i)
	elif resource_type == "stone":
		var rock_mat: StandardMaterial3D = make_stone_pbr_material(Color(0.82, 0.82, 0.85))
		_add_sphere(root, 1.05, Vector3(0.0, 0.65, 0.0), rock_mat, "Boulder1", Vector3(1.25, 0.85, 1.15), 10)
		_add_sphere(root, 0.72, Vector3(0.85, 0.45, 0.45), rock_mat, "Boulder2", Vector3(1.15, 0.8, 1.0), 10)
	else:
		var rock_mat: StandardMaterial3D = make_pbr_material(Color(0.22, 0.22, 0.28), 0.8, 0.15)
		var crystal_mat: StandardMaterial3D = make_pbr_material(Color(0.32, 0.78, 1.0), 0.12, 0.3, Color(0.24, 0.68, 1.0), 2.8)
		_add_sphere(root, 0.9, Vector3(0.0, 0.45, 0.0), rock_mat, "OreBase", Vector3(1.2, 0.65, 1.2), 10)
		_add_cylinder(root, 0.03, 0.28, 2.0, Vector3(0.0, 1.15, 0.0), crystal_mat, "Crystal1", 6, Vector3(8.0, 0.0, -10.0))
		_add_cylinder(root, 0.02, 0.2, 1.45, Vector3(0.45, 0.88, 0.25), crystal_mat, "Crystal2", 6, Vector3(-14.0, 15.0, 22.0))
		_add_cylinder(root, 0.02, 0.2, 1.35, Vector3(-0.42, 0.82, -0.2), crystal_mat, "Crystal3", 6, Vector3(18.0, -20.0, -20.0))


static func build_loot_chest_visual(root: Node3D) -> void:
	for child: Node in root.get_children():
		child.queue_free()
	var wood_mat: StandardMaterial3D = make_pbr_material(Color(0.38, 0.22, 0.12), 0.72, 0.08)
	var gold_mat: StandardMaterial3D = make_pbr_material(Color(0.95, 0.78, 0.24), 0.24, 0.88, Color(0.95, 0.75, 0.2), 0.9)
	_add_capsule(root, 0.38, 1.05, Vector3(0.0, 0.4, 0.0), wood_mat, "VaultedChest", Vector3(0.0, 0.0, 90.0))
	_add_torus(root, 0.36, 0.42, Vector3(-0.26, 0.4, 0.0), gold_mat, "GoldBandL", Vector3(0.0, 0.0, 90.0))
	_add_torus(root, 0.36, 0.42, Vector3(0.26, 0.4, 0.0), gold_mat, "GoldBandR", Vector3(0.0, 0.0, 90.0))
	var beam_mat: StandardMaterial3D = make_pbr_material(Color(1.0, 0.82, 0.32, 0.35), 0.2, 0.0, Color(1.0, 0.8, 0.25), 1.8)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add_cylinder(root, 0.12, 0.22, 3.8, Vector3(0.0, 2.2, 0.0), beam_mat, "LootBeacon", 10)
