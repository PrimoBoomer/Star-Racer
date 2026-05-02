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
	var floor_mat: StandardMaterial3D = load("res://tracks/circuit_one/floor_mat.tres")
	var wall_mat := _make_concrete_mat()

	var primitives: Array = track_def.get("primitives", [])
	for prim in primitives:
		var kind: String = prim.get("type", "")
		match kind:
			"floor":
				_make_static_box(parent, prim, FLOOR_DEFAULT_COLOR, false, floor_mat)
			"wall":
				_make_static_box(parent, prim, WALL_DEFAULT_COLOR, false, wall_mat)
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


static func _make_concrete_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://tracks/circuit_one/concrete_color.png")
	mat.normal_enabled = true
	mat.normal_texture = load("res://tracks/circuit_one/concrete_normal.png")
	mat.roughness = 0.9
	mat.uv1_scale = Vector3(3.0, 3.0, 3.0)
	return mat


static func _make_static_box(parent: Node3D, prim: Dictionary, default_color: Color, sensor: bool, override_mat: StandardMaterial3D = null) -> void:
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
	if override_mat != null:
		mesh.material = override_mat
	else:
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

	# Oriented visual: chevrons point along heading. The Area3D sensor stays
	# axis-aligned (server matches the AABB), so only the visuals get rotated.
	var visual := Node3D.new()
	visual.position.y = -size.y * 0.5
	visual.rotation.y = atan2(heading.x, -heading.z)
	root.add_child(visual)

	# Local dome dims (along chevron-forward axis = local Z).
	var width  := size.x
	var length := size.z
	var dome_h := minf(size.y * 0.45, 0.35)

	# Domed base — transverse arch you drive over.
	var dome_mat := StandardMaterial3D.new()
	dome_mat.albedo_color = PAD_BASE_COLOR
	dome_mat.roughness = 0.45
	dome_mat.metallic  = 0.25
	var dome_mi := MeshInstance3D.new()
	dome_mi.mesh = _build_dome_mesh(width, length, dome_h, 16, 6)
	dome_mi.set_surface_override_material(0, dome_mat)
	visual.add_child(dome_mi)

	# Three chevrons stepped along length, sitting just above the dome surface.
	var chev_mat := StandardMaterial3D.new()
	chev_mat.albedo_color = PAD_ARROW_COLOR
	chev_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chev_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var chev_w := width * 0.62
	var chev_l := length * 0.18
	var chev_t := width * 0.10
	var chev_mesh := _build_chevron_mesh(chev_w, chev_l, chev_t)

	var slots := [-0.30, 0.0, 0.30]  # fractions of length
	for i in slots.size():
		var f: float = slots[i]
		var z_off := f * length
		# Y on dome at this Z (dome bumps along local X, which is uniform along Z).
		var y_top := dome_h + 0.02
		var chev := MeshInstance3D.new()
		chev.mesh = chev_mesh
		chev.set_surface_override_material(0, chev_mat)
		chev.position = Vector3(0.0, y_top, z_off)
		visual.add_child(chev)

	# Sensor area: full pad volume, axis-aligned (matches server).
	var sensor := Area3D.new()
	sensor.name = "%s_sensor" % nm
	root.add_child(sensor)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sensor.add_child(cs)


# Builds a transverse-arched plane (bump along X, flat along Z).
# Returns an ArrayMesh with normals.
static func _build_dome_mesh(width: float, length: float, height: float,
		w_segs: int, l_segs: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs   := PackedVector2Array()
	var idx   := PackedInt32Array()

	for j in range(l_segs + 1):
		var v := float(j) / float(l_segs)
		var z := (v - 0.5) * length
		for i in range(w_segs + 1):
			var u := float(i) / float(w_segs)
			var x := (u - 0.5) * width
			var t := (u - 0.5) * 2.0          # -1..1
			var y := height * (1.0 - t * t)   # parabolic arch
			verts.append(Vector3(x, y, z))
			# Normal of y = h*(1 - t^2) wrt x: dy/dx = -2*h*t / (width/2)
			var slope := -2.0 * height * t / (width * 0.5)
			var n := Vector3(-slope, 1.0, 0.0).normalized()
			norms.append(n)
			uvs.append(Vector2(u, v))

	for j in range(l_segs):
		for i in range(w_segs):
			var a := j * (w_segs + 1) + i
			var b := a + 1
			var c := a + (w_segs + 1)
			var d := c + 1
			idx.append(a); idx.append(c); idx.append(b)
			idx.append(b); idx.append(c); idx.append(d)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = idx

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


# Flat chevron `>` shape in the XZ plane, pointing toward +Z.
# `width` = total span along X, `length` = depth along Z, `thickness` = arm width.
static func _build_chevron_mesh(width: float, length: float, thickness: float) -> ArrayMesh:
	var hw := width * 0.5
	var hl := length * 0.5
	# Two parallelogram arms meeting at the tip (0, 0, +hl).
	# Each arm: outer edge from (±hw, 0, -hl) → tip (0, 0, hl).
	# Inner edge offset by `thickness` along arm-normal.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs   := PackedVector2Array()
	var idx   := PackedInt32Array()

	var up := Vector3.UP

	# Right arm: from base-right (hw, 0, -hl) to tip (0, 0, hl).
	var br := Vector3(hw, 0, -hl)
	var tp := Vector3(0, 0, hl)
	var dir_r := (tp - br).normalized()
	var nrm_r := Vector3(-dir_r.z, 0, dir_r.x).normalized()  # left-of-arm in XZ
	var br_in := br + nrm_r * thickness
	var tp_in_r := tp + nrm_r * thickness

	# Left arm: mirror.
	var bl := Vector3(-hw, 0, -hl)
	var dir_l := (tp - bl).normalized()
	var nrm_l := Vector3(-dir_l.z, 0, dir_l.x).normalized()  # right-of-arm = inward
	var bl_in := bl - nrm_l * thickness   # invert sign so inset goes toward center
	var tp_in_l := tp - nrm_l * thickness

	var base_idx := verts.size()
	verts.append(br); verts.append(br_in); verts.append(tp_in_r); verts.append(tp)
	for k in 4:
		norms.append(up); uvs.append(Vector2(0, 0))
	idx.append(base_idx + 0); idx.append(base_idx + 1); idx.append(base_idx + 2)
	idx.append(base_idx + 0); idx.append(base_idx + 2); idx.append(base_idx + 3)

	base_idx = verts.size()
	verts.append(bl); verts.append(tp); verts.append(tp_in_l); verts.append(bl_in)
	for k in 4:
		norms.append(up); uvs.append(Vector2(0, 0))
	idx.append(base_idx + 0); idx.append(base_idx + 1); idx.append(base_idx + 2)
	idx.append(base_idx + 0); idx.append(base_idx + 2); idx.append(base_idx + 3)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = idx

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am
