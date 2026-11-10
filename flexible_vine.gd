class_name FlexibleVine
extends Node2D

@export_group("Vine simulation")
@export_range(6, 24, 1) var segment_count := 16
@export var vine_length := 500.0
@export var gravity := 1450.0
@export_range(1, 12, 1) var constraint_iterations := 8
@export_range(1, 4, 1) var simulation_substeps := 2
@export_range(0.9, 1.0, 0.001) var damping_per_60_fps := 0.998
@export var player_extra_gravity := 950.0
@export var swing_pump_acceleration := 700.0

@export_group("Appearance")
@export var outline_width := 17.0
@export var vine_width := 11.0

@onready var outline: Line2D = $Outline
@onready var vine_line: Line2D = $VineLine

var _points: Array[Vector2] = []
var _previous_points: Array[Vector2] = []
var _segment_length := 0.0
var _attached_progress := -1.0
var _swing_input := 0.0
var _last_substep_delta := 1.0 / 120.0
var _swing_active := false
var _swing_hand_world_position := Vector2.ZERO


func _ready() -> void:
	add_to_group("climbable_vines")
	segment_count = maxi(segment_count, 6)
	_segment_length = vine_length / float(segment_count)
	for index in range(segment_count + 1):
		var point := Vector2(0.0, _segment_length * index)
		_points.append(point)
		_previous_points.append(point)
	outline.width = outline_width
	outline.default_color = Color("26351b")
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	vine_line.width = 100.0
	vine_line.texture = load("res://assets/level01/vine_bark.png")
	vine_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	vine_line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	vine_line.antialiased = true
	outline.hide()
	vine_line.default_color = Color.WHITE
	vine_line.joint_mode = Line2D.LINE_JOINT_ROUND
	vine_line.begin_cap_mode = Line2D.LINE_CAP_NONE
	vine_line.end_cap_mode = Line2D.LINE_CAP_NONE
	_update_visual()


func _physics_process(delta: float) -> void:
	if _points.is_empty():
		return
	if _swing_active:
		_set_points_to_swing_hand()
		_update_visual()
		return
	var steps := maxi(simulation_substeps, 1)
	var step_delta := delta / float(steps)
	_last_substep_delta = maxf(step_delta, 0.0001)
	for _step in range(steps):
		_integrate(step_delta)
		_solve_constraints()
	_update_visual()


func get_anchor_world_position() -> Vector2:
	return to_global(Vector2.ZERO)


func begin_player_swing(hand_world_position: Vector2) -> void:
	_swing_active = true
	_attached_progress = -1.0
	_swing_hand_world_position = hand_world_position
	_set_points_to_swing_hand()
	_update_visual()


func update_player_swing(hand_world_position: Vector2) -> void:
	if not _swing_active:
		return
	_swing_hand_world_position = hand_world_position
	_set_points_to_swing_hand()


func end_player_swing(hand_world_position: Vector2, hand_velocity: Vector2) -> void:
	if not _swing_active:
		return
	_swing_hand_world_position = hand_world_position
	_set_points_to_swing_hand()
	# Pass part of the released player's motion into the flexible vine.
	for index in range(_points.size()):
		var fraction := float(index) / float(maxi(_points.size() - 1, 1))
		_previous_points[index] = _points[index] - hand_velocity * _last_substep_delta * fraction
	_swing_active = false
	_attached_progress = -1.0
	_swing_input = 0.0


func _set_points_to_swing_hand() -> void:
	var endpoint := to_local(_swing_hand_world_position)
	for index in range(_points.size()):
		var fraction := float(index) / float(maxi(_points.size() - 1, 1))
		_points[index] = Vector2.ZERO.lerp(endpoint, fraction)
		if _swing_active:
			_previous_points[index] = _points[index]


func _integrate(delta: float) -> void:
	var attached_index := _get_attached_index()
	var damping := pow(damping_per_60_fps, delta * 60.0)
	for index in range(1, _points.size()):
		var current := _points[index]
		var movement := (current - _previous_points[index]) * damping
		var acceleration := Vector2(0.0, gravity)
		if index == attached_index:
			acceleration.y += player_extra_gravity
			if not is_zero_approx(_swing_input):
				var radial := (current - _points[0]).normalized()
				var tangent := Vector2(-radial.y, radial.x)
				var requested_force := Vector2(_swing_input * swing_pump_acceleration, 0.0)
				acceleration += tangent * requested_force.dot(tangent)
		_previous_points[index] = current
		_points[index] = current + movement + acceleration * delta * delta
	_points[0] = Vector2.ZERO
	_previous_points[0] = Vector2.ZERO


