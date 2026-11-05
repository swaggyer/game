extends SceneTree
## Update UI only: no network calls, browser launches, or save writes.
var ui
var checks = 0
var failures: Array[String] = []
var requests = 0
var downloads: Array = []
var starts = 0
var opened = 0
var closed = 0
var story_callbacks = 0
const INFO = {"available": true, "version": "1.5.1", "notes": "移动与战斗更流畅。\n新增剧情内容，改善触屏操作与声音设置。", "download_url": "https://github.com/swaggyer/game/releases/download/v1.5.1/StarLanternIsland-v1.5.1-arm64.apk"}

func _initialize() -> void: call_deferred("run")
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL: " + text)
func frames(count: int = 3) -> void:
	for i in range(count): await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	if "--mobile" in OS.get_cmdline_user_args():
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.content_scale_size = Vector2i(1280, 720)
		root.size = Vector2i(2640, 1216)
	ui = load("res://scripts/mobile_ui.gd").new()
	root.add_child(ui); ui.setup(load("res://scripts/campaign.gd").new())
	ui.update_check_requested.connect(func(): requests += 1)
	ui.update_download_requested.connect(func(info): downloads.append(info))
	ui.start_requested.connect(func(_continue): starts += 1)
	ui.story_opened.connect(func(_id, _text): opened += 1)
	ui.story_closed.connect(func(): closed += 1)
	await frames()
	var initial_serial = ui._dialog_serial
	var bounds = Rect2(Vector2.ZERO, ui.root.size)
	check(bounds.encloses(ui.update_check_button.get_global_rect()) and ui.update_check_button.size.x < 180, "small update button stays inside title bounds")
	check(not ui.update_check_button.get_global_rect().intersects(ui.continue_button.get_global_rect()), "update button does not cover the main title actions")
	await screenshot("v150-title-update-button.png")
	await tap(ui.update_check_button)
	check(requests == 1 and ui.update_check_button.disabled and ui.update_check_button.text == "检查中…", "manual check emits one request and shows disabled checking state")
	await tap(ui.update_check_button)
	check(requests == 1, "checking cannot be submitted twice")
	ui.show_update_result({"available": false}, true)
	check(not ui.update_check_button.disabled and ui.toast_label.text == "当前已是最新版本" and not ui.update_screen.visible, "manual current result restores button and shows only a toast")
	clear_toast()
	ui.show_update_result({"available": false}, false)
	check(not ui.toast_panel.visible and not ui.update_screen.visible, "automatic current result is silent")
	ui.show_update_result({"error": "网络暂不可用"}, false)
	check(not ui.toast_panel.visible and not ui.update_screen.visible, "automatic network error is silent")
	ui.show_update_result({"error": "网络暂不可用"}, true)
	check("网络暂不可用" in ui.toast_label.text and not ui.update_check_button.disabled, "manual error is readable and allows retry")
	ui.show_update_result(INFO)
	await frames()
	check(ui.update_screen.visible and paused and ui._dialog_serial == initial_serial and opened == 0 and closed == 0, "update overlay changes no pause state, story lifecycle, or modal callback")
	check(ui._update_version_label.text == "发现新版本  v1.5.1" and ui._update_notes_label.text == INFO.notes, "available version and short release notes are displayed")
	var panel: Control = ui.update_screen.find_child("UpdatePanel", true, false)
	check(bounds.encloses(panel.get_global_rect()), "update panel fits the landscape viewport")
	for name in ["UpdateDownload", "UpdateLater"]:
		check(panel.get_global_rect().encloses(ui.update_screen.find_child(name, true, false).get_global_rect()), name + " remains inside the update panel")
	await screenshot("v150-update-notice.png")
	await tap(ui.continue_button)
	check(starts == 0, "update overlay blocks touches from reaching title buttons behind it")
	await tap(ui._update_download_button)
	check(downloads.size() == 1 and downloads[0].download_url == INFO.download_url and ui.update_screen.visible, "download emits the selected info once and keeps Later available")
	await tap(ui._update_download_button)
	check(downloads.size() == 1 and ui._update_download_button.disabled, "repeated touch cannot open the download page twice")
	await tap(ui.update_screen.find_child("UpdateLater", true, false))
	check(not ui.update_screen.visible and paused and opened == 0 and closed == 0, "Later closes only the update overlay")
	ui.show_update_result(INFO)
	var key = InputEventKey.new(); key.keycode = KEY_ESCAPE; key.pressed = true
	ui._input(key)
	check(not ui.update_screen.visible and paused, "Escape dismisses update notice without changing title pause")
	ui.show_hud(); paused = false
	ui.show_update_result(INFO, false)
	check(not ui.update_screen.visible and not paused and not ui._pending_update_info.is_empty(), "late automatic reply is deferred while playing")
	ui.show_title(); await frames()
	check(ui.update_screen.visible and ui._update_version_label.text.ends_with("v1.5.1") and not ui._update_download_button.disabled, "returning to title displays the deferred update with its download intact")
	ui.show_hud(); paused = false
	check(not ui.update_screen.visible, "starting the game hides the update overlay")
	ui.show_dialog("剧情", "这个故事继续朗读。", "继续", func(): story_callbacks += 1, "intro_0")
	ui.set_story_audio_state("playing")
	ui.show_update_result(INFO, false)
	check(not ui.update_screen.visible and ui.dialog_screen.visible and ui._active_story_id == "intro_0" and ui.story_audio_state == "playing" and opened == 1 and closed == 0, "late update cannot interrupt or close narration")
	ui._close_dialog()
	check(story_callbacks == 1 and closed == 1 and not paused, "story still continues once with its original pause state")
	paused = false; ui.queue_free(); await frames()
	if failures.is_empty(): print("UPDATE UI V1.5.0 PASSED: %d checks" % checks)
	else: printerr("UPDATE UI V1.5.0 FAILED: %d / %d" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func tap(button: Button) -> void:
	var point = button.get_global_rect().get_center() * Vector2(root.size) / ui.root.size
	for pressed in [true, false]:
		var event = InputEventScreenTouch.new()
		event.index = 3; event.position = point; event.pressed = pressed
		Input.parse_input_event(event); await frames(1)
	await frames(1)

func clear_toast() -> void:
	ui.toast_time = 0; ui.toast_panel.hide()

func screenshot(filename: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	clear_toast(); await frames(3); await RenderingServer.frame_post_draw
	var shot = root.get_texture().get_image()
	shot.resize(root.size.x, root.size.y, Image.INTERPOLATE_BILINEAR)
	check(shot.save_png("user://" + filename) == OK, "native screenshot saved")
	print("UPDATE_UI_PROOF ", ProjectSettings.globalize_path("user://" + filename))
