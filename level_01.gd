extends Node2D
## Chapter one: a complete, checkpointed jungle-temple route.
const GOLD := Color("e3bd70")
const INK := Color("101e1b")
const CREAM := Color("eee4c9")
const LEVEL_WIDTH := 6800.0
const GATE_X := 6630.0
const GATE_FLOOR := -400.0
const TERRAIN := [Rect2(0,620,1000,550), Rect2(1120,620,760,550), Rect2(2260,620,740,550), Rect2(3120,620,600,550), Rect2(4540,200,340,970), Rect2(5480,-160,270,1330), Rect2(6390,-400,410,1570)]
const LEDGES := [Rect2(570,575,180,45), Rect2(750,530,190,90), Rect2(1300,575,180,45), Rect2(1480,530,200,90), Rect2(2480,575,160,45), Rect2(2640,530,210,90), Rect2(3370,575,170,45), Rect2(3540,530,210,90), Rect2(3740,540,160,630), Rect2(3950,450,150,720), Rect2(4160,360,150,810), Rect2(4370,270,170,900), Rect2(5850,-240,180,1410), Rect2(6110,-320,200,1490)]
const RELIC_POSITIONS := [Vector2(840,476), Vector2(2740,476), Vector2(5610,-214)]
var actor: CharacterBody2D
var camera: Camera2D
var atlas: Texture2D
var backdrop: Sprite2D
var relics: Array[bool] = [false,false,false]
var checkpoint := Vector2(190,547.5)
var checkpoint_index := 0
var elapsed := 0.0
var clock_time := 0.0
var deaths := 0
var completed := false
var respawn_time := 0.0
var notice_time := 0.0
var notice := ""
var title_label: Label
var count_label: Label
var hint_label: Label
var notice_label: Label
var notice_panel: Panel
var gate_bars: Node2D
var pause_panel: Panel
var end_panel: Panel
var end_detail: Label
var fade: ColorRect
var gate: StaticBody2D
var gate_open := false
var gate_sprite: Sprite2D
var bounds_cache: Dictionary = {}
var atlas_image: Image
const CHECKPOINTS := [Vector2(1770,620),Vector2(2370,620),Vector2(4650,200),Vector2(5580,-160)]
var rng := RandomNumberGenerator.new()
var dust: Array[Vector3] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	actor = $Player
	camera = $Player/Camera2D
	camera.reparent(self)
	camera.offset = Vector2.ZERO
	camera.position = Vector2(640,360)
	camera.limit_bottom = 850
	camera.limit_top = -1040
	camera.limit_right = int(LEVEL_WIDTH)
	actor.process_mode = Node.PROCESS_MODE_PAUSABLE
	$Vine2D.process_mode = Node.PROCESS_MODE_PAUSABLE
	rng.seed = 18091987
	atlas = load("res://assets/level01/temple_atlas.png") as Texture2D
	atlas_image = atlas.get_image()
	_add_climbing_vine()
	_build_background()
	for rect in TERRAIN:
		_platform(rect)
	for rect in LEDGES:
		_platform(rect)
	_decorate()
	_build_gate()
	_build_hud()
	for i in range(65):
		dust.append(Vector3(rng.randf_range(0,LEVEL_WIDTH), rng.randf_range(180,610), rng.randf_range(0.5,1.7)))
	_ambience()
	_notify("Дневник экспедиции: три печати откроют путь в храм.", 6.0)

func _build_background() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	backdrop = Sprite2D.new()
	backdrop.texture = load("res://assets/level01/jungle_panorama.png")
	backdrop.centered = false
	backdrop.scale = Vector2.ONE * 1.08
	layer.add_child(backdrop)

func _asset(region: Rect2i, point: Vector2, height: float, depth: int = 0, tint: Color = Color.WHITE) -> Sprite2D:
	var used: Rect2i = _opaque_bounds(region)
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(region.position + used.position, used.size)
	texture.filter_clip = true
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * height / texture.get_height()
	sprite.position = point - Vector2(texture.get_width() * sprite.scale.x * 0.5, height - 6.0)
	sprite.z_index = depth
	sprite.modulate = tint
	add_child(sprite)
	return sprite

