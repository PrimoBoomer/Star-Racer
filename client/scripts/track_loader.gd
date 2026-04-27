extends Node3D

class_name TrackLoader

## Builds a track scene from a JSON track definition (as a Dictionary).
## The definition is the same shape the server sends in the LobbyJoined response.
##
## `parent` is the node under which all primitives are added.
## Returns { "spawn_pos": Vector3, "spawn_y_rotation_deg": float }.

const FLOOR_DEFAULT_COLOR := Color(0.3, 0.3, 0.3)
const WALL_DEFAULT_COLOR  := Color(0.55, 0.55, 0.6)
const PAD_BASE_COLOR      := Color(0.10, 0.30, 0.95)
const PAD_ARROW_COLOR     := Color(1.0, 0.9, 0.1)
const HAZARD_DEFAULT_COLOR := Color(0.85, 0.15, 0.15)


static func build(parent: Node3D, track_def: Dictionary) -> Dictionary:
	var primitives: Array = track_def.get("primitives", [])
	for prim in primitives:
		var kind: String = prim.get("type", "")
		match kind:
			"floor":
				_make_static_box(parent, prim, FLOOR_DEFAULT_COLOR, false)
			"wall":
				_make_static_box(parent, prim, WALL_DEFAULT_COLOR, false)
			"hazard":
				_make_static_box(parent, prim, HAZARD_DEFAULT_COLOR, true)
			"pad":
				_make_pad(parent, prim)
			_:
				push_warning("TrackLoader: unknown primitive type '%s'" % kind)

	var spawn: Dictionary = track_def.get("spawn", {})
	var sp_arr: Array = spawn.get("position", [0.0, 0.0, 0.0])
	return {
		"spawn_pos": Vector3(float(sp_arr[0]), float(sp_arr[1]), float(sp_arr[2])),
		"spawn_y_rotation_deg": float(spawn.get("y_rotation_deg", 0.0)),
	}


static func _vec3_from_array(arr: Array, default: Vector3 = Vector3.ZERO) -> Vector3:
	if arr.size() < 3:
		return default
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


static func _color_from_array(arr, default: Color) -> Color:
	if arr == null or not arr is Array or arr.size() < 3:
		return default
	return Color(float(arr[0]), float(arr[1]), float(arr[2]))


static func _make_static_box(parent: Node3D, prim: Dictionary, default_color: Color, sensor: bool) -> void:
	var size := _vec3_from_array(prim.get("size", []))
	var pos  := _vec3_from_array(prim.get("position", []))
	var rot  := _vec3_from_array(prim.get("rotation_deg", []), Vector3.ZERO)
	var color := _color_from_array(prim.get("color", null), default_color)
	var nm: String = prim.get("name", "primitive")

	var body: CollisionObject3D
	if sensor:
		body = Area3D.new()
	else:
		body = StaticBody3D.new()
	body.name = nm
	body.position = pos
	body.rotation_degrees = rot

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mat.metallic = 0.1
	mesh.material = mat
	mi.mesh = mesh
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)

	parent.add_child(body)


static func _make_pad(parent: Node3D, prim: Dictionary) -> void:
	var size := _vec3_from_array(prim.get("size", []))
	var pos  := _vec3_from_array(prim.get("position", []))
	var heading := _vec3_from_array(prim.get("heading", []), Vector3(0.0, 0.0, -1.0))
	var nm: String = prim.get("name", "pad")

	var root := Node3D.new()
	root.name = nm
	root.position = pos
	parent.add_child(root)

	# Visible plane on top of the pad surface (Y = pad top + epsilon).
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = PAD_BASE_COLOR
	pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var pad_mesh := PlaneMesh.new()
	pad_mesh.size = Vector2(size.x, size.z)
	pad_mesh.material = pad_mat

	var pad_mi := MeshInstance3D.new()
	pad_mi.mesh = pad_mesh
	pad_mi.position.y = -size.y * 0.5 + 0.02
	root.add_child(pad_mi)

	# Direction arrow.
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.albedo_color = PAD_ARROW_COLOR
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(1.2, 0.08, 4.5)
	shaft_mesh.material = arrow_mat

	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(3.5, 0.08, 2.5)
	head_mesh.material = arrow_mat

	var arrow := Node3D.new()
	arrow.position.y = -size.y * 0.5 + 0.06
	arrow.rotation.y = atan2(heading.x, -heading.z)
	root.add_child(arrow)

	var shaft_mi := MeshInstance3D.new()
	shaft_mi.mesh = shaft_mesh
	shaft_mi.position.z = 1.5
	arrow.add_child(shaft_mi)

	var head_mi := MeshInstance3D.new()
	head_mi.mesh = head_mesh
	head_mi.position.z = -1.0
	arrow.add_child(head_mi)

	# Sensor area for collision-side parity (server is authoritative for boost).
	# We still create it client-side for visual consistency / future client-side effects.
	var sensor := Area3D.new()
	sensor.name = "%s_sensor" % nm
	root.add_child(sensor)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sensor.add_child(cs)
