extends CharacterBody2D

enum PlayerState { NORMAL, JUMPING, GRABBING, SWINGING, FALLING }

@export_group("Movement")
@export var move_speed := 300.0
@export var acceleration := 1800.0
@export var friction := 2200.0
@export var air_friction := 180.0
@export var jump_velocity := -430.0
@export var gravity := 1200.0
@export var max_fall_speed := 900.0

@export_group("Vine grab")
@export var rope_grab_distance := 120.0
@export var max_vertical_grab_offset := 96.0
@export var min_grab_speed := 85.0
@export_range(-1.0, 1.0, 0.05) var approach_dot_threshold := 0.05
@export var grab_hang_distance := 68.0
@export var grab_transition_time := 0.12
@export var grab_cooldown := 0.3
@export var minimum_swing_launch_speed := 280.0
@export var swing_angular_damp := 0.12
@export var release_upward_boost := 35.0

@export_group("Debug")
@export var debug_grab := true

@onready var rope: RigidBody2D = %RigidBody2D
@onready var rope_collision: CollisionShape2D = rope.get_node("CollisionShape2D")

var state: PlayerState = PlayerState.NORMAL
var jump_armed := false
var jump_direction := 0.0
var cooldown_timer := 0.0
var ignoring_rope_collision := false
var rope_local_grab_point := Vector2.ZERO
var rope_local_player_offset := Vector2.ZERO
var previous_follow_position := Vector2.ZERO
var grab_start_position := Vector2.ZERO
var grab_elapsed := 0.0
var debug_candidate_valid := false
var debug_candidate_world := Vector2.ZERO
var rope_rest_rotation := 0.0
var rope_gravity_before_grab := 1.0
var rope_angular_damp_before_grab := -1.0
var rope_freeze_before_grab := false
var rope_freeze_mode_before_grab := RigidBody2D.FREEZE_MODE_STATIC
var rope_pendulum_length := 250.0
var swing_angle := 0.0
var swing_angular_velocity := 0.0


func _ready() -> void:
	# SegmentShape2D has no area, so automatic mass calculation leaves the vine's
	# center of mass at its pivot. Put it halfway down the segment to give gravity
	# a restoring torque and make it behave like a pendulum.
	if rope_collision.shape is SegmentShape2D:
		var segment := rope_collision.shape as SegmentShape2D
		rope.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
		rope.center_of_mass = rope.to_local(rope_collision.to_global((segment.a + segment.b) * 0.5))
		rope_pendulum_length = maxf(rope.center_of_mass.length(), 1.0)
	rope_rest_rotation = rope.rotation


func _physics_process(delta: float) -> void:
	var previous_cooldown := cooldown_timer
	cooldown_timer = maxf(cooldown_timer - delta, 0.0)
	if previous_cooldown > 0.0 and cooldown_timer <= 0.0 and ignoring_rope_collision and is_instance_valid(rope):
		remove_collision_exception_with(rope)
		ignoring_rope_collision = false

	if state == PlayerState.GRABBING or state == PlayerState.SWINGING:
		_process_rope_follow(delta)
		queue_redraw()
		return

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * move_speed, acceleration * delta)
	else:
		var current_friction := friction if is_on_floor() else air_friction
		velocity.x = move_toward(velocity.x, 0.0, current_friction * delta)

	if is_on_floor():
		if velocity.y > 0.0:
			velocity.y = 0.0
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
			jump_armed = true
			jump_direction = signf(direction) if direction != 0.0 else signf(velocity.x)
			state = PlayerState.JUMPING
	else:
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
		if jump_armed and direction != 0.0:
			jump_direction = signf(direction)

	if jump_armed and cooldown_timer <= 0.0 and _try_grab_rope():
		queue_redraw()
		return

	move_and_slide()
	if is_on_floor() and velocity.y >= 0.0:
		jump_armed = false
		state = PlayerState.NORMAL
	elif velocity.y < 0.0:
		state = PlayerState.JUMPING
	else:
		state = PlayerState.FALLING
	queue_redraw()


func _try_grab_rope() -> bool:
	debug_candidate_valid = false
	if not is_instance_valid(rope) or not is_instance_valid(rope_collision):
		return false
	if not rope_collision.shape is SegmentShape2D:
		return false

	var segment := rope_collision.shape as SegmentShape2D
	var local_player := rope_collision.to_local(global_position)
	var closest_local := Geometry2D.get_closest_point_to_segment(local_player, segment.a, segment.b)
	var candidate := rope_collision.to_global(closest_local)
	debug_candidate_world = candidate
	debug_candidate_valid = true

	var to_vine := candidate - global_position
	if to_vine.length() > rope_grab_distance:
		return false
	if absf(to_vine.y) > max_vertical_grab_offset:
		return false
	if velocity.length() < min_grab_speed:
		return false
	if velocity.normalized().dot(to_vine.normalized()) < approach_dot_threshold:
		return false
	if not _has_clear_grab_path(candidate):
		return false

	_begin_rope_grab(candidate, closest_local)
	return true


func _has_clear_grab_path(candidate: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, candidate, collision_mask)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Object = hit.get("collider")
	return collider == rope


