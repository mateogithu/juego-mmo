class_name CharacterCreator
extends HBoxContainer

## 3D Character Creator with rotating SubViewport preview, 5 Classes, 5 Races,
## and appearance customization (skin tone, hair color, armor tint, hide helmet).

signal selection_changed(class_id: String, race_id: String, appearance: Dictionary)

var selected_class_id: String = "ARCANE_KNIGHT"
var selected_race_id: String = "HUMAN_VALLEY"
var appearance: Dictionary = {
	"skin_hex": "#e6bc98",
	"hair_hex": "#3b2618",
	"armor_tint": "#96a2b4",
	"hide_helmet": false
}

var _preview_root: Node3D = null
var _preview_holder: Node3D = null
var _class_opt: OptionButton = null
var _race_opt: OptionButton = null
var _desc_label: Label = null
var _skin_opt: OptionButton = null
var _armor_tint_opt: OptionButton = null
var _hide_helm_cb: CheckBox = null

const SKIN_PRESETS: Array[Dictionary] = [
	{"name": "Alba Clara", "hex": "#f0c8a8"},
	{"name": "Valle Cálido", "hex": "#d9a276"},
	{"name": "Norteño Pálido", "hex": "#e5d5c8"},
	{"name": "Ceniza Oscura", "hex": "#7f5b4a"},
	{"name": "Ébano Profundo", "hex": "#4b3224"}
]

const TINT_PRESETS: Array[Dictionary] = [
	{"name": "Acero Clásico", "hex": "#96a2b4"},
	{"name": "Oro del Orden", "hex": "#e8c052"},
	{"name": "Llama del Caos", "hex": "#cf432b"},
	{"name": "Esmeralda Bosque", "hex": "#3f9c64"},
	{"name": "Amatista Arcana", "hex": "#7f52cc"}
]


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_build_ui()
	_rebuild_3d_preview()


func _build_ui() -> void:
	# Left: 3D Rotating SubViewport Preview
	var vp_container: SubViewportContainer = SubViewportContainer.new()
	vp_container.custom_minimum_size = Vector2(210.0, 240.0)
	vp_container.stretch = true
	add_child(vp_container)

	var vp: SubViewport = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.size = Vector2i(210, 240)
	vp_container.add_child(vp)

	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.11, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 1.15
	env_node.environment = env
	vp.add_child(env_node)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	light.light_energy = 1.4
	vp.add_child(light)

	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0.0, 1.25, 3.0)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true
	vp.add_child(cam)

	_preview_root = Node3D.new()
	vp.add_child(_preview_root)
	_preview_holder = Node3D.new()
	_preview_root.add_child(_preview_holder)

	# Pedestal
	var ped: MeshInstance3D = MeshInstance3D.new()
	var pm: CylinderMesh = CylinderMesh.new()
	pm.top_radius = 0.85
	pm.bottom_radius = 1.0
	pm.height = 0.16
	ped.mesh = pm
	ped.position = Vector3(0.0, -0.08, 0.0)
	ped.material_override = ProceduralMeshFactory.make_stone_pbr_material(Color(0.32, 0.36, 0.42))
	vp.add_child(ped)

	# Right: Controls
	var ctrl: VBoxContainer = VBoxContainer.new()
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.add_theme_constant_override("separation", 6)
	add_child(ctrl)

	var c_lbl: Label = Label.new()
	c_lbl.text = "Clase (5 Clases Jugables)"
	ctrl.add_child(c_lbl)

	_class_opt = OptionButton.new()
	var c_idx: int = 0
	for cid: String in GameConfig.CLASSES.keys():
		var cdef: Dictionary = GameConfig.CLASSES[cid] as Dictionary
		_class_opt.add_item(str(cdef.get("name", cid)), c_idx)
		_class_opt.set_item_metadata(c_idx, cid)
		c_idx += 1
	_class_opt.item_selected.connect(_on_class_selected)
	ctrl.add_child(_class_opt)

	var r_lbl: Label = Label.new()
	r_lbl.text = "Raza (5 Razas con Pasivas)"
	ctrl.add_child(r_lbl)

	_race_opt = OptionButton.new()
	var r_idx: int = 0
	for rid: String in GameConfig.RACES.keys():
		var rdef: Dictionary = GameConfig.RACES[rid] as Dictionary
		_race_opt.add_item("%s" % str(rdef.get("name", rid)), r_idx)
		_race_opt.set_item_metadata(r_idx, rid)
		r_idx += 1
	_race_opt.item_selected.connect(_on_race_selected)
	ctrl.add_child(_race_opt)

	var app_row: HBoxContainer = HBoxContainer.new()
	app_row.add_theme_constant_override("separation", 6)
	ctrl.add_child(app_row)

	_skin_opt = OptionButton.new()
	_skin_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i: int in range(SKIN_PRESETS.size()):
		_skin_opt.add_item("Piel: %s" % str(SKIN_PRESETS[i]["name"]), i)
	_skin_opt.item_selected.connect(_on_appearance_changed)
	app_row.add_child(_skin_opt)

	_armor_tint_opt = OptionButton.new()
	_armor_tint_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i: int in range(TINT_PRESETS.size()):
		_armor_tint_opt.add_item("Tinte: %s" % str(TINT_PRESETS[i]["name"]), i)
	_armor_tint_opt.item_selected.connect(_on_appearance_changed)
	app_row.add_child(_armor_tint_opt)

	_hide_helm_cb = CheckBox.new()
	_hide_helm_cb.text = "Ocultar yelmo / mostrar rostro"
	_hide_helm_cb.toggled.connect(func(pressed: bool) -> void:
		appearance["hide_helmet"] = pressed
		_emit_selection()
	)
	ctrl.add_child(_hide_helm_cb)

	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_font_size_override("font_size", 12)
	_desc_label.add_theme_color_override("font_color", Color(0.84, 0.88, 0.95))
	ctrl.add_child(_desc_label)
	_update_description()


