extends Node2D
## Continuous limb meshes driven by real Skeleton2D/Bone2D joints.
@export var preview_run := false
@export_range(0.0, 500.0) var preview_speed := 240.0
@export_range(40.0, 72.0) var stride_length := 68.0
@export_range(1.0, 1.5) var arm_fullness := 1.22
@export_range(1.0, 1.5) var leg_fullness := 1.20
@export var blend_speed := 12.0
var phase := 0.0
var facing := 1.0
var joints: Dictionary = {}
var body: Skeleton2D
var run_weight := 0.0
const BODY_Y := -30.0
const LIMB_PATH := "res://assets/characters/rig/limbs_continuous_v3.png"
var limbs: Texture2D
var chest: Bone2D
var hair: Bone2D
var hair_velocity := 0.0
var previous_velocity_x := 0.0
var pose_compression := 0.0
var air_blend := 0.0

func _ready() -> void:
	limbs = load(LIMB_PATH) as Texture2D
	body = Skeleton2D.new()
	body.name = "Skeleton2D"
	body.position.y = BODY_Y
	add_child(body)
	chest = _joint(body, "Chest", Vector2.ZERO)
	hair = _joint(chest, "Hair", Vector2(-8, -42))
	_leg("Far", 0.0, -3)
	_arm("Far", -1.5, -2)
	_leg("Near", 0.0, -1)
	var atlas := load("res://assets/characters/rig/parts_v2.png") as Texture2D
	var rect := Rect2i(170, 0, 340, 650)
	var used := atlas.get_image().get_region(rect).get_used_rect()
	var torso_texture := AtlasTexture.new()
	torso_texture.atlas = atlas
	torso_texture.region = Rect2(rect.position + used.position, used.size)
	_torso_mesh(atlas, torso_texture.region)
	_arm("Near", -1.5, 1)

func _joint(parent: Node2D, key: String, point: Vector2) -> Bone2D:
	var bone := Bone2D.new()
	bone.name = key
	bone.position = point
	bone.set_autocalculate_length_and_angle(false)
	bone.set_length(20.0)
	bone.set_bone_angle(PI / 2.0)
	bone.rest = bone.transform
	parent.add_child(bone)
	joints[key] = bone
	return bone

func _leg(side: String, x: float, depth: int) -> void:
	var anchor := Vector2(748, -35)
	var knee_pixel := Vector2(725, 560)
	var ankle_pixel := Vector2(705, 1110)
	var factor := 0.070
	var origin := Vector2(x, 6)
	var hip := _joint(body, side + "Hip", origin)
	var knee := _joint(hip, side + "Knee", (knee_pixel - anchor) * factor)
	var ankle := _joint(knee, side + "Ankle", (ankle_pixel - knee_pixel) * factor)
	_mesh(side + "Leg", Rect2(585, 65, 420, 1305), anchor, origin, factor,
		[hip, knee, ankle], [560.0, 1110.0], [55.0, 35.0], depth)

func _arm(side: String, x: float, depth: int) -> void:
	var anchor := Vector2(245, 250)
	var elbow_pixel := Vector2(238, 595)
	var factor := 0.061
	var origin := Vector2(x, -32)
	var shoulder := _joint(chest, side + "Shoulder", origin)
	var elbow := _joint(shoulder, side + "Elbow", (elbow_pixel - anchor) * factor)
	_mesh(side + "Arm", Rect2(145, 155, 220, 1040), anchor, origin, factor,
		[shoulder, elbow], [595.0], [65.0], depth)

