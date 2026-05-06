extends Node

class_name Game

const CAR_MODELS = [
	{"id": "sport",   "name": "Sport",
	 "path": "res://scenes/cars/sport.tscn",
	 "wheel_fl": "WheelFL", "wheel_fr": "WheelFR",
	 "body_mesh": "body"},
	{"id": "classic", "name": "Classic",
	 "path": "res://scenes/cars/classic.tscn",
	 "wheel_fl": "WheelFL", "wheel_fr": "WheelFR",
	 "body_mesh": "body"},
	{"id": "future",  "name": "Future",
	 "path": "res://scenes/cars/future.tscn",
	 "wheel_fl": "WheelFL", "wheel_fr": "WheelFR",
	 "body_mesh": "body"},
]

static func get_car_model(model_id: String) -> Dictionary:
	for m in CAR_MODELS:
		if m["id"] == model_id:
			var def: Dictionary = m.duplicate()
			def["transform"] = Transform3D.IDENTITY
			return def
	return get_car_model("sport")

enum Mode {
	WELCOME_PAGE,
	FETCH_LOBBIES,
	CREATING_LOBBY,
	JOINING_LOBBY,
	LOBBY_INTERMISSION,
	IN_RACE,
	SPECTATOR,
}

var modes_strings = {
	Mode.WELCOME_PAGE: "WELCOME PAGE",
	Mode.FETCH_LOBBIES: "FETCHING",
	Mode.CREATING_LOBBY: "CREATING",
	Mode.JOINING_LOBBY: "JOINING",
	Mode.LOBBY_INTERMISSION: "INTERMISSION",
	Mode.IN_RACE: "RACING",
	Mode.SPECTATOR: "SPECTATOR",
}

class NameGenerator:
	static func nickname() -> String:
		var prefixes = ["Neo", "Dark", "Ultra", "Mega", "Hyper", "Shadow", "Cyber", "Iron", "Ghost"]
		var cores = ["Fox", "Wolf", "Tiger", "Eagle", "Viper", "Falcon", "Blade", "Storm", "Nova"]
		var suffixes = ["", "X", "99", "Pro", "HD", "Prime", "Z", "One"]
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		return prefixes[rng.randi_range(0, prefixes.size() - 1)] \
			+ cores[rng.randi_range(0, cores.size() - 1)] \
			+ suffixes[rng.randi_range(0, suffixes.size() - 1)]

	static func lobby_name() -> String:
		var adjectives = ["Red", "Blue", "Green", "Yellow", "Purple", "Orange", "Silver", "Golden", "Black"]
		var nouns = ["Comet", "Meteor", "Asteroid", "Nebula", "Galaxy", "Star", "Planet", "Rocket", "Satellite"]
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		return adjectives[rng.randi_range(0, adjectives.size() - 1)] \
			+ nouns[rng.randi_range(0, nouns.size() - 1)]

class Settings:
	const FILE_PATH = "user://settings.cfg"

	static func save(ui: UI) -> void:
		var config = ConfigFile.new()
		var game = ui.get_node("%Game") as Game
		if game.check_min_players(ui.get_min_players()):
			config.set_value("Settings", "min_players", ui.get_min_players())
		if game.check_max_players(ui.get_max_players()):
			config.set_value("Settings", "max_players", ui.get_max_players())
		if game.check_lobby_name(ui.get_lobby_name()):
			config.set_value("Settings", "lobby_name", ui.get_lobby_name())
		if game.check_nickname(ui.get_nickname()):
			config.set_value("Settings", "nickname", ui.get_nickname())
		config.set_value("Settings", "car_color", ui.get_car_color())
		config.save(FILE_PATH)

	static func load(ui: UI, defaults: Dictionary) -> void:
		var config = ConfigFile.new()
		if config.load(FILE_PATH) != OK:
			if config.save(FILE_PATH) != OK:
				printerr("Could not create settings file")
				return
		ui.set_min_players(int(config.get_value("Settings", "min_players", defaults.min_players)))
		ui.set_max_players(int(config.get_value("Settings", "max_players", defaults.max_players)))
		ui.set_lobby_name(config.get_value("Settings", "lobby_name", defaults.lobby_name))
		ui.set_nickname(config.get_value("Settings", "nickname", defaults.nickname))
		var c_arr = config.get_value("Settings", "car_color", defaults.car_color)
		ui.set_car_color(Color(c_arr[0], c_arr[1], c_arr[2]))

