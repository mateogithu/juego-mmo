class_name MainMenu
extends Control

## Main Menu: Account Login/Register, Medieval Class & Cosmetic Selection,
## Crónicas del Mundo button, Connect (IP:Port), Host Local, and Launch Dedicated Server.

@onready var user_input: LineEdit = $Margin/RootVBox/Columns/LeftCard/LeftVBox/UserInput
@onready var pass_input: LineEdit = $Margin/RootVBox/Columns/LeftCard/LeftVBox/PassInput
@onready var register_check: CheckButton = $Margin/RootVBox/Columns/LeftCard/LeftVBox/RegisterCheck
@onready var host_input: LineEdit = $Margin/RootVBox/Columns/LeftCard/LeftVBox/NetGrid/HostInput
@onready var port_input: SpinBox = $Margin/RootVBox/Columns/LeftCard/LeftVBox/NetGrid/PortInput
@onready var connect_btn: Button = $Margin/RootVBox/Columns/LeftCard/LeftVBox/ButtonsBox/ConnectBtn
@onready var host_btn: Button = $Margin/RootVBox/Columns/LeftCard/LeftVBox/ButtonsBox/HostBtn
@onready var dedicated_btn: Button = $Margin/RootVBox/Columns/LeftCard/LeftVBox/ButtonsBox/DedicatedBtn
@onready var lore_btn: Button = $Margin/RootVBox/Columns/LeftCard/LeftVBox/LoreBtn
@onready var status_label: Label = $Margin/RootVBox/StatusLabel

@onready var class_option: OptionButton = $Margin/RootVBox/Columns/RightCard/RightVBox/ClassOption
@onready var class_desc: RichTextLabel = $Margin/RootVBox/Columns/RightCard/RightVBox/ClassDesc
@onready var armor_option: OptionButton = $Margin/RootVBox/Columns/RightCard/RightVBox/ArmorOption
@onready var dragon_option: OptionButton = $Margin/RootVBox/Columns/RightCard/RightVBox/DragonOption

var _class_keys: Array[String] = []
var _armor_keys: Array[String] = []
var _dragon_keys: Array[String] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Auto-boot Dedicated Headless Server if launched with --server or headless display
	if NetworkManager.is_dedicated_server_launch():
		var port: int = NetworkManager.get_launch_port()
		var err: Error = NetworkManager.start_dedicated_server(port)
		if err == OK:
			get_tree().change_scene_to_file.call_deferred("res://Client/World/World.tscn")
		return

	_populate_selectors()

	host_input.text = str(DatabaseManager.client_prefs.get("last_host", GameConfig.DEFAULT_HOST))
	port_input.value = float(DatabaseManager.client_prefs.get("last_port", GameConfig.DEFAULT_PORT))
	user_input.text = str(DatabaseManager.client_prefs.get("last_username", ""))

	connect_btn.pressed.connect(_on_connect_pressed)
	host_btn.pressed.connect(_on_host_pressed)
	dedicated_btn.pressed.connect(_on_dedicated_pressed)
	lore_btn.pressed.connect(_on_lore_pressed)
	class_option.item_selected.connect(_on_class_selected)

	NetworkManager.connection_status_changed.connect(_on_status_changed)
	NetworkManager.auth_succeeded.connect(_on_auth_succeeded)
	NetworkManager.auth_failed.connect(_on_auth_failed)
	_on_class_selected(0)
	_setup_gamepad_focus_neighbors()


func _setup_gamepad_focus_neighbors() -> void:
	var left_chain: Array[Control] = [user_input, pass_input, register_check, host_input, port_input, host_btn, connect_btn, dedicated_btn, lore_btn]
	for i: int in range(left_chain.size()):
		var ctrl: Control = left_chain[i]
		if i > 0:
			ctrl.focus_neighbor_top = ctrl.get_path_to(left_chain[i - 1])
		if i < left_chain.size() - 1:
			ctrl.focus_neighbor_bottom = ctrl.get_path_to(left_chain[i + 1])
		ctrl.focus_neighbor_right = ctrl.get_path_to(class_option)

	var right_chain: Array[Control] = [class_option, armor_option, dragon_option]
	for i: int in range(right_chain.size()):
		var ctrl: Control = right_chain[i]
		if i > 0:
			ctrl.focus_neighbor_top = ctrl.get_path_to(right_chain[i - 1])
		if i < right_chain.size() - 1:
			ctrl.focus_neighbor_bottom = ctrl.get_path_to(right_chain[i + 1])
		ctrl.focus_neighbor_left = ctrl.get_path_to(host_btn)

	if user_input.text.strip_edges().is_empty():
		user_input.grab_focus()
	else:
		host_btn.grab_focus()


func _populate_selectors() -> void:
	class_option.clear()
	_class_keys.clear()
	for cid: Variant in GameConfig.CLASSES.keys():
		var key: String = str(cid)
		var spec: Dictionary = GameConfig.CLASSES[key] as Dictionary
		_class_keys.append(key)
		class_option.add_item("%s — %s" % [str(spec["name"]), str(spec["role"])])

	armor_option.clear()
	_armor_keys.clear()
	for aid: Variant in GameConfig.COSMETIC_ARMORS.keys():
		var key: String = str(aid)
		var spec: Dictionary = GameConfig.COSMETIC_ARMORS[key] as Dictionary
		_armor_keys.append(key)
		var tag: String = " (Gratis)" if int(spec["price_crowns"]) == 0 else " (Tienda: %d Coronas)" % int(spec["price_crowns"])
		armor_option.add_item(str(spec["name"]) + tag)

	dragon_option.clear()
	_dragon_keys.clear()
	for did: Variant in GameConfig.COSMETIC_DRAGONS.keys():
		var key: String = str(did)
		var spec: Dictionary = GameConfig.COSMETIC_DRAGONS[key] as Dictionary
		_dragon_keys.append(key)
		var tag: String = " (Gratis)" if int(spec["price_crowns"]) == 0 else " (Tienda: %d Coronas)" % int(spec["price_crowns"])
		dragon_option.add_item(str(spec["name"]) + tag)