func _mesh(mesh_name: String, region: Rect2, anchor: Vector2, origin: Vector2,
		factor: float, bones: Array, boundaries: Array, widths: Array, depth: int) -> void:
	var mesh := Polygon2D.new()
	mesh.name = mesh_name
	mesh.texture = limbs
	mesh.z_index = depth
	mesh.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	body.add_child(mesh)
	mesh.skeleton = mesh.get_path_to(body)
	var vertices := PackedVector2Array()
	var uv := PackedVector2Array()
	var faces: Array[PackedInt32Array] = []
	var weights: Array[PackedFloat32Array] = []
	for _bone in bones:
		weights.append(PackedFloat32Array())
	var rows := 100
	var cols := 8
	for row in range(rows + 1):
		var y := region.position.y + region.size.y * float(row) / rows
		var transfers: Array[float] = []
		for b in range(boundaries.size()):
			transfers.append(smoothstep(boundaries[b] - widths[b], boundaries[b] + widths[b], y))
		for col in range(cols + 1):
			var pixel := Vector2(region.position.x + region.size.x * float(col) / cols, y)
			var local := (pixel - anchor) * factor
			# Widen around the limb's centerline, tapering back to the original hand/boot.
			var is_leg := mesh_name.ends_with("Leg")
			var middle := lerpf(anchor.x, 725.0 if is_leg else 238.0, clampf((y - anchor.y) / (560.0 - anchor.y if is_leg else 595.0 - anchor.y), 0.0, 1.0))
			if y > (560.0 if is_leg else 595.0):
				middle = lerpf(725.0 if is_leg else 238.0, 705.0 if is_leg else 265.0, clampf((y - (560.0 if is_leg else 595.0)) / (550.0 if is_leg else 325.0), 0.0, 1.0))
			var taper := 1.0 - smoothstep(970.0 if is_leg else 840.0, 1120.0 if is_leg else 940.0, y)
			local.x += (pixel.x - middle) * factor * ((leg_fullness if is_leg else arm_fullness) - 1.0) * taper
			vertices.append(origin + local)
			uv.append(pixel)
			for b in range(bones.size()):
				var w: float = 1.0
				if b > 0:
					w *= transfers[b - 1]
				if b < transfers.size():
					w *= 1.0 - transfers[b]
				weights[b].append(w)
	for row in range(rows):
		for col in range(cols):
			var a := row * (cols + 1) + col
			var c := a + cols + 1
			faces.append(PackedInt32Array([a, a + 1, c + 1]))
			faces.append(PackedInt32Array([a, c + 1, c]))
	mesh.polygon = vertices
	mesh.uv = uv
	mesh.polygons = faces
	for b in range(bones.size()):
		mesh.add_bone(body.get_path_to(bones[b]), weights[b])

func _leg_pose(side: String, foot_target: Vector2) -> Vector2:
	var hip_bone: Bone2D = joints[side + "Hip"]
	var knee_bone: Bone2D = joints[side + "Knee"]
	var ankle_bone: Bone2D = joints[side + "Ankle"]
	var upper := knee_bone.position
	var lower := ankle_bone.position
	var target := foot_target - hip_bone.position
	var a := upper.length()
	var b := lower.length()
	var d := clampf(target.length(), absf(a - b) + 0.01, a + b - 0.01)
	var first := target.angle() - acos(clampf((a*a + d*d - b*b) / (2.0*a*d), -1.0, 1.0))
	var second := first + acos(clampf((d*d - a*a - b*b) / (2.0*a*b), -1.0, 1.0))
	var hip_rotation := first - upper.angle()
	return Vector2(hip_rotation, second - lower.angle() - hip_rotation)

func _angle(key: String, target: float, blend: float) -> void:
	var node: Bone2D = joints[key]
	node.rotation = lerp_angle(node.rotation, target, blend)

func _torso_mesh(atlas: Texture2D, region: Rect2) -> void:
	var mesh := Polygon2D.new()
	mesh.name = "TorsoAndHair"
	mesh.texture = atlas
	body.add_child(mesh)
	mesh.skeleton = mesh.get_path_to(body)
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	var chest_weights := PackedFloat32Array()
	var hair_weights := PackedFloat32Array()
	var faces: Array[PackedInt32Array] = []
	var rows := 60
	var cols := 24
	for row in range(rows + 1):
		for col in range(cols + 1):
			var unit := Vector2(float(col) / cols, float(row) / rows)
			var point := Vector2(-20, -72.5) + unit * region.size * (95.0 / region.size.y)
			points.append(point)
			uv.append(region.position + unit * region.size)
			var weight := (1.0 - smoothstep(-8.0, 1.0, point.x)) * smoothstep(-72.0, -55.0, point.y) * (1.0 - smoothstep(-28.0, -12.0, point.y)) * 0.8
			hair_weights.append(weight)
			chest_weights.append(1.0 - weight)
	for row in range(rows):
		for col in range(cols):
			var a := row * (cols + 1) + col
			var c := a + cols + 1
			faces.append(PackedInt32Array([a,a+1,c+1]))
			faces.append(PackedInt32Array([a,c+1,c]))
	mesh.polygon = points
	mesh.uv = uv
	mesh.polygons = faces
	mesh.add_bone(body.get_path_to(chest), chest_weights)
	mesh.add_bone(body.get_path_to(hair), hair_weights)