func _process(delta: float) -> void:
	if _preview_holder != null:
		_preview_holder.rotation.y += delta * 0.75


func _on_class_selected(idx: int) -> void:
	selected_class_id = str(_class_opt.get_item_metadata(idx))
	_update_description()
	_rebuild_3d_preview()
	_emit_selection()


func _on_race_selected(idx: int) -> void:
	selected_race_id = str(_race_opt.get_item_metadata(idx))
	var rdef: Dictionary = GameConfig.RACES.get(selected_race_id, {}) as Dictionary
	var rcol: Color = rdef.get("default_skin", Color(0.88, 0.72, 0.58)) as Color
	appearance["skin_hex"] = "#" + rcol.to_html(false)
	_update_description()
	_rebuild_3d_preview()
	_emit_selection()


func _on_appearance_changed(_idx: int) -> void:
	var si: int = clampi(_skin_opt.selected, 0, SKIN_PRESETS.size() - 1)
	var ti: int = clampi(_armor_tint_opt.selected, 0, TINT_PRESETS.size() - 1)
	appearance["skin_hex"] = str(SKIN_PRESETS[si]["hex"])
	appearance["armor_tint"] = str(TINT_PRESETS[ti]["hex"])
	_rebuild_3d_preview()
	_emit_selection()


func _update_description() -> void:
	if _desc_label == null:
		return
	var cdef: Dictionary = GameConfig.CLASSES.get(selected_class_id, {}) as Dictionary
	var rdef: Dictionary = GameConfig.RACES.get(selected_race_id, {}) as Dictionary
	_desc_label.text = "%s\nRaza: %s — %s" % [
		str(cdef.get("description", "")),
		str(rdef.get("name", "")),
		str(rdef.get("desc", ""))
	]


func _rebuild_3d_preview() -> void:
	if _preview_holder == null:
		return
	var refs: Dictionary = ProceduralMeshFactory.build_humanoid_rig(
		_preview_holder,
		selected_class_id,
		"default_iron",
		selected_race_id,
		appearance
	)
	var bp: Node3D = refs.get("body_pivot", null) as Node3D
	if bp != null:
		bp.rotation.y = 0.0 # Face camera in 3D character creator preview
	var ap: AnimationPlayer = refs.get("anim_player", null) as AnimationPlayer
	if ap != null and ap.has_animation("Idle"):
		var anim: Animation = ap.get_animation("Idle")
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		ap.play("Idle")


func _emit_selection() -> void:
	selection_changed.emit(selected_class_id, selected_race_id, appearance.duplicate(true))