func _on_class_selected(idx: int) -> void:
	if idx < 0 or idx >= _class_keys.size():
		return
	var key: String = _class_keys[idx]
	var c: Dictionary = GameConfig.CLASSES[key] as Dictionary
	var abilities: Array = c.get("abilities", []) as Array
	var ab_lines: String = ""
	for i: int in range(abilities.size()):
		var ab: Dictionary = abilities[i] as Dictionary
		ab_lines += "\n  [color=#ffe066][%d] %s:[/color] %s" % [i + 1, str(ab["name"]), str(ab["desc"])]
	class_desc.text = (
		"[b]%s[/b]\n%s\n\n"
		+ "[color=#9ec5fe]HP:[/color] %d  |  [color=#9ec5fe]Maná:[/color] %d  |  [color=#9ec5fe]Estamina:[/color] %d\n"
		+ "[color=#9ec5fe]Ataque:[/color] %d  |  [color=#9ec5fe]Poder Mágico:[/color] %d  |  [color=#9ec5fe]Defensa:[/color] %d\n"
		+ "\n[b]Habilidades Activas:[/b]%s"
	) % [
		str(c["name"]),
		str(c["description"]),
		int(c["max_hp"]),
		int(c["max_mana"]),
		int(c["max_stamina"]),
		int(c["attack_power"]),
		int(c["spell_power"]),
		int(c["defense"]),
		ab_lines
	]


func _collect_cosmetics_choice() -> Dictionary:
	var a_key: String = _armor_keys[armor_option.selected] if armor_option.selected >= 0 and armor_option.selected < _armor_keys.size() else "default_iron"
	var d_key: String = _dragon_keys[dragon_option.selected] if dragon_option.selected >= 0 and dragon_option.selected < _dragon_keys.size() else "crimson_wyrm"
	return {
		"equipped_armor": a_key,
		"equipped_dragon": d_key,
		"equipped_trail": "none"
	}


func _save_prefs() -> void:
	DatabaseManager.client_prefs["last_host"] = host_input.text.strip_edges()
	DatabaseManager.client_prefs["last_port"] = int(port_input.value)
	DatabaseManager.client_prefs["last_username"] = user_input.text.strip_edges()
	DatabaseManager.save_client_prefs()


func _validate_credentials() -> bool:
	var u: String = user_input.text.strip_edges()
	var p: String = pass_input.text
	if u.length() < 3:
		status_label.text = "Ingresá un nombre de usuario de al menos 3 caracteres."
		return false
	if p.length() < 4:
		status_label.text = "Ingresá una contraseña de al menos 4 caracteres."
		return false
	return true


func _on_connect_pressed() -> void:
	AudioSynth.play_ui_click()
	if not _validate_credentials():
		return
	_save_prefs()
	var cid: String = _class_keys[class_option.selected] if class_option.selected >= 0 else "ARCANE_KNIGHT"
	NetworkManager.connect_to_server(
		host_input.text.strip_edges(),
		int(port_input.value),
		user_input.text.strip_edges(),
		pass_input.text,
		register_check.button_pressed,
		cid,
		_collect_cosmetics_choice()
	)


func _on_host_pressed() -> void:
	AudioSynth.play_ui_click()
	if not _validate_credentials():
		return
	_save_prefs()
	var cid: String = _class_keys[class_option.selected] if class_option.selected >= 0 else "ARCANE_KNIGHT"
	NetworkManager.start_host(
		int(port_input.value),
		user_input.text.strip_edges(),
		pass_input.text,
		register_check.button_pressed,
		cid,
		_collect_cosmetics_choice()
	)


func _on_dedicated_pressed() -> void:
	AudioSynth.play_ui_click()
	var err: Error = NetworkManager.start_dedicated_server(int(port_input.value))
	if err == OK:
		get_tree().change_scene_to_file("res://Client/World/World.tscn")
	else:
		status_label.text = "No se pudo lanzar el Servidor Dedicado en el puerto %d." % int(port_input.value)


func _on_lore_pressed() -> void:
	AudioSynth.play_ui_click()
	IntroLore.enter_world_after = false
	get_tree().change_scene_to_file("res://Client/UI/IntroLore.tscn")


func _on_status_changed(text: String) -> void:
	status_label.text = text


func _on_auth_failed(reason: String) -> void:
	status_label.text = "Error: " + reason


func _on_auth_succeeded(profile: Dictionary, is_new: bool) -> void:
	var uname: String = str(profile.get("username", ""))
	if is_new and not DatabaseManager.has_seen_intro(uname):
		DatabaseManager.mark_intro_seen(uname)
		IntroLore.enter_world_after = true
		get_tree().change_scene_to_file("res://Client/UI/IntroLore.tscn")
	else:
		get_tree().change_scene_to_file("res://Client/World/World.tscn")
