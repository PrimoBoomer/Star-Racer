extends RigidBody3D

const THROTTLE_FORCE     := 10_000.0
const REVERSE_FORCE      := 5_000.0
const BRAKE_FORCE        := 8_000.0
const BRAKE_MIN_SPEED    := 1.0
const MOTION_DIRECTION_EPSILON := 0.25
const MAX_TURN_RATE_GRIP := 1.2
const MAX_TURN_RATE_DRIFT := 3.2
const STEER_P_GAIN       := 25_000.0
const LATERAL_GRIP       := 0.55
const LATERAL_DRIFT      := 0.08
const NORMAL_LINEAR_DAMP := 0.3
const TURN_DRAG_PER_STEER := 0.06
const DRIFT_LINEAR_DAMP  := 0.18

const POS_SOFT_RATE := 0.08
const ROT_SOFT_RATE := 0.08

var _reversing := false

var _server_pos       := Vector3.ZERO
var _server_pos_valid := false
var _server_rot       := Quaternion.IDENTITY
var _server_rot_valid := false

@onready var _wheel_fl: Node3D = $Body.get_node("wheel-front-left")
@onready var _wheel_fr: Node3D = $Body.get_node("wheel-front-right")
@onready var init_rot_wheel: float = _wheel_fl.rotation_degrees.y
var delta_rot_wheel := 0.0
const LIMIT_ROT_WHEEL := 30.0

var network_timer := 0.0
const NETWORK_SEND_INTERVAL := 0.05

@onready var network = get_tree().get_first_node_in_group("Network")
@onready var _game := get_node("/root/Root/Game")

func _ready() -> void:
	self.angular_damp = 0.5
	self.linear_damp  = NORMAL_LINEAR_DAMP

func _physics_process(delta: float) -> void:
	if self._game.mode != Game.Mode.IN_RACE \
	or self._game.paused:
		return

	var forward_dir := -self.transform.basis.z
	var right_dir   :=  self.transform.basis.x

	var throttle := Input.is_action_pressed("Throttle")
	var steer    := Input.get_axis("Steering Left", "Steering Right")
	var star_drift_input := Input.is_action_pressed("Star Drift")

	var drift    := star_drift_input and self.linear_velocity.length() > 3.0

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

	var lateral_speed := right_dir.dot(self.linear_velocity)
	var grip_cancel   := LATERAL_DRIFT if drift else LATERAL_GRIP
	apply_central_impulse(-right_dir * lateral_speed * self.mass * grip_cancel)
	self.linear_damp = DRIFT_LINEAR_DAMP if drift else NORMAL_LINEAR_DAMP

	var steer_amount := abs(effective_steer) as float
	if steer_amount > 0.0 and forward_speed > 0.0:
		var turn_drag := clampf(1.0 - TURN_DRAG_PER_STEER * steer_amount * delta, 0.0, 1.0)
		var lateral_component := right_dir * lateral_speed
		var forward_component := self.linear_velocity - lateral_component
		self.linear_velocity = forward_component * turn_drag + lateral_component

	if self._server_pos_valid:
		self.global_position = self.global_position.lerp(self._server_pos, POS_SOFT_RATE)

	if self._server_rot_valid:
		self.quaternion = self.quaternion.slerp(self._server_rot, ROT_SOFT_RATE)

	if steer != 0.0:
		self.delta_rot_wheel -= steer * delta * 120
		self.delta_rot_wheel = clamp(self.delta_rot_wheel, -LIMIT_ROT_WHEEL, LIMIT_ROT_WHEEL)
	else:
		self.delta_rot_wheel = lerp(self.delta_rot_wheel, 0.0, delta * 10)
	_wheel_fl.rotation_degrees.y = self.init_rot_wheel + self.delta_rot_wheel
	_wheel_fr.rotation_degrees.y = self.init_rot_wheel + self.delta_rot_wheel

	self.network_timer += delta
	if self.network_timer >= NETWORK_SEND_INTERVAL:
		self.network_timer = 0.0
		self.network.send({
			"State": {
				"throttle":    throttle,
				"steer_left":  max(-steer, 0.0),
				"steer_right": max(steer, 0.0),
				"star_drift":  drift
			}
		})

func apply_server_correction(server_pos: Vector3, server_rot: Quaternion) -> void:
	self._server_pos       = server_pos
	self._server_pos_valid = true
	self._server_rot       = server_rot
	self._server_rot_valid = true
