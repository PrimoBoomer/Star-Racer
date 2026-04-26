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
@onready var back_button: Button = $IntermissionMenu/BackButton
@onready var refresh_list_button: Button = $OnlineMenu/Container/CreateLobbyMenu3/RefreshListButton
@onready var lobbies_list: Tree = $OnlineMenu/Container/LobbiesList
@onready var info_label: Label = $InfoLabel
@onready var intermission_menu: Control = $IntermissionMenu
@onready var online_menu: Control = $OnlineMenu
@onready var play_menu_panel: Control = $PlayMenuPanel
@onready var alpha_info: Control = $AlphaInfo
@onready var car_color_picker_panel: Panel = $ColorPickerPanel
@onready var car_color_picker: ColorPicker = $ColorPickerPanel/ColorPicker
@onready var players_in_lobby: VBoxContainer = $IntermissionMenu/Control/PlayersInLobby
@onready var intermission_lobby_name: Label = $IntermissionMenu/LobbyName
@onready var intermission_track_name: Label = $IntermissionMenu/CurrentTrackname
@onready var intermission_players_list: VBoxContainer = $IntermissionMenu/Control/PlayersInLobby
@onready var network = %Network
@onready var label_scene: PackedScene = load("res://scenes/label.tscn")
@onready var countdown_label: Label = $IntermissionMenu/CountdownLabel

var bindings_label: Label

func _ready() -> void:
	self.lobbies_list.set_column_title(0, "Name");
	self.lobbies_list.set_column_title(1, "Owner");
	self.lobbies_list.set_column_title(2, "Players");
	self.lobbies_list.set_column_title(3, "Min needed");
	self.lobbies_list.set_column_title(4, "State");
	self.lobbies_list.set_column_title(5, "Start time");

	self.bindings_label = Label.new()
	self.bindings_label.position = Vector2(12, 12)
	self.bindings_label.text = _build_bindings_text()
	self.bindings_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	self.bindings_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	self.bindings_label.add_theme_constant_override("outline_size", 4)
	self.bindings_label.visible = false
	add_child(self.bindings_label)

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
				self.create_button.disabled = false
	elif next_mode == Game.Mode.LOBBY_INTERMISSION:
		self.back_button.grab_focus()
		for child in self.players_in_lobby.get_children():
			child.queue_free()
		self.intermission_menu.visible = true
		self.online_menu.visible = false
		self.info_label.text = ""
	elif next_mode == Game.Mode.IN_RACE:
		self.leave_button.grab_focus()
		self.alpha_info.visible = false
		self.online_menu.visible = false
		self.intermission_menu.visible = false
		self.info_label.text = ""
	elif next_mode == Game.Mode.SPECTATOR:
		self.alpha_info.visible = false
		self.online_menu.visible = false
		self.intermission_menu.visible = false
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

func set_color_picker_button_color(color: Color) -> void:
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = color
	stylebox.corner_radius_top_left = 15
	stylebox.corner_radius_top_right = 15
	stylebox.corner_radius_bottom_left = 15
	stylebox.corner_radius_bottom_right = 15
	self.car_color_button.add_theme_stylebox_override("normal", stylebox)
	self.car_color_button.add_theme_stylebox_override("hover", stylebox)
	self.car_color_button.add_theme_stylebox_override("pressed", stylebox)

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
	self.car_color_button.text = "Close color picker"

func set_intermission_lobby_name(str_name: String) -> void:
	self.intermission_lobby_name.text = str_name

func set_intermission_track_name(str_name: String) -> void:
	self.intermission_track_name.text = str_name

func add_player_to_lobby(player_name: String) -> void:
	var label = Label.new()
	label.text = player_name
	self.players_in_lobby.add_child(label)

func clear_players_in_lobby() -> void:
	for child in self.players_in_lobby.get_children():
		child.queue_free()

func set_intermission_players_count(str_count: String) -> void:
	self.countdown_label.text = str_count

func set_intermission_players_list(players: Array) -> void:
	for player in players:
		var nickname: String = player["nickname"]
		if ! self.players_in_lobby.get_node_or_null(nickname):
			var label: Label = self.label_scene.instantiate()
			label.text = nickname
			label.name = nickname
			self.players_in_lobby.add_child(label)

func get_play_menu_panel():
	return self.play_menu_panel

func get_selected_lobby_name() -> String:
	var selected_item: TreeItem = (self.lobbies_list as Tree).get_selected()
	return selected_item.get_text(0)

func set_info_label(text: String):
	self.info_label.text = text

func show_race_results(rankings: Array) -> void:
	for child in self.players_in_lobby.get_children():
		child.queue_free()
	for i in rankings.size():
		var label := Label.new()
		label.text = "%d.  %s" % [i + 1, rankings[i]]
		self.players_in_lobby.add_child(label)
	self.info_label.text = "Race finished!"
