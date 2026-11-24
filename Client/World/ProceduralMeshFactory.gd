class_name ProceduralMeshFactory
extends RefCounted

## Real .glb Model & 1K PBR Material Factory (Release 2.0).
## - Instantiates real rigged .glb scenes (player_knight, player_mage, player_cleric,
##   player_rogue, player_ranger, dragon) for all characters, bosses, and mounts.
## - Applies real 1K PBR texture sets (Albedo, Normal, Roughness) to terrain props,
##   sanctuary walls, player structures, stations, trees, and rocks.
## - Zero subsurface_scattering anywhere (100% Compatibility/Mobile safe on Radeon Vega 8).
## - Zero procedural capsule/block fallbacks for characters, enemies, trees, or dragons.

const SHADER_GRACE_AURA: Shader = preload("res://Client/Shaders/combat_grace_aura.gdshader")
const SHADER_DRAGON_FIRE: Shader = preload("res://Client/Shaders/dragon_fire.gdshader")

# Preloaded real rigged .glb assets (forces Godot import & zero runtime fallback to primitives)
const GLB_PATH_KNIGHT: String = "res://Assets/Models/player_knight.glb"
const GLB_PATH_MAGE: String = "res://Assets/Models/player_mage.glb"
const GLB_PATH_CLERIC: String = "res://Assets/Models/player_cleric.glb"
const GLB_PATH_ROGUE: String = "res://Assets/Models/player_rogue.glb"
const GLB_PATH_RANGER: String = "res://Assets/Models/player_ranger.glb"
const GLB_PATH_DRAGON: String = "res://Assets/Models/dragon.glb"

const GLB_KNIGHT: PackedScene = preload("res://Assets/Models/player_knight.glb")
const GLB_MAGE: PackedScene = preload("res://Assets/Models/player_mage.glb")
const GLB_CLERIC: PackedScene = preload("res://Assets/Models/player_cleric.glb")
const GLB_ROGUE: PackedScene = preload("res://Assets/Models/player_rogue.glb")
const GLB_RANGER: PackedScene = preload("res://Assets/Models/player_ranger.glb")
const GLB_DRAGON: PackedScene = preload("res://Assets/Models/dragon.glb")

# Preloaded 1K PBR Texture Sets (Albedo + Normal + Roughness)
const TEX_STONE_ALBEDO: Texture2D = preload("res://Assets/Textures/stone_albedo.jpg")
const TEX_STONE_NORMAL: Texture2D = preload("res://Assets/Textures/stone_normal.jpg")
const TEX_STONE_ROUGH: Texture2D = preload("res://Assets/Textures/stone_roughness.jpg")

const TEX_ROCK_ALBEDO: Texture2D = preload("res://Assets/Textures/rock_albedo.jpg")
const TEX_ROCK_NORMAL: Texture2D = preload("res://Assets/Textures/rock_normal.jpg")
const TEX_ROCK_ROUGH: Texture2D = preload("res://Assets/Textures/rock_roughness.jpg")

const TEX_DIRT_ALBEDO: Texture2D = preload("res://Assets/Textures/dirt_albedo.jpg")
const TEX_DIRT_NORMAL: Texture2D = preload("res://Assets/Textures/dirt_normal.jpg")

const TEX_GRASS_ALBEDO: Texture2D = preload("res://Assets/Textures/grass_albedo.jpg")
const TEX_GRASS_NORMAL: Texture2D = preload("res://Assets/Textures/grass_normal.jpg")
const TEX_GRASS_ROUGH: Texture2D = preload("res://Assets/Textures/grass_roughness.jpg")


# --- 1K PBR Material Builders (Zero Subsurface Scattering — Mobile/Compatibility Clean) ---

static func make_stone_pbr_material(tint: Color = Color(0.95, 0.95, 0.95), uv_scale: float = 0.35) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = TEX_STONE_ALBEDO
	mat.normal_enabled = true
	mat.normal_texture = TEX_STONE_NORMAL
	mat.normal_scale = 1.0
	mat.roughness_texture = TEX_STONE_ROUGH
	mat.roughness = 0.85
	mat.metallic = 0.04
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.subsurf_scatter_enabled = false
	return mat


static func make_rock_pbr_material(tint: Color = Color(0.86, 0.86, 0.9), uv_scale: float = 0.4) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = TEX_ROCK_ALBEDO
	mat.normal_enabled = true
	mat.normal_texture = TEX_ROCK_NORMAL
	mat.normal_scale = 1.15
	mat.roughness_texture = TEX_ROCK_ROUGH
	mat.roughness = 0.9
	mat.metallic = 0.06
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.subsurf_scatter_enabled = false
	return mat


static func make_wood_pbr_material(tint: Color = Color(0.56, 0.38, 0.24), uv_scale: float = 0.45) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = TEX_DIRT_ALBEDO
	mat.normal_enabled = true
	mat.normal_texture = TEX_DIRT_NORMAL
	mat.normal_scale = 0.95
	mat.roughness = 0.86
	mat.metallic = 0.0
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.subsurf_scatter_enabled = false
	return mat


static func make_foliage_pbr_material(tint: Color = Color(0.46, 0.68, 0.4), uv_scale: float = 0.45) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = TEX_GRASS_ALBEDO
	mat.normal_enabled = true
	mat.normal_texture = TEX_GRASS_NORMAL
	mat.normal_scale = 0.85
	mat.roughness_texture = TEX_GRASS_ROUGH
	mat.roughness = 0.84
	mat.metallic = 0.0
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	mat.subsurf_scatter_enabled = false
	return mat


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
	mat.subsurf_scatter_enabled = false
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


# --- GLB Loader & Sanitizer (Guaranteed Load via Preload + GLTFDocument Fallback) ---

static func _find_child_of_type(node: Node, type_name: String) -> Node:
	if node == null:
		return null
	if node.is_class(type_name):
		return node
	for c: Node in node.get_children():
		var found: Node = _find_child_of_type(c, type_name)
		if found != null:
			return found
	return null


