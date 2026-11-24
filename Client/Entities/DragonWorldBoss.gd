class_name DragonWorldBoss
extends WorldBoss

## Supreme Dragon World Boss inhabiting "Valle Dracónico / Nido de los Ancestros".
## Strongest creature in the world below Orden & Caos; defeating it drops the
## "Piedra de Vínculo de Dragón" mount item directly into contestable loot.


func _ready() -> void:
	super._ready()
	add_to_group("dragon_world_bosses")


func _rebuild_visual() -> void:
	boss_style = "wyrm"
	_rig = ProceduralMeshFactory.build_world_boss_rig(visual_root, "wyrm")
	var drig: Dictionary = _rig.get("dragon_rig", {}) as Dictionary
	var ap: AnimationPlayer = drig.get("anim_player", null) as AnimationPlayer
	if ap != null and ap.has_animation("Dragon_Flying"):
		var anim: Animation = ap.get_animation("Dragon_Flying")
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		ap.play("Dragon_Flying")
	_update_label()


func _update_label() -> void:
	if label_3d == null:
		return
	label_3d.modulate = Color(1.0, 0.55, 0.2)
	label_3d.text = "🐉 JEFE SUPREMO: %s 🐉\nHP: %d / %d (Otorga Sello de Dragón Ancestral)" % [boss_name, int(ceilf(hp)), int(max_hp)]
