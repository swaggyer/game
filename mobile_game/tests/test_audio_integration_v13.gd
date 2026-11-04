extends SceneTree
## Actual main scene + actual UI and AudioDirector. Only objective completion is
## simulated: this suite tests audio/story flow, not the combat or trial rules.
## -- --require-assets checks final packaged files; -- --fixtures isolates hooks
## with locally encoded WAVs while production audio is still being prepared.
## --capture saves actual scene story/settings proof to the isolated user folder.
## --capture-only renders those two proofs without rerunning the complete suite.

const FIXTURE = "user://audio-integration-v13"
const SETTINGS = FIXTURE + "/settings.json"
const SAVE = FIXTURE + "/campaign.json"
var game: Node2D
var audio
var production: Dictionary
var using_production = false
var checks = 0
var failures: Array[String] = []
var opened: Array = []
var started: Array[String] = []
var finished: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func frames(count: int = 3) -> void:
	for i in range(count): await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE))
	_clean_saves()
	production = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio_v13.json"))
	var missing = _missing_assets()
	using_production = missing.is_empty() and not "--fixtures" in OS.get_cmdline_user_args()
	if "--require-assets" in OS.get_cmdline_user_args():
		check(missing.is_empty(), "all final narration and music files exist: " + str(missing))
		if not missing.is_empty(): quit(1); return
	var manifest_path = "res://data/audio_v13.json" if using_production else _make_fixtures()
	print("AUDIO INTEGRATION MODE: ", "PRODUCTION ASSETS" if using_production else "LOCAL AUDIO FIXTURES")
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	game.campaign.save_path = SAVE
	game.audio_director.settings_path = SETTINGS
	game.audio_director.manifest_path = manifest_path
	root.add_child(game)
	audio = game.audio_director
	game.set_process(false)
	game.ui.story_opened.connect(func(id, text): opened.append([id, text]))
	audio.narration_started.connect(func(id): started.append(id))
	audio.narration_finished.connect(func(id): finished.append(id))
	await frames()
	check(audio.music_context == "title" and audio.music_player.playing, "actual main scene opens with playing title music")
	check(audio._music_path == audio.manifest.music.contexts.title.path, "title selects its manifest music file")
	check(game.music == audio.music_player and game.ui.audio_controller == audio, "main scene shares the AudioDirector player and settings provider")
	var capture_only = "--capture-only" in OS.get_cmdline_user_args()
	if capture_only:
		game._start(false); await frames()
		await _capture("v13-main-story.png")
		await _tap_name("SkipStory")
		game._pause(); game.ui.pause_tab = "settings"; game.ui.refresh_pause()
		await _capture("v13-audio-settings.png")
	else:
		await _test_regions_and_skip()
		await _test_pause_replay_and_finish()
		await _test_all_clear_callbacks()
		await _test_unvoiced_dialogs()
		await _test_music_contexts()
		await _test_settings_persistence()
	paused = false
	audio.stop_narration(); audio.stop_music()
	game.hero_actions.game = null; game.locomotion.game = null
	game.queue_free(); await frames()
	check(not is_instance_valid(game) and not is_instance_valid(audio), "main scene and its AudioDirector are freed cleanly after stopping playback")
	game = null; audio = null
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == 0, "audio integration cleanup leaves no orphan nodes")
	_clean_saves()
	if failures.is_empty(): print("AUDIO INTEGRATION V1.3 %s PASSED: %d checks (%s)" % ["NATIVE CAPTURE" if capture_only else "TESTS", checks, "production" if using_production else "fixtures"])
	else: printerr("AUDIO INTEGRATION V1.3 FAILED: %d / %d" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _test_regions_and_skip() -> void:
	game._start(false)
	for chapter in range(7):
		_fresh_stage(chapter * 3)
		await frames()
		var id = "intro_%d" % chapter
		check(audio.region == chapter and audio.music_context == "explore", "chapter %d selects its region exploration context" % chapter)
		check(audio._music_path == audio.manifest.music.regions[chapter].path and audio.music_player.playing, "chapter %d plays its distinct region stream" % chapter)
		check(game.ui.dialog_screen.visible and paused and audio.narration_status().id == id and audio.narration_state == "playing", id + " is voiced by the actual stage intro hook")
		check(opened.back() == [id, production.stories[id].text], id + " narrates only the authored summary, without objectives or control hints")
		var invulnerability = game.invulnerable
		var clock = game.elapsed
		game.set_process(true)
		await create_timer(.06, true).timeout
		game.set_process(false)
		check(is_equal_approx(game.invulnerable, invulnerability) and is_equal_approx(game.elapsed, clock), id + " pauses gameplay and preserves spawn protection")
		if chapter == 0: await _capture("v13-main-story.png")
		var completed_count = finished.size()
		await _tap_name("SkipStory")
		check(not paused and not game.ui.dialog_screen.visible and game.campaign.stage == chapter * 3, id + " skip immediately resumes this stage")
		check(audio.narration_state == "idle" and not audio.voice_player.playing and audio.voice_player.stream == null and finished.size() == completed_count, id + " skip stops its voice without a natural-finish event")

func _test_pause_replay_and_finish() -> void:
	_fresh_stage(1)
	game.done = 3; game.objective_done = [true, true, true]
	game._complete_stage()
	await frames()
	check(audio.narration_status().id == "clear_1" and game.changing_stage, "actual completion opens the clear story before advancing")
	await _tap_name("NarrationToggle")
	check(audio.narration_state == "paused" and audio.voice_player.stream_paused and game.campaign.stage == 1 and paused, "voice pause leaves the story and game progression paused")
	await create_timer(.08, true).timeout
	check(game.campaign.stage == 1 and game.ui.dialog_screen.visible, "waiting during paused voice cannot advance a stage")
	await _tap_name("NarrationToggle")
	check(audio.narration_state == "playing" and not audio.voice_player.stream_paused, "the same story button resumes the actual voice player")
	await _tap_name("NarrationReplay")
	check(audio.narration_status().id == "clear_1" and audio.narration_status().position < .3 and game.campaign.stage == 1, "replay restarts voice without invoking the completion callback")
	# Let the real stream emit finished after seeking close to its end.
	var duration: float = audio.voice_player.stream.get_length()
	var before = finished.size()
	audio.voice_player.play(maxf(0.0, duration - .04))
	await create_timer(.30, true).timeout
	check(finished.size() == before + 1 and finished.back() == "clear_1", "actual voice stream emits its natural completion")
	check(game.ui.story_audio_state == "finished" and game.ui.dialog_screen.visible and paused and game.campaign.stage == 1, "narration completion updates the indicator and waits for explicit Continue")
	await _tap_name("ContinueDialog")
	check(game.campaign.stage == 2 and not paused and not game.ui.dialog_screen.visible and audio.narration_state == "idle", "Continue invokes the real next-stage callback exactly once")

func _test_all_clear_callbacks() -> void:
	for index in range(21):
		_fresh_stage(index)
		if game.ui.dialog_screen.visible: await _tap_name("SkipStory")
		game.done = 3; game.objective_done = [true, true, true]
		var opens_before = opened.size()
		game._complete_stage()
		await frames()
		var id = "clear_%d" % index if index < 20 else "ending"
		check(opened.size() == opens_before + 1 and opened.back() == [id, production.stories[id].text], id + " selects the exact clear-story ID and prose")
		check(audio.narration_status().id == id and audio.narration_state == "playing" and game.ui.dialog_screen.visible and paused, id + " plays in the real paused completion modal")
		check(game.campaign.stage == index and game.changing_stage, id + " cannot advance before player confirmation")
		var stale_serial = game.ui._dialog_serial
		await _tap_name("SkipStory" if index % 2 == 0 else "ContinueDialog")
		var expected_stage = index + 1 if index < 20 else 20
		check(game.campaign.stage == expected_stage and not game.changing_stage, id + " explicit action runs the intended stage/ending callback")
		game.ui._close_dialog_if_current(stale_serial)
		check(game.campaign.stage == expected_stage, id + " old button cannot invoke its callback twice")
		if game.ui.dialog_screen.visible: await _tap_name("SkipStory")
		check(not paused and audio.narration_state == "idle" and not audio.voice_player.playing, id + " leaves no overlapping or stale narration")
	check(production.stories.clear_20.path == production.stories.ending.path and production.stories.clear_20.text == production.stories.ending.text, "clear_20 is the authored ending alias rather than a duplicate narrative")

func _test_unvoiced_dialogs() -> void:
	_fresh_stage(2)
	var before = started.size()
	game.invulnerable = 0; game.shield_time = 0; game.hp = 1
	game._hurt(100000, game.player.position + Vector2(70, 0), true)
	await frames()
	check(game.ui.dialog_screen.visible and paused and game.hp == game.campaign.max_hp(), "actual lethal hit opens the camp-retry modal")
	check(started.size() == before and audio.narration_state == "idle" and game.ui.dialog_screen.find_child("StoryAudioControls", true, false) == null, "death/retry hints are not narrated")
	await _tap_name("ContinueDialog")
	check(not paused and is_equal_approx(game.invulnerable, 3.0), "retry confirmation preserves post-death protection")
	game._pause(); game.ui.pause_tab = "settings"; game.ui.refresh_pause()
	await frames()
	var scroller: ScrollContainer = game.ui.pause_content.get_parent()
	scroller.scroll_vertical = 100000
	await frames()
	await _tap_text("重新开始冒险…", game.ui.pause_screen)
	check(game.ui.dialog_screen.visible and started.size() == before and audio.narration_state == "idle", "actual restart confirmation is not voiced")
	var old_stage = game.campaign.stage
	await _tap_text("保留当前旅程", game.ui.dialog_screen)
	check(game.campaign.stage == old_stage and game.ui.pause_screen.visible and paused, "declining restart preserves the current progress and pause state")
	game._resume()

func _test_music_contexts() -> void:
	_fresh_stage(2)
	game.enemy_director.clear(); game._sync_enemies()
	game.music_combat_hold = 0; game._update_music_context(0)
	check(audio.music_context == "explore", "safe gameplay selects exploration music")
	var enemy = game.enemy_director.spawn("shadow_blob", game.player.position + Vector2(60, 0))
	enemy.memory = 1.0
	game._update_music_context(.01)
	check(audio.music_context == "battle" and audio._music_path == audio.manifest.music.contexts.battle.path, "a real nearby enemy selects battle music")
	game.enemy_director.clear()
	var boss = game.enemy_director.spawn("thorn_treant", game.player.position + Vector2(80, 0), true)
	boss.memory = 1.0
	game._update_music_context(.01)
	check(audio.music_context == "boss" and audio._music_path == audio.manifest.music.contexts.boss.path, "a real nearby boss selects boss music")
	game._pause()
	check(audio.music_context == "pause" and paused, "the actual pause menu changes the music context")
	game._resume()
	check(audio.music_context == "boss" and not paused, "resuming restores the live combat context")
	game.hp = 1
	game._rest(game.spawn_position)
	check(game.hp == game.campaign.max_hp() and game.checkpoint_position.distance_to(game.spawn_position) < 130, "actual camp rest restores the team and records the checkpoint")
	game.enemy_director.clear(); game._sync_enemies()
	game._update_music_context(3.1)
	check(audio.music_context == "explore" and audio._music_path == audio.manifest.music.regions[audio.region].path, "after camp combat settles the correct regional music returns")
	game._pause(); await frames()
	await _tap_text("返回标题", game.ui.pause_screen)
	check(game.ui.title_screen.visible and paused and audio.narration_state == "idle", "the actual return-title button leaves no narration")
	check(audio.music_context == "title" and audio._music_path == audio.manifest.music.contexts.title.path, "returning to title restores the title score")
	game._start(true)
	if game.ui.dialog_screen.visible: await _tap_name("SkipStory")
	check(audio.music_context == "explore" and not paused, "Continue from the title restores the saved region music")

func _test_settings_persistence() -> void:
	game._pause(); game.ui.pause_tab = "settings"; game.ui.refresh_pause()
	var scroller: ScrollContainer = game.ui.pause_content.get_parent()
	scroller.scroll_vertical = 0
	await frames()
	for pair in [["MusicVolume", "music", .23], ["SfxVolume", "sfx", .46], ["VoiceVolume", "voice", .67]]:
		var slider: HSlider = game.ui.pause_content.find_child(pair[0], true, false)
		await _drag_slider(slider, float(pair[2]))
		check(absf(float(audio.settings()[str(pair[1]) + "_volume"]) - float(pair[2])) < .04, str(pair[1]) + " touch slider reaches the real AudioDirector")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(audio.SFX_BUS)), audio.sfx_volume), "SFX slider updates the existing gameplay sound bus")
	await _tap_name("VoiceEnabled", game.ui.pause_content)
	check(not audio.voice_enabled, "UI voice toggle disables narration through the real controller")
	var persisted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	check(not persisted.voice_enabled and absf(persisted.music_volume - .23) < .04 and absf(persisted.sfx_volume - .46) < .04 and absf(persisted.voice_volume - .67) < .04, "all three volumes and voice enable persist to the isolated audio settings file")
	var reloaded = load("res://scripts/audio_director.gd").new()
	reloaded.settings_path = SETTINGS
	check(reloaded.load_settings() and reloaded.settings() == audio.settings(), "a fresh controller loads the same persisted settings")
	reloaded.free()
	game.ui.refresh_pause(); await frames()
	check(game.ui.pause_content.find_child("VoiceEnabled", true, false).text == "剧情朗读：关闭", "reopening settings reflects the persisted disabled voice")
	await _capture("v13-audio-settings.png")
	game._resume()
	_fresh_stage(0); await frames()
	check(game.ui.dialog_screen.visible and audio.narration_state == "disabled" and not audio.voice_player.playing and game.ui._story_toggle_button.disabled, "future stories remain readable while persisted voice mute prevents playback")
	await _tap_name("SkipStory")
	check(not paused and not game.ui.dialog_screen.visible and not audio.voice_enabled, "muted story skip remains immediate and retains the audio preference")

