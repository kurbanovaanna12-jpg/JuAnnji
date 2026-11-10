extends Control
## Two independent fingers: jump on the left, analog movement on the right.
const DEAD_ZONE := 0.16
const TRAVEL := 52.0
var stick_center := Vector2.ZERO
var jump_center := Vector2.ZERO
var stick_offset := Vector2.ZERO
var stick_finger := -1
var jump_finger := -1
var owned_actions: Dictionary = {}
var level: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	reset_input()
	var bounds := get_viewport_rect()
	if OS.has_feature("ios") or OS.has_feature("android"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if safe.size.x > 0 and safe.size.y > 0:
			var inverse := get_viewport().get_screen_transform().affine_inverse()
			bounds = Rect2(inverse * safe.position, inverse.basis_xform(safe.size))
	stick_center = Vector2(bounds.end.x - 138.0, bounds.end.y - 130.0)
	jump_center = Vector2(bounds.position.x + 138.0, bounds.end.y - 130.0)
	queue_redraw()

func _process(_delta: float) -> void:
	var enabled: bool = not get_tree().paused and (not is_instance_valid(level) or not level.completed)
	if visible != enabled:
		visible = enabled
		reset_input()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset_input()

func _exit_tree() -> void:
	reset_input()

func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	var handled := false
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			handled = _press(event.index, event.position)
		else:
			handled = _release(event.index)
	elif event is InputEventScreenDrag:
		handled = _drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != -1:
		handled = _press(-2, event.position) if event.pressed else _release(-2)
	elif event is InputEventMouseMotion and event.device != -1:
		handled = _drag(-2, event.position)
	if handled:
		get_viewport().set_input_as_handled()

func _press(finger: int, point: Vector2) -> bool:
	if stick_finger == -1 and point.distance_to(stick_center) <= 92.0:
		stick_finger = finger
		_drag(finger, point)
		return true
	if jump_finger == -1 and point.distance_to(jump_center) <= 76.0:
		jump_finger = finger
		_action("jump", 1.0)
		queue_redraw()
		return true
	return false

func _drag(finger: int, point: Vector2) -> bool:
	if finger == stick_finger and stick_finger != -1:
		stick_offset = (point - stick_center).limit_length(TRAVEL)
		var direction := stick_offset / TRAVEL
		var x := _axis(direction.x)
		var y := _axis(direction.y)
		_action("move_left", maxf(-x, 0.0))
		_action("move_right", maxf(x, 0.0))
		_action("climb_up", maxf(-y, 0.0))
		_action("climb_down", maxf(y, 0.0))
		queue_redraw()
		return true
	return finger == jump_finger and jump_finger != -1

func _axis(value: float) -> float:
	return signf(value) * maxf(0.0, (absf(value) - DEAD_ZONE) / (1.0 - DEAD_ZONE))

func _release(finger: int) -> bool:
	var handled := false
	if finger == stick_finger and stick_finger != -1:
		stick_finger = -1
		stick_offset = Vector2.ZERO
		for action in ["move_left", "move_right", "climb_up", "climb_down"]:
			_action(action, 0.0)
		handled = true
	if finger == jump_finger and jump_finger != -1:
		jump_finger = -1
		_action("jump", 0.0)
		handled = true
	queue_redraw()
	return handled

func _action(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
		owned_actions[action] = true
	elif owned_actions.has(action):
		Input.action_release(action)
		owned_actions.erase(action)

func reset_input() -> void:
	for action in owned_actions:
		Input.action_release(action)
	owned_actions.clear()
	stick_finger = -1
	jump_finger = -1
	stick_offset = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	var rim := Color(0.96, 0.93, 0.81, 0.48)
	var fill := Color(0.06, 0.11, 0.10, 0.25)
	draw_circle(stick_center, 78.0, fill, true, -1.0, true)
	draw_arc(stick_center, 78.0, 0, TAU, 96, rim, 2.0, true)
	draw_arc(stick_center, 52.0, 0, TAU, 80, Color(0.96, 0.93, 0.81, 0.13), 1.0, true)
	var knob := stick_center + stick_offset
	draw_circle(knob, 32.0, Color(0.93, 0.91, 0.78, 0.38 if stick_finger != -1 else 0.24), true, -1.0, true)
	draw_arc(knob, 32.0, 0, TAU, 64, rim, 2.0, true)
	draw_circle(jump_center, 61.0, Color(0.89, 0.79, 0.56, 0.35) if jump_finger != -1 else fill, true, -1.0, true)
	draw_arc(jump_center, 61.0, 0, TAU, 80, rim, 2.0, true)
	var arrow := PackedVector2Array([jump_center+Vector2(-18,0),jump_center+Vector2(0,-18),jump_center+Vector2(18,0)])
	draw_polyline(arrow, Color(0.97,0.94,0.83,0.7), 3.0, true)
	draw_line(jump_center+Vector2(0,-16),jump_center+Vector2(0,21),Color(0.97,0.94,0.83,0.7),3.0,true)

