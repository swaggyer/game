extends SceneTree
## UI-only regression: stable HUD resources, immediate attack, independent
## fingers, cancellation, menu release-to-confirm, and event-driven redraw.
var ui
var checks = 0
var failures: Array[String] = []
var attacks = 0
var context_down = 0
var context_up = 0
var context_cancel = 0
var theme_changes = 0
var joystick_draws = 0
var callbacks = 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL: " + message)

func frames(count: int = 3) -> void:
	for i in range(count): await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	var mobile = "--mobile" in OS.get_cmdline_user_args()
	if mobile:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.content_scale_size = Vector2i(1280, 720)
		root.size = Vector2i(2640, 1216)
	ui = load("res://scripts/mobile_ui.gd").new()
	root.add_child(ui)
	ui.setup(load("res://scripts/campaign.gd").new())
	ui.attack_pressed.connect(func(): attacks += 1)
	ui.context_pressed.connect(func(): context_down += 1)
	ui.context_released.connect(func(): context_up += 1)
	ui.context_cancelled.connect(func(): context_cancel += 1)
	ui.joystick.draw.connect(func(): joystick_draws += 1)
	ui.show_hud(); paused = false
	_hud(); await frames()
	_test_stable_hud()
	await _test_idle_redraw()
	await _test_multitouch()
	await _test_mouse_attack()
	if mobile: await _test_mobile_layout()
	await _test_modal_confirmation()
	paused = false; ui.queue_free(); await frames()
	if failures.is_empty(): print("MOBILE UI PERFORMANCE V1.3.1 PASSED: %d checks" % checks)
	else: printerr("MOBILE UI PERFORMANCE V1.3.1 FAILED: %d / %d" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _hud() -> void:
	ui.update_hud(110, 110, "区域探索0/3", "自由选择路线", "微光", 0, "序章 · 院子里的小流星")

func _test_stable_hud() -> void:
	var ids: Array[int] = []
	for portrait in ui.portraits:
		ids.append(portrait.get_theme_stylebox("normal").get_instance_id())
		portrait.theme_changed.connect(func(): theme_changes += 1)
	var start = Time.get_ticks_usec()
	for i in range(2000): _hud()
	var duration = Time.get_ticks_usec() - start
	var after: Array[int] = []
	for portrait in ui.portraits: after.append(portrait.get_theme_stylebox("normal").get_instance_id())
	print("HUD_2000_CALLS_US ", duration, " PORTRAIT_THEME_CHANGES ", theme_changes, " STYLES_STABLE ", ids == after)
	check(ids == after and theme_changes == 0, "unchanged HUD never reallocates portrait styles or invalidates themes")
	ui.campaign.active_character = 1; _hud()
	check(ui.attack_button.text == "星矢\n攻击" and ui.portraits[1].get_theme_stylebox("normal").border_color == ui.GOLD, "character switch updates the existing attack label and selected portrait")
	ui.update_hud(82, 110, "区域探索1/3", "新目标", "水罩", 2.35, "第一章")
	check(ui.hp_bar.value == 82 and "82 / 110" in ui.hp_label.text and ui.goal_label.text == "区域探索1/3" and ui.detail_label.text == "新目标", "changed health and objectives still update immediately")
	check(ui.context_button.text == "2.4s\n水罩", "cooldown text retains its tenth-second presentation")
	ui.campaign.active_character = 0; _hud()

func _test_idle_redraw() -> void:
	await frames()
	joystick_draws = 0; await frames(5)
	print("IDLE_JOYSTICK_DRAWS ", joystick_draws)
	check(joystick_draws == 0, "stationary joystick retains its draw list across frames")
	var original_size: Vector2 = ui.root.size
	ui.root.size = Vector2(1320, 760); await frames()
	check(ui.stick_origin.y == 618, "viewport resize repositions the idle joystick without a polling redraw")
	ui.root.size = original_size; await frames()
	check(ui.stick_origin.y == 578, "returning to landscape size restores the same joystick appearance")

func _test_multitouch() -> void:
	var stick = Vector2(142, 578)
	var attack = ui.attack_button.get_global_rect().get_center()
	var context = ui.context_button.get_global_rect().get_center()
	_event_touch(0, stick, true)
	_event_drag(0, stick + Vector2(42, 0))
	check(ui.stick_id == 0 and ui.direction.x > .8, "first finger moves the joystick")
	_event_touch(1, attack, true)
	print("ATTACKS_BEFORE_RELEASE ", attacks)
	check(attacks == 1, "attack begins on touch down without waiting for finger release")
	_event_drag(0, stick + Vector2(0, -42))
	check(ui.stick_id == 0 and ui.direction.y < -.8, "movement remains independent while attack is held")
	_event_touch(1, attack, false)
	check(attacks == 1, "attack release never generates a duplicate attack")
	_event_touch(2, context, true)
	check(context_down == 1 and ui.stick_id == 0, "third finger presses context without stealing joystick capture")
	_event_touch(2, context + Vector2(200, -150), false, true)
	check(context_up == 0 and context_cancel == 1 and ui.stick_id == 0, "canceled context touch cancels rather than commits its interaction, preserving joystick")
	_event_touch(1, attack, true); _event_touch(1, attack + Vector2(100, 0), false, true)
	check(attacks == 2, "canceled attack touch cannot undo its immediate action or fire twice")
	_event_touch(0, stick, false)
	check(ui.stick_id == -1 and ui.direction == Vector2.ZERO, "movement stops when its own finger releases")
	_event_touch(2, context, true)
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(context_up == 0 and context_cancel == 2 and ui.touch_buttons.is_empty(), "focus loss cancels held context exactly once")
	_event_touch(2, context, false)
	check(context_up == 0 and context_cancel == 2, "late release after focus cancellation cannot repeat context release")
	_event_touch(2, context, true)
	ui.show_pause()
	check(context_up == 0 and context_cancel == 3 and ui.touch_buttons.is_empty(), "opening a modal cancels held gameplay controls")
	ui.hide_pause(); paused = false
	_event_touch(2, context, false)
	check(context_up == 0 and context_cancel == 3, "late release from a canceled modal transition cannot fire a second release")
	_event_touch(2, context, true); _event_touch(2, context, false)
	check(context_up == 1 and context_cancel == 3, "normal context release still commits exactly one interaction")
	# Native event path, rather than direct dispatch, for simultaneous contacts.
	var before = attacks
	_parse_touch(0, stick, true); _parse_touch(1, attack, true)
	await frames(1)
	check(attacks == before + 1 and ui.stick_id == 0, "engine ScreenTouch events produce immediate attack with independent movement")
	_parse_touch(1, attack, false); _parse_touch(0, stick, false)
	await frames(1)
	check(attacks == before + 1 and ui.stick_id == -1, "engine touch releases keep action count stable")

func _test_mouse_attack() -> void:
	var before = attacks
	var point = _window_point(ui.attack_button.get_global_rect().get_center())
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.global_position = point; event.pressed = true
	Input.parse_input_event(event); await frames(1)
	check(attacks == before + 1, "native mouse attack starts on button down as well")
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.global_position = point; event.pressed = false
	Input.parse_input_event(event); await frames(1)
	check(attacks == before + 1, "native mouse release cannot duplicate an attack")

func _test_modal_confirmation() -> void:
	ui.show_dialog("剧情", "仍然可以跳过这段故事。", "继续", func(): callbacks += 1, "intro_0")
	await frames()
	var skip: Button = ui.dialog_screen.find_child("SkipStory", true, false)
	var point = skip.get_global_rect().get_center()
	_event_touch(3, point, true)
	check(callbacks == 0 and ui.dialog_screen.visible, "story skip remains release-to-confirm")
	_event_touch(3, point, false)
	check(callbacks == 1 and not ui.dialog_screen.visible and not paused, "story skip still closes and invokes its callback once")

func _test_mobile_layout() -> void:
	await frames()
	print("MOBILE_WINDOW ", root.size, " LOGICAL_UI ", ui.root.size, " STRETCH ", root.get_stretch_transform())
	check(root.size == Vector2i(2640, 1216) and ui.root.size.x > 1500 and is_equal_approx(ui.root.size.y, 720), "2640x1216 viewport mode expands the logical UI width while retaining720px height")
	var bounds = Rect2(Vector2.ZERO, ui.root.size)
	check(bounds.encloses(ui.attack_button.get_global_rect()) and bounds.encloses(ui.context_button.get_global_rect()), "both action hit rectangles remain inside the expanded mobile viewport")
	var before = attacks
	_parse_touch(0, Vector2(142, 578), true)
	var drag = InputEventScreenDrag.new(); drag.index = 0; drag.position = _window_point(Vector2(180, 578))
	Input.parse_input_event(drag)
	_parse_touch(1, ui.attack_button.get_global_rect().get_center(), true)
	await frames(2)
	check(ui.stick_id == 0 and ui.direction.x > .7 and attacks == before + 1, "expanded viewport engine touch coordinates hit joystick and attack simultaneously")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path = "user://mobile-ui-2640x1216.png"
		var shot = root.get_texture().get_image()
		shot.resize(root.size.x, root.size.y, Image.INTERPOLATE_BILINEAR)
		check(shot.save_png(path) == OK, "native mobile aspect proof saved at its presented window resolution")
		print("MOBILE_UI_PROOF ", ProjectSettings.globalize_path(path))
	_parse_touch(1, ui.attack_button.get_global_rect().get_center(), false)
	_parse_touch(0, Vector2(180, 578), false); await frames(1)
	check(ui.stick_id == -1 and attacks == before + 1, "expanded viewport releases stop movement without a second attack")

func _event_touch(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index; event.position = point; event.pressed = pressed; event.canceled = canceled
	ui._input(event)

func _parse_touch(index: int, point: Vector2, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index; event.position = _window_point(point); event.pressed = pressed
	Input.parse_input_event(event)

func _window_point(logical: Vector2) -> Vector2:
	# Input.parse_input_event simulates hardware/window pixels. Window converts
	# these into the expanded logical viewport before UI._input receives them.
	return logical * Vector2(root.size) / ui.root.size

func _event_drag(index: int, point: Vector2) -> void:
	var event = InputEventScreenDrag.new(); event.index = index; event.position = point
	ui._input(event)
