extends CharacterBody2D

enum PlayerState { NORMAL, JUMPING, GRABBING, SWINGING, FALLING }

@export_group("Movement")
@export var move_speed := 240.0
@export var ground_acceleration := 1400.0
@export var ground_friction := 1700.0
@export var air_control := 650.0
@export var air_friction := 130.0
@export var jump_velocity := -478.4
@export var gravity_up := 1000.0
@export var gravity_down := 1500.0
@export var max_fall_speed := 900.0
@export_range(0.0, 0.25, 0.01) var coyote_time := 0.12
@export_range(0.0, 0.25, 0.01) var jump_buffer_time := 0.13
@export_range(0.1, 0.9, 0.05) var jump_release_multiplier := 0.5

@export_group("Vine grab")
@export var rope_grab_distance := 120.0
@export var max_vertical_grab_offset := 96.0
@export var min_grab_speed := 85.0
@export_range(-1.0, 1.0, 0.05) var approach_dot_threshold := 0.05
@export var grab_transition_time := 0.12
@export var grab_cooldown := 0.3
@export var release_upward_boost := 35.0
@export_range(1.0, 20.0, 0.1) var release_distance_multiplier := 2.5
@export_range(0.05, 1.0, 0.05) var release_hold_time := 0.25

@export_group("Pendulum swing")
@export var swing_gravity := 980.0
@export_range(0.0, 2.0, 0.01) var swing_damping := 0.12
@export_range(0.1, 3.0, 0.05) var launch_multiplier := 1.25
@export var additional_jump_impulse := Vector2(0.0, -140.0)
@export_range(0.0, 2000.0, 10.0) var maximum_launch_speed := 1500.0
@export_range(0.0, 1000.0, 10.0) var minimum_launch_speed := 0.0
@export_range(0.0, 1200.0, 10.0) var swing_pump_acceleration := 220.0
@export var hand_offset := Vector2(0.0, -48.0)
@export_range(30.0, 300.0, 5.0) var minimum_swing_length := 80.0

@export_group("Vine climb")
@export var climb_speed := 240.0

@export_group("Debug")
@export var debug_grab := true

@onready var rope: FlexibleVine = %Vine2D

var state: PlayerState = PlayerState.NORMAL
var jump_armed := false
var cooldown_timer := 0.0
var grab_start_position := Vector2.ZERO
var grab_elapsed := 0.0
var debug_candidate_valid := false
var debug_candidate_world := Vector2.ZERO
var flight_horizontal_multiplier := 1.0
var release_input_ready := false
var release_pending := false
var release_hold_elapsed := 0.0
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jump_cut_allowed := false
var swing_pivot_world := Vector2.ZERO
var swing_length := 0.0
var swing_angle := 0.0
var swing_angular_velocity := 0.0
var swing_incoming_velocity := Vector2.ZERO
var grab_target_position := Vector2.ZERO


@export_group("Jump presentation")
@export_range(0.0, 0.15) var anticipation_time := 0.09
@export_range(0.1, 0.4) var landing_duration := 0.22
var jump_preparation := 0.0
var landing_compression := 0.0
var takeoff_elapsed := 10.0
var preparing_jump := false
var preparation_elapsed := 0.0
var preparation_released := false
var landing_elapsed := 10.0
var landing_strength := 0.0

func _launch_jump() -> void:
	preparing_jump = false
	jump_preparation = 0.0
	velocity.y = jump_velocity
	if preparation_released or not Input.is_action_pressed("jump"):
		velocity.y *= jump_release_multiplier
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	jump_armed = true
	jump_cut_allowed = not preparation_released
	takeoff_elapsed = 0.0
	landing_strength = 0.0
	state = PlayerState.JUMPING

