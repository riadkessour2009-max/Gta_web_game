extends Node2D

# ==============================================================================
# HARBOR SHADOWS (GODOT 4) - قيادة + تيربو + إطلاق نار ودفاع + قصة وفصول
# ==============================================================================

enum GameState { INTRO, PLAYING, CHAPTER_CLEAR, GAME_OVER, VICTORY }

@export var move_speed: float = 370.0
@export var boost_multiplier: float = 1.65
@export var turn_rate: float = 4.0
@export var max_health: float = 100.0
@export var fire_cooldown: float = 0.24

var chapters: Array[Dictionary] = [
	{
		"title": "الفصل 1: شحنة الميناء",
		"story": "انقل الشحنة بين النقاط الذهبية وتصدَّ لأول دورية تحاول اعتراض طريقك.",
		"checkpoints": 3,
		"patrols": 2,
		"patrol_speed": 205.0,
		"reward": 1000
	},
	{
		"title": "الفصل 2: كمين الحاويات",
		"story": "الدوريات أصبحت أسرع. استخدم التيربو ووجّه نيرانك لإبعاد المطاردين.",
		"checkpoints": 4,
		"patrols": 3,
		"patrol_speed": 245.0,
		"reward": 1800
	},
	{
		"title": "الفصل 3: مطاردة الليل",
		"story": "الطرقات مشددة والضغط مرتفع. اجمع النقاط وحافظ على درع مركبتك.",
		"checkpoints": 5,
		"patrols": 4,
		"patrol_speed": 285.0,
		"reward": 2800
	},
	{
		"title": "الفصل 4: الجسر الأخير",
		"story": "الخطوة الأخيرة لتأمين الشحنة كاملة وإنهاء المهمة بنجاح.",
		"checkpoints": 6,
		"patrols": 5,
		"patrol_speed": 320.0,
		"reward": 4500
	}
]

var state: GameState = GameState.INTRO
var chapter_idx: int = 0
var checkpoints_done: int = 0
var checkpoints_target: int = 3
var cash: int = 1000
var health: float = 100.0
var boost: float = 100.0
var is_boosting: bool = false
var shoot_timer: float = 0.0

var player_pos: Vector2 = Vector2(640, 360)
var player_vel: Vector2 = Vector2.ZERO
var player_angle: float = 0.0
var target_pos: Vector2 = Vector2(960, 220)
var shake: float = 0.0

var banner_text: String = ""
var banner_timer: float = 0.0

var buildings: Array[Rect2] = []
var patrols: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var sparks: Array[Dictionary] = []

# تحكم اللمس (هاتف)
var active_touches: Dictionary = {}
var touch_dir: Vector2 = Vector2.ZERO
var touch_boost: bool = false
var touch_fire: bool = false

var btn_up: Rect2
var btn_down: Rect2
var btn_left: Rect2
var btn_right: Rect2
var btn_boost: Rect2
var btn_fire: Rect2
var modal_btn: Rect2

func _ready() -> void:
	randomize()
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	_build_map()
	_layout_ui()
	_start_chapter(0, false)
	state = GameState.INTRO

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_layout_ui()

func _layout_ui() -> void:
	var vp = get_viewport_rect().size
	var s = clamp(min(vp.x, vp.y) * 0.125, 50.0, 72.0)
	var pad = 16.0
	var by = vp.y - s - pad

	btn_left = Rect2(pad, by, s, s)
	btn_down = Rect2(pad + s + 8.0, by, s, s)
	btn_right = Rect2(pad + (s + 8.0) * 2.0, by, s, s)
	btn_up = Rect2(pad + s + 8.0, by - s - 8.0, s, s)

	btn_fire = Rect2(vp.x - pad - s * 1.3, by - s - 8.0, s * 1.3, s)
	btn_boost = Rect2(vp.x - pad - s * 1.3, by, s * 1.3, s)
	modal_btn = Rect2(vp.x * 0.5 - 155.0, vp.y * 0.64, 310.0, 50.0)

func _build_map() -> void:
	buildings.clear()
	var vp = get_viewport_rect().size
	var w = max(vp.x, 1280.0)
	var h = max(vp.y, 720.0)

	buildings.append(Rect2(w * 0.15, h * 0.16, w * 0.15, h * 0.16))
	buildings.append(Rect2(w * 0.42, h * 0.15, w * 0.16, h * 0.15))
	buildings.append(Rect2(w * 0.71, h * 0.17, w * 0.15, h * 0.17))
	buildings.append(Rect2(w * 0.16, h * 0.62, w * 0.15, h * 0.16))
	buildings.append(Rect2(w * 0.43, h * 0.63, w * 0.16, h * 0.16))
	buildings.append(Rect2(w * 0.70, h * 0.61, w * 0.15, h * 0.17))

