extends RigidBody3D

const THROTTLE_FORCE     := 10_000.0
const REVERSE_FORCE      := 5_000.0
const BRAKE_FORCE        := 8_000.0
const BRAKE_MIN_SPEED    := 1.0
const MOTION_DIRECTION_EPSILON := 0.25
const MAX_TURN_RATE_GRIP := 1.2
const MAX_TURN_RATE_DRIFT := 3.2
const STEER_P_GAIN       := 25_000.0
const ALIGN_RATE_GRIP    := 4.0
const ALIGN_RATE_DRIFT   := 0.6
const NORMAL_LINEAR_DAMP := 0.3
const DRIFT_LINEAR_DAMP  := 0.18
const DRIFT_MIN_SPEED    := 3.0

const BOOST_CHARGE_RATE   := 1.0
const BOOST_CHARGE_DECAY  := 2.0
const BOOST_CHARGE_MIN    := 0.30
const BOOST_PEAK_BONUS    := 18.0
const BOOST_DURATION      := 1.5
const BOOST_ALIGN_THRESHOLD_COS := 0.9781476  # cos(12°)
const BOOST_PENDING_TIMEOUT := 1.5
const BOOST_SUSTAIN_FORCE  := 30_000.0

const POS_SOFT_RATE := 0.08
const ROT_SOFT_RATE := 0.08

enum BoostState { IDLE, PENDING, BOOSTING }

var drift_charge: float = 0.0
var boost_flash: bool = false
var _was_star_drift_pressed := false
var _boost_state: int = BoostState.IDLE
var _boost_t_remaining: float = 0.0
var _boost_pending_t: float = 0.0
var _boost_peak_speed: float = 0.0
var _reversing := false

var _server_pos       := Vector3.ZERO
var _server_pos_valid := false
var _server_rot       := Quaternion.IDENTITY
var _server_rot_valid := false

var _wheel_fl: Node3D = null
var _wheel_fr: Node3D = null
var init_rot_wheel: float = 0.0
var delta_rot_wheel := 0.0
const LIMIT_ROT_WHEEL := 30.0

var car_model_id: String = "sport"

var network_timer := 0.0
const NETWORK_SEND_INTERVAL := 0.05

@onready var network = get_tree().get_first_node_in_group("Network")
@onready var _game := get_node("/root/Root/Game")

func _ready() -> void:
	self.angular_damp = 0.5
	self.linear_damp  = NORMAL_LINEAR_DAMP
	_load_car_body()

func _load_car_body() -> void:
	var model_def := Game.get_car_model(car_model_id)
	var scene := load(model_def["path"]) as PackedScene
	if scene == null:
		printerr("Could not load car model: ", model_def["path"])
		return
	var body := scene.instantiate() as Node3D
	body.name = "Body"
	body.transform = model_def["transform"]
	add_child(body)
	_wheel_fl = body.find_child(model_def["wheel_fl"], true, false)
	_wheel_fr = body.find_child(model_def["wheel_fr"], true, false)
	init_rot_wheel = _wheel_fl.rotation_degrees.y if _wheel_fl else 0.0