func _physics_process(delta: float) -> void:
	cooldown_timer = maxf(cooldown_timer - delta, 0.0)
	takeoff_elapsed += delta
	landing_elapsed += delta
	var landing_t := clampf(landing_elapsed / landing_duration, 0.0, 1.0)
	landing_compression = landing_strength * pow(sin(PI * landing_t), 2.0)

	if state == PlayerState.GRABBING:
		_process_grab_transition(delta)
		queue_redraw()
		return
	if state == PlayerState.SWINGING:
		_process_pendulum(delta)
		queue_redraw()
		return

	var was_grounded := is_on_floor()
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)
	if was_grounded:
		coyote_timer = coyote_time
		flight_horizontal_multiplier = 1.0
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	var direction := Input.get_axis("move_left", "move_right")
	var horizontal_scale := flight_horizontal_multiplier
	var change_rate := ground_acceleration if was_grounded else air_control
	if is_zero_approx(direction):
		change_rate = ground_friction if was_grounded else air_friction
	velocity.x = move_toward(velocity.x, direction * move_speed * horizontal_scale, change_rate * horizontal_scale * delta)

	if not preparing_jump and jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		preparation_released = false
		jump_buffer_timer = 0.0
		if was_grounded and anticipation_time > 0.0:
			preparing_jump = true
			preparation_elapsed = 0.0
		else:
			_launch_jump()

	if preparing_jump:
		preparation_released = preparation_released or Input.is_action_just_released("jump")
		preparation_elapsed += delta
		jump_preparation = smoothstep(0.0, anticipation_time, preparation_elapsed)
		if not was_grounded or preparation_elapsed >= anticipation_time:
			# A pending jump still launches if the actor walks off the edge during preparation.
			_launch_jump()

	if jump_cut_allowed and Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_release_multiplier
		jump_cut_allowed = false
	if velocity.y < 0.0:
		velocity.y += gravity_up * delta
	else:
		velocity.y = minf(velocity.y + gravity_down * delta, max_fall_speed)
	if jump_armed and cooldown_timer <= 0.0 and _try_grab_rope():
		queue_redraw()
		return

	var impact_speed := maxf(velocity.y, 0.0)
	move_and_slide()
	if is_on_floor() and velocity.y >= 0.0:
		if not was_grounded and impact_speed > 80.0:
			landing_elapsed = 0.0
			landing_strength = clampf(impact_speed / 650.0, 0.2, 1.0)
		flight_horizontal_multiplier = 1.0
		jump_armed = false
		jump_cut_allowed = false
		state = PlayerState.NORMAL
	elif velocity.y < 0.0:
		state = PlayerState.JUMPING
	else:
		state = PlayerState.FALLING
	queue_redraw()

func _try_grab_rope() -> bool:
	debug_candidate_valid = false
	if velocity.length() < min_grab_speed:
		return false
	var hand_world_position := global_position + hand_offset
	var nearest_distance := rope_grab_distance
	var selected: FlexibleVine = null
	var selected_point := Vector2.ZERO
	for item in get_tree().get_nodes_in_group("climbable_vines"):
		var vine := item as FlexibleVine
		if vine == null:
			continue
		# Do not catch a trailing vine after reaching the far bank.
		if absf(hand_world_position.x - vine.get_anchor_world_position().x) > 230.0:
			continue
		var nearest := vine.get_closest_point(hand_world_position)
		var candidate: Vector2 = nearest["position"]
		var offset := candidate - hand_world_position
		if offset.length() > nearest_distance or absf(offset.y) > max_vertical_grab_offset:
			continue
		if velocity.normalized().dot(offset.normalized()) < approach_dot_threshold:
			continue
		if not _has_clear_grab_path(candidate, hand_world_position):
			continue
		nearest_distance = offset.length()
		selected = vine
		selected_point = candidate
	if selected == null:
		return false
	rope = selected
	debug_candidate_valid = true
	debug_candidate_world = selected_point
	_begin_rope_grab(selected_point)
	return true