func _start_chapter(idx: int, play_now: bool = true) -> void:
	chapter_idx = clamp(idx, 0, chapters.size() - 1)
	var ch = chapters[chapter_idx]
	checkpoints_done = 0
	checkpoints_target = ch["checkpoints"]
	health = max_health
	boost = 100.0
	player_vel = Vector2.ZERO
	bullets.clear()

	var vp = get_viewport_rect().size
	player_pos = Vector2(vp.x * 0.5, vp.y * 0.5)
	player_angle = 0.0

	_pick_target()
	_spawn_patrols(ch["patrols"], ch["patrol_speed"])

	if play_now:
		state = GameState.PLAYING
		_notify(ch["title"] + " — " + ch["story"], 4.5)

func _pick_target() -> void:
	var vp = get_viewport_rect().size
	for _i in range(30):
		var p = Vector2(
			randf_range(85.0, max(180.0, vp.x - 85.0)),
			randf_range(105.0, max(200.0, vp.y - 110.0))
		)
		if not _hit_building(p, 38.0) and p.distance_to(player_pos) > 160.0:
			target_pos = p
			return
	target_pos = Vector2(vp.x * 0.78, vp.y * 0.28)

func _spawn_patrols(count: int, spd: float) -> void:
	patrols.clear()
	var vp = get_viewport_rect().size
	var spawns: Array[Vector2] = [
		Vector2(80, 95),
		Vector2(vp.x - 80, 95),
		Vector2(80, vp.y - 110),
		Vector2(vp.x - 80, vp.y - 110),
		Vector2(vp.x * 0.5, 90)
	]
	for i in range(count):
		patrols.append({
			"pos": spawns[i % spawns.size()],
			"angle": 0.0,
			"speed": spd + randf_range(-15.0, 20.0),
			"hp": 60.0
		})

func _notify(msg: String, dur: float = 2.5) -> void:
	banner_text = msg
	banner_timer = dur

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER:
			_on_modal_action()
		elif event.keycode == KEY_R:
			_restart_all()

	if event is InputEventScreenTouch:
		if event.pressed:
			active_touches[event.index] = event.position
			if state != GameState.PLAYING and modal_btn.has_point(event.position):
				_on_modal_action()
		else:
			active_touches.erase(event.index)
		_update_touch_state()
	elif event is InputEventScreenDrag:
		active_touches[event.index] = event.position
		_update_touch_state()

func _update_touch_state() -> void:
	var x_val: float = 0.0
	var y_val: float = 0.0
	var b_val: bool = false
	var f_val: bool = false

	for idx in active_touches.keys():
		var pos: Vector2 = active_touches[idx]
		if btn_left.has_point(pos): x_val -= 1.0
		if btn_right.has_point(pos): x_val += 1.0
		if btn_up.has_point(pos): y_val -= 1.0
		if btn_down.has_point(pos): y_val += 1.0
		if btn_boost.has_point(pos): b_val = true
		if btn_fire.has_point(pos): f_val = true

	touch_dir = Vector2(clamp(x_val, -1.0, 1.0), clamp(y_val, -1.0, 1.0))
	touch_boost = b_val
	touch_fire = f_val

func _on_modal_action() -> void:
	match state:
		GameState.INTRO:
			state = GameState.PLAYING
			_notify(chapters[chapter_idx]["title"] + " — ابدأ المهمة!", 3.0)
		GameState.CHAPTER_CLEAR:
			if chapter_idx + 1 < chapters.size():
				_start_chapter(chapter_idx + 1, true)
			else:
				state = GameState.VICTORY
		GameState.GAME_OVER:
			_start_chapter(chapter_idx, true)
		GameState.VICTORY:
			_restart_all()

func _restart_all() -> void:
	cash = 1000
	_start_chapter(0, true)

func _process(delta: float) -> void:
	if banner_timer > 0.0:
		banner_timer = max(0.0, banner_timer - delta)
	if shake > 0.0:
		shake = max(0.0, shake - delta * 26.0)
	if shoot_timer > 0.0:
		shoot_timer = max(0.0, shoot_timer - delta)

	_step_sparks(delta)

	if state != GameState.PLAYING:
		queue_redraw()
		return

	_step_player(delta)
	_step_shooting()
	_step_bullets(delta)
	_step_checkpoints()
	_step_patrols(delta)

	queue_redraw()

