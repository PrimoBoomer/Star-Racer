extends Control

class_name UI

var tree_root: TreeItem

@onready var star_racer = %Game

@onready var min_players_field: LineEdit = $OnlineMenu/Container/CreateLobbyMenu1/MinPlayersField
@onready var max_players_field: LineEdit = $OnlineMenu/Container/CreateLobbyMenu1/MaxPlayersField
@onready var lobby_name_field: LineEdit = $OnlineMenu/Container/CreateLobbyMenu2/LobbyNameField
@onready var nickname_field: LineEdit = $OnlineMenu/Container/PlayerOptions/NicknameField
@onready var car_color_button: Button = $OnlineMenu/Container/PlayerOptions/ColorPickerButton
@onready var join_button: Button = $OnlineMenu/Container/CreateLobbyMenu3/JoinButton
@onready var create_button: Button = $OnlineMenu/Container/CreateLobbyMenu2/CreateButton
@onready var leave_button: Button = $PlayMenuPanel/PlayMenu/LeaveButton
@onready var back_button: Button = $IntermissionMenu/Container/BackButton
@onready var refresh_list_button: Button = $OnlineMenu/Container/CreateLobbyMenu3/RefreshListButton
@onready var lobbies_list: Tree = $OnlineMenu/Container/LobbiesList
@onready var info_label: Label = $InfoLabel
@onready var intermission_menu: Control = $IntermissionMenu
@onready var online_menu: Control = $OnlineMenu
@onready var play_menu_panel: Control = $PlayMenuPanel
@onready var alpha_info: Control = $AlphaInfo
@onready var car_color_picker_panel: Panel = $ColorPickerPanel
@onready var car_color_picker: ColorPicker = $ColorPickerPanel/ColorPicker
@onready var players_in_lobby: VBoxContainer = $IntermissionMenu/Container/Control/PlayersInLobby
@onready var intermission_lobby_name: Label = $IntermissionMenu/Container/LobbyName
@onready var intermission_track_name: Label = $IntermissionMenu/Container/CurrentTrackname
@onready var intermission_players_count: Label = $IntermissionMenu/Container/PlayersCount
@onready var intermission_players_list: VBoxContainer = $IntermissionMenu/Container/Control/PlayersInLobby
@onready var network = %Network
@onready var label_scene: PackedScene = load("res://scenes/label.tscn")
@onready var countdown_label: Label = $IntermissionMenu/Container/CountdownLabel
@onready var menu_background: ColorRect = $MenuBackground
@onready var start_lights = $StartLights

var bindings_label: Label

var _car_model_idx: int = 0
var _car_model_label: Label = null
var _car_preview_viewport: SubViewport = null
var _car_preview_node: Node3D = null
var _pilot_color_rect: ColorRect = null

var _track_picker: OptionButton = null

func _ready() -> void:
	self.lobbies_list.set_column_title(0, "Name");
	self.lobbies_list.set_column_title(1, "Owner");
	self.lobbies_list.set_column_title(2, "Players");
	self.lobbies_list.set_column_title(3, "Min needed");
	self.lobbies_list.set_column_title(4, "State");
	self.lobbies_list.set_column_title(5, "Start time");
	self.lobbies_list.set_column_title(6, "Track");

	self.bindings_label = Label.new()
	self.bindings_label.position = Vector2(12, 12)
	self.bindings_label.text = _build_bindings_text()
	self.bindings_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	self.bindings_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	self.bindings_label.add_theme_constant_override("outline_size", 4)
	self.bindings_label.visible = false
	add_child(self.bindings_label)

	self.car_color_button.visible = false
	_setup_pilot_panel()
	_setup_track_picker()