func _begin_rope_grab(candidate_world: Vector2, candidate_local: Vector2) -> void:
	add_collision_exception_with(rope)
	ignoring_rope_collision = true
	rope_local_grab_point = rope.to_local(candidate_world)
	rope_local_player_offset = rope.to_local(global_position) - rope_local_grab_point
	if rope_local_player_offset.length() > grab_hang_distance:
		rope_local_player_offset = rope_local_player_offset.normalized() * grab_hang_distance
	previous_follow_position = global_position
	grab_start_position = global_position
	grab_elapsed = 0.0
	state = PlayerState.GRABBING

	# Carry the incoming tangential speed into the pendulum, with a minimum launch
	# speed so a normal jump always starts a visible swing.
	var arm := candidate_world - rope.global_position
	var radial := arm.normalized()
	var tangent := Vector2(-radial.y, radial.x)
	var tangential_speed := absf(velocity.dot(tangent))
	var launch_speed := maxf(tangential_speed, minimum_swing_launch_speed)
	var launch_direction := jump_direction
	if launch_direction == 0.0:
		launch_direction = signf(velocity.x)
	if launch_direction == 0.0:
		launch_direction = signf((candidate_world - global_position).x)

	# Angular velocity determines the horizontal direction of the vine's first
	# arc. For a hanging rope, the tangent's x sign reverses with rotation sign.
	var angular_direction := launch_direction * signf(tangent.x)
	swing_angle = wrapf(rope.rotation - rope_rest_rotation, -PI, PI)
	swing_angular_velocity = angular_direction * launch_speed / rope_pendulum_length
	rope_gravity_before_grab = rope.gravity_scale
	rope_angular_damp_before_grab = rope.angular_damp
	rope_freeze_before_grab = rope.freeze
	rope_freeze_mode_before_grab = rope.freeze_mode
	rope.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	rope.freeze = true
	rope.gravity_scale = 0.0
	rope.angular_damp = 0.0
	rope.angular_velocity = 0.0

	# Keep the closest point in vine-local coordinates so the player follows that
	# point as the rigid vine rotates.
	rope_local_grab_point = rope.to_local(rope_collision.to_global(candidate_local))


func _process_rope_follow(delta: float) -> void:
	if not is_instance_valid(rope):
		_release_rope(Vector2.ZERO)
		return
	# Integrate a damped pendulum rather than moving between points linearly.
	# Gravity restores the vine toward vertical; speed is naturally highest at
	# the center of the arc and close to zero at each end.
	var restoring_acceleration := -(gravity / rope_pendulum_length) * sin(swing_angle)
	swing_angular_velocity += restoring_acceleration * delta
	swing_angular_velocity *= exp(-swing_angular_damp * delta)
	swing_angle += swing_angular_velocity * delta
	rope.rotation = rope_rest_rotation + swing_angle
	rope.angular_velocity = swing_angular_velocity

	var follow_position := rope.to_global(rope_local_grab_point + rope_local_player_offset)
	if state == PlayerState.GRABBING:
		grab_elapsed += delta
		var blend := clampf(grab_elapsed / maxf(grab_transition_time, 0.001), 0.0, 1.0)
		blend = blend * blend * (3.0 - 2.0 * blend)
		follow_position = grab_start_position.lerp(follow_position, blend)
		if grab_elapsed >= grab_transition_time:
			state = PlayerState.SWINGING

	velocity = (follow_position - previous_follow_position) / maxf(delta, 0.0001)
	var collision := move_and_collide(velocity * delta)
	previous_follow_position = global_position
	if collision != null:
		_release_rope(velocity)
		return

	if Input.is_action_just_pressed("release_grab"):
		_release_rope(velocity)


func _release_rope(inherited_velocity: Vector2) -> void:
	if is_instance_valid(rope):
		rope.rotation = rope_rest_rotation + swing_angle
		rope.angular_velocity = swing_angular_velocity
		rope.gravity_scale = rope_gravity_before_grab
		rope.angular_damp = rope_angular_damp_before_grab
		rope.freeze_mode = rope_freeze_mode_before_grab
		rope.freeze = rope_freeze_before_grab
	velocity = inherited_velocity + Vector2.UP * release_upward_boost
	cooldown_timer = grab_cooldown
	state = PlayerState.FALLING if velocity.y >= 0.0 else PlayerState.JUMPING
	jump_armed = true
	previous_follow_position = global_position


func _draw() -> void:
	if not debug_grab:
		return
	draw_arc(Vector2.ZERO, rope_grab_distance, 0.0, TAU, 64, Color(0.2, 0.85, 1.0, 0.65), 2.0, true)
	if debug_candidate_valid:
		var point_local := to_local(debug_candidate_world)
		draw_line(Vector2.ZERO, point_local, Color(1.0, 0.75, 0.15, 0.9), 2.0, true)
		draw_circle(point_local, 5.0, Color(1.0, 0.25, 0.2, 0.95))
	var label := "%s  cooldown %.2f" % [_state_name(), cooldown_timer]
	draw_string(ThemeDB.fallback_font, Vector2(-72.0, -58.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color.WHITE)


func _state_name() -> String:
	match state:
		PlayerState.NORMAL:
			return "NORMAL"
		PlayerState.JUMPING:
			return "JUMPING"
		PlayerState.GRABBING:
			return "GRABBING"
		PlayerState.SWINGING:
			return "SWINGING"
		PlayerState.FALLING:
			return "FALLING"
	return "UNKNOWN"