func _process(delta: float) -> void:
	if body == null:
		return
	var actor := get_parent() as CharacterBody2D
	var speed := preview_speed if preview_run else 0.0
	var grounded := true
	var hanging := false
	var vertical_speed := 0.0
	var horizontal_speed := speed
	var preparation := 0.0
	var landing := 0.0
	var takeoff := 10.0
	if actor != null and not preview_run:
		speed = absf(actor.velocity.x)
		horizontal_speed = actor.velocity.x
		vertical_speed = actor.velocity.y
		grounded = actor.is_on_floor()
		var state = actor.get("state")
		hanging = state == 2 or state == 3
		preparation = actor.get("jump_preparation")
		landing = actor.get("landing_compression")
		takeoff = actor.get("takeoff_elapsed")
		if speed > 15.0 and not hanging:
			facing = signf(actor.velocity.x)
	var blend := 1.0 - exp(-blend_speed * delta)
	var running := grounded and speed > 8.0 and preparation < 0.01
	run_weight = lerpf(run_weight, clampf(speed / 220.0, 0.0, 1.0) if running else 0.0, blend)
	if run_weight > 0.001:
		phase = fmod(phase + delta * TAU * speed * 0.52 / stride_length, TAU)
	scale.x = absf(scale.x) * facing
	pose_compression = lerpf(pose_compression, 9.0 * maxf(preparation, landing), 1.0 - exp(-22.0 * delta))
	air_blend = move_toward(air_blend, 0.0 if grounded else 1.0, delta * 10.0)
	body.position.y = BODY_Y + (12.0 - 0.8 * pow(sin(phase), 2.0)) * run_weight + pose_compression
	var acceleration_x := (horizontal_speed - previous_velocity_x) / maxf(delta, 0.001)
	previous_velocity_x = horizontal_speed
	var lean := clampf(horizontal_speed * facing / 6000.0 + acceleration_x * facing / 28000.0, -0.065, 0.10)
	lean += preparation * 0.06 + landing * 0.035
	chest.rotation = lerp_angle(chest.rotation, 0.0 if hanging else lean, blend)
	var hair_target := clampf(-acceleration_x * facing / 18000.0 + vertical_speed / 14000.0, -0.07, 0.07)
	var steps := maxi(1, ceili(delta / (1.0 / 120.0)))
	var step := delta / steps
	for _i in range(steps):
		hair_velocity += ((hair_target - hair.rotation) * 100.0 - hair_velocity * 14.0) * step
		hair.rotation = clampf(hair.rotation + hair_velocity * step, -0.09, 0.09)
	for index in range(2):
		var side := "Near" if index == 0 else "Far"
		var p := phase + float(index) * PI
		var t := fposmod(p / TAU, 1.0)
		var foot_x: float
		var lift := 0.0
		if t < 0.52:
			foot_x = lerpf(stride_length * 0.5, -stride_length * 0.5, t / 0.52)
		else:
			var u := (t - 0.52) / 0.48
			# Hermite endpoints match the backward velocity of the contact phase.
			var tangent := -stride_length * 0.48 / 0.52
			foot_x = -stride_length * 0.5 + stride_length * smoothstep(0.0, 1.0, u) + tangent * (2.0*u*u*u - 3.0*u*u + u)
			lift = 8.0 * pow(sin(u * PI), 2.0)
		var foot_target := Vector2(lerpf(-3.01, foot_x, run_weight), 56.2 - body.position.y - lift * run_weight)
		var pose := _leg_pose(side, foot_target)
		var hip := pose.x
		var knee := pose.y
		var shoulder := 0.36 * cos(p) * run_weight + preparation * 0.25
		var elbow := -0.5 * run_weight - preparation * 0.35
		if air_blend > 0.0:
			var tuck := smoothstep(0.06, 0.22, takeoff)
			var falling := smoothstep(-80.0, 250.0, vertical_speed)
			var air_hip := lerpf(-0.12, -0.42 if index == 0 else 0.12, tuck)
			var air_knee := lerpf(0.12, 0.85 if index == 0 else 0.5, tuck)
			air_hip = lerpf(air_hip, -0.18 if index == 0 else 0.05, falling)
			air_knee = lerpf(air_knee, 0.28 if index == 0 else 0.20, falling)
			hip = lerp_angle(hip, air_hip, air_blend)
			knee = lerp_angle(knee, air_knee, air_blend)
			shoulder = lerp_angle(shoulder, -0.65 + falling * 0.35, air_blend)
			elbow = lerp_angle(elbow, -0.85 + falling * 0.35, air_blend)
		if hanging:
			shoulder = PI - 0.15 if index == 0 else PI + 0.15
			elbow = 0.0
		var leg_blend := lerpf(1.0, blend, air_blend)
		var hip_bone: Bone2D = joints[side + "Hip"]
		var knee_bone: Bone2D = joints[side + "Knee"]
		hip_bone.rotation = move_toward(hip_bone.rotation, lerp_angle(hip_bone.rotation, hip, leg_blend), 6.0 * delta)
		knee_bone.rotation = move_toward(knee_bone.rotation, lerp_angle(knee_bone.rotation, knee, leg_blend), 7.0 * delta)
		_angle(side + "Ankle", -hip_bone.rotation - knee_bone.rotation, 1.0)
		_angle(side + "Shoulder", shoulder, blend)
		_angle(side + "Elbow", elbow, blend)