func _setup_pilot_panel() -> void:
	var container := $OnlineMenu/Container as VBoxContainer

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.16, 0.60)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.34, 0.55, 0.78, 0.45)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12.0; sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0;  sb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", sb)
	container.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	panel.add_child(hbox)

	# 3D preview
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(480, 370)
	svc.size_flags_horizontal = SIZE_SHRINK_CENTER
	svc.stretch = true
	hbox.add_child(svc)

	_car_preview_viewport = SubViewport.new()
	_car_preview_viewport.size = Vector2i(480, 370)
	_car_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_car_preview_viewport.transparent_bg = false
	svc.add_child(_car_preview_viewport)

	var cam := Camera3D.new()
	cam.look_at_from_position(Vector3(5.5, 3.5, 7.0), Vector3(0.0, 0.5, 0.0), Vector3.UP)
	_car_preview_viewport.add_child(cam)

	var dir_light := DirectionalLight3D.new()
	dir_light.rotation = Vector3(-PI / 4.0, PI / 4.0, 0.0)
	dir_light.shadow_enabled = false
	dir_light.light_energy = 1.2
	_car_preview_viewport.add_child(dir_light)

	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-5.0, 3.0, -3.0)
	fill_light.light_energy = 0.4
	_car_preview_viewport.add_child(fill_light)

	var wenv := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.10, 0.16)
	env.ambient_light_color = Color(0.75, 0.80, 0.90)
	env.ambient_light_energy = 0.5
	wenv.environment = env
	_car_preview_viewport.add_child(wenv)

	# Right column
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.size_flags_vertical = SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 8)
	hbox.add_child(right)

	var model_hdr := Label.new()
	model_hdr.text = "MODÈLE"
	model_hdr.add_theme_font_size_override("font_size", 12)
	model_hdr.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95, 0.75))
	right.add_child(model_hdr)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	right.add_child(nav)

	var prev_btn := Button.new()
	prev_btn.text = "‹"
	prev_btn.custom_minimum_size = Vector2(34, 32)
	prev_btn.pressed.connect(_on_car_prev)
	nav.add_child(prev_btn)

	_car_model_label = Label.new()
	_car_model_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_car_model_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_model_label.text = Game.CAR_MODELS[0]["name"]
	nav.add_child(_car_model_label)

	var next_btn := Button.new()
	next_btn.text = "›"
	next_btn.custom_minimum_size = Vector2(34, 32)
	next_btn.pressed.connect(_on_car_next)
	nav.add_child(next_btn)

	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	right.add_child(spacer)

	var color_hdr := Label.new()
	color_hdr.text = "COULEUR"
	color_hdr.add_theme_font_size_override("font_size", 12)
	color_hdr.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95, 0.75))
	right.add_child(color_hdr)

	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 8)
	right.add_child(color_row)

	_pilot_color_rect = ColorRect.new()
	_pilot_color_rect.color = Color(1, 1, 1)
	_pilot_color_rect.custom_minimum_size = Vector2(32, 32)
	_pilot_color_rect.size_flags_vertical = SIZE_SHRINK_CENTER
	color_row.add_child(_pilot_color_rect)

	var color_btn := Button.new()
	color_btn.text = "Choisir…"
	color_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	color_btn.pressed.connect(func():
		car_color_picker_panel.visible = not car_color_picker_panel.visible
	)
	color_row.add_child(color_btn)

	_update_car_preview()

func _setup_track_picker() -> void:
	var menu1 := $OnlineMenu/Container/CreateLobbyMenu1 as HBoxContainer
	var label := Label.new()
	label.text = "Track:"
	menu1.add_child(label)

	_track_picker = OptionButton.new()
	_track_picker.size_flags_horizontal = SIZE_EXPAND_FILL
	_track_picker.disabled = true
	_track_picker.add_item("(loading...)")
	menu1.add_child(_track_picker)

func _update_car_preview() -> void:
	if _car_preview_viewport == null:
		return
	if _car_preview_node != null:
		_car_preview_node.queue_free()
		_car_preview_node = null

	var model_def: Dictionary = Game.get_car_model(Game.CAR_MODELS[_car_model_idx]["id"])
	var scene := load(model_def["path"]) as PackedScene
	if scene == null:
		return
	_car_preview_node = scene.instantiate() as Node3D
	_car_preview_node.transform = model_def["transform"]
	_car_preview_viewport.add_child(_car_preview_node)

	if _car_model_label != null:
		_car_model_label.text = model_def["name"]

func _on_car_prev() -> void:
	_car_model_idx = (_car_model_idx - 1 + Game.CAR_MODELS.size()) % Game.CAR_MODELS.size()
	_update_car_preview()

func _on_car_next() -> void:
	_car_model_idx = (_car_model_idx + 1) % Game.CAR_MODELS.size()
	_update_car_preview()

func get_car_model_id() -> String:
	return Game.CAR_MODELS[_car_model_idx]["id"]

func set_car_model_id(model_id: String) -> void:
	for i in Game.CAR_MODELS.size():
		if Game.CAR_MODELS[i]["id"] == model_id:
			_car_model_idx = i
			_update_car_preview()
			return

func _build_bindings_text() -> String:
	var lines: Array[String] = []
	for action in InputMap.get_actions():
		var s := str(action)
		if s.begins_with("ui_"):
			continue
		var keys: Array[String] = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				keys.append(ev.as_text().replace(" (Physical)", ""))
		if keys.is_empty():
			continue
		lines.append("%s: %s" % [s, ", ".join(keys)])
	return "\n".join(lines)

func _process(_delta: float) -> void:
	self.join_button.disabled = self.lobbies_list.get_selected() == null
	var in_race: bool = %Game.mode == Game.Mode.IN_RACE
	self.bindings_label.visible = in_race and not %Game.paused
	if %Game.mode == Game.Mode.IN_RACE or %Game.mode == Game.Mode.SPECTATOR:
		if Input.is_action_just_released("Pause"):
			self.play_menu_panel.visible = ! self.play_menu_panel.visible