func _platform(rect: Rect2) -> void:
	var solid := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	solid.position = rect.position + rect.size * 0.5
	solid.add_child(collision)
	add_child(solid)
	var count := maxi(1, ceili(rect.size.x / 300.0))
	var width := rect.size.x / count
	for i in range(count):
		var texture := AtlasTexture.new()
		texture.atlas = atlas
		texture.region = Rect2(0,170,610,310)
		texture.filter_clip = true
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2.ONE * width / 570.0
		sprite.position = rect.position + Vector2(i*width-4, -30.0*sprite.scale.y)
		sprite.z_index = 2
		add_child(sprite)

func _opaque_bounds(region: Rect2i) -> Rect2i:
	if bounds_cache.has(region):
		return bounds_cache[region]
	var minimum := region.size
	var maximum := Vector2i.ZERO
	for y in range(region.size.y):
		for x in range(region.size.x):
			if atlas_image.get_pixel(region.position.x+x,region.position.y+y).a > 0.5:
				minimum = minimum.min(Vector2i(x,y))
				maximum = maximum.max(Vector2i(x,y))
	var result := Rect2i(minimum,maximum-minimum+Vector2i.ONE)
	bounds_cache[region] = result
	return result

func _add_climbing_vine() -> void:
	var vine := Node2D.new()
	vine.set_script(load("res://flexible_vine.gd"))
	vine.name = "AscentVine"
	vine.position = Vector2(5100,-1800)
	vine.vine_length = 2010.0
	vine.process_mode = Node.PROCESS_MODE_PAUSABLE
	for title in ["Outline","VineLine"]:
		var line := Line2D.new()
		line.name = title
		line.z_index = 2
		vine.add_child(line)
	add_child(vine)

func _decorate() -> void:
	# A shallow rear terrace supports the tent's perspective-raised back pegs.
	var camp_base := Sprite2D.new()
	var camp_texture := AtlasTexture.new()
	camp_texture.atlas = atlas
	camp_texture.region = Rect2(0,170,610,310)
	camp_base.texture = camp_texture
	camp_base.centered = false
	camp_base.position = Vector2(145,585)
	camp_base.scale = Vector2(0.46,0.16)
	camp_base.z_index = -2
	camp_base.modulate = Color(0.7,0.8,0.6)
	add_child(camp_base)
	_asset(Rect2i(520,520,550,500), Vector2(270,620), 230,-1)
	for point in [Vector2(110,620), Vector2(480,620), Vector2(1240,620), Vector2(1760,620), Vector2(2370,620), Vector2(2890,620), Vector2(3230,620), Vector2(4650,200), Vector2(5590,-160),Vector2(6500,-400)]:
		_asset(Rect2i(0,560,520,460),point,rng.randf_range(90,135),-1)
	for point in [Vector2(520,620),Vector2(1390,620),Vector2(2410,620),Vector2(3280,620),Vector2(4720,200),Vector2(6500,-400)]:
		_asset(Rect2i(640,0,310,510),point,rng.randf_range(220,320),-3,Color(0.78,0.85,0.72))
	for point in [Vector2(1580,530),Vector2(2750,530),Vector2(3650,530),Vector2(5620,-160),Vector2(6510,-400)]:
		_asset(Rect2i(1080,510,450,510),point,190,-2,Color(0.85,0.9,0.8))
	_asset(Rect2i(0,560,520,460),Vector2(30,626),190,9,Color(0.35,0.52,0.35))
	_asset(Rect2i(0,560,520,460),Vector2(1230,626),125,9,Color(0.4,0.55,0.4))
	_asset(Rect2i(0,560,520,460),Vector2(3300,626),130,9,Color(0.4,0.55,0.4))

