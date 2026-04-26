extends Control

const RADIUS    := 68.0
const THICKNESS := 13.0
# Arc centred at bottom-left; sweeps from pointing down-left through up to right
const ARC_FROM  := 205.0   # deg – lower-left direction
const ARC_SPAN  := 230.0   # deg – ends upper-right

const MARGIN    := 32.0    # inset from screen edges

var _charge: float = 0.0
var _boost_flash: float = 0.0
var _speed_kmh: int = 0
var _prev_pos: Vector3 = Vector3.ZERO
var _prev_pos_valid := false
var _kmh_smoothed: float = 0.0

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	var game := get_node_or_null("/root/Root/Game") as Game
	if game == null or game.mode != Game.Mode.IN_RACE:
		visible = false
		_prev_pos_valid = false
		return

	visible = true

	if game.car_node != null and delta > 0.0:
		var rb := game.car_node as RigidBody3D
		_charge = rb.get("drift_charge") as float
		if rb.get("boost_flash") as bool:
			_boost_flash = 0.28
			rb.set("boost_flash", false)

		# Speed via position delta — reliable even when global_position is
		# being written directly for server reconciliation (which leaves
		# linear_velocity stale).
		var pos := rb.global_position
		var inst_kmh := 0.0
		if _prev_pos_valid:
			var d := Vector2(pos.x - _prev_pos.x, pos.z - _prev_pos.z).length()
			inst_kmh = (d / delta) * 3.6
		_prev_pos = pos
		_prev_pos_valid = true

		# Low-pass filter to hide per-frame jitter.
		_kmh_smoothed = lerp(_kmh_smoothed, inst_kmh, clampf(delta * 12.0, 0.0, 1.0))
		var kmh := _kmh_smoothed
		if kmh < 1.0:
			kmh = 0.0
		_speed_kmh = int(round(kmh))

	if _boost_flash > 0.0:
		_boost_flash -= delta

	queue_redraw()

func _draw() -> void:
	# Bottom-left corner, inset by MARGIN
	var center := Vector2(RADIUS + MARGIN, size.y - RADIUS - MARGIN)
	var from_rad := deg_to_rad(ARC_FROM)
	var to_rad   := from_rad + deg_to_rad(ARC_SPAN)

	# Background track
	draw_arc(center, RADIUS, from_rad, to_rad, 80,
		Color(0.05, 0.10, 0.22, 0.65), THICKNESS, true)

	_draw_speed()

	if _charge <= 0.002:
		return

	var fill_end := from_rad + _charge * deg_to_rad(ARC_SPAN)
	var arc_c: Color

	if _boost_flash > 0.0:
		arc_c = Color(1.0, 1.0, 1.0, 0.95)
	else:
		arc_c = _arc_color(_charge)

	# Glow halo when charge >= 30 %
	if _charge >= 0.3:
		var glow := Color(arc_c.r, arc_c.g, arc_c.b, 0.20)
		draw_arc(center, RADIUS, from_rad, fill_end, 80, glow, THICKNESS + 10.0, true)

	# Main arc
	draw_arc(center, RADIUS, from_rad, fill_end, 80, arc_c, THICKNESS, true)

	# Tip dot at the leading edge
	var tip := center + Vector2(cos(fill_end), sin(fill_end)) * RADIUS
	draw_circle(tip, THICKNESS * 0.58, arc_c)

func _draw_speed() -> void:
	var font := ThemeDB.fallback_font
	var center := Vector2(RADIUS + MARGIN, size.y - RADIUS - MARGIN)
	var spd_str := "%d" % _speed_kmh
	var spd_size := font.get_string_size(spd_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 48)
	draw_string(font, center + Vector2(-spd_size.x * 0.5, spd_size.y * 0.28),
		spd_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(1, 1, 1, 0.98))
	var unit_size := font.get_string_size("km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_string(font, center + Vector2(-unit_size.x * 0.5, RADIUS * 0.55),
		"km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.85, 1.0, 0.75))

func _arc_color(t: float) -> Color:
	if t < 0.5:
		return Color(0.15, 0.55, 1.0).lerp(Color(0.95, 0.88, 0.10), t * 2.0)
	return Color(0.95, 0.88, 0.10).lerp(Color(1.0, 0.32, 0.0), (t - 0.5) * 2.0)