class MessageParser:

	static func parse_join_response(msg: Dictionary) -> Dictionary:
		var joined = msg["Response"]["LobbyJoined"]
		if joined.has("error") and joined["error"] != null:
			var err = joined["error"]
			var err_str = "Unknown error: %s" % str(err)
			match err:
				"NicknameAlreadyUsed": err_str = "Nickname already in use"
				"LobbyFull":           err_str = "Lobby is full"
				"LobbyAlreadyExists":  err_str = "Lobby already exists"
				"LobbyNotFound":       err_str = "Lobby not found"
				"InvalidLobbyConfig":  err_str = "Invalid lobby configuration"
				"TrackNotFound":       err_str = "Track not found on server"
			return {"ok": false, "error_str": err_str}
		return {
			"ok": true,
			"track_id": String(joined.get("track_id", "")),
			"race_ongoing": bool(joined.get("race_ongoing", false)),
			"min_players": int(joined.get("min_players", 2)),
			"max_players": int(joined.get("max_players", 4)),
			"track": joined.get("track", null),
		}

	static func parse_player(raw: Dictionary) -> Dictionary:
		var pos = raw["position"]
		var rot = raw["rotation"]
		var col = raw["color"]
		return {
			"nickname": raw["nickname"],
			"racing": raw["racing"],
			"laps": int(raw.get("laps", 0)),
			"position": Vector3(pos["x"], pos["y"], pos["z"]),
			"rotation": Quaternion(rot["x"], rot["y"], rot["z"], rot["w"]),
			"color": Color(col["x"], col["y"], col["z"]),
		}

	static func parse_spawn_info(raw: Dictionary) -> Dictionary:
		var pos = raw["position"]
		return {
			"y_rotation": float(raw["y_rotation"]),
			"position": Vector3(pos["x"], pos["y"], pos["z"]),
		}

	static func color_to_proto(color: Color) -> Dictionary:
		return {"x": color.r, "y": color.g, "z": color.b}

class GhostManager:
	var _node: Node3D = null
	var _target_pos: Vector3 = Vector3.ZERO
	var _target_rot: Quaternion = Quaternion.IDENTITY
	var _velocity: Vector3 = Vector3.ZERO
	var _last_time: float = 0.0

	func setup(track: Node3D, scene: PackedScene, color: Color) -> void:
		self._node = scene.instantiate() as Node3D
		self._node.name = "__ghost__"
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color.r, color.g, color.b, 0.4)
		for mesh_name in ["Body", "WheelFixedLeft", "WheelFixedRight", "WheelTurnLeft", "WheelTurnRight"]:
			(self._node.get_node(mesh_name) as MeshInstance3D).set_surface_override_material(0, mat)
		self._node.visible = false
		track.add_child(self._node)

	func apply_server_state(pos: Vector3, rot: Quaternion) -> void:
		if !self._node:
			return
		var now := Time.get_ticks_msec() * 0.001
		if !self._node.visible:
			self._node.position = pos
			self._node.quaternion = rot
			self._node.visible = true
		else:
			var dt := now - self._last_time
			if dt > 0.0:
				self._velocity = (pos - self._target_pos) / dt
		self._last_time = now
		self._target_pos = pos
		self._target_rot = rot

	func interpolate(delta: float) -> void:
		if !self._node || !self._node.visible:
			return
		self._node.position += self._velocity * delta
		self._node.position = self._node.position.lerp(self._target_pos, delta * 5.0)
		self._node.quaternion = self._node.quaternion.slerp(self._target_rot, delta * 6.0)

	func clear() -> void:
		if self._node:
			self._node.queue_free()
			self._node = null