func switch_mode(next_mode: Game.Mode, server_up: bool):
	if %Game.mode == Game.Mode.WELCOME_PAGE:
		self.join_button.disabled = true
		self.refresh_list_button.disabled = true
		self.create_button.disabled = true
		if next_mode == Game.Mode.FETCH_LOBBIES:
			self.info_label.text = "Fetching lobbies..."
	elif %Game.mode == Game.Mode.LOBBY_INTERMISSION:
		self.intermission_menu.visible = false

	if next_mode == Game.Mode.WELCOME_PAGE:
		self.alpha_info.visible = true
		self.online_menu.visible = true
		self.play_menu_panel.visible = false
		self.menu_background.visible = true
		self.info_label.text = ""
		self.refresh_list_button.disabled = false
		if self.star_racer.mode == Game.Mode.IN_RACE \
		   || self.star_racer.mode == Game.Mode.LOBBY_INTERMISSION \
		   || self.star_racer.mode == Game.Mode.SPECTATOR:
			self.create_button.disabled = false
			self.nickname_field.grab_focus()
		elif self.star_racer.mode == Game.Mode.FETCH_LOBBIES:
			if !server_up:
				self.info_label.text = "Couldn't connect to server"
				self.join_button.disabled = true
				self.create_button.disabled = true
			else:
				self.info_label.text = "Lobbies fetched, select one to join or create a new one"
				self.join_button.disabled = false
				self.create_button.disabled = (_track_picker == null) or (_track_picker.item_count == 0) or _track_picker.disabled
	elif next_mode == Game.Mode.LOBBY_INTERMISSION:
		self.back_button.grab_focus()
		for child in self.players_in_lobby.get_children():
			child.queue_free()
		self.intermission_menu.visible = true
		self.online_menu.visible = false
		self.menu_background.visible = true
		self.info_label.text = ""
	elif next_mode == Game.Mode.IN_RACE:
		self.leave_button.grab_focus()
		self.alpha_info.visible = false
		self.online_menu.visible = false
		self.intermission_menu.visible = false
		self.menu_background.visible = false
		self.info_label.text = ""
	elif next_mode == Game.Mode.SPECTATOR:
		self.alpha_info.visible = false
		self.online_menu.visible = false
		self.intermission_menu.visible = false
		self.menu_background.visible = false
		self.info_label.text = "Spectating — next race you'll be in"

func _on_back_to_race_pressed() -> void:
	self.play_menu_panel.visible = false
	self.star_racer.paused = false

func _on_leave_pressed() -> void:
	self.star_racer.paused = false
	self.network.terminate()

func _on_back_pressed() -> void:
	self.online_menu.visible = false

func _on_join_button_pressed() -> void:
	self.star_racer.switch_mode(Game.Mode.JOINING_LOBBY, true)

func _on_create_button_pressed() -> void:
	self.star_racer.switch_mode(Game.Mode.CREATING_LOBBY, true)

func _on_back_button_pressed() -> void:
	self.network.terminate()

func refresh_tracks(tracks: Array) -> void:
	if _track_picker == null:
		return
	var prev_id := get_selected_track_id()
	_track_picker.clear()
	for i in tracks.size():
		var t: Dictionary = tracks[i]
		_track_picker.add_item(String(t.get("name", t.get("id", "?"))), i)
		_track_picker.set_item_metadata(i, String(t.get("id", "")))
	_track_picker.disabled = tracks.is_empty()
	if !prev_id.is_empty():
		for i in _track_picker.item_count:
			if String(_track_picker.get_item_metadata(i)) == prev_id:
				_track_picker.select(i)
				break
	if !tracks.is_empty() && self.star_racer.mode == Game.Mode.FETCH_LOBBIES:
		self.create_button.disabled = false

func get_selected_track_id() -> String:
	if _track_picker == null || _track_picker.item_count == 0:
		return ""
	var idx := _track_picker.selected
	if idx < 0:
		idx = 0
	var meta = _track_picker.get_item_metadata(idx)
	return String(meta) if meta != null else ""