func _solve_constraints() -> void:
	for _iteration in range(constraint_iterations):
		_points[0] = Vector2.ZERO
		for index in range(_points.size() - 1):
			var difference := _points[index + 1] - _points[index]
			var distance := difference.length()
			if distance <= 0.0001:
				continue
			var correction := difference * ((distance - _segment_length) / distance)
			if index == 0:
				_points[index + 1] -= correction
			else:
				_points[index] += correction * 0.5
				_points[index + 1] -= correction * 0.5
		_points[0] = Vector2.ZERO


func get_closest_point(world_position: Vector2) -> Dictionary:
	var local_position := to_local(world_position)
	var best_distance_squared := INF
	var best_local_point := Vector2.ZERO
	var best_progress := 0.0
	for index in range(_points.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(local_position, _points[index], _points[index + 1])
		var distance_squared := local_position.distance_squared_to(closest)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_local_point = closest
			var segment_fraction := _fraction_along_segment(closest, _points[index], _points[index + 1])
			best_progress = (float(index) + segment_fraction) / float(maxi(_points.size() - 1, 1))
	return {
		"position": to_global(best_local_point),
		"progress": best_progress,
		"distance": sqrt(best_distance_squared)
	}


func get_point_at_progress(progress: float) -> Vector2:
	return to_global(_sample_local(_points, progress))


func get_point_velocity(progress: float) -> Vector2:
	var current := _sample_local(_points, progress)
	var previous := _sample_local(_previous_points, progress)
	return (current - previous) / maxf(_last_substep_delta, 0.0001)


func get_tangent_at_progress(progress: float) -> Vector2:
	var step := 1.0 / float(maxi(_points.size() - 1, 1))
	var before := _sample_local(_points, clampf(progress - step, 0.0, 1.0))
	var after := _sample_local(_points, clampf(progress + step, 0.0, 1.0))
	return (after - before).normalized()


func attach_player(progress: float, launch_velocity: Vector2) -> void:
	_attached_progress = clampf(progress, 0.0, 1.0)
	var index := _get_attached_index()
	_previous_points[index] = _points[index] - launch_velocity * _last_substep_delta


func update_player_attachment(progress: float, horizontal_input: float) -> void:
	_attached_progress = clampf(progress, 0.0, 1.0)
	_swing_input = clampf(horizontal_input, -1.0, 1.0)


func detach_player() -> void:
	_attached_progress = -1.0
	_swing_input = 0.0


func _get_attached_index() -> int:
	if _attached_progress < 0.0 or _points.is_empty():
		return -1
	return clampi(roundi(_attached_progress * float(_points.size() - 1)), 1, _points.size() - 1)


func _sample_local(source: Array[Vector2], progress: float) -> Vector2:
	if source.is_empty():
		return Vector2.ZERO
	var scaled_progress := clampf(progress, 0.0, 1.0) * float(source.size() - 1)
	var first_index := mini(floori(scaled_progress), source.size() - 1)
	var second_index := mini(first_index + 1, source.size() - 1)
	return source[first_index].lerp(source[second_index], scaled_progress - float(first_index))


func _fraction_along_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	if segment.length_squared() <= 0.0001:
		return 0.0
	return clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)


func _update_visual() -> void:
	var curve := Curve2D.new()
	curve.bake_interval = 5.0
	for index in range(_points.size()):
		var previous := _points[maxi(index - 1, 0)]
		var following := _points[mini(index + 1, _points.size() - 1)]
		var tangent := (following - previous) / 6.0
		curve.add_point(_points[index], -tangent, tangent)
	var smooth_points := curve.get_baked_points()
	outline.points = smooth_points
	# Subtle irregularity follows the load-bearing curve; endpoints stay at the hands.
	for i in range(1,smooth_points.size()-1):
		var t := float(i)/float(smooth_points.size()-1)
		var normal := (smooth_points[i+1]-smooth_points[i-1]).normalized().orthogonal()
		smooth_points[i] += normal * sin(t*PI) * (sin(t*43.0)*2.5 + sin(t*97.0)*0.8)
	vine_line.points = smooth_points