class OpponentManager:
	var _track: Node3D
	var _states: Dictionary = {}

	func _init(track: Node3D) -> void:
		self._track = track

	func update(player: Dictionary) -> void:
		var nickname: String = player["nickname"]
		var now := Time.get_ticks_msec() * 0.001

		if nickname not in self._states:
			var rng := RandomNumberGenerator.new()
			rng.seed = nickname.hash()
			var rand_m = Game.CAR_MODELS[rng.randi() % Game.CAR_MODELS.size()]
			var model_def = Game.get_car_model(rand_m["id"])
			var model_scene := load(model_def["path"]) as PackedScene
			var model_node := model_scene.instantiate() as Node3D
			model_node.transform = model_def["transform"]
			var mat := StandardMaterial3D.new()
			mat.albedo_color = player["color"]
			var body_mesh := model_node.find_child(model_def["body_mesh"], true, false) as MeshInstance3D
			if body_mesh:
				body_mesh.set_surface_override_material(0, mat)
			var node := Node3D.new()
			node.name = nickname
			node.add_child(model_node)
			self._track.add_child(node, true)

			node.position = player["position"]
			node.quaternion = player["rotation"]
			self._states[nickname] = {
				"node": node,
				"target_pos": player["position"],
				"target_rot": player["rotation"],
				"velocity": Vector3.ZERO,
				"last_time": now,
			}
			return

		var state: Dictionary = self._states[nickname]
		var dt: float = now - state["last_time"]
		if dt > 0.0:
			state["velocity"] = (player["position"] - state["target_pos"]) / dt
		state["target_pos"] = player["position"]
		state["target_rot"] = player["rotation"]
		state["last_time"] = now

	func interpolate(delta: float) -> void:
		for nickname in self._states:
			var state: Dictionary = self._states[nickname]
			var node: Node3D = state["node"]

			node.position += state["velocity"] * delta

			node.position = node.position.lerp(state["target_pos"], delta * 8.0)
			node.quaternion = node.quaternion.slerp(state["target_rot"], delta * 8.0)

	func clear() -> void:
		for state in self._states.values():
			state["node"].queue_free()
		self._states.clear()

var _debug_enabled := false
@export var MIN_LIMIT_PLAYERS := 1
@export var MAX_LIMIT_PLAYERS := 6
@export var MIN_PLAYERS_DEFAULT = 2
@export var MAX_PLAYERS_DEFAULT = 4
@export var COLOR_DEFAULT = [1.0, 1.0, 1.0]
var available_tracks: Array = []  # Array of {id, name}, populated from server
var _fetch_pending: int = 0  # responses still expected during FETCH_LOBBIES

@onready var player_scene: PackedScene = load("res://scenes/player.tscn")
@onready var opponent_scene: PackedScene = load("res://scenes/opponent.tscn")

var mode = Mode.WELCOME_PAGE
var track_node: Node3D = null
var track_def: Dictionary = {}
var car_node: Node3D = null
var paused = false

var _opponents: OpponentManager
var _ghost: GhostManager
var _spectator_camera: Camera3D = null
var _spectator_target: Vector3 = Vector3.ZERO
var _last_race_rankings: Array = []
var _lobby_min_players: int = 2
var _lobby_max_players: int = 4
var regex = RegEx.new()

func _init():
	self.regex.compile("^[A-Za-z][A-Za-z0-9_]*$")

func _ready() -> void:
	_load_settings()
	switch_mode(Mode.FETCH_LOBBIES, false)

func _unhandled_input(event: InputEvent) -> void:
	if OS.has_feature("debug") \
	and event is InputEventKey and event.pressed and not event.echo \
	and event.keycode == KEY_F3:
		self._debug_enabled = not self._debug_enabled

func _process(delta):
	if self.mode == Mode.IN_RACE or self.mode == Mode.SPECTATOR:
		if Input.is_action_just_released("Pause"):
			self.paused = ! self.paused
		if self._ghost:
			self._ghost.interpolate(delta)
	if self.mode == Mode.IN_RACE || self.mode == Mode.SPECTATOR:
		if self._opponents:
			self._opponents.interpolate(delta)
	if self.mode == Mode.SPECTATOR and self._spectator_camera != null:
		var cam_goal := _spectator_target + Vector3(0.0, 22.0, 14.0)
		self._spectator_camera.global_position = self._spectator_camera.global_position.lerp(cam_goal, delta * 3.5)
		if _spectator_target != Vector3.ZERO:
			self._spectator_camera.look_at(_spectator_target, Vector3.UP)

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_settings()
		get_tree().quit()