static func _find_child_by_name(node: Node, target_name: String) -> Node:
	if node == null:
		return null
	if node.name == target_name:
		return node
	for c: Node in node.get_children():
		var found: Node = _find_child_by_name(c, target_name)
		if found != null:
			return found
	return null


static func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c: Node in node.get_children():
		_collect_mesh_instances(c, out)


static func _instantiate_glb(packed: PackedScene, res_path: String) -> Node3D:
	if packed != null:
		var inst: Node = packed.instantiate()
		if inst is Node3D:
			_sanitize_glb_materials(inst)
			return inst as Node3D
		if inst != null:
			inst.queue_free()

	if ResourceLoader.exists(res_path):
		var loaded: PackedScene = ResourceLoader.load(res_path) as PackedScene
		if loaded != null:
			var inst2: Node = loaded.instantiate()
			if inst2 is Node3D:
				_sanitize_glb_materials(inst2)
				return inst2 as Node3D
			if inst2 != null:
				inst2.queue_free()

	# Runtime GLTFDocument fallback guarantees .glb loads even on unimported fresh clones
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(res_path) or FileAccess.file_exists(abs_path):
		var gltf_doc: GLTFDocument = GLTFDocument.new()
		var gltf_state: GLTFState = GLTFState.new()
		var err: Error = gltf_doc.append_from_file(abs_path, gltf_state)
		if err == OK:
			var generated: Node = gltf_doc.generate_scene(gltf_state)
			if generated is Node3D:
				_sanitize_glb_materials(generated)
				return generated as Node3D
			if generated != null:
				generated.queue_free()

	push_error("[ProceduralMeshFactory] Failed to load required .glb asset: %s" % res_path)
	return Node3D.new()


static func _sanitize_glb_materials(root: Node) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, meshes)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var surf_count: int = mi.mesh.get_surface_count()
		for s: int in range(surf_count):
			var mat: Material = mi.get_active_material(s)
			if mat is BaseMaterial3D:
				var bm: BaseMaterial3D = mat.duplicate() as BaseMaterial3D
				bm.subsurf_scatter_enabled = false
				mi.set_surface_override_material(s, bm)


static func _tint_glb_materials(root: Node, tint_col: Color, blend_weight: float = 0.25, metallic_boost: float = 0.0, emission_col: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, meshes)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for s: int in range(mi.mesh.get_surface_count()):
			var base_mat: Material = mi.get_surface_override_material(s)
			if base_mat == null:
				base_mat = mi.mesh.surface_get_material(s)
			if base_mat is BaseMaterial3D:
				var bm: BaseMaterial3D = base_mat.duplicate() as BaseMaterial3D
				bm.subsurf_scatter_enabled = false
				if blend_weight > 0.001:
					bm.albedo_color = bm.albedo_color.lerp(tint_col, blend_weight)
				if metallic_boost > 0.001:
					bm.metallic = clampf(bm.metallic + metallic_boost, 0.0, 0.92)
				if emission_energy > 0.001:
					bm.emission_enabled = true
					bm.emission = emission_col
					bm.emission_energy_multiplier = emission_energy
				mi.set_surface_override_material(s, bm)


static func _set_nodes_visible(root: Node, names: Array[String], is_vis: bool) -> void:
	for nm: String in names:
		var found: Node = _find_child_by_name(root, nm)
		if found is Node3D:
			(found as Node3D).visible = is_vis


static func _configure_class_glb_attachments(glb_root: Node3D, class_id: String, hide_helmet: bool) -> void:
	# Hide duplicate multi-weapon meshes baked into KayKit Adventurer handslots
	if class_id == "ARCANE_KNIGHT":
		_set_nodes_visible(glb_root, ["1H_Sword_Offhand", "Rectangle_Shield", "Round_Shield", "Spike_Shield", "2H_Sword"], false)
		_set_nodes_visible(glb_root, ["1H_Sword", "Badge_Shield"], true)
		_set_nodes_visible(glb_root, ["Knight_Helmet"], not hide_helmet)
	elif class_id == "PYROMANCER":
		_set_nodes_visible(glb_root, ["1H_Wand", "Spellbook"], false)
		_set_nodes_visible(glb_root, ["2H_Staff", "Spellbook_open"], true)
		_set_nodes_visible(glb_root, ["Mage_Hat"], not hide_helmet)
	elif class_id == "WAR_CLERIC":
		_set_nodes_visible(glb_root, ["1H_Axe_Offhand", "2H_Axe", "Mug"], false)
		_set_nodes_visible(glb_root, ["1H_Axe", "Barbarian_Round_Shield"], true)
		_set_nodes_visible(glb_root, ["Barbarian_Hat"], not hide_helmet)
	elif class_id == "SHADOW_ASSASSIN":
		_set_nodes_visible(glb_root, ["1H_Crossbow", "2H_Crossbow", "Throwable"], false)
		_set_nodes_visible(glb_root, ["Knife", "Knife_Offhand"], true)
	elif class_id == "VALLEY_HUNTER":
		_set_nodes_visible(glb_root, ["Knife", "Knife_Offhand", "1H_Crossbow", "Throwable"], false)
		_set_nodes_visible(glb_root, ["2H_Crossbow"], true)


static func _get_class_glb_pair(class_id: String) -> Array:
	match class_id:
		"PYROMANCER":
			return [GLB_MAGE, GLB_PATH_MAGE]
		"WAR_CLERIC":
			return [GLB_CLERIC, GLB_PATH_CLERIC]
		"SHADOW_ASSASSIN":
			return [GLB_ROGUE, GLB_PATH_ROGUE]
		"VALLEY_HUNTER":
			return [GLB_RANGER, GLB_PATH_RANGER]
		_:
			return [GLB_KNIGHT, GLB_PATH_KNIGHT]


# --- Primitive Helpers (Used strictly for Runic VFX, Structures, Stations & Portals) ---

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
	mesh.rings = maxi(8, int(floorf(float(segments) / 2.0)))
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


# --- Real Rigged .glb Humanoid Characters + Active Runic Guard Barrier ---

