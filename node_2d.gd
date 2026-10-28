extends CharacterBody2D

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

func _physics_process(delta: float) -> void:
	# Добавляем гравитацию, чтобы персонаж падал вниз
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Прыжок по нажатию клавиши пробела (пока для теста на компьютере)
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Получаем направление движения (стрелки влево / вправо на клавиатуре)
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	# Применяем движение к персонажу
	move_and_slide()