func _save_settings() -> void:
	var config = ConfigFile.new()
	if check_min_players(%UI.get_min_players()):
		config.set_value("Settings", "min_players", %UI.get_min_players())
	if check_max_players(%UI.get_max_players()):
		config.set_value("Settings", "max_players", %UI.get_max_players())
	if check_lobby_name(%UI.get_lobby_name()):
		config.set_value("Settings", "lobby_name", %UI.get_lobby_name())
	if check_nickname(%UI.get_nickname()):
		config.set_value("Settings", "nickname", %UI.get_nickname())
	config.set_value("Settings", "car_color", %UI.get_car_color())
	config.set_value("Settings", "car_model_id", %UI.get_car_model_id())
	config.save("user://settings.cfg")

func _load_settings() -> void:
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		if config.save("user://settings.cfg") != OK:
			printerr("Could not create settings file")
			return
	%UI.set_min_players(int(config.get_value("Settings", "min_players", self.MIN_PLAYERS_DEFAULT)))
	%UI.set_max_players(int(config.get_value("Settings", "max_players", self.MAX_PLAYERS_DEFAULT)))
	%UI.set_lobby_name(config.get_value("Settings", "lobby_name", NameGenerator.lobby_name()))
	%UI.set_nickname(config.get_value("Settings", "nickname", NameGenerator.nickname()))
	var c_arr = config.get_value("Settings", "car_color", self.COLOR_DEFAULT)
	%UI.set_car_color(Color(c_arr[0], c_arr[1], c_arr[2]))
	%UI.set_car_model_id(config.get_value("Settings", "car_model_id", "sport"))

func check_min_players(value: int) -> bool:
	return value >= self.MIN_LIMIT_PLAYERS and value <= self.MAX_LIMIT_PLAYERS and value <= %UI.get_max_players()

func check_max_players(value: int) -> bool:
	return value >= self.MIN_LIMIT_PLAYERS and value <= self.MAX_LIMIT_PLAYERS and value >= %UI.get_min_players()

func check_lobby_name(lobby_name: String) -> bool:
	return is_valid_name(lobby_name)

func check_nickname(nickname: String) -> bool:
	return is_valid_name(nickname)

func is_valid_name(name_to_check: String) -> bool:
	if name_to_check.length() < 3 or name_to_check.length() > 20:
		return false
	return self.regex.search(name_to_check) != null

func switch_mode(next_mode: Mode, server_up: bool):
	if OS.has_feature("debug"):
		print("### %s -> %s ###" % [ self.modes_strings[ self.mode], self.modes_strings[next_mode]])
	assert(next_mode != self.mode)

	var leaving_track := self.mode == Mode.IN_RACE || self.mode == Mode.LOBBY_INTERMISSION || self.mode == Mode.SPECTATOR
	if leaving_track && next_mode == Mode.WELCOME_PAGE:
		self.track_node.visible = false
		if self.car_node:
			self.car_node.visible = false
		if self._spectator_camera:
			self._spectator_camera.queue_free()
			self._spectator_camera = null
		if self._opponents:
			self._opponents.clear()
		if self._ghost:
			self._ghost.clear()
			self._ghost = null
		for n in $Track.get_children():
			n.queue_free()

	if next_mode == Mode.IN_RACE:
		self.track_node.visible = true
		self.car_node.visible = true

		var rb := self.car_node as RigidBody3D
		rb.freeze = false
		if self._ghost:
			self._ghost.apply_server_state(self.car_node.global_position, self.car_node.quaternion)

	if self.mode == Mode.SPECTATOR && next_mode == Mode.LOBBY_INTERMISSION:
		self.car_node.visible = true
		if self._spectator_camera:
			self._spectator_camera.queue_free()
			self._spectator_camera = null
		var cam := self.car_node.get_node_or_null("Camera") as Camera3D
		if cam:
			cam.make_current()
		if self._debug_enabled:
			self._ghost = GhostManager.new()
			self._ghost.setup($Track, self.opponent_scene, %UI.get_car_color())

	if leaving_track:
		if next_mode == Mode.WELCOME_PAGE:
			%Network.terminate()
	elif self.mode == Mode.WELCOME_PAGE:
		if next_mode == Mode.FETCH_LOBBIES \
		   || next_mode == Mode.JOINING_LOBBY \
		   || next_mode == Mode.CREATING_LOBBY:
			if !%Network.connect_to_server():
				return

	%UI.switch_mode(next_mode, server_up)

	self.mode = next_mode