func _step_player(delta: float) -> void:
	var ix = Input.get_axis("ui_left", "ui_right")
	var iy = Input.get_axis("ui_up", "ui_down")
	if abs(ix) < 0.05: ix = touch_dir.x
	if abs(iy) < 0.05: iy = touch_dir.y

	var wants_boost = touch_boost or Input.is_key_pressed(KEY_SHIFT)
	var moving = abs(ix) > 0.05 or abs(iy) > 0.05

	if wants_boost and boost > 5.0 and moving:
		is_boosting = true
		boost = max(0.0, boost - 35.0 * delta)
	else:
		is_boosting = false
		boost = min(100.0, boost + 18.0 * delta)

	var spd = move_speed * (boost_multiplier if is_boosting else 1.0)
	var dir = Vector2(ix, iy)
	if dir.length() > 0.05:
		dir = dir.normalized()
		player_angle = lerp_angle(player_angle, dir.angle(), turn_rate * delta)
		player_vel = player_vel.lerp(dir * spd, 8.5 * delta)
		if is_boosting:
			_add_spark(player_pos - Vector2.RIGHT.rotated(player_angle) * 20.0, Color(0.22, 0.74, 0.97, 0.8), 5.0)
	else:
		player_vel = player_vel.lerp(Vector2.ZERO, 7.0 * delta)

	var vp = get_viewport_rect().size
	var next_pos = player_pos + player_vel * delta
	next_pos.x = clamp(next_pos.x, 24.0, vp.x - 24.0)
	next_pos.y = clamp(next_pos.y, 70.0, vp.y - 24.0)

	if not _hit_building(next_pos, 18.0):
		player_pos = next_pos
	else:
		if player_vel.length() > 150.0:
			health = max(0.0, health - 7.0)
			shake = 5.5
		player_vel = -player_vel * 0.35

func _step_shooting() -> void:
	var wants_fire = touch_fire or Input.is_key_pressed(KEY_SPACE)
	if wants_fire and shoot_timer <= 0.0:
		shoot_timer = fire_cooldown
		var muzzle = player_pos + Vector2.RIGHT.rotated(player_angle) * 24.0
		bullets.append({
			"pos": muzzle,
			"vel": Vector2.RIGHT.rotated(player_angle) * 680.0,
			"life": 1.1
		})

func _step_bullets(delta: float) -> void:
	var vp = get_viewport_rect().size
	for i in range(bullets.size() - 1, -1, -1):
		bullets[i]["pos"] += bullets[i]["vel"] * delta
		bullets[i]["life"] -= delta
		var bpos: Vector2 = bullets[i]["pos"]

		var hit = false
		if bullets[i]["life"] <= 0.0 or bpos.x < 0 or bpos.x > vp.x or bpos.y < 0 or bpos.y > vp.y or _hit_building(bpos, 4.0):
			hit = true
		else:
			for p_idx in range(patrols.size() - 1, -1, -1):
				if bpos.distance_to(patrols[p_idx]["pos"]) < 24.0:
					patrols[p_idx]["hp"] -= 25.0
					_add_spark(bpos, Color(1.0, 0.5, 0.1, 0.95), 6.0)
					hit = true
					if patrols[p_idx]["hp"] <= 0.0:
						cash += 150
						_add_spark(patrols[p_idx]["pos"], Color(0.98, 0.8, 0.08, 0.95), 16.0)
						_notify("تم تحييد دورية! +$150", 1.8)
						patrols.remove_at(p_idx)
					break

		if hit:
			bullets.remove_at(i)

func _step_checkpoints() -> void:
	if player_pos.distance_to(target_pos) <= 36.0:
		checkpoints_done += 1
		cash += 250
		health = min(max_health, health + 10.0)
		_add_spark(target_pos, Color(0.98, 0.8, 0.08, 0.9), 14.0)

		if checkpoints_done >= checkpoints_target:
			var bonus: int = chapters[chapter_idx]["reward"]
			cash += bonus
			if chapter_idx + 1 < chapters.size():
				state = GameState.CHAPTER_CLEAR
				_notify("أنهيت الفصل! مكافأة +$" + str(bonus), 4.0)
			else:
				state = GameState.VICTORY
		else:
			_pick_target()
			_notify("نقطة مستلمة (" + str(checkpoints_done) + "/" + str(checkpoints_target) + ")", 1.8)