static func build_humanoid_rig(root: Node3D, class_id: String, armor_skin_id: String, race_id: String = "HUMAN_VALLEY", appearance: Dictionary = {}) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var skin: Dictionary = GameConfig.COSMETIC_ARMORS.get(armor_skin_id, GameConfig.COSMETIC_ARMORS["default_iron"]) as Dictionary
	var class_def: Dictionary = GameConfig.CLASSES.get(class_id, GameConfig.CLASSES["ARCANE_KNIGHT"]) as Dictionary
	var race_def: Dictionary = GameConfig.RACES.get(race_id, GameConfig.RACES["HUMAN_VALLEY"]) as Dictionary
	var race_scale_y: float = float(race_def.get("scale_y", 1.0))
	var accent: Color = class_def.get("accent_color", Color(0.3, 0.72, 1.0)) as Color
	var hide_helmet: bool = bool(appearance.get("hide_helmet", false))

	# BodyPivot rotated PI so +Z glTF front faces -Z world forward
	var body_pivot: Node3D = Node3D.new()
	body_pivot.name = "BodyPivot"
	body_pivot.rotation.y = PI
	body_pivot.scale = Vector3(1.0, race_scale_y, 1.0)
	root.add_child(body_pivot)

	var pair: Array = _get_class_glb_pair(class_id)
	var custom_glb: Node3D = _instantiate_glb(pair[0] as PackedScene, str(pair[1]))
	custom_glb.name = "ExternalGLB"
	custom_glb.scale = Vector3.ONE * 0.88
	body_pivot.add_child(custom_glb)

	_configure_class_glb_attachments(custom_glb, class_id, hide_helmet)

	# Apply subtle cosmetic armor tint without washing out the real .glb textures
	if armor_skin_id != "default_iron":
		var primary_col: Color = skin.get("primary", Color(0.55, 0.58, 0.64)) as Color
		_tint_glb_materials(custom_glb, primary_col, 0.34, float(skin.get("metallic", 0.3)) * 0.35)
	elif appearance.has("armor_tint"):
		var tint_hex: String = str(appearance.get("armor_tint", ""))
		if tint_hex.length() >= 6:
			_tint_glb_materials(custom_glb, Color.html(tint_hex), 0.22, 0.08)

	var ap: AnimationPlayer = _find_child_of_type(custom_glb, "AnimationPlayer") as AnimationPlayer
	var skel: Skeleton3D = _find_child_of_type(custom_glb, "Skeleton3D") as Skeleton3D
	if ap != null and ap.has_animation("Idle"):
		var idle_anim: Animation = ap.get_animation("Idle")
		if idle_anim != null:
			idle_anim.loop_mode = Animation.LOOP_LINEAR
		ap.play("Idle")

	# Divine Avatar Crown
	var divine_crown: Node3D = Node3D.new()
	divine_crown.name = "DivineCrown"
	divine_crown.position = Vector3(0.0, 2.28, 0.0)
	divine_crown.visible = false
	body_pivot.add_child(divine_crown)
	var crown_mat: StandardMaterial3D = make_pbr_material(Color(1.0, 0.88, 0.35), 0.15, 0.92, Color(1.0, 0.85, 0.3), 2.8)
	_add_torus(divine_crown, 0.28, 0.35, Vector3.ZERO, crown_mat, "DivineHalo")

	# Active Block / Defense Runic Energy Barrier (front of character at -Z in root space)
	var block_barrier: Node3D = _build_runic_block_barrier(root, accent, Vector3(0.0, 1.18, -0.78), 1.0)
	var aura_glb: MeshInstance3D = _build_humanoid_grace_aura(root)

	return {
		"body_pivot": body_pivot,
		"model_root": custom_glb,
		"anim_player": ap,
		"skeleton": skel,
		"block_barrier": block_barrier,
		"divine_crown": divine_crown,
		"grace_aura": aura_glb
	}


static func _build_runic_block_barrier(parent: Node3D, accent: Color, local_pos: Vector3, barrier_scale: float = 1.0) -> Node3D:
	var barrier_root: Node3D = Node3D.new()
	barrier_root.name = "RunicBlockBarrier"
	barrier_root.position = local_pos
	barrier_root.scale = Vector3.ONE * barrier_scale
	barrier_root.visible = false
	parent.add_child(barrier_root)

	var rune_col: Color = accent.lerp(Color(0.45, 0.88, 1.0), 0.45)
	var disc_mat: StandardMaterial3D = make_pbr_material(Color(rune_col.r, rune_col.g, rune_col.b, 0.28), 0.08, 0.15, rune_col, 2.4)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var ring_mat: StandardMaterial3D = make_pbr_material(Color(rune_col.r, rune_col.g, rune_col.b, 0.82), 0.1, 0.2, rune_col.lightened(0.35), 3.4)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Hexagonal translucent runic shield disc
	var hex_disc: MeshInstance3D = MeshInstance3D.new()
	hex_disc.name = "RuneDisc"
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.72
	cm.bottom_radius = 0.72
	cm.height = 0.04
	cm.radial_segments = 6
	hex_disc.mesh = cm
	hex_disc.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	hex_disc.material_override = disc_mat
	barrier_root.add_child(hex_disc)

	# Outer & inner glowing runic rings (spun smoothly in PlayerController)
	_add_torus(barrier_root, 0.64, 0.73, Vector3.ZERO, ring_mat, "OuterRuneRing", Vector3(90.0, 0.0, 0.0))
	_add_torus(barrier_root, 0.34, 0.4, Vector3(0.0, 0.0, -0.03), ring_mat, "InnerRuneRing", Vector3(90.0, 0.0, 0.0))

	return barrier_root


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


# --- First-Person Viewmodel Using Real .glb Weapon & Shield Meshes ---

static func _extract_glb_weapon_mesh(glb_root: Node3D, node_name: String) -> MeshInstance3D:
	var src: Node = _find_child_by_name(glb_root, node_name)
	if src is MeshInstance3D and (src as MeshInstance3D).mesh != null:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "FP_" + node_name
		mi.mesh = (src as MeshInstance3D).mesh
		for s: int in range(mi.mesh.get_surface_count()):
			var mat: Material = (src as MeshInstance3D).get_active_material(s)
			if mat is BaseMaterial3D:
				var dup: BaseMaterial3D = mat.duplicate() as BaseMaterial3D
				dup.subsurf_scatter_enabled = false
				mi.set_surface_override_material(s, dup)
		return mi
	return null