func refresh(lobby_infos: Array):
	self.lobbies_list.clear()
	self.tree_root = self.lobbies_list.create_item()

	for info in lobby_infos:
		var item = self.tree_root.create_child()

		item.set_text(0, info.name)
		item.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_text(1, info.owner)
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_text(2, str(int(info.player_count)) + "/" + str(int(info.max_players)))
		item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_text(3, str(int(info.min_players)))
		item.set_text_alignment(3, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_text(4, str("Racing" if info.racing else "Intermission"))
		item.set_text_alignment(4, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_text(5, info.start_time)
		item.set_text_alignment(5, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_text(6, str(info.get("track_name", "")))
		item.set_text_alignment(6, HORIZONTAL_ALIGNMENT_CENTER)

func set_color_picker_button_color(color: Color) -> void:
	if _pilot_color_rect:
		_pilot_color_rect.color = color

func _on_refresh_list_button_pressed() -> void:
	%Game.switch_mode(Game.Mode.FETCH_LOBBIES, false)

func _on_color_picker_color_changed(color: Color) -> void:
	set_color_picker_button_color(color)

func _on_button_pressed() -> void:
	self.car_color_picker_panel.visible = ! self.car_color_picker_panel.visible

func _on_color_picker_visibility_changed() -> void:
	self.car_color_button.text = "Close color picker" if self.car_color_picker.visible else "Pick your car color"

func get_min_players() -> int:
	return int(self.min_players_field.text)

func get_max_players() -> int:
	return int(self.max_players_field.text)

func get_lobby_name() -> String:
	return self.lobby_name_field.text

func get_nickname() -> String:
	return self.nickname_field.text

func get_car_color() -> Color:
	return self.car_color_picker.color

func set_min_players(value: int) -> void:
	self.min_players_field.text = str(value)

func set_max_players(value: int) -> void:
	self.max_players_field.text = str(value)

func set_lobby_name(value: String) -> void:
	self.lobby_name_field.text = value

func set_nickname(value: String) -> void:
	self.nickname_field.text = value

func set_car_color(value: Color) -> void:
	self.car_color_picker.color = value
	set_color_picker_button_color(value)

func set_intermission_lobby_name(str_name: String) -> void:
	self.intermission_lobby_name.text = str_name

func set_intermission_track_name(str_name: String) -> void:
	self.intermission_track_name.text = str_name

func add_player_to_lobby(player_name: String, color: Color = Color(0.55, 0.78, 0.95)) -> void:
	if self.players_in_lobby.get_node_or_null(player_name):
		return
	self.players_in_lobby.add_child(_make_pilot_chip(player_name, color))

func clear_players_in_lobby() -> void:
	for child in self.players_in_lobby.get_children():
		child.queue_free()

func set_intermission_players_count(str_count: String) -> void:
	self.intermission_players_count.text = str_count

func set_intermission_players_list(players: Array) -> void:
	# Drop chips for players no longer in the lobby.
	var present := {}
	for player in players:
		present[String(player["nickname"])] = true
	for child in self.players_in_lobby.get_children():
		if not present.has(child.name):
			child.queue_free()

	for player in players:
		var nickname: String = player["nickname"]
		if self.players_in_lobby.get_node_or_null(nickname):
			continue
		var col := Color(0.55, 0.78, 0.95)
		if player.has("color"):
			var raw = player["color"]
			if raw is Color:
				col = raw
			elif raw is Dictionary:
				col = Color(float(raw.get("x", 0.55)), float(raw.get("y", 0.78)), float(raw.get("z", 0.95)))
		self.players_in_lobby.add_child(_make_pilot_chip(nickname, col))

func _make_pilot_chip(nickname: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = nickname
	chip.size_flags_horizontal = SIZE_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.13, 0.22, 0.78)
	sb.set_border_width_all(1)
	sb.border_color = color
	sb.border_width_left = 6
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	chip.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	chip.add_child(hbox)

	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = SIZE_SHRINK_CENTER
	hbox.add_child(dot)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 0)
	hbox.add_child(spacer)

	var label := Label.new()
	label.text = nickname
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.add_child(label)

	return chip

func get_play_menu_panel():
	return self.play_menu_panel

func get_selected_lobby_name() -> String:
	var selected_item: TreeItem = (self.lobbies_list as Tree).get_selected()
	return selected_item.get_text(0)

func set_info_label(text: String):
	self.info_label.text = text

func show_pre_race_view() -> void:
	self.intermission_menu.visible = false
	self.online_menu.visible = false
	self.alpha_info.visible = false
	self.menu_background.visible = false

func reset_start_lights() -> void:
	if self.start_lights:
		self.start_lights.reset()

func start_lights_countdown(time_sec: float) -> void:
	if self.start_lights:
		self.start_lights.on_countdown(time_sec)

func start_lights_go() -> void:
	if self.start_lights:
		self.start_lights.on_race_started()

func show_race_results(rankings: Array) -> void:
	for child in self.players_in_lobby.get_children():
		child.queue_free()
	for i in rankings.size():
		var label := Label.new()
		label.text = "%d.  %s" % [i + 1, rankings[i]]
		self.players_in_lobby.add_child(label)
	self.info_label.text = "Race finished!"