func _step_patrols(delta: float) -> void:
	for p in patrols:
		var delta_v = player_pos - p["pos"]
		var dist = delta_v.length()
		if dist > 1.0:
			p["angle"] = lerp_angle(p["angle"], delta_v.angle(), 4.5 * delta)

		var step = Vector2.RIGHT.rotated(p["angle"]) * p["speed"] * delta
		if not _hit_building(p["pos"] + step, 18.0):
			p["pos"] += step
		else:
			var a = Vector2.RIGHT.rotated(p["angle"] + PI * 0.5) * p["speed"] * delta
			var b = Vector2.RIGHT.rotated(p["angle"] - PI * 0.5) * p["speed"] * delta
			if not _hit_building(p["pos"] + a, 18.0):
				p["pos"] += a
			elif not _hit_building(p["pos"] + b, 18.0):
				p["pos"] += b

		if dist < 32.0:
			var factor = 0.45 if is_boosting else 1.0
			health = max(0.0, health - 22.0 * factor * delta)
			shake = max(shake, 3.5)

	if health <= 0.0:
		cash = max(0, cash - 250)
		state = GameState.GAME_OVER

func _hit_building(pt: Vector2, pad: float) -> bool:
	for rect in buildings:
		if rect.grow(pad).has_point(pt):
			return true
	return false

func _add_spark(pos: Vector2, col: Color, rad: float) -> void:
	if sparks.size() > 70:
		sparks.pop_front()
	sparks.append({"pos": pos, "color": col, "rad": rad, "life": 0.4, "max_life": 0.4})

func _step_sparks(delta: float) -> void:
	for i in range(sparks.size() - 1, -1, -1):
		sparks[i]["life"] -= delta
		sparks[i]["rad"] *= 0.93
		if sparks[i]["life"] <= 0.0:
			sparks.remove_at(i)

func _draw() -> void:
	var vp = get_viewport_rect().size
	var cam_off = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	draw_set_transform(cam_off, 0.0, Vector2.ONE)

	# الطرقات والأرضية
	draw_rect(Rect2(Vector2.ZERO, vp), Color("#0f172a"))
	for x in range(0, int(vp.x) + 160, 160):
		draw_line(Vector2(x, 0), Vector2(x, vp.y), Color(0.2, 0.27, 0.36, 0.45), 2.0)
	for y in range(0, int(vp.y) + 160, 160):
		draw_line(Vector2(0, y), Vector2(vp.x, y), Color(0.2, 0.27, 0.36, 0.45), 2.0)

	# المباني
	for rect in buildings:
		draw_rect(Rect2(rect.position + Vector2(5, 6), rect.size), Color(0, 0, 0, 0.4))
		draw_rect(rect, Color("#1e293b"))
		draw_rect(rect, Color("#475569"), false, 2.0)

	# النقاط والشرر والطلقات
	var pulse = 22.0 + sin(Time.get_ticks_msec() * 0.008) * 4.0
	draw_arc(target_pos, pulse, 0.0, TAU, 32, Color("#facc15"), 3.0)
	draw_circle(target_pos, 6.0, Color("#fef08a"))

	for b in bullets:
		draw_circle(b["pos"], 4.5, Color("#fb923c"))

	for s in sparks:
		var c: Color = s["color"]
		c.a *= clamp(s["life"] / s["max_life"], 0.0, 1.0)
		draw_circle(s["pos"], s["rad"], c)

	# الدوريات واللاعب
	var siren = int(Time.get_ticks_msec() / 160) % 2 == 0
	for p in patrols:
		_draw_car(p["pos"], p["angle"], Color("#f1f5f9"), true, siren)

	_draw_car(player_pos, player_angle, Color("#ef4444") if not is_boosting else Color("#38bdf8"), false, false)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud(vp)
	_draw_touch_pads()

	if state != GameState.PLAYING:
		_draw_overlay(vp)