func _has_clear_grab_path(candidate: Vector2, hand_world_position: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(hand_world_position, candidate, collision_mask)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _begin_rope_grab(candidate_world: Vector2) -> void:
	flight_horizontal_multiplier = 1.0
	# The jump used to reach the vine must be released before a second press can launch.
	release_input_ready = not Input.is_action_pressed("jump")
	release_pending = false
	release_hold_elapsed = 0.0
	swing_pivot_world = rope.get_anchor_world_position()
	var shortest_allowed_length := minf(minimum_swing_length, rope.vine_length)
	swing_length = maxf(swing_pivot_world.distance_to(candidate_world), shortest_allowed_length)
	swing_incoming_velocity = velocity
	grab_target_position = candidate_world - hand_offset
	grab_start_position = global_position
	grab_elapsed = 0.0
	state = PlayerState.GRABBING
	rope.begin_player_swing(global_position + hand_offset)


func _process_grab_transition(delta: float) -> void:
	if not is_instance_valid(rope):
		_detach_from_vine(velocity)
		return
	grab_elapsed += delta
	var blend := clampf(grab_elapsed / maxf(grab_transition_time, 0.001), 0.0, 1.0)
	blend = blend * blend * (3.0 - 2.0 * blend)
	var next_position := grab_start_position.lerp(grab_target_position, blend)
	velocity = (next_position - global_position) / maxf(delta, 0.0001)
	var collision := move_and_collide(velocity * delta)
	rope.update_player_swing(global_position + hand_offset)
	if collision != null:
		_detach_from_vine(velocity)
		return
	if blend >= 1.0:
		var hand_position := global_position + hand_offset
		var radial := (hand_position - swing_pivot_world).normalized()
		if radial.length_squared() < 0.001:
			radial = Vector2.DOWN
		swing_length = maxf(hand_position.distance_to(swing_pivot_world), minf(minimum_swing_length, rope.vine_length))
		swing_angle = atan2(radial.x, radial.y)
		var tangent := _swing_tangent(swing_angle)
		swing_angular_velocity = swing_incoming_velocity.dot(tangent) / swing_length
		swing_angular_velocity = clampf(swing_angular_velocity, -maximum_launch_speed / swing_length, maximum_launch_speed / swing_length)
		state = PlayerState.SWINGING
		velocity = tangent * swing_angular_velocity * swing_length


func _process_pendulum(delta: float) -> void:
	if not is_instance_valid(rope):
		_detach_from_vine(velocity)
		return
	var steps := maxi(ceili(delta / (1.0 / 120.0)), 1)
	var step_delta := delta / float(steps)
	for _step in range(steps):
		# Keep the rope length fixed unless the player explicitly reels in or out.
		var old_length := swing_length
		var climb_direction := Input.get_axis("climb_up", "climb_down")
		if not is_zero_approx(climb_direction):
			var shortest_allowed_length := minf(minimum_swing_length, rope.vine_length)
			swing_length = clampf(swing_length + climb_direction * climb_speed * step_delta, shortest_allowed_length, rope.vine_length)
			if not is_equal_approx(old_length, swing_length):
				# Preserve tangential speed while the player changes rope length.
				swing_angular_velocity *= old_length / swing_length
		var tangent := _swing_tangent(swing_angle)
		var input_direction := Input.get_axis("move_left", "move_right")
		var angular_acceleration := -(swing_gravity / maxf(swing_length, 1.0)) * sin(swing_angle)
		angular_acceleration -= swing_damping * swing_angular_velocity
		# Directional pumping adds a small, controlled force along the current arc.
		angular_acceleration += input_direction * swing_pump_acceleration * absf(tangent.x) / maxf(swing_length, 1.0)
		swing_angular_velocity += angular_acceleration * step_delta
		swing_angle += swing_angular_velocity * step_delta
	var hand_position := swing_pivot_world + _swing_radial(swing_angle) * swing_length
	var target_position := hand_position - hand_offset
	velocity = (target_position - global_position) / maxf(delta, 0.0001)
	var collision := move_and_collide(velocity * delta)
	rope.update_player_swing(global_position + hand_offset)
	if collision != null:
		var carried_velocity := _current_tangent_velocity()
		_detach_from_vine(carried_velocity)
		return
	_process_release_input(delta)


func _swing_radial(angle: float) -> Vector2:
	# Angle is measured from the downward vertical; positive angles swing right.
	return Vector2(sin(angle), cos(angle))


func _swing_tangent(angle: float) -> Vector2:
	return Vector2(cos(angle), -sin(angle))


func _current_tangent_velocity() -> Vector2:
	return _swing_tangent(swing_angle) * swing_angular_velocity * swing_length


func _process_release_input(delta: float) -> void:
	if not release_input_ready:
		if Input.is_action_just_released("jump"):
			release_input_ready = true
		return

	if not release_pending and Input.is_action_just_pressed("jump"):
		release_pending = true
		release_hold_elapsed = 0.0
	if not release_pending:
		return

	# A tap releases normally on key-up; a hold retains the earlier distance boost.
	if Input.is_action_just_released("jump"):
		_release_from_swing(false)
		return
	if Input.is_action_pressed("jump"):
		release_hold_elapsed += delta
		if release_hold_elapsed >= release_hold_time:
			_release_from_swing(true)


func _release_from_swing(held_boost: bool) -> void:
	var tangent_velocity := _current_tangent_velocity()
	var effective_multiplier := launch_multiplier
	if held_boost:
		effective_multiplier *= release_distance_multiplier
	var launch_velocity := tangent_velocity * effective_multiplier + additional_jump_impulse + Vector2.UP * release_upward_boost
	if minimum_launch_speed > 0.0 and launch_velocity.length() < minimum_launch_speed:
		var fallback_direction := tangent_velocity.normalized()
		if fallback_direction.length_squared() < 0.001:
			fallback_direction = Vector2(signf(Input.get_axis("move_left", "move_right")), -0.35).normalized()
		if fallback_direction.length_squared() < 0.001:
			fallback_direction = Vector2.RIGHT
		launch_velocity = fallback_direction * minimum_launch_speed
	if maximum_launch_speed > 0.0:
		launch_velocity = launch_velocity.limit_length(maximum_launch_speed)
	_detach_from_vine(launch_velocity)
	# A deliberate release must not immediately reattach to the same trailing vine.
	jump_armed = false


func _detach_from_vine(inherited_velocity: Vector2) -> void:
	release_pending = false
	release_hold_elapsed = 0.0
	release_input_ready = false
	if is_instance_valid(rope):
		rope.end_player_swing(global_position + hand_offset, inherited_velocity)
	velocity = inherited_velocity
	flight_horizontal_multiplier = 1.0
	cooldown_timer = grab_cooldown
	state = PlayerState.FALLING if velocity.y >= 0.0 else PlayerState.JUMPING
	jump_armed = true


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