static func build_first_person_viewmodel(root: Node3D, class_id: String, armor_skin_id: String) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var class_def: Dictionary = GameConfig.CLASSES.get(class_id, GameConfig.CLASSES["ARCANE_KNIGHT"]) as Dictionary
	var accent: Color = class_def.get("accent_color", Color(0.3, 0.72, 1.0)) as Color
	var pair: Array = _get_class_glb_pair(class_id)
	var temp_glb: Node3D = _instantiate_glb(pair[0] as PackedScene, str(pair[1]))

	var right_hand: Node3D = Node3D.new()
	right_hand.name = "FPRightHand"
	right_hand.position = Vector3(0.36, -0.32, -0.58)
	root.add_child(right_hand)

	var left_hand: Node3D = Node3D.new()
	left_hand.name = "FPLeftHand"
	left_hand.position = Vector3(-0.38, -0.34, -0.55)
	root.add_child(left_hand)

	var r_weapon_name: String = "1H_Sword"
	var l_weapon_name: String = "Badge_Shield"
	var r_scale: float = 0.42
	var l_scale: float = 0.45
	var r_rot: Vector3 = Vector3(-18.0, 180.0, 0.0)
	var l_rot: Vector3 = Vector3(0.0, 165.0, 0.0)

	if class_id == "PYROMANCER":
		r_weapon_name = "2H_Staff"
		l_weapon_name = "Spellbook_open"
		r_scale = 0.42
		l_scale = 0.38
		r_rot = Vector3(-12.0, 180.0, 0.0)
		l_rot = Vector3(24.0, 155.0, 0.0)
	elif class_id == "WAR_CLERIC":
		r_weapon_name = "1H_Axe"
		l_weapon_name = "Barbarian_Round_Shield"
		r_scale = 0.44
		l_scale = 0.44
	elif class_id == "SHADOW_ASSASSIN":
		r_weapon_name = "Knife"
		l_weapon_name = "Knife_Offhand"
		r_scale = 0.48
		l_scale = 0.48
		l_rot = Vector3(-18.0, 180.0, 0.0)
	elif class_id == "VALLEY_HUNTER":
		r_weapon_name = "2H_Crossbow"
		l_weapon_name = ""
		r_scale = 0.44
		r_rot = Vector3(0.0, 90.0, 0.0)

	var r_mesh: MeshInstance3D = _extract_glb_weapon_mesh(temp_glb, r_weapon_name)
	if r_mesh != null:
		r_mesh.scale = Vector3.ONE * r_scale
		r_mesh.rotation_degrees = r_rot
		right_hand.add_child(r_mesh)

	if not l_weapon_name.is_empty():
		var l_mesh: MeshInstance3D = _extract_glb_weapon_mesh(temp_glb, l_weapon_name)
		if l_mesh != null:
			l_mesh.scale = Vector3.ONE * l_scale
			l_mesh.rotation_degrees = l_rot
			left_hand.add_child(l_mesh)

	temp_glb.free()

	if armor_skin_id != "default_iron":
		var skin: Dictionary = GameConfig.COSMETIC_ARMORS.get(armor_skin_id, {}) as Dictionary
		var pcol: Color = skin.get("primary", Color(0.7, 0.7, 0.75)) as Color
		_tint_glb_materials(right_hand, pcol, 0.25, 0.2)
		_tint_glb_materials(left_hand, pcol, 0.25, 0.2)

	var fp_barrier: Node3D = _build_runic_block_barrier(root, accent, Vector3(0.0, -0.06, -0.72), 0.55)
	return {"right_hand": right_hand, "left_hand": left_hand, "block_barrier": fp_barrier}


# --- Real Rigged dragon.glb Mount (Zero Procedural Blocks/Capsules/Subsurface) ---

static func build_dragon_rig(root: Node3D, dragon_skin_id: String, trail_id: String) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var skin: Dictionary = GameConfig.COSMETIC_DRAGONS.get(dragon_skin_id, GameConfig.COSMETIC_DRAGONS["crimson_wyrm"]) as Dictionary
	var scale_col: Color = skin.get("scales", Color(0.68, 0.16, 0.14)) as Color
	var belly_col: Color = skin.get("belly", Color(0.84, 0.66, 0.44)) as Color
	var wing_col: Color = skin.get("wings", Color(0.45, 0.1, 0.1)) as Color
	var breath_col: Color = skin.get("breath", Color(1.0, 0.45, 0.12)) as Color

	var body: Node3D = Node3D.new()
	body.name = "DragonBody"
	root.add_child(body)

	var custom_dragon: Node3D = _instantiate_glb(GLB_DRAGON, GLB_PATH_DRAGON)
	custom_dragon.name = "ExternalDragonGLB"
	custom_dragon.rotation.y = PI
	custom_dragon.scale = Vector3.ONE * 1.55
	body.add_child(custom_dragon)

	# Apply dragon cosmetic skin colors onto duplicated GLB surface materials (no subsurface!)
	var d_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(custom_dragon, d_meshes)
	for mi: MeshInstance3D in d_meshes:
		if mi.mesh == null:
			continue
		for s: int in range(mi.mesh.get_surface_count()):
			var base_mat: Material = mi.get_surface_override_material(s)
			if base_mat == null:
				base_mat = mi.mesh.surface_get_material(s)
			if base_mat is BaseMaterial3D:
				var bm: BaseMaterial3D = base_mat.duplicate() as BaseMaterial3D
				bm.subsurf_scatter_enabled = false
				var mname: String = bm.resource_name.to_lower()
				if mname.contains("belly"):
					bm.albedo_color = belly_col
					bm.roughness = 0.5
				elif mname.contains("wing"):
					bm.albedo_color = wing_col
					bm.cull_mode = BaseMaterial3D.CULL_DISABLED
					bm.roughness = 0.52
				elif mname.contains("eye"):
					bm.albedo_color = breath_col
					bm.emission_enabled = true
					bm.emission = breath_col
					bm.emission_energy_multiplier = 3.0
				elif mname.contains("claw"):
					bm.albedo_color = Color(0.16, 0.14, 0.12)
					bm.roughness = 0.3
				else:
					bm.albedo_color = scale_col
					bm.roughness = 0.38
					bm.metallic = 0.25
				mi.set_surface_override_material(s, bm)

	var dap: AnimationPlayer = _find_child_of_type(custom_dragon, "AnimationPlayer") as AnimationPlayer
	var dskel: Skeleton3D = _find_child_of_type(custom_dragon, "Skeleton3D") as Skeleton3D
	if dap != null and dap.has_animation("Dragon_Flying"):
		var fa: Animation = dap.get_animation("Dragon_Flying")
		if fa != null:
			fa.loop_mode = Animation.LOOP_LINEAR
		dap.play("Dragon_Flying")

	var cone_glb: MeshInstance3D = _make_dragon_breath_cone(body, breath_col, Vector3(0.0, 2.35, -11.8))
	var aura_glb: MeshInstance3D = _make_dragon_grace_aura(body)

	# Cosmetic Flight Trail
	var trail: CPUParticles3D = CPUParticles3D.new()
	trail.name = "CosmeticTrail"
	trail.position = Vector3(0.0, 1.8, 2.9)
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

	return {
		"body": body,
		"model_root": custom_dragon,
		"head": custom_dragon,
		"anim_player": dap,
		"skeleton": dskel,
		"breath_cone": cone_glb,
		"trail": trail,
		"grace_aura": aura_glb
	}


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


