class_name IntroLore
extends Control

## Official Mythology Opening Cinematic (IntroLore.tscn).
## Automatically played on first account creation (with Skip button)
## and accessible anytime via "Crónicas del Mundo" in MainMenu.

static var enter_world_after: bool = false

@onready var chapter_title: Label = $MarginContainer/VBox/HeaderBox/ChapterTitle
@onready var lore_text: RichTextLabel = $MarginContainer/VBox/Panel/Margin/LoreText
@onready var progress_label: Label = $MarginContainer/VBox/FooterBox/ProgressLabel
@onready var next_button: Button = $MarginContainer/VBox/FooterBox/NextButton
@onready var skip_button: Button = $MarginContainer/VBox/FooterBox/SkipButton
@onready var backdrop: ColorRect = $Backdrop

const CHAPTER_TITLES: Array[String] = [
	"I. LOS DOS ARQUITECTOS PRIMORDIALES",
	"II. EL ALMA NEUTRAL Y EL DOMINIO DE LOS DRAGONES",
	"III. EL DESCENSO Y LA GRACIA COMBATIVA"
]

var _current_index: int = 0
var _fade_tween: Tween = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	next_button.pressed.connect(_on_next_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	AudioSynth.play_combat_grace_fanfare()
	_show_chapter(0)
	next_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_skip_pressed()
		get_viewport().set_input_as_handled()


func _show_chapter(idx: int) -> void:
	_current_index = clampi(idx, 0, GameConfig.OFFICIAL_LORE_CHAPTERS.size() - 1)
	chapter_title.text = CHAPTER_TITLES[_current_index]
	var raw: String = GameConfig.OFFICIAL_LORE_CHAPTERS[_current_index]
	var styled: String = raw.replace("El Orden", "[color=#ffe066][b]El Orden[/b][/color]")
	styled = styled.replace("El Caos", "[color=#ff6448][b]El Caos[/b][/color]")
	styled = styled.replace("Gracia Combativa", "[color=#ffe066][b]Gracia Combativa[/b][/color]")
	lore_text.text = "[center][i]\"%s\"[/i][/center]" % styled
	progress_label.text = "Crónica %d de %d" % [_current_index + 1, GameConfig.OFFICIAL_LORE_CHAPTERS.size()]

	if _current_index == GameConfig.OFFICIAL_LORE_CHAPTERS.size() - 1:
		next_button.text = "Entrar al Mundo" if enter_world_after else "Volver al Menú"
	else:
		next_button.text = "Siguiente Capítulo"

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	lore_text.modulate.a = 0.0
	chapter_title.modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(chapter_title, "modulate:a", 1.0, 0.55)
	_fade_tween.tween_property(lore_text, "modulate:a", 1.0, 0.85)

	var bg_colors: Array[Color] = [
		Color(0.06, 0.08, 0.14, 1.0),
		Color(0.09, 0.07, 0.11, 1.0),
		Color(0.13, 0.09, 0.07, 1.0)
	]
	_fade_tween.tween_property(backdrop, "color", bg_colors[_current_index], 0.9)


func _on_next_pressed() -> void:
	AudioSynth.play_ui_click()
	if _current_index < GameConfig.OFFICIAL_LORE_CHAPTERS.size() - 1:
		_show_chapter(_current_index + 1)
	else:
		_finish_intro()


func _on_skip_pressed() -> void:
	AudioSynth.play_ui_click()
	_finish_intro()


func _finish_intro() -> void:
	var go_world: bool = enter_world_after
	enter_world_after = false
	if go_world:
		get_tree().change_scene_to_file("res://Client/World/World.tscn")
	else:
		get_tree().change_scene_to_file("res://Client/UI/MainMenu.tscn")