func _build_gate() -> void:
	gate_sprite = _asset(Rect2i(1030,0,506,510),Vector2(GATE_X,GATE_FLOOR),390,3)
	gate = StaticBody2D.new()
	gate.position = Vector2(GATE_X,GATE_FLOOR-160)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(35,320)
	var col := CollisionShape2D.new()
	col.shape = shape
	gate.add_child(col)
	add_child(gate)
	gate_bars = Node2D.new()
	gate_bars.z_index = 4
	add_child(gate_bars)
	for x in range(int(GATE_X)-45,int(GATE_X)+46,18):
		var bar := Line2D.new()
		bar.points = PackedVector2Array([Vector2(x,GATE_FLOOR-270),Vector2(x,GATE_FLOOR-2)])
		bar.width = 4.0
		bar.default_color = Color("9a7b41")
		gate_bars.add_child(bar)

func _label(parent: Node, text: String, point: Vector2, size: int, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _panel(parent: Node, rect: Rect2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.72,0.59,0.35,0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	return panel

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var top := _panel(layer,Rect2(28,24,430,84),Color(0.04,0.09,0.08,0.84))
	_label(top,"ГЛАВА I  /  ЗАТЕРЯННАЯ ДОЛИНА",Vector2(20,12),13,GOLD)
	title_label = _label(top,"Храм изумрудного солнца",Vector2(20,34),24)
	var journal := _panel(layer,Rect2(1000,24,252,84),Color(0.04,0.09,0.08,0.84))
	_label(journal,"ЦЕЛЬ ЭКСПЕДИЦИИ",Vector2(18,12),13,GOLD)
	count_label = _label(journal,"Печати солнца   0 / 3",Vector2(18,39),19)
	var help := _panel(layer,Rect2(190,182,900,48),Color(0.04,0.09,0.08,0.86))
	hint_label = _label(help,"",Vector2(18,15),16)
	_label(layer,"ESC  пауза     R  к контрольной точке",Vector2(480,688),13,Color(0.9,0.88,0.77,0.65))
	notice_panel = _panel(layer,Rect2(240,122,800,48),Color(0.04,0.09,0.08,0.86))
	notice_label = _label(notice_panel,"",Vector2(18,13),16,GOLD)
	notice_label.size.x = 764
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_panel = _panel(layer,Rect2(390,260,500,190),Color(0.04,0.09,0.08,0.97))
	_label(pause_panel,"ПРИВАЛ",Vector2(185,35),30,GOLD)
	_label(pause_panel,"ESC — продолжить экспедицию",Vector2(100,108),18)
	pause_panel.hide()
	end_panel = _panel(layer,Rect2(310,190,660,330),Color(0.04,0.09,0.08,0.97))
	_label(end_panel,"ТРИ ПЕЧАТИ. ОДНА ЛЕГЕНДА.",Vector2(120,35),18,GOLD)
	_label(end_panel,"Храм открыл свои двери",Vector2(115,95),30)
	end_detail = _label(end_panel,"",Vector2(145,163),18)
	_label(end_panel,"Первый уровень пройден.   R — новая экспедиция",Vector2(100,255),17,GOLD)
	end_panel.hide()
	fade = ColorRect.new()
	fade.size = Vector2(1280,720)
	fade.color = Color(0.03,0.07,0.06,0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	var controls := Control.new()
	controls.name = "TouchControls"
	controls.set_script(load("res://touch_controls.gd"))
	controls.level = self
	layer.add_child(controls)

func _notify(text: String, duration: float = 3.0) -> void:
	notice = text
	notice_time = duration

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	clock_time += delta
	camera.position = Vector2(actor.position.x + 140,clampf(actor.position.y-155,-650,360))
	if not completed:
		elapsed += delta
	backdrop.position.x = -camera.get_screen_center_position().x * 0.12
	notice_time = maxf(0.0,notice_time-delta)
	notice_label.text = notice if notice_time > 0 else ""
	notice_panel.visible = notice_time > 0
	notice_label.modulate.a = minf(1.0,notice_time)
	count_label.text = "Печати солнца   %d / 3" % relics.count(true)
	if actor.position.x < 550:
		hint_label.text = "Слева — джойстик движения. Справа — прыжок; удерживайте для высоты"
	elif actor.position.x < 1720:
		hint_label.text = "Соберите золотые печати на террасах. Короткое нажатие — короткий прыжок."
	elif actor.position.x < 2300:
		hint_label.text = "На лиане: джойстик — раскачивание и подъём; повторный прыжок — отпустить"
	elif actor.position.x < 4400:
		hint_label.text = "Поднимайтесь по каменным блокам. Удерживайте кнопку прыжка для высоты."
	elif actor.position.x < 5480:
		hint_label.text = "Лиана ведёт наверх: джойстик вверх — подъём; вправо — раскачивание."
	else:
		hint_label.text = "Войдите в храм." if gate_open else "Ворота откроются, когда вы соберёте все три печати."
	if respawn_time > 0:
		respawn_time = maxf(0.0,respawn_time-delta)
		fade.color.a = respawn_time / 0.45
	else:
		fade.color.a = 0.0
	if not completed:
		for i in range(3):
			if not relics[i] and actor.global_position.distance_to(RELIC_POSITIONS[i] + Vector2(0,30)) < 85:
				relics[i] = true
				_tone(660.0 + i * 110)
				_notify("Печать найдена — %d из 3" % relics.count(true))
		for i in range(CHECKPOINTS.size()):
			var point: Vector2 = CHECKPOINTS[i]
			if checkpoint_index < i+1 and absf(actor.position.x-point.x)<80 and absf(actor.position.y+72.5-point.y)<8 and actor.is_on_floor():
				_set_checkpoint(point-Vector2(0,72.5),i+1)
		if actor.position.y > 1030:
			_respawn()
		if relics.count(true) == 3 and not gate_open:
			gate_open = true
			gate.queue_free()
			gate_bars.hide()
			_notify("Солнечные печати пробудили храм. Ворота открыты.",5.0)
		if gate_open and actor.position.x > GATE_X-30:
			_complete()
	queue_redraw()

func _set_checkpoint(point: Vector2, index: int) -> void:
	checkpoint = point
	checkpoint_index = index
	_notify("Контрольная точка сохранена")
	_tone(440)

func _respawn() -> void:
	if completed:
		return
	deaths += 1
	if actor.state == 2 or actor.state == 3:
		actor._detach_from_vine(Vector2.ZERO)
	actor.position = checkpoint
	actor.velocity = Vector2.ZERO
	actor.state = 0
	actor.jump_armed = false
	actor.preparing_jump = false
	actor.jump_preparation = 0.0
	actor.jump_cut_allowed = false
	actor.preparation_elapsed = 0.0
	actor.jump_buffer_timer = 0.0
	actor.coyote_timer = 0.0
	actor.landing_strength = 0.0
	actor.landing_compression = 0.0
	actor.cooldown_timer = 0.3
	actor.reset_physics_interpolation()
	camera.reset_smoothing()
	respawn_time = 0.45
	_notify("Возвращение к последнему лагерю. Найденные печати сохранены.")

func _complete() -> void:
	completed = true
	actor.velocity = Vector2.ZERO
	actor.set_physics_process(false)
	actor.get_node("HeroRig").set_process(false)
	end_detail.text = "Все печати найдены  •  %02d:%02d  •  Возвращений: %d" % [int(elapsed)/60,int(elapsed)%60,deaths]
	end_panel.show()
	_tone(880)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not completed:
			get_tree().paused = not get_tree().paused
			pause_panel.visible = get_tree().paused
		if event.keycode == KEY_R or event.physical_keycode == KEY_R:
			if completed:
				get_tree().paused = false
				get_tree().reload_current_scene()
			elif not get_tree().paused:
				_respawn()

func _draw() -> void:
	for rect in TERRAIN + LEDGES:
		draw_rect(Rect2(rect.position + Vector2(0,60), Vector2(rect.size.x,maxf(rect.size.y-60,0))),Color("253b2c"))
		if rect.position.y < 400 and rect.size.y > 200:
			var block_height: float = rect.size.x / 5.0
			for block in range(ceili((rect.size.y-60.0)/block_height)):
				var target := Rect2(rect.position+Vector2(0,60+block*block_height),Vector2(rect.size.x,block_height+1))
				draw_texture_rect_region(atlas,target,Rect2(40,245,500,100),Color(0.52,0.62,0.47))
		for row in range(5):
			var y: float = rect.position.y + 135 + row * 70
			draw_line(Vector2(rect.position.x,y),Vector2(rect.end.x,y+7),Color(0.1,0.17,0.12,0.35),2)
	for x in [1060,2070,3060]:
		for j in range(10):
			var px: float = x - 60 + j*13
			draw_colored_polygon(PackedVector2Array([Vector2(px,970),Vector2(px+6,925),Vector2(px+12,970)]),Color("334a3b"))
	for i in range(3):
		if relics[i]:
			continue
		var p: Vector2 = RELIC_POSITIONS[i] + Vector2(0,sin(clock_time*2.0+i)*5)
		for ring in range(10,0,-1):
			draw_circle(p,float(ring)*4.0,Color(1.0,0.72,0.25,0.012))
		var points := PackedVector2Array()
		for k in range(16):
			var angle := k*TAU/16.0 + clock_time*0.12
			points.append(p+Vector2.from_angle(angle)*(19.0 if k%2==0 else 12.0))
		draw_colored_polygon(points,GOLD)
		draw_circle(p,9,Color("775a2e"))
		draw_arc(p,6,0,TAU,24,Color("f7dfa3"),2,true)
	for i in range(CHECKPOINTS.size()):
		var point: Vector2 = CHECKPOINTS[i]
		draw_line(point,point-Vector2(0,70),Color("5d5136"),5)
		draw_rect(Rect2(point-Vector2(9,76),Vector2(18,23)),Color("b3995d"),false,2)
		draw_circle(point-Vector2(0,65),5,GOLD if checkpoint_index>=i+1 else Color("7b8b60"))
	if gate_open:
		for i in range(12,0,-1):
			draw_circle(Vector2(GATE_X,GATE_FLOOR-150),i*10,Color(0.92,0.72,0.32,0.012))
	else:
		for x in range(int(GATE_X)-45,int(GATE_X)+46,18):
			draw_line(Vector2(x,GATE_FLOOR-275),Vector2(x,GATE_FLOOR),Color("7b683d"),5,true)
	for d in dust:
		var p := Vector2(fposmod(d.x+clock_time*7*d.z,LEVEL_WIDTH),d.y+sin(clock_time*0.5+d.x)*10)
		draw_circle(p,d.z,Color(0.95,0.87,0.55,0.18))

func _tone(frequency: float) -> void:
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(8820*2)
	for i in range(8820):
		var t := float(i)/22050.0
		var value := sin(TAU*frequency*t)*exp(-t*10.0)*minf(t*100,1)*0.22
		data.encode_s16(i*2,int(value*32767))
	sample.data = data
	var player := AudioStreamPlayer.new()
	player.stream = sample
	player.volume_db = -12
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _ambience() -> void:
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = 22050
	sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sample.loop_end = 22050*6
	var data := PackedByteArray()
	data.resize(sample.loop_end*2)
	var wind := 0.0
	for i in range(sample.loop_end):
		var t := float(i)/22050.0
		wind = lerpf(wind,rng.randf_range(-1,1),0.015)
		var chirp := 0.0
		var bird_t := fposmod(t,3.0)
		if bird_t > 1.0 and bird_t < 1.4:
			chirp = sin(TAU*(1300*t+100*sin(t*9)))*pow(sin((bird_t-1.0)/0.4*PI),2)*0.05
		data.encode_s16(i*2,int(clampf(wind*0.35+chirp,-1,1)*32767))
	sample.data = data
	var player := AudioStreamPlayer.new()
	player.stream = sample
	player.volume_db = -20
	add_child(player)
	player.play()