# --- Colossal .glb World Bosses & Dungeon Bosses (Zero Procedural Titans) ---

static func build_world_boss_rig(root: Node3D, style: String) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var body: Node3D = Node3D.new()
	body.name = "BossBody"
	root.add_child(body)

	if style == "wyrm":
		var drig: Dictionary = build_dragon_rig(body, "abyssal_black", "ember_sparks")
		body.scale = Vector3.ONE * 1.95
		return {
			"body": body,
			"dragon_rig": drig,
			"anim_player": drig.get("anim_player", null),
			"is_wyrm": true
		}

	var is_order: bool = (style == "seraphim")
	var boss_glb: Node3D = _instantiate_glb(
		GLB_KNIGHT if is_order else GLB_CLERIC,
		GLB_PATH_KNIGHT if is_order else GLB_PATH_CLERIC
	)
	boss_glb.name = "BossGLB"
	boss_glb.scale = Vector3.ONE * 2.75
	body.add_child(boss_glb)

	if is_order:
		_set_nodes_visible(boss_glb, ["1H_Sword", "1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Round_Shield"], false)
		_set_nodes_visible(boss_glb, ["2H_Sword", "Spike_Shield", "Knight_Helmet"], true)
		_tint_glb_materials(boss_glb, Color(0.98, 0.85, 0.36), 0.58, 0.45, Color(1.0, 0.84, 0.32), 0.45)
	else:
		_set_nodes_visible(boss_glb, ["1H_Axe", "1H_Axe_Offhand", "Barbarian_Round_Shield", "Mug"], false)
		_set_nodes_visible(boss_glb, ["2H_Axe", "Barbarian_Hat"], true)
		_tint_glb_materials(boss_glb, Color(0.18, 0.08, 0.14), 0.65, 0.35, Color(1.0, 0.24, 0.08), 0.65)

	var glow_col: Color = Color(1.0, 0.9, 0.38) if is_order else Color(1.0, 0.26, 0.08)
	var glow_mat: StandardMaterial3D = make_pbr_material(glow_col, 0.15, 0.2, glow_col, 2.8)
	_add_torus(body, 0.9, 1.08, Vector3(0.0, 6.2, 0.0), glow_mat, "BossCrown")

	var bap: AnimationPlayer = _find_child_of_type(boss_glb, "AnimationPlayer") as AnimationPlayer
	if bap != null and bap.has_animation("Idle"):
		var ia: Animation = bap.get_animation("Idle")
		if ia != null:
			ia.loop_mode = Animation.LOOP_LINEAR
		bap.play("Idle")

	return {
		"body": body,
		"model_root": boss_glb,
		"anim_player": bap,
		"is_wyrm": false
	}


# --- 1K PBR Medieval Stations (Blacksmith Forge, Alchemy Bench, Campfire, Market Stall) ---

