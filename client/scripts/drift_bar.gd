extends Control

const RADIUS    := 68.0
const THICKNESS := 13.0
# Arc centred at bottom-left; sweeps from pointing down-left through up to right
const ARC_FROM  := 205.0   # deg – lower-left direction
const ARC_SPAN  := 230.0   # deg – ends upper-right

const MARGIN    := 32.0    # inset from screen edges

var _charge: float = 0.0
var _boost_flash: float = 0.0
var _speed_label: Label = null

func _ready() -> void:
	_speed_label = Label.new()
	_speed_label.text = "0"
	_speed_label.add_theme_font_size_override("font_size", 56)
	_speed_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	_speed_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_speed_label.add_theme_constant_override("outline_size", 6)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_speed_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_speed_label.offset_left  = 24.0
	_speed_label.offset_top   = -90.0
	_speed_label.offset_right = 200.0
	_speed_label.offset_bottom = -28.0
	add_child(_speed_label)

	var unit_label := Label.new()
	unit_label.name = "SpeedUnit"
	unit_label.text = "km/h"
	unit_label.add_theme_font_size_override("font_size", 18)
	unit_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.85))
	unit_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	unit_label.add_theme_constant_override("outline_size", 4)
	unit_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	unit_label.offset_left  = 162.0
	unit_label.offset_top   = -42.0
	unit_label.offset_right = 220.0
	unit_label.offset_bottom = -22.0
	add_child(unit_label)

func _process(delta: float) -> void:
	var game := get_node_or_null("/root/Root/Game") as Game
	if game == null or game.mode != Game.Mode.IN_RACE:
		visible = false
		return

	visible = true

	if game.car_node != null:
		var rb := game.car_node as RigidBody3D
		_charge = rb.get("drift_charge") as float
		if rb.get("boost_flash") as bool:
			_boost_flash = 0.28
			rb.set("boost_flash", false)
		var v := rb.linear_velocity
		var horiz_speed := Vector2(v.x, v.z).length()
		var kmh := horiz_speed * 3.6
		# Deadzone for physics jitter at rest.
		if kmh < 1.0:
			kmh = 0.0
		_speed_label.text = "%d" % int(round(kmh))

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

func _arc_color(t: float) -> Color:
	if t < 0.5:
		return Color(0.15, 0.55, 1.0).lerp(Color(0.95, 0.88, 0.10), t * 2.0)
	return Color(0.95, 0.88, 0.10).lerp(Color(1.0, 0.32, 0.0), (t - 0.5) * 2.0)