func _fresh_stage(index: int) -> void:
	game.set_process(false)
	game.ui.show_hud(); paused = false
	game.stage_info.clear(); game.world_saves.erase(str(index))
	game._load_stage(index)

func _tap_name(name: String, surface: Node = null) -> void:
	await _tap((surface if surface != null else game.ui.dialog_screen).find_child(name, true, false) as Button)

func _tap_text(text: String, surface: Node) -> void:
	await _tap(_button_with_text(surface, text))

func _button_with_text(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var button = _button_with_text(child, text)
		if button != null: return button
	return null

func _tap(button: Button) -> void:
	check(is_instance_valid(button) and button.is_visible_in_tree(), "requested actual touch button is visible")
	if not is_instance_valid(button): return
	var point = button.get_global_rect().get_center()
	_touch(5, point, true); await frames(1)
	_touch(5, point, false); await frames(2)

func _drag_slider(slider: HSlider, fraction: float) -> void:
	check(is_instance_valid(slider) and slider.is_visible_in_tree(), "requested actual volume slider exists")
	if not is_instance_valid(slider): return
	var rect = slider.get_global_rect()
	var start = rect.position + Vector2(rect.size.x * .5, rect.size.y * .5)
	var end = rect.position + Vector2(12 + (rect.size.x - 24) * fraction, rect.size.y * .5)
	_touch(7, start, true); await frames(1)
	var drag = InputEventScreenDrag.new(); drag.index = 7; drag.position = end
	Input.parse_input_event(drag); await frames(1)
	_touch(7, end, false); await frames(1)

func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index; event.position = position; event.pressed = pressed
	Input.parse_input_event(event)

func _missing_assets() -> Array[String]:
	var result: Array[String] = []
	var paths: Array = []
	for entry in production.music.regions: paths.append(entry.path)
	for entry in production.music.contexts.values(): paths.append(entry.path)
	for entry in production.stories.values(): paths.append(entry.path)
	for path in paths:
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
			if not path in result: result.append(path)
	return result

func _make_fixtures() -> String:
	var data = production.duplicate(true)
	for index in range(7):
		var path = FIXTURE + "/region_%d.wav" % index
		_wave(path, .4, 150 + index * 30)
		data.music.regions[index].path = path
	for id in data.music.contexts:
		var path = FIXTURE + "/" + id + ".wav"
		_wave(path, .4, 250)
		data.music.contexts[id].path = path
	var voice = FIXTURE + "/voice.wav"
	_wave(voice, 6, 330)
	for entry in data.stories.values(): entry.path = voice
	var path = FIXTURE + "/manifest.json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data)); file.close()
	return path

func _wave(path: String, duration: float, frequency: float) -> void:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = 8000
	var data = PackedByteArray(); data.resize(int(duration * 8000) * 2)
	for index in range(data.size() / 2): data.encode_s16(index * 2, int(sin(index * TAU * frequency / 8000) * 220))
	stream.data = data
	check(stream.save_to_wav(ProjectSettings.globalize_path(path)) == OK, "local audio fixture encoded")

func _clean_saves() -> void:
	for path in [SETTINGS, SAVE, SAVE + ".world.json"]:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _capture(filename: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	# Transient notifications are unrelated to this screenshot's audio controls.
	game.ui.toast_time = 0; game.ui.toast_panel.hide()
	game._update_hud(); game.queue_redraw(); game.combat_overlay.queue_redraw(); game.mini_map.queue_redraw()
	await frames(5)
	await RenderingServer.frame_post_draw
	var path = FIXTURE + "/" + filename
	check(root.get_texture().get_image().save_png(path) == OK, "native scene screenshot saved: " + filename)
	print("AUDIO_NATIVE_PROOF ", ProjectSettings.globalize_path(path))