static func build_station_visual(root: Node3D, station_type: String) -> void:
	for child: Node in root.get_children():
		child.queue_free()
	var stone_mat: StandardMaterial3D = make_stone_pbr_material(Color(0.88, 0.88, 0.9))
	var rock_mat: StandardMaterial3D = make_rock_pbr_material(Color(0.68, 0.68, 0.72))
	var wood_mat: StandardMaterial3D = make_wood_pbr_material(Color(0.58, 0.38, 0.22))
	var iron_mat: StandardMaterial3D = make_pbr_material(Color(0.24, 0.26, 0.3), 0.32, 0.88)
	var fire_mat: StandardMaterial3D = make_pbr_material(Color(1.0, 0.46, 0.12), 0.2, 0.0, Color(1.0, 0.42, 0.08), 3.0)

	if station_type == "forge":
		_add_cylinder(root, 1.35, 1.55, 1.2, Vector3(-0.8, 0.6, -0.4), stone_mat, "ForgeHearth", 10)
		_add_cylinder(root, 0.65, 1.05, 1.9, Vector3(-0.8, 2.1, -0.5), stone_mat, "Chimney", 8)
		_add_sphere(root, 0.72, Vector3(-0.8, 1.28, -0.25), fire_mat, "Embers", Vector3(1.1, 0.45, 1.0))
		_add_cylinder(root, 0.42, 0.5, 0.55, Vector3(1.0, 0.28, 0.4), wood_mat, "AnvilStump", 12)
		_add_cylinder(root, 0.24, 0.34, 0.35, Vector3(1.0, 0.72, 0.4), iron_mat, "AnvilWaist", 10)
		_add_prism(root, Vector3(0.92, 0.36, 0.42), Vector3(1.0, 1.02, 0.4), iron_mat, "AnvilHorn", Vector3(0.0, 0.0, 180.0))
	elif station_type == "campfire":
		_add_torus(root, 0.75, 1.05, Vector3(0.0, 0.14, 0.0), rock_mat, "FireRing")
		_add_sphere(root, 0.48, Vector3(0.0, 0.36, 0.0), fire_mat, "CampFlames", Vector3(1.0, 1.35, 1.0))
		_add_cylinder(root, 0.06, 0.07, 1.9, Vector3(-0.85, 0.9, 0.0), wood_mat, "TripodL", 8, Vector3(0.0, 0.0, -18.0))
		_add_cylinder(root, 0.06, 0.07, 1.9, Vector3(0.85, 0.9, 0.0), wood_mat, "TripodR", 8, Vector3(0.0, 0.0, 18.0))
		_add_sphere(root, 0.44, Vector3(0.0, 0.92, 0.0), iron_mat, "CookingPot", Vector3(1.0, 0.78, 1.0))
	elif station_type == "alchemy":
		var emerald_mat: StandardMaterial3D = make_pbr_material(Color(0.24, 0.95, 0.55), 0.12, 0.1, Color(0.2, 0.9, 0.48), 2.5)
		var arcane_mat: StandardMaterial3D = make_pbr_material(Color(0.45, 0.68, 1.0), 0.12, 0.1, Color(0.38, 0.62, 1.0), 2.5)
		_add_cylinder(root, 1.25, 1.15, 0.16, Vector3(0.0, 0.95, 0.0), wood_mat, "AlchemyTableTop", 12)
		_add_cylinder(root, 0.22, 0.36, 0.92, Vector3(0.0, 0.46, 0.0), stone_mat, "TablePedestal", 10)
		_add_sphere(root, 0.22, Vector3(-0.45, 1.22, 0.15), emerald_mat, "FlaskGreen")
		_add_sphere(root, 0.18, Vector3(0.42, 1.18, -0.2), arcane_mat, "FlaskBlue")
		_add_torus(root, 0.32, 0.38, Vector3(0.0, 1.45, 0.0), arcane_mat, "AlchemyRing")
	else:
		var canopy_mat: StandardMaterial3D = make_pbr_material(Color(0.74, 0.2, 0.16), 0.72, 0.0)
		canopy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_add_cylinder(root, 2.2, 2.35, 0.22, Vector3(0.0, 0.11, 0.0), stone_mat, "StallDeck", 12)
		for p: Vector3 in [Vector3(-1.6, 1.6, -1.0), Vector3(1.6, 1.6, -1.0), Vector3(-1.6, 1.6, 1.0), Vector3(1.6, 1.6, 1.0)]:
			_add_cylinder(root, 0.1, 0.12, 3.1, p, wood_mat, "Post", 8)
		_add_cylinder(root, 0.1, 2.6, 1.1, Vector3(0.0, 3.55, 0.0), canopy_mat, "PavilionCanopy", 8)
		_add_cylinder(root, 0.42, 0.38, 0.85, Vector3(-1.0, 0.55, 0.5), wood_mat, "Barrel1", 12)
		_add_cylinder(root, 0.36, 0.34, 0.75, Vector3(1.05, 0.5, 0.4), wood_mat, "Barrel2", 12)
		_add_sphere(root, 0.22, Vector3(0.0, 2.65, 1.05), fire_mat, "ShopLantern")


# --- 1K PBR Dungeon Entrance Portal ---

static func build_dungeon_portal_visual(root: Node3D, theme: String) -> Node3D:
	for child: Node in root.get_children():
		child.queue_free()
	var is_order: bool = (theme == "order")
	var stone_mat: StandardMaterial3D = make_stone_pbr_material(Color(0.76, 0.78, 0.86) if is_order else Color(0.45, 0.38, 0.42))
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


# --- 1K PBR Player Buildings (Walls, Gates, Towers, Houses, Chests, Altars, Trade Posts) ---

static func build_structure_visual(root: Node3D, piece_type: String, is_ghost: bool = false, valid_ghost: bool = true) -> Dictionary:
	for child: Node in root.get_children():
		child.queue_free()

	var spec: Dictionary = GameConfig.BUILD_PIECES.get(piece_type, GameConfig.BUILD_PIECES["wall"]) as Dictionary
	var base_col: Color = spec.get("color", Color(0.55, 0.55, 0.58)) as Color
	var stone_mat: StandardMaterial3D = make_stone_pbr_material(base_col.lightened(0.35))
	var wood_mat: StandardMaterial3D = make_wood_pbr_material(Color(0.62, 0.42, 0.25))
	var trim_mat: StandardMaterial3D = make_rock_pbr_material(Color(0.52, 0.54, 0.58))

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
		var roof_mat: StandardMaterial3D = make_rock_pbr_material(Color(0.36, 0.42, 0.58)) if not is_ghost else stone_mat
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


# --- Cached 1K PBR Organic Trees & Boulders (Acyclic Shared Meshes for TerrainChunk & Resources) ---

static var _cached_pine_mesh: ArrayMesh = null
static var _cached_oak_mesh: ArrayMesh = null
static var _cached_rock_mesh: ArrayMesh = null


static func _append_uv_cone(st: SurfaceTool, base_y: float, top_y: float, base_r: float, top_r: float, segs: int, jitter: float = 0.0) -> void:
	for i: int in range(segs):
		var u0: float = float(i) / float(segs)
		var u1: float = float(i + 1) / float(segs)
		var a0: float = u0 * TAU
		var a1: float = u1 * TAU
		var r0: float = base_r * (1.0 + sin(a0 * 3.0 + base_y) * jitter)
		var r1: float = base_r * (1.0 + sin(a1 * 3.0 + base_y) * jitter)
		var b0: Vector3 = Vector3(cos(a0) * r0, base_y, sin(a0) * r0)
		var b1: Vector3 = Vector3(cos(a1) * r1, base_y, sin(a1) * r1)
		var t0: Vector3 = Vector3(cos(a0) * top_r, top_y, sin(a0) * top_r)
		var t1: Vector3 = Vector3(cos(a1) * top_r, top_y, sin(a1) * top_r)
		st.set_uv(Vector2(u0 * 2.0, 0.0))
		st.add_vertex(b0)
		st.set_uv(Vector2(u1 * 2.0, 1.0))
		st.add_vertex(t1)
		st.set_uv(Vector2(u0 * 2.0, 1.0))
		st.add_vertex(t0)
		st.set_uv(Vector2(u0 * 2.0, 0.0))
		st.add_vertex(b0)
		st.set_uv(Vector2(u1 * 2.0, 0.0))
		st.add_vertex(b1)
		st.set_uv(Vector2(u1 * 2.0, 1.0))
		st.add_vertex(t1)


