extends SceneTree
## Isolated UI contract, modal lifecycle, and actual multitouch input routing.
## -- --capture additionally writes native screenshots to user://.

class FakeAudio extends RefCounted:
	var values = {"music_volume": 0.31, "sfx_volume": 0.72, "voice_volume": 0.58, "voice_enabled": false}
	func settings() -> Dictionary:
		return values.duplicate()

var ui
var checks = 0
var failures: Array[String] = []
var opens: Array = []
var closes = 0
var callbacks = 0
var toggles = 0
var replays = 0
var changes: Array = []
var capture = false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func frames(count: int = 3) -> void:
	for i in range(count):
		await process_frame

func run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 720)
	ui = load("res://scripts/mobile_ui.gd").new()
	root.add_child(ui)
	ui.setup(load("res://scripts/campaign.gd").new())
	ui.story_opened.connect(func(id, text): opens.append([id, text]))
	ui.story_closed.connect(func(): closes += 1)
	ui.narration_toggle_requested.connect(func(): toggles += 1; ui.set_story_audio_state("paused"))
	ui.narration_replay_requested.connect(func(): replays += 1; ui.set_story_audio_state("playing"))
	ui.audio_setting_changed.connect(func(kind, value): changes.append([kind, value]))
	await frames()
	await test_story_controls()
	await test_modal_lifecycle()
	await test_audio_settings()
	await test_story_capture()
	paused = false
	ui.queue_free()
	await frames()
	if failures.is_empty():
		print("STORY UI V1.3 TESTS PASSED: %d checks" % checks)
	else:
		printerr("STORY UI V1.3 FAILED: %d / %d" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func test_story_controls() -> void:
	ui.show_hud(); paused = false
	ui.show_dialog("星灯仍在等你", "这是死亡后的普通提示。", "再试一次", func(): callbacks += 1)
	await frames()
	check(opens.is_empty(), "legacy four-argument death/hint dialog never starts narration")
	check(ui.dialog_screen.find_child("StoryAudioControls", true, false) == null, "ordinary dialog has no voice or skip controls")
	ui._close_dialog(); ui._close_dialog()
	check(callbacks == 1 and closes == 0 and not paused, "ordinary close restores simulation and executes its callback once")
	ui.show_dialog("院子里的小流星", "旺仔和小馒头在院子里发现了一束落下的星光。", "出发闯关", func(): callbacks += 1, "intro_0")
	await frames()
	check(opens == [["intro_0", "旺仔和小馒头在院子里发现了一束落下的星光。"]], "story event uses body when narration override is omitted")
	check(paused and ui.dialog_screen.visible, "story modal pauses the world while its UI remains active")
	ui.set_story_audio_state("playing")
	var toggle: Button = ui.dialog_screen.find_child("NarrationToggle", true, false)
	var replay: Button = ui.dialog_screen.find_child("NarrationReplay", true, false)
	var skip: Button = ui.dialog_screen.find_child("SkipStory", true, false)
	check(toggle.text == "暂停朗读" and not toggle.disabled, "playing state offers pause")
	await tap(toggle)
	check(toggles == 1 and toggle.text == "继续朗读", "touch pause sends one request and reflects paused audio")
	await tap(replay)
	check(replays == 1 and toggle.text == "暂停朗读", "touch replay sends one request and reflects playback")
	ui.set_story_audio_state("unavailable")
	check(toggle.disabled and replay.disabled and not skip.disabled, "missing voice disables only voice controls, leaving immediate progress available")
	ui.set_story_audio_state("disabled")
	check(ui._story_audio_label.text == "剧情朗读已关闭", "disabled narration gives a clear status")
	ui.set_story_audio_state("finished")
	check(not replay.disabled and ui._story_audio_label.text == "朗读已结束", "finished narration remains replayable")
	var panel: Control = ui.dialog_screen.find_child("DialogPanel", true, false)
	check(panel.size.x == 820 and panel.size.y <= 600 and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(panel.get_global_rect()), "story panel fits the landscape screen")
	for name in ["NarrationToggle", "NarrationReplay", "SkipStory", "ContinueDialog"]:
		var button: Control = ui.dialog_screen.find_child(name, true, false)
		check(panel.get_global_rect().encloses(button.get_global_rect()), name + " fits inside the 820px dialog")
	ui.set_story_audio_state("playing")
	await tap(skip)
	check(callbacks == 2 and closes == 1 and not paused and not ui.dialog_screen.visible, "skip immediately closes playing narration and invokes the same story callback")
	ui._close_dialog()
	check(callbacks == 2 and closes == 1, "duplicate close cannot invoke callback or stop twice")

func test_modal_lifecycle() -> void:
	var before = callbacks
	ui.show_dialog("旧剧情", "旧朗读", "继续", func(): callbacks += 100, "intro_1", "明确的语音文本")
	check(opens.back() == ["intro_1", "明确的语音文本"], "explicit narration text is passed without objectives or UI instructions")
	var serial = ui._dialog_serial
	ui.show_dialog("新剧情", "新朗读", "继续", func(): callbacks += 1, "intro_2")
	check(closes == 2 and paused, "replacing story stops old narration and remains paused")
	ui._close_dialog_if_current(serial)
	check(ui.dialog_screen.visible and callbacks == before, "stale button release cannot dismiss a replacement story")
	await key(KEY_ESCAPE)
	check(ui.dialog_screen.visible and callbacks == before, "Escape cannot bypass a modal or accidentally confirm restart")
	await key(KEY_ENTER)
	check(callbacks == before + 1 and closes == 3 and not paused, "Enter continues before voice finishes and restores original pause state")
	ui.show_dialog("片尾", "回家的门，也为朋友敞开。", "继续探索", func(): callbacks += 1, "ending")
	await key(KEY_SPACE)
	check(callbacks == before + 2 and closes == 4 and not paused, "Space can continue an ending")
	paused = true
	ui.show_dialog("暂停中剧情", "继续后仍是暂停页。", "继续", func(): callbacks += 1, "clear_0")
	ui._close_dialog()
	check(paused and closes == 5, "story opened while paused restores paused state")
	ui.show_dialog("返回标题", "未播放完。", "继续", func(): callbacks += 100, "intro_3")
	ui.show_title(); ui.show_title()
	check(closes == 6 and paused and not ui.dialog_screen.visible, "returning to title stops voice once and discards pending callbacks")
	ui.show_dialog("显示游戏", "未播放完。", "继续", func(): callbacks += 100, "intro_4")
	ui.show_hud(); ui._close_dialog()
	check(closes == 7 and callbacks == before + 3, "show_hud cancels narration and cannot execute its superseded callback")
	ui.show_dialog("直接隐藏", "未播放完。", "继续", func(): pass, "intro_5")
	ui.dialog_screen.hide()
	check(closes == 8, "directly hiding the story surface stops narration")
	ui.show_hud(); paused = false
	ui.pause_tab = "settings"; ui.show_pause(); paused = true
	ui.show_dialog("重新开始冒险", "确认清除当前主线旅程？", "确认重新开始", func(): callbacks += 100)
	await frames()
	check(ui.dialog_screen.find_child("SkipStory", true, false) == null, "restart confirmation remains outside the narration flow")
	var retain: Button
	for button in buttons(ui.dialog_screen):
		if button.text == "保留当前旅程": retain = button
	await tap(retain)
	check(callbacks == before + 3 and paused and ui.pause_screen.visible, "cancel restart keeps progress and the previous pause menu")
	ui.hide_pause(); paused = false
	var stops = closes
	ui.show_dialog("隐藏界面", "停止隐藏界面的语音。", "继续", func(): pass, "intro_6")
	ui.hide()
	check(closes == stops + 1, "hiding the CanvasLayer stops its narration")
	ui.show(); ui.show_hud(); paused = false
	ui.show_dialog("连续剧情一", "第一段", "继续", func():
		callbacks += 1
		ui.show_dialog("连续剧情二", "第二段", "继续", func(): callbacks += 1, "clear_2"), "clear_1")
	var first_serial = ui._dialog_serial
	ui._close_dialog()
	check(ui.dialog_screen.visible and paused and ui._active_story_id == "clear_2", "a continuation callback can synchronously open the next paused story")
	ui._close_dialog_if_current(first_serial)
	check(ui._active_story_id == "clear_2", "the first story's stale button cannot close the second")
	ui._close_dialog()
	check(not paused and callbacks == before + 5, "sequential story callbacks run once and restore the original world state")

func test_audio_settings() -> void:
	var provider = FakeAudio.new()
	ui.audio_controller = provider
	ui.pause_tab = "settings"; ui.show_pause(); paused = true
	await frames()
	var music: HSlider = ui.pause_content.find_child("MusicVolume", true, false)
	var sfx: HSlider = ui.pause_content.find_child("SfxVolume", true, false)
	var voice: HSlider = ui.pause_content.find_child("VoiceVolume", true, false)
	check(is_equal_approx(music.value, .31) and is_equal_approx(sfx.value, .72) and is_equal_approx(voice.value, .58), "audio settings read all three persisted provider volumes")
	check(ui.pause_content.find_child("VoiceEnabled", true, false).text == "剧情朗读：关闭", "voice enable state comes from the provider")
	for pair in [[music, "music"], [sfx, "sfx"], [voice, "voice"]]:
		var slider: HSlider = pair[0]
		var start = slider.get_global_rect().position + Vector2(24, slider.size.y / 2)
		var end = slider.get_global_rect().end - Vector2(12, slider.size.y / 2)
		touch(7, start, true); await frames(1)
		var drag = InputEventScreenDrag.new(); drag.index = 7; drag.position = end
		Input.parse_input_event(drag); await frames(1)
		touch(7, end, false); await frames(1)
		check(slider.value > .98 and changes.back()[0] == pair[1], "real finger drag adjusts " + pair[1] + " without scrolling or moving the hero")
		check(ui.touch_sliders.is_empty() and ui.stick_id == -1, "released volume finger clears capture")
	var enabled: Button = ui.pause_content.find_child("VoiceEnabled", true, false)
	await tap(enabled)
	check(changes.back() == ["voice_enabled", true] and enabled.text == "剧情朗读：开启", "touch toggles voice availability through the settings signal")
	var scroller: ScrollContainer = ui.pause_content.get_parent()
	check(scroller.scroll_vertical == 0, "horizontal volume drags do not scroll the settings page")
	if capture: await screenshot("story-v13-audio-settings.png")
	ui.hide_pause(); paused = false

func test_story_capture() -> void:
	ui.show_title()
	ui.show_dialog("第一章 · 微光森林", "旺仔把手里的小盾牌举高了一点。小馒头踮起脚，望向树林深处一闪一闪的微光。\n\n小龙低下头，用鼻尖轻轻碰了碰他们的手。只要一起走，最黑的路也会亮起来。", "一起出发", func(): pass, "intro_0")
	ui.set_story_audio_state("playing")
	await frames()
	if capture: await screenshot("story-v13-dialog.png")
	ui._close_dialog()

func buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	if node is Button: result.append(node)
	for child in node.get_children(): result.append_array(buttons(child))
	return result

func tap(button: Button) -> void:
	check(button != null, "expected touch button exists")
	if button == null: return
	var point = button.get_global_rect().get_center()
	touch(5, point, true); await frames(1)
	touch(5, point, false); await frames(2)

func touch(index: int, point: Vector2, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index; event.position = point; event.pressed = pressed
	Input.parse_input_event(event)

func key(code: Key) -> void:
	var event = InputEventKey.new()
	event.keycode = code; event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = InputEventKey.new(); event.keycode = code; event.pressed = false
	Input.parse_input_event(event)
	await frames(1)

func screenshot(filename: String) -> void:
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://" + filename)
	print("UI_CAPTURE ", ProjectSettings.globalize_path("user://" + filename))