func _draw_car(pos: Vector2, ang: float, col: Color, is_patrol: bool, siren: bool) -> void:
	draw_set_transform(pos, ang, Vector2.ONE)
	draw_rect(Rect2(-22, -12, 44, 24), col)
	draw_rect(Rect2(-8, -9, 18, 18), Color("#090d16"))
	draw_rect(Rect2(16, -9, 5, 6), Color("#fef9c3"))
	draw_rect(Rect2(16, 3, 5, 6), Color("#fef9c3"))
	if is_patrol:
		draw_rect(Rect2(-4, -6, 8, 12), Color("#ef4444") if siren else Color("#38bdf8"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_hud(vp: Vector2) -> void:
	draw_rect(Rect2(12, 10, vp.x - 24, 46), Color(0.04, 0.07, 0.13, 0.8))
	var line = "%s  |  النقاط: %d/%d  |  المال: $%d" % [chapters[chapter_idx]["title"], checkpoints_done, checkpoints_target, cash]
	draw_string(ThemeDB.fallback_font, Vector2(22, 38), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#f8fafc"))

	var bx = vp.x - 184.0
	draw_rect(Rect2(bx, 16, 160, 10), Color("#1e293b"))
	draw_rect(Rect2(bx, 16, 160.0 * (health / max_health), 10), Color("#22c55e") if health > 40.0 else Color("#ef4444"))
	draw_rect(Rect2(bx, 32, 160, 8), Color("#1e293b"))
	draw_rect(Rect2(bx, 32, 160.0 * (boost / 100.0), 8), Color("#38bdf8"))

	if banner_timer > 0.0 and banner_text != "":
		var bw = min(vp.x - 40.0, 640.0)
		var rx = (vp.x - bw) * 0.5
		draw_rect(Rect2(rx, 64, bw, 32), Color(0.06, 0.1, 0.18, 0.88))
		draw_string(ThemeDB.fallback_font, Vector2(rx + 12, 85), banner_text, HORIZONTAL_ALIGNMENT_CENTER, int(bw - 24), 14, Color("#fde047"))

func _draw_touch_pads() -> void:
	var bg = Color(0.08, 0.12, 0.2, 0.58)
	var bd = Color(0.95, 0.97, 1.0, 0.35)
	for r in [btn_left, btn_down, btn_right, btn_up, btn_boost, btn_fire]:
		draw_rect(r, bg)
		draw_rect(r, bd, false, 2.0)

	draw_string(ThemeDB.fallback_font, btn_left.position + Vector2(18, 35), "◀", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(ThemeDB.fallback_font, btn_right.position + Vector2(18, 35), "▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(ThemeDB.fallback_font, btn_up.position + Vector2(18, 35), "▲", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(ThemeDB.fallback_font, btn_down.position + Vector2(18, 35), "▼", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_string(ThemeDB.fallback_font, btn_fire.position + Vector2(14, 34), "نار", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#fdba74"))
	draw_string(ThemeDB.fallback_font, btn_boost.position + Vector2(12, 34), "تيربو", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#7dd3fc"))

func _draw_overlay(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.04, 0.08, 0.84))
	var w = min(vp.x - 48.0, 640.0)
	var h = 230.0
	var pos = Vector2((vp.x - w) * 0.5, (vp.y - h) * 0.5)
	draw_rect(Rect2(pos, Vector2(w, h)), Color("#0f172a"))
	draw_rect(Rect2(pos, Vector2(w, h)), Color("#facc15"), false, 2.5)

	var title = "ظلال الميناء"
	var body = chapters[chapter_idx]["story"]
	var cta = "اضغط هنا أو Enter للبدء"

	if state == GameState.CHAPTER_CLEAR:
		title = "تم إتمام الفصل " + str(chapter_idx + 1)
		body = "الرصيد الحالي: $" + str(cash)
		cta = "اضغط للانتقال إلى الفصل التالي"
	elif state == GameState.GAME_OVER:
		title = "تعطلت المركبة!"
		body = "أعد محاولة الفصل الحالي."
		cta = "اضغط لإعادة المحاولة"
	elif state == GameState.VICTORY:
		title = "أنهيت القصة بنجاح!"
		body = "الرصيد النهائي: $" + str(cash)
		cta = "اضغط لبدء قصة جديدة"

	draw_string(ThemeDB.fallback_font, pos + Vector2(24, 44), title, HORIZONTAL_ALIGNMENT_LEFT, int(w - 48), 20, Color("#facc15"))
	draw_string(ThemeDB.fallback_font, pos + Vector2(24, 88), body, HORIZONTAL_ALIGNMENT_LEFT, int(w - 48), 15, Color("#e2e8f0"))
	draw_rect(modal_btn, Color("#facc15"))
	draw_string(ThemeDB.fallback_font, modal_btn.position + Vector2(10, 32), cta, HORIZONTAL_ALIGNMENT_CENTER, int(modal_btn.size.x - 20), 15, Color("#0f172a"))