static func _append_uv_displaced_sphere(st: SurfaceTool, center: Vector3, radius: float, segs: int, rings: int, jitter: float) -> void:
	var grid: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for r: int in range(rings + 1):
		var v: float = float(r) / float(rings)
		var phi: float = v * PI
		for s: int in range(segs + 1):
			var u: float = float(s) / float(segs)
			var theta: float = u * TAU
			var dir: Vector3 = Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var disp: float = 1.0 + sin(dir.x * 5.2 + dir.y * 4.1) * cos(dir.z * 5.7) * jitter
			grid.append(center + dir * radius * disp)
			uvs.append(Vector2(u * 2.0, v * 2.0))
	var stride: int = segs + 1
	for r: int in range(rings):
		for s: int in range(segs):
			var i00: int = r * stride + s
			var i10: int = i00 + 1
			var i01: int = i00 + stride
			var i11: int = i01 + 1
			st.set_uv(uvs[i00])
			st.add_vertex(grid[i00])
			st.set_uv(uvs[i10])
			st.add_vertex(grid[i10])
			st.set_uv(uvs[i11])
			st.add_vertex(grid[i11])
			st.set_uv(uvs[i00])
			st.add_vertex(grid[i00])
			st.set_uv(uvs[i11])
			st.add_vertex(grid[i11])
			st.set_uv(uvs[i01])
			st.add_vertex(grid[i01])


static func get_shared_pine_mesh() -> ArrayMesh:
	if _cached_pine_mesh != null:
		return _cached_pine_mesh
	var out: ArrayMesh = ArrayMesh.new()
	var st_bark: SurfaceTool = SurfaceTool.new()
	st_bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_bark.set_smooth_group(0)
	_append_uv_cone(st_bark, 0.0, 3.0, 0.4, 0.14, 8, 0.08)
	st_bark.index()
	st_bark.generate_normals()
	st_bark.set_material(make_wood_pbr_material(Color(0.46, 0.32, 0.22), 0.7))
	st_bark.commit(out)

	var st_leaf: SurfaceTool = SurfaceTool.new()
	st_leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_leaf.set_smooth_group(0)
	_append_uv_cone(st_leaf, 1.8, 4.5, 2.25, 0.28, 9, 0.16)
	_append_uv_cone(st_leaf, 3.4, 6.1, 1.75, 0.2, 9, 0.16)
	_append_uv_cone(st_leaf, 4.9, 7.6, 1.2, 0.03, 8, 0.14)
	st_leaf.index()
	st_leaf.generate_normals()
	st_leaf.set_material(make_foliage_pbr_material(Color(0.32, 0.56, 0.34), 0.65))
	st_leaf.commit(out)
	_cached_pine_mesh = out
	return _cached_pine_mesh


static func get_shared_oak_mesh() -> ArrayMesh:
	if _cached_oak_mesh != null:
		return _cached_oak_mesh
	var out: ArrayMesh = ArrayMesh.new()
	var st_bark: SurfaceTool = SurfaceTool.new()
	st_bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_bark.set_smooth_group(0)
	_append_uv_cone(st_bark, 0.0, 3.4, 0.48, 0.24, 9, 0.1)
	st_bark.index()
	st_bark.generate_normals()
	st_bark.set_material(make_wood_pbr_material(Color(0.5, 0.35, 0.24), 0.65))
	st_bark.commit(out)

	var st_leaf: SurfaceTool = SurfaceTool.new()
	st_leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_leaf.set_smooth_group(0)
	var crown_blobs: Array = [
		[Vector3(0.0, 4.4, 0.0), 2.2],
		[Vector3(1.25, 3.85, 0.72), 1.55],
		[Vector3(-1.15, 4.05, -0.62), 1.65],
		[Vector3(0.22, 5.45, -0.32), 1.45]
	]
	for blob_var: Variant in crown_blobs:
		var blob: Array = blob_var as Array
		_append_uv_displaced_sphere(st_leaf, blob[0] as Vector3, float(blob[1]), 8, 6, 0.22)
	st_leaf.index()
	st_leaf.generate_normals()
	st_leaf.set_material(make_foliage_pbr_material(Color(0.45, 0.7, 0.38), 0.55))
	st_leaf.commit(out)
	_cached_oak_mesh = out
	return _cached_oak_mesh


static func get_shared_rock_mesh() -> ArrayMesh:
	if _cached_rock_mesh != null:
		return _cached_rock_mesh
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	_append_uv_displaced_sphere(st, Vector3(0.0, 0.45, 0.0), 0.95, 10, 7, 0.28)
	st.index()
	st.generate_normals()
	st.set_material(make_rock_pbr_material(Color(0.84, 0.84, 0.88), 0.55))
	_cached_rock_mesh = st.commit()
	return _cached_rock_mesh


# --- 1K PBR Gatherable Resource Nodes (Organic Textured Trees & Rocky Veins) ---