func switch_to_track(track_id: String, race_ongoing: bool):
	var display_name := track_id
	for t in self.available_tracks:
		if t.get("id", "") == track_id:
			display_name = String(t.get("name", track_id))
			break
	%UI.set_intermission_lobby_name(%UI.get_lobby_name())
	%UI.set_intermission_track_name("Current track: %s" % display_name)

	var per_track_path := "res://tracks/" + track_id + "/level.tscn"
	var fallback_path := "res://tracks/circuit_one/level.tscn"
	var scene_path := per_track_path if ResourceLoader.exists(per_track_path) else fallback_path
	var track_scene: PackedScene = load(scene_path)
	self.track_node = track_scene.instantiate()
	$Track.add_child(self.track_node)

	var physical_node: Node3D = self.track_node.get_node("Physical") as Node3D
	var spawn_info: Dictionary = TrackLoader.build(physical_node, self.track_def)

	self._opponents = OpponentManager.new($Track)

	self.car_node = self.player_scene.instantiate()
	self.car_node.car_model_id = %UI.get_car_model_id()
	self.car_node.name = %UI.get_nickname()
	$Track.add_child(self.car_node)
	var model_def := get_car_model(%UI.get_car_model_id())
	var mat := StandardMaterial3D.new()
	mat.albedo_color = %UI.get_car_color()
	var body_mesh := self.car_node.find_child(model_def["body_mesh"], true, false) as MeshInstance3D
	if body_mesh:
		body_mesh.set_surface_override_material(0, mat)

	self.car_node.global_position = spawn_info["spawn_pos"]
	self.car_node.global_rotation = Vector3(0.0, deg_to_rad(spawn_info["spawn_y_rotation_deg"]), 0.0)

	(self.car_node as RigidBody3D).freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	(self.car_node as RigidBody3D).freeze = true

	if race_ongoing:

		self.car_node.visible = false
		self._spectator_camera = Camera3D.new()
		self._spectator_camera.fov = 90.0
		self._spectator_camera.position = Vector3(0.0, 200.0, 80.0)
		$Track.add_child(self._spectator_camera)

		self._spectator_camera.look_at(Vector3.ZERO, Vector3.UP)
		self._spectator_camera.make_current()
		switch_mode(Mode.SPECTATOR, true)
	else:
		if self._debug_enabled:
			self._ghost = GhostManager.new()
			self._ghost.setup($Track, self.opponent_scene, %UI.get_car_color())
		var camera_node: Camera3D = self.car_node.get_node_or_null("Camera")
		if camera_node:
			camera_node.make_current()
		switch_mode(Mode.LOBBY_INTERMISSION, true)

func on_connection():
	var requests: Array = []
	if self.mode == Mode.FETCH_LOBBIES:
		requests.append({"Request": "FetchLobbyList"})
		if self.available_tracks.is_empty():
			requests.append({"Request": "FetchTrackList"})
		self._fetch_pending = requests.size()
	elif self.mode == Mode.JOINING_LOBBY:
		requests.append({"Request": {"JoinLobby": {
			"lobby_id": %UI.get_selected_lobby_name(),
			"nickname": %UI.get_nickname(),
			"color": MessageParser.color_to_proto(%UI.get_car_color()),
		}}})
	elif self.mode == Mode.CREATING_LOBBY:
		requests.append({"Request": {"CreateLobby": {
			"lobby_id": %UI.get_lobby_name(),
			"track_id": %UI.get_selected_track_id(),
			"nickname": %UI.get_nickname(),
			"min_players": %UI.get_min_players(),
			"max_players": %UI.get_max_players(),
			"color": MessageParser.color_to_proto(%UI.get_car_color()),
		}}})
	else:
		return

	for req in requests:
		var result = %Network.socket.send_text(JSON.stringify(req))
		if result != OK:
			printerr("Could not send request: %s" % req)

	if self.mode == Mode.CREATING_LOBBY:
		switch_mode(Mode.JOINING_LOBBY, true)