func _physics_process(delta: float) -> void:
	if self._game.mode != Game.Mode.IN_RACE \
	or self._game.paused:
		return

	var forward_dir := -self.transform.basis.z

	var throttle := Input.is_action_pressed("Throttle")
	var steer    := Input.get_axis("Steering Left", "Steering Right")
	var star_drift_input := Input.is_action_pressed("Star Drift")

	var speed := self.linear_velocity.length()
	var drift := star_drift_input and speed > DRIFT_MIN_SPEED

	var forward_speed := forward_dir.dot(self.linear_velocity)
	if forward_speed <= -MOTION_DIRECTION_EPSILON:
		self._reversing = true
	elif forward_speed >= MOTION_DIRECTION_EPSILON:
		self._reversing = false
	elif throttle:
		self._reversing = false  # throttle while nearly stopped → go forward
	elif star_drift_input and not throttle:
		self._reversing = true

	if throttle and not self._reversing:
		apply_central_force(forward_dir * THROTTLE_FORCE)
	if not throttle and self._reversing:
		apply_central_force(-forward_dir * REVERSE_FORCE)

	if star_drift_input and not throttle and forward_speed > BRAKE_MIN_SPEED:
		var v := self.linear_velocity
		if v.length() > 0.01:
			apply_central_force(-v.normalized() * BRAKE_FORCE)

	var effective_steer := -steer if self._reversing else steer
	var max_turn   := MAX_TURN_RATE_DRIFT if drift else MAX_TURN_RATE_GRIP
	var target_yaw := -effective_steer * max_turn
	var yaw_error  := target_yaw - self.angular_velocity.y
	apply_torque(Vector3.UP * yaw_error * STEER_P_GAIN)

	# Velocity-vector slerp toward forward, magnitude preserved.
	if speed > 0.5 and not self._reversing:
		var cur_dir := self.linear_velocity / speed
		var rate := ALIGN_RATE_DRIFT if drift else ALIGN_RATE_GRIP
		var new_dir := _vec3_slerp_clamped(cur_dir, forward_dir, rate * delta)
		self.linear_velocity = new_dir * speed

	self.linear_damp = DRIFT_LINEAR_DAMP if drift else NORMAL_LINEAR_DAMP

	# Boost FSM (mirrors server).
	_update_boost_fsm(forward_dir, speed, star_drift_input, delta)
	_was_star_drift_pressed = star_drift_input

	if self._server_pos_valid:
		self.global_position = self.global_position.lerp(self._server_pos, POS_SOFT_RATE)

	if self._server_rot_valid:
		self.quaternion = self.quaternion.slerp(self._server_rot, ROT_SOFT_RATE)

	if steer != 0.0:
		self.delta_rot_wheel -= steer * delta * 120
		self.delta_rot_wheel = clamp(self.delta_rot_wheel, -LIMIT_ROT_WHEEL, LIMIT_ROT_WHEEL)
	else:
		self.delta_rot_wheel = lerp(self.delta_rot_wheel, 0.0, delta * 10)
	if _wheel_fl:
		_wheel_fl.rotation_degrees.y = self.init_rot_wheel + self.delta_rot_wheel
	if _wheel_fr:
		_wheel_fr.rotation_degrees.y = self.init_rot_wheel + self.delta_rot_wheel

	self.network_timer += delta
	if self.network_timer >= NETWORK_SEND_INTERVAL:
		self.network_timer = 0.0
		self.network.send({
			"State": {
				"throttle":    throttle,
				"steer_left":  max(-steer, 0.0),
				"steer_right": max(steer, 0.0),
				"star_drift":  star_drift_input
			}
		})

func apply_server_correction(server_pos: Vector3, server_rot: Quaternion) -> void:
	self._server_pos       = server_pos
	self._server_pos_valid = true
	self._server_rot       = server_rot
	self._server_rot_valid = true

func _vec3_slerp_clamped(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var d = clampf(from.dot(to), -1.0, 1.0)
	var angle = acos(d)
	if angle < 1e-4 or max_angle <= 0.0:
		return from
	var t := minf(max_angle / angle, 1.0)
	var sin_a := sin(angle)
	if absf(sin_a) < 1e-4:
		return from
	var a := sin((1.0 - t) * angle) / sin_a
	var b := sin(t * angle) / sin_a
	return from * a + to * b

func _update_boost_fsm(forward_dir: Vector3, speed: float, star_drift_input: bool, delta: float) -> void:
	if star_drift_input and speed > DRIFT_MIN_SPEED:
		drift_charge = minf(drift_charge + BOOST_CHARGE_RATE * delta, 1.0)
	elif _boost_state != BoostState.PENDING:
		drift_charge = maxf(drift_charge - BOOST_CHARGE_DECAY * delta, 0.0)

	var just_released := _was_star_drift_pressed and not star_drift_input

	match _boost_state:
		BoostState.IDLE:
			if just_released and drift_charge >= BOOST_CHARGE_MIN:
				_boost_state = BoostState.PENDING
				_boost_pending_t = BOOST_PENDING_TIMEOUT
		BoostState.PENDING:
			_boost_pending_t -= delta
			if star_drift_input:
				_boost_state = BoostState.IDLE
			elif _boost_pending_t <= 0.0:
				_boost_state = BoostState.IDLE
			elif speed > 1.0:
				var vel_dir := self.linear_velocity / speed
				if vel_dir.dot(forward_dir) >= BOOST_ALIGN_THRESHOLD_COS:
					var base = maxf(speed, DRIFT_MIN_SPEED)
					_boost_peak_speed = base + BOOST_PEAK_BONUS * drift_charge
					var new_speed = maxf(_boost_peak_speed, speed)
					self.linear_velocity = forward_dir * new_speed
					_boost_state = BoostState.BOOSTING
					_boost_t_remaining = BOOST_DURATION
					drift_charge = 0.0
					boost_flash = true
		BoostState.BOOSTING:
			_boost_t_remaining -= delta
			if _boost_t_remaining <= 0.0:
				_boost_state = BoostState.IDLE
			else:
				var fwd_speed := forward_dir.dot(self.linear_velocity)
				if fwd_speed < _boost_peak_speed:
					apply_central_force(forward_dir * BOOST_SUSTAIN_FORCE)