static func build_resource_visual(root: Node3D, resource_type: String) -> void:
	for child: Node in root.get_children():
		child.queue_free()

	if resource_type == "wood":
		var tree_mi: MeshInstance3D = MeshInstance3D.new()
		tree_mi.name = "OakResourceTree"
		tree_mi.mesh = get_shared_oak_mesh()
		tree_mi.scale = Vector3.ONE * 0.85
		root.add_child(tree_mi)
	elif resource_type == "iron_ore" or resource_type == "silver_ore" or resource_type == "gold_ore":
		var rock_mi: MeshInstance3D = MeshInstance3D.new()
		rock_mi.name = "OreBoulder"
		rock_mi.mesh = get_shared_rock_mesh()
		rock_mi.scale = Vector3(1.25, 0.9, 1.15)
		root.add_child(rock_mi)
		var vein_col: Color = Color(0.68, 0.72, 0.78)
		var emit_e: float = 0.0
		if resource_type == "silver_ore":
			vein_col = Color(0.84, 0.9, 1.0)
			emit_e = 0.8
		elif resource_type == "gold_ore":
			vein_col = Color(1.0, 0.82, 0.26)
			emit_e = 1.4
		var ore_mat: StandardMaterial3D = make_pbr_material(vein_col, 0.22, 0.92, vein_col, emit_e)
		_add_prism(root, Vector3(0.45, 0.85, 0.45), Vector3(0.35, 0.95, 0.2), ore_mat, "Vein1", Vector3(16.0, 25.0, -18.0))
		_add_prism(root, Vector3(0.38, 0.72, 0.38), Vector3(-0.42, 0.85, -0.18), ore_mat, "Vein2", Vector3(-18.0, -30.0, 22.0))
	elif resource_type == "raw_meat":
		var crate_mat: StandardMaterial3D = make_wood_pbr_material(Color(0.64, 0.32, 0.24))
		var bone_mat: StandardMaterial3D = make_pbr_material(Color(0.92, 0.88, 0.78), 0.65, 0.0)
		_add_sphere(root, 0.62, Vector3(0.0, 0.55, 0.0), crate_mat, "GameRoast", Vector3(1.3, 0.75, 0.95), 10)
		_add_cylinder(root, 0.12, 0.12, 1.25, Vector3(0.0, 0.55, 0.0), bone_mat, "Bone", 8, Vector3(0.0, 0.0, 90.0))
	elif resource_type == "alchemy_herb":
		var stem_mat: StandardMaterial3D = make_foliage_pbr_material(Color(0.24, 0.62, 0.32))
		var bloom_mat: StandardMaterial3D = make_pbr_material(Color(0.35, 1.0, 0.68), 0.2, 0.0, Color(0.28, 0.95, 0.62), 2.4)
		for i: int in range(5):
			var ang: float = (float(i) / 5.0) * TAU
			var sx: float = cos(ang) * 0.42
			var sz: float = sin(ang) * 0.42
			_add_cylinder(root, 0.03, 0.06, 0.85, Vector3(sx, 0.42, sz), stem_mat, "Stem_%d" % i, 6, Vector3(sin(ang) * 18.0, 0.0, -cos(ang) * 18.0))
			_add_sphere(root, 0.16, Vector3(sx * 1.25, 0.88, sz * 1.25), bloom_mat, "Bloom_%d" % i)
	elif resource_type == "stone":
		var b1: MeshInstance3D = MeshInstance3D.new()
		b1.name = "Boulder1"
		b1.mesh = get_shared_rock_mesh()
		b1.scale = Vector3(1.35, 0.95, 1.2)
		root.add_child(b1)
		var b2: MeshInstance3D = MeshInstance3D.new()
		b2.name = "Boulder2"
		b2.mesh = get_shared_rock_mesh()
		b2.position = Vector3(0.85, -0.05, 0.45)
		b2.scale = Vector3(0.85, 0.7, 0.85)
		root.add_child(b2)
	else:
		var rock_mi: MeshInstance3D = MeshInstance3D.new()
		rock_mi.name = "OreBase"
		rock_mi.mesh = get_shared_rock_mesh()
		rock_mi.scale = Vector3(1.15, 0.72, 1.15)
		root.add_child(rock_mi)
		var crystal_mat: StandardMaterial3D = make_pbr_material(Color(0.32, 0.78, 1.0), 0.12, 0.3, Color(0.24, 0.68, 1.0), 2.8)
		_add_cylinder(root, 0.03, 0.28, 2.0, Vector3(0.0, 1.15, 0.0), crystal_mat, "Crystal1", 6, Vector3(8.0, 0.0, -10.0))
		_add_cylinder(root, 0.02, 0.2, 1.45, Vector3(0.45, 0.88, 0.25), crystal_mat, "Crystal2", 6, Vector3(-14.0, 15.0, 22.0))
		_add_cylinder(root, 0.02, 0.2, 1.35, Vector3(-0.42, 0.82, -0.2), crystal_mat, "Crystal3", 6, Vector3(18.0, -20.0, -20.0))


static func build_loot_chest_visual(root: Node3D) -> void:
	for child: Node in root.get_children():
		child.queue_free()
	var wood_mat: StandardMaterial3D = make_wood_pbr_material(Color(0.55, 0.34, 0.18))
	var gold_mat: StandardMaterial3D = make_pbr_material(Color(0.95, 0.78, 0.24), 0.24, 0.88, Color(0.95, 0.75, 0.2), 0.9)
	_add_box(root, Vector3(1.15, 0.56, 0.72), Vector3(0.0, 0.28, 0.0), wood_mat, "ChestBase")
	_add_cylinder(root, 0.36, 0.36, 1.15, Vector3(0.0, 0.56, 0.0), wood_mat, "ChestLid", 10, Vector3(0.0, 0.0, 90.0))
	_add_torus(root, 0.35, 0.4, Vector3(-0.32, 0.56, 0.0), gold_mat, "GoldBandL", Vector3(0.0, 0.0, 90.0))
	_add_torus(root, 0.35, 0.4, Vector3(0.32, 0.56, 0.0), gold_mat, "GoldBandR", Vector3(0.0, 0.0, 90.0))
	var beam_mat: StandardMaterial3D = make_pbr_material(Color(1.0, 0.82, 0.32, 0.35), 0.2, 0.0, Color(1.0, 0.8, 0.25), 1.8)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add_cylinder(root, 0.12, 0.22, 3.8, Vector3(0.0, 2.2, 0.0), beam_mat, "LootBeacon", 10)