func on_server_message(message: Dictionary) -> bool:
	if OS.has_feature("debug") && self._debug_enabled:
		print(message)

	if self.mode == Mode.FETCH_LOBBIES:
		if message.has("Response") && message["Response"].has("LobbyList"):
			%UI.refresh(message["Response"]["LobbyList"])
		elif message.has("Response") && message["Response"].has("TrackList"):
			var raw_list: Array = message["Response"]["TrackList"]
			self.available_tracks.clear()
			for entry in raw_list:
				self.available_tracks.append({
					"id": String(entry.get("id", "")),
					"name": String(entry.get("name", "")),
				})
			%UI.refresh_tracks(self.available_tracks)
		else:
			printerr("Unexpected response in FETCH_LOBBIES")
		self._fetch_pending = max(0, self._fetch_pending - 1)
		return self._fetch_pending > 0  # keep connection until all pending responses are in

	elif self.mode == Mode.JOINING_LOBBY:
		if !message.has("Response") || !message["Response"].has("LobbyJoined"):
			printerr("Unexpected response for join lobby")
			return false
		var parsed = MessageParser.parse_join_response(message)
		if !parsed["ok"]:
			%UI.set_info_label("Could not join: %s" % parsed["error_str"])
			return false
		self._lobby_min_players = parsed["min_players"]
		self._lobby_max_players = parsed["max_players"]
		var t = parsed.get("track", null)
		if t == null:
			printerr("LobbyJoined did not include a track definition")
			return false
		self.track_def = t
		switch_to_track(parsed["track_id"], parsed["race_ongoing"])

	elif self.mode == Mode.LOBBY_INTERMISSION || self.mode == Mode.IN_RACE || self.mode == Mode.SPECTATOR:
		_handle_lobby_message(message)

	return true

func _handle_lobby_message(message: Dictionary) -> void:
	if message.has("Event"):
		var event = message["Event"]
		if event.has("RaceAboutToStart"):
			var spawn = MessageParser.parse_spawn_info(event["RaceAboutToStart"])

			self.car_node.global_position = spawn["position"]
			self.car_node.global_rotation = Vector3(0.0, deg_to_rad(spawn["y_rotation"]), 0.0)

			%UI.reset_start_lights()

			if self.mode == Mode.SPECTATOR:
				switch_mode(Mode.LOBBY_INTERMISSION, true)
		if event.has("RaceStarted") && self.mode == Mode.LOBBY_INTERMISSION:
			%UI.start_lights_go()
			switch_mode(Mode.IN_RACE, true)
		if event.has("Countdown"):
			var t: float = float(event["Countdown"]["time"])
			%UI.set_info_label("Start in %d..." % int(t))
			%UI.start_lights_countdown(t)
			if self.mode == Mode.LOBBY_INTERMISSION:
				%UI.show_pre_race_view()
		if event.has("RaceFinished"):
			var finished = event["RaceFinished"]
			self._last_race_rankings = finished.get("rankings", [])
			if self.mode == Mode.IN_RACE or self.mode == Mode.SPECTATOR:
				switch_mode(Mode.LOBBY_INTERMISSION, true)
			%UI.show_race_results(self._last_race_rankings)

	elif message.has("State"):
		var state = message["State"]
		if state.has("Players"):
			var players = state["Players"] as Array
			if self.mode == Mode.LOBBY_INTERMISSION:
				%UI.set_intermission_players_count("%d/%d (%d minimum)" % [
					players.size(), self._lobby_max_players, self._lobby_min_players
				])
				%UI.set_intermission_players_list(players)
			var _spectator_target_set := false
			for raw in players:
				var player = MessageParser.parse_player(raw)
				if !player["racing"]:
					continue
				if player["nickname"] == %UI.get_nickname():
					if self.mode == Mode.IN_RACE:
						if self._ghost:
							self._ghost.apply_server_state(player["position"], player["rotation"])
						if self.car_node:
							self.car_node.apply_server_correction(player["position"], player["rotation"])
						var laps: int = player.get("laps", 0)
						if laps >= 3:
							%UI.set_info_label("Finished!")
						else:
							%UI.set_info_label("Lap %d / 3" % (laps + 1))
				else:
					self._opponents.update(player)
					if self.mode == Mode.SPECTATOR and not _spectator_target_set:
						_spectator_target = player["position"]
						_spectator_target_set = true
		elif state.has("WaitingForPlayers"):
			var missing = int(state["WaitingForPlayers"])
			%UI.set_info_label("Waiting for %d player%s" % [missing, ("" if missing == 1 else "s")])
