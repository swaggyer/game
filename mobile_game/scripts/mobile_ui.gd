extends CanvasLayer

signal move_changed(direction: Vector2)
signal attack_pressed
signal context_pressed
signal context_released
signal context_cancelled
signal switch_requested(index: int)
signal pause_requested
signal resume_requested
signal stage_requested(index: int)
signal equip_requested(slot: String, id: String)
signal upgrade_requested(slot: String)
signal reset_upgrades_requested
signal fruit_requested
signal skill_requested(id: String)
signal difficulty_requested(id: String)
signal new_game_requested
signal start_requested(continue_game: bool)
signal story_opened(id: String, text: String)
signal story_closed
signal narration_toggle_requested
signal narration_replay_requested
signal audio_setting_changed(kind: String, value)
signal update_check_requested
signal update_download_requested(info: Dictionary)

const INK = Color("102b35")
const DEEP = Color("102b35f2")
const GOLD = Color("e6c783")
const CREAM = Color("f5efd9")
const CYAN = Color("94e0d2")
const MUTED = Color("9db7b7")
const COOLDOWN_CONTEXTS = ["微光", "星火", "火焰", "御风", "水罩", "护罩", "星门"]

var campaign
var root: Control
var hud: Control
var title_screen: Control
var pause_screen: Control
var dialog_screen: Control
var toast_panel: PanelContainer
var toast_label: Label
var toast_time = 0.0
var hp_bar: ProgressBar
var hp_label: Label
var level_label: Label
var goal_label: Label
var detail_label: Label
var chapter_label: Label
var attack_button: Button
var context_button: Button
var continue_button: Button
var difficulty_choice: Button
var portraits: Array[Button] = []
var pause_content: VBoxContainer
var pause_tab = "map"
var dialog_callback: Callable
var was_paused = false
var joystick: Control
var stick_origin = Vector2(142, 578)
var stick_offset = Vector2.ZERO
var stick_id = -1
var mouse_stick = false
var direction = Vector2.ZERO
var hud_visible = false
var ui_font: Font
var touch_buttons: Dictionary = {}
var touch_scrolls: Dictionary = {}
var touch_sliders: Dictionary = {}
## Optional AudioDirector; settings are read again each time the page opens.
var audio_controller: Object
var story_audio_state = "idle"
var _active_story_id = ""
var _dialog_serial = 0
var _story_audio_label: Label
var _story_toggle_button: Button
var _story_replay_button: Button
var _audio_values = {"music_volume": 0.65, "sfx_volume": 1.0, "voice_volume": 1.0, "voice_enabled": true}
var _portrait_active_style: StyleBoxFlat
var _portrait_idle_style: StyleBoxFlat
var _hud_character = -1
var _hud_hp = -1
var _hud_max_hp = -1
var _hud_crystals = -1
var _hud_xp = -1
var _hud_context = ""
var _hud_cooldown_tenth = -2
var _context_is_down = false
var update_screen: Control
var update_check_button: Button
var _update_version_label: Label
var _update_notes_label: Label
var _update_download_button: Button
var _update_info: Dictionary = {}
var _pending_update_info: Dictionary = {}
var _update_checking = false
var _update_download_sent = false

func setup(value: RefCounted) -> void:
	campaign = value
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	visibility_changed.connect(func():
		if not visible:
			_cancel_touch_controls()
			_release_stick()
			_stop_story_audio())
	root = Control.new()
	root.name = "MobileInterface"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	if ResourceLoader.exists("res://assets/ui.ttf"):
		ui_font = load("res://assets/ui.ttf")
		if ResourceLoader.exists("res://assets/ui-symbols.ttf"):
			ui_font.fallbacks = [load("res://assets/ui-symbols.ttf")]
		theme.default_font = ui_font
	theme.default_font_size = 19
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", CREAM)
	theme.set_stylebox("normal", "Button", _style(Color("153e49ec"), Color("6c8b83"), 12, 1))
	theme.set_stylebox("hover", "Button", _style(Color("245461"), GOLD, 12, 2))
	theme.set_stylebox("pressed", "Button", _style(Color("28615c"), CYAN, 12, 2))
	theme.set_stylebox("disabled", "Button", _style(Color("1c3339"), Color("3d5254"), 12, 1))
	theme.set_color("font_disabled_color", "Button", Color("617c81"))
	theme.set_stylebox("focus", "Button", _style(Color.TRANSPARENT, CYAN, 12, 2))
	root.theme = theme
	add_child(root)
	_build_hud()
	_build_title()
	_build_pause()
	_build_dialog()
	_build_update_overlay()
	toast_panel = PanelContainer.new()
	toast_panel.add_theme_stylebox_override("panel", _style(DEEP, GOLD, 12, 1))
	root.add_child(toast_panel)
	_anchor_rect(toast_panel, Control.PRESET_CENTER_TOP, Vector2(-260, 160), Vector2(580, 50))
	toast_panel.custom_minimum_size = Vector2(580, 50)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = _label("", 20, CREAM)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.max_lines_visible = 2
	toast_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toast_panel.add_child(toast_label)
	toast_panel.hide()
	show_title()

func _style(bg: Color, edge: Color, radius: int = 14, border: int = 1) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

func _label(text: String, size: int = 20, color: Color = CREAM) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(text: String, callback: Callable, min_size: Vector2 = Vector2(0, 46)) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	return b

func _full(parent: Node, name_value: String) -> Control:
	var c = Control.new()
	c.name = name_value
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c

func _anchor_rect(control: Control, preset: int, offset: Vector2, dimensions: Vector2) -> void:
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = offset.x
	control.offset_top = offset.y
	control.offset_right = offset.x + dimensions.x
	control.offset_bottom = offset.y + dimensions.y

func _panel(parent: Node, pos: Vector2, dimensions: Vector2, edge: Color = Color("59736b")) -> Panel:
	var p = Panel.new()
	p.position = pos
	p.size = dimensions
	p.add_theme_stylebox_override("panel", _style(Color("102c36dd"), edge, 18, 1))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

func _build_hud() -> void:
	hud = _full(root, "GameHUD")
	_portrait_active_style = _style(Color("204b50f0"), GOLD, 12, 2)
	_portrait_idle_style = _style(Color("15333cd0"), Color("526e72"), 12, 1)
	var party = _panel(hud, Vector2(22, 20), Vector2(355, 108))
	for i in 2:
		var b = _button("", func(): switch_requested.emit(i), Vector2(70, 88))
		b.position = Vector2(10 + i * 72, 11)
		b.size = Vector2(70, 88)
		b.tooltip_text = "切换为旺仔" if i == 0 else "切换为小馒头"
		party.add_child(b)
		var img = TextureRect.new()
		img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		img.name = "WangzaiPortrait" if i == 0 else "XiaomantouPortrait"
		var portrait_path = "res://assets/portraits_v12/" + ("wangzai" if i == 0 else "xiaomantou") + ".png"
		if ResourceLoader.exists(portrait_path):
			img.texture = load(portrait_path)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(img)
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.offset_left = 4
		img.offset_right = -4
		img.offset_top = 2
		img.offset_bottom = -24
		var name_label = _label("旺仔" if i == 0 else "小馒头", 13, GOLD)
		name_label.position = Vector2(7, 66)
		b.add_child(name_label)
		portraits.append(b)
	var party_stats = VBoxContainer.new()
	party_stats.name = "PartyStats"
	party_stats.position = Vector2(164, 10)
	party_stats.size = Vector2(174, 88)
	party_stats.alignment = BoxContainer.ALIGNMENT_CENTER
	party_stats.add_theme_constant_override("separation", 6)
	party.add_child(party_stats)
	level_label = _label("Lv.1 · 星契伙伴", 18, GOLD)
	party_stats.add_child(level_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(174, 14)
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var health_background = _style(Color("091e25"), Color("31515a"), 6, 1)
	var health_fill = _style(Color("86c9ae"), Color.TRANSPARENT, 6, 0)
	for health_style in [health_background, health_fill]:
		health_style.content_margin_top = 0
		health_style.content_margin_bottom = 0
		health_style.content_margin_left = 0
		health_style.content_margin_right = 0
	hp_bar.add_theme_stylebox_override("background", health_background)
	hp_bar.add_theme_stylebox_override("fill", health_fill)
	party_stats.add_child(hp_bar)
	hp_bar.draw.connect(func():
		for quarter in range(1,4):
			var x=hp_bar.size.x*float(quarter)/4.0
			hp_bar.draw_line(Vector2(x,1),Vector2(x,hp_bar.size.y-1),Color("244c4c"),2,true))
	hp_label = _label("130 / 130", 14, CREAM)
	hp_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	party_stats.add_child(hp_label)
	var mission = _panel(hud, Vector2.ZERO, Vector2(560, 122), Color("9a8f66"))
	_anchor_rect(mission, Control.PRESET_CENTER_TOP, Vector2(-225, 20), Vector2(560, 122))
	var star = _label("✦", 36, GOLD)
	star.position = Vector2(18, 27)
	mission.add_child(star)
	goal_label = _label("点亮回家的路", 20, GOLD)
	goal_label.position = Vector2(65, 10)
	goal_label.size = Vector2(478, 60)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_label.max_lines_visible = 2
	goal_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	goal_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mission.add_child(goal_label)
	detail_label = _label("和伙伴一起，寻找第一束星光。", 15, CREAM)
	detail_label.position = Vector2(65, 78)
	detail_label.size = Vector2(478, 27)
	detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mission.add_child(detail_label)
	var pause = _button("Ⅱ", func(): _release_stick(); pause_requested.emit(), Vector2(62, 62))
	pause.add_theme_font_size_override("font_size", 30)
	hud.add_child(pause)
	_anchor_rect(pause, Control.PRESET_TOP_RIGHT, Vector2(-86, 24), Vector2(62, 62))
	pause.tooltip_text = "暂停 · 地图 · 装备 · 补给"
	chapter_label = _label("序章 · 院子里的小流星", 15, CREAM)
	hud.add_child(chapter_label)
	_anchor_rect(chapter_label, Control.PRESET_BOTTOM_LEFT, Vector2(28, -32), Vector2(340, 26))
	var hint = _label("WASD 移动   J 连击   K 技能 / 互动   Tab 切换   M 地图   Esc 暂停", 13, Color("d9e6d2aa"))
	hud.add_child(hint)
	_anchor_rect(hint, Control.PRESET_CENTER_BOTTOM, Vector2(-275, -31), Vector2(570, 25))
	joystick = Control.new()
	joystick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(joystick)
	joystick.draw.connect(_draw_joystick)
	root.resized.connect(joystick.queue_redraw)
	var attack = _button("剑·盾\n攻击", func(): attack_pressed.emit(), Vector2(110, 110))
	attack.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	attack_button = attack
	attack.add_theme_font_size_override("font_size", 24)
	attack.tooltip_text = "轻点攻击；及时连续轻点接出三段连击。第三式：旺仔盾震，小馒头回声震荡。"
	attack.add_theme_stylebox_override("normal", _style(Color("183f46e8"), GOLD, 55, 2))
	attack.add_theme_stylebox_override("hover", _style(Color("2c5656f0"), GOLD, 55, 3))
	attack.add_theme_stylebox_override("pressed", _style(Color("507165"), CREAM, 55, 3))
	hud.add_child(attack)
	_anchor_rect(attack, Control.PRESET_BOTTOM_RIGHT, Vector2(-150, -158), Vector2(110, 110))
	context_button = _button("✦\n星火", func(): pass, Vector2(88, 88))
	context_button.add_theme_font_size_override("font_size", 18)
	context_button.clip_text = true
	context_button.add_theme_stylebox_override("normal", _style(Color("143e45e8"), CYAN, 44, 2))
	context_button.add_theme_stylebox_override("hover", _style(Color("285a5a"), CYAN, 44, 2))
	context_button.add_theme_stylebox_override("pressed", _style(Color("357475"), CREAM, 44, 3))
	for style_name in ["normal", "hover", "pressed"]:
		var box = context_button.get_theme_stylebox(style_name).duplicate()
		box.content_margin_left = 4
		box.content_margin_right = 4
		context_button.add_theme_stylebox_override(style_name, box)
	context_button.button_down.connect(_press_context)
	context_button.button_up.connect(_release_context)
	hud.add_child(context_button)
	_anchor_rect(context_button, Control.PRESET_BOTTOM_RIGHT, Vector2(-253, -249), Vector2(88, 88))
	_update_character_hud(int(campaign.active_character))

func _build_title() -> void:
	title_screen = _full(root, "TitleScreen")
	title_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var art = TextureRect.new()
	art.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if ResourceLoader.exists("res://assets/environment_v11/title_landscape.png"):
		art.texture=load("res://assets/environment_v11/title_landscape.png")
	elif ResourceLoader.exists("res://assets/title.png"):
		art.texture = load("res://assets/title.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade = ColorRect.new()
	shade.color = Color("0d2833a9")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box = VBoxContainer.new()
	box.position = Vector2(94, 100)
	box.size = Vector2(590, 550)
	box.add_theme_constant_override("separation", 12)
	title_screen.add_child(box)
	box.add_child(_label("S T A R  L A N T E R N  I S L A N D", 17, GOLD))
	box.add_child(_label("星灯岛", 76, CREAM))
	box.add_child(_label("与回家的小龙", 37, GOLD))
	var caption = _label("两个孩子，一只小龙。\n把散落的星光，连成回家的路。", 22, Color("c9dad1"))
	caption.add_theme_constant_override("line_spacing", 8)
	box.add_child(caption)
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 15
	box.add_child(spacer)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	box.add_child(actions)
	var go = _button("开启冒险  →", func(): start_requested.emit(false), Vector2(210, 62))
	go.add_theme_color_override("font_color", INK)
	go.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 12, 1))
	go.add_theme_stylebox_override("hover", _style(Color("f2dca2"), CREAM, 12, 2))
	actions.add_child(go)
	continue_button = _button("继续旅程", func(): start_requested.emit(true), Vector2(175, 62))
	actions.add_child(continue_button)
	var difficulty = HBoxContainer.new()
	difficulty.add_theme_constant_override("separation", 12)
	box.add_child(difficulty)
	difficulty.add_child(_label("冒险难度", 17, MUTED))
	var choice = _button("小小守护者 · 推荐   ↻", _cycle_difficulty, Vector2(258, 40))
	difficulty_choice = choice
	difficulty.add_child(choice)
	box.add_child(_label("自由寻路 · 支路宝箱 · 星灯营地 · 本地存档", 16, MUTED))
	var guide = _panel(title_screen, Vector2(824, 415), Vector2(358, 200), Color("7a8064"))
	var guide_title = _label("每束星光，都有自己的路", 20, GOLD)
	guide_title.position = Vector2(20, 16)
	guide.add_child(guide_title)
	var guide_text = _label("展开地图，自由选择探索路线。\n支路寻找宝箱，星灯营地恢复。\n连续轻点攻击，接出第三式。\n观察预警，抓住收招的空隙。", 17, Color("c9dad1"))
	guide_text.position = Vector2(20, 58)
	guide_text.add_theme_constant_override("line_spacing", 6)
	guide.add_child(guide_text)
	var footer = _label("✦  七章冒险 · 开放区域 · 二十一段星光", 16, Color("d8d9bf"))
	title_screen.add_child(footer)
	_anchor_rect(footer, Control.PRESET_BOTTOM_LEFT, Vector2(94, -41), Vector2(900, 28))
	update_check_button = _button("检查更新", _request_update_check, Vector2(158, 42))
	update_check_button.name = "CheckUpdatesButton"
	update_check_button.add_theme_font_size_override("font_size", 16)
	update_check_button.tooltip_text = "检查是否有新版本"
	title_screen.add_child(update_check_button)
	_anchor_rect(update_check_button, Control.PRESET_TOP_RIGHT, Vector2(-192, 30), Vector2(158, 42))
	var installed_version = str(ProjectSettings.get_setting("application/config/version", "")).get_slice("-", 0)
	var version_label = _label("当前版本 v" + installed_version, 14, MUTED)
	version_label.name = "InstalledVersion"
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(version_label)
	_anchor_rect(version_label, Control.PRESET_TOP_RIGHT, Vector2(-242, 78), Vector2(208, 24))

func _build_update_overlay() -> void:
	update_screen = _full(root, "UpdateNotice")
	update_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade = ColorRect.new()
	shade.color = Color("061a26c9")
	update_screen.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel = PanelContainer.new()
	panel.name = "UpdatePanel"
	panel.add_theme_stylebox_override("panel", _style(DEEP, GOLD, 22, 2))
	update_screen.add_child(panel)
	_anchor_rect(panel, Control.PRESET_CENTER, Vector2(-340, -190), Vector2(680, 380))
	var margin = MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	panel.add_child(margin)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	box.add_child(_label("星灯岛 · 版本更新", 16, CYAN))
	_update_version_label = _label("发现新版本", 28, GOLD)
	_update_version_label.name = "UpdateVersion"
	_update_version_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_version_label.max_lines_visible = 2
	box.add_child(_update_version_label)
	_update_notes_label = _paragraph("", 19, CREAM)
	_update_notes_label.name = "UpdateNotes"
	_update_notes_label.max_lines_visible = 4
	_update_notes_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_update_notes_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_update_notes_label)
	box.add_child(_paragraph("下载页面将在浏览器中打开，由你选择是否下载和安装。", 15))
	var actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	var later = _button("稍后", _hide_update_result, Vector2(132, 48))
	later.name = "UpdateLater"
	actions.add_child(later)
	_update_download_button = _button("前往下载", _request_update_download, Vector2(190, 48))
	_update_download_button.name = "UpdateDownload"
	actions.add_child(_update_download_button)
	update_screen.hide()

func _request_update_check() -> void:
	if _update_checking: return
	set_update_checking(true)
	update_check_requested.emit()

func set_update_checking(checking: bool) -> void:
	_update_checking = checking
	update_check_button.disabled = checking
	update_check_button.text = "检查中…" if checking else "检查更新"

func show_update_result(info: Dictionary, manual: bool = true) -> void:
	set_update_checking(false)
	var error = str(info.get("error", ""))
	if not error.is_empty():
		if manual: toast("检查更新失败：" + error.left(90))
		return
	if not bool(info.get("available", false)):
		if manual: toast("当前已是最新版本")
		return
	# An HTTP reply may arrive after the player has already started a game.
	if not title_screen.visible or dialog_screen.visible:
		_pending_update_info = info.duplicate(true)
		return
	_show_update_available(info)

func _show_update_available(info: Dictionary) -> void:
	_cancel_touch_controls()
	_update_info = info.duplicate(true)
	_pending_update_info = {}
	_update_download_sent = false
	var version = str(info.get("version", ""))
	_update_version_label.text = "发现新版本" + ("  " + (version if version.begins_with("v") else "v" + version) if not version.is_empty() else "")
	var notes = str(info.get("notes", "")).strip_edges()
	_update_notes_label.text = notes.left(320) if not notes.is_empty() else "新版本已经发布。前往下载页面查看更新说明。"
	_update_download_button.text = "前往下载"
	_update_download_button.disabled = str(info.get("download_url", "")).is_empty()
	toast_time = 0; toast_panel.hide()
	update_screen.show()

func _request_update_download() -> void:
	if _update_download_sent or str(_update_info.get("download_url", "")).is_empty(): return
	_update_download_sent = true
	_update_download_button.disabled = true
	_update_download_button.text = "已打开下载页"
	update_download_requested.emit(_update_info.duplicate(true))

func _hide_update_result() -> void:
	if is_instance_valid(update_screen): update_screen.hide()

func _build_pause() -> void:
	pause_screen = _full(root, "PauseMenu")
	pause_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade = ColorRect.new()
	shade.color = Color("071a25d9")
	pause_screen.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel = _panel(pause_screen, Vector2.ZERO, Vector2(1100, 602), GOLD)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_anchor_rect(panel, Control.PRESET_CENTER, Vector2(-550, -301), Vector2(1100, 602))
	var title = _label("旅途手记", 30, GOLD)
	title.position = Vector2(28, 22)
	panel.add_child(title)
	var sub = _label("歇一会儿，星光会等你。", 16, MUTED)
	sub.position = Vector2(198, 33)
	panel.add_child(sub)
	var resume = _button("继续冒险  →", func(): resume_requested.emit(), Vector2(158, 44))
	resume.position = Vector2(910, 22)
	panel.add_child(resume)
	var tabs = VBoxContainer.new()
	tabs.position = Vector2(28, 100)
	tabs.size = Vector2(168, 450)
	tabs.add_theme_constant_override("separation", 14)
	panel.add_child(tabs)
	for entry in [["map", "✧  星灯地图"], ["equipment", "◇  装备与强化"], ["supplies", "✦  补给与龙术"], ["settings", "☷  操作与设置"]]:
		var tab_id: String = entry[0]
		var b = _button(entry[1], func(): pause_tab = tab_id; refresh_pause(), Vector2(168, 55))
		tabs.add_child(b)
	var separator = HSeparator.new()
	tabs.add_child(separator)
	tabs.add_child(_button("返回标题", show_title, Vector2(168, 44)))
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(220, 92)
	scroll.size = Vector2(850, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	pause_content = VBoxContainer.new()
	pause_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_content.add_theme_constant_override("separation", 12)
	scroll.add_child(pause_content)
	pause_screen.hide()

func _build_dialog() -> void:
	dialog_screen = _full(root, "StoryDialog")
	dialog_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade = ColorRect.new()
	shade.color = Color("061a26bf")
	dialog_screen.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog_screen.hide()
	dialog_screen.visibility_changed.connect(func():
		if not dialog_screen.visible: _stop_story_audio())

func show_title() -> void:
	_cancel_touch_controls()
	_release_stick()
	_dismiss_dialog(false, false)
	get_tree().paused = true
	continue_button.disabled = not campaign.has_save
	_update_difficulty_choice()
	hud_visible = false
	hud.hide()
	pause_screen.hide()
	dialog_screen.hide()
	title_screen.show()
	if not _pending_update_info.is_empty(): _show_update_available(_pending_update_info)

func show_hud() -> void:
	_hide_update_result()
	_cancel_touch_controls()
	_dismiss_dialog(false, false)
	title_screen.hide()
	pause_screen.hide()
	dialog_screen.hide()
	hud.show()
	hud_visible = true
	joystick.queue_redraw()

func update_hud(hp: float, max_hp: float, goal: String, detail: String, context: String, cooldown: float, progress_text: String) -> void:
	if hp_bar.max_value != max_hp: hp_bar.max_value = max_hp
	if hp_bar.value != hp: hp_bar.value = hp
	var crystals = int(campaign.crystals)
	if _hud_hp != int(hp) or _hud_max_hp != int(max_hp) or _hud_crystals != crystals:
		_hud_hp = int(hp); _hud_max_hp = int(max_hp); _hud_crystals = crystals
		hp_label.text = "%d / %d     星晶 %d" % [_hud_hp, _hud_max_hp, crystals]
	if _hud_xp != int(campaign.xp):
		_hud_xp = int(campaign.xp)
		level_label.text = "Lv.%d · 星契伙伴" % campaign.level()
	if goal_label.text != goal: goal_label.text = goal
	if detail_label.text != detail: detail_label.text = detail
	if chapter_label.text != progress_text: chapter_label.text = progress_text
	_update_character_hud(int(campaign.active_character))
	var tenth = roundi(cooldown * 10.0) if cooldown > 0.05 and context in COOLDOWN_CONTEXTS else -1
	if context != _hud_context or tenth != _hud_cooldown_tenth:
		_hud_context = context; _hud_cooldown_tenth = tenth
		context_button.text = "%.1fs\n%s" % [cooldown, context] if tenth >= 0 else "✦\n" + context

func _update_character_hud(character: int) -> void:
	if _hud_character == character: return
	_hud_character = character
	attack_button.text = "剑·盾\n攻击" if character == 0 else "星矢\n攻击"
	for i in portraits.size():
		portraits[i].add_theme_stylebox_override("normal", _portrait_active_style if i == character else _portrait_idle_style)

func show_pause() -> void:
	_cancel_touch_controls()
	_release_stick()
	pause_screen.show()
	refresh_pause()

func hide_pause() -> void:
	pause_screen.hide()
	_stop_story_audio()

func refresh_pause() -> void:
	for node in pause_content.get_children():
		pause_content.remove_child(node)
		node.queue_free()
	if pause_tab == "map":
		_build_map_content()
	elif pause_tab == "equipment":
		_build_equipment_content()
	elif pause_tab == "supplies":
		_build_supplies_content()
	else:
		_build_settings_content()

func _paragraph(text: String, size: int = 18, color: Color = MUTED) -> Label:
	var l = _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _build_map_content() -> void:
	pause_content.add_child(_label("点亮的星灯，都是可以回来的地方", 23, GOLD))
	pause_content.add_child(_paragraph("轻点右上小地图或按 M 查看当前区域；下面选择已开放的章节即可回访。主线经验与源晶首次获得后不会重复发放。"))
	for ch in 7:
		var first = campaign.stage_data(ch * 3)
		pause_content.add_child(_label(str(first.get("chapter_name", "第 %d 章" % ch)), 20, CYAN))
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		pause_content.add_child(row)
		for step in 3:
			var index = ch * 3 + step
			var data = campaign.stage_data(index)
			var done = campaign.completed.has(data.get("id", "")) or campaign.completed.has(index)
			var text = ("✓ " if done else ("◆ " if index == campaign.stage else "")) + str(data.get("name", "关卡 %d" % (index + 1)))
			var b = _button(text, func(): stage_requested.emit(index), Vector2(0, 55))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 16)
			b.disabled = index > campaign.progress
			row.add_child(b)

func _build_equipment_content() -> void:
	pause_content.add_child(_label("把星光装进行囊", 24, GOLD))
	pause_content.add_child(_paragraph("星晶 %d · 强化按槽位保留，更换同类装备继承强化。重置返还全部星晶。" % campaign.crystals))
	for pair in [["weapon", "武器"], ["armor", "护甲"], ["accessory", "饰品"]]:
		var slot: String = pair[0]
		var heading = HBoxContainer.new()
		pause_content.add_child(heading)
		var text = _label(str(pair[1]) + "  +%d" % int(campaign.upgrades.get(slot, 0)), 20, CYAN)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(text)
		var up = int(campaign.upgrades.get(slot, 0))
		var uptext = "已强化至 +3" if up >= 3 else "强化  ·  %d 星晶" % [10, 20, 35][up]
		var upgrade_button = _button(uptext, func(): upgrade_requested.emit(slot); refresh_pause(), Vector2(180, 40))
		upgrade_button.disabled = up >= 3 or campaign.crystals < ([10, 20, 35][mini(up, 2)])
		heading.add_child(upgrade_button)
		var items = campaign.available_equipment(slot)
		if items.is_empty():
			pause_content.add_child(_paragraph("在接下来的旅途中寻找。"))
		for item in items:
			var item_id = str(item.get("id", ""))
			var active = str(campaign.equipped.get(slot, "")) == item_id
			var text_value = ("◆ 已装备  " if active else "装备  ") + str(item.get("name", item_id))
			var b = _button(text_value, func(): equip_requested.emit(slot, item_id); refresh_pause(), Vector2(0, 42))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if active:
				b.add_theme_color_override("font_color", GOLD)
			pause_content.add_child(b)
			pause_content.add_child(_paragraph(str(item.get("description", "")), 15))
	var artifacts = HBoxContainer.new()
	artifacts.add_theme_constant_override("separation", 12)
	pause_content.add_child(artifacts)
	for pair in [["shield", "盾震强化"], ["bell", "星矢强化"]]:
		var slot: String = pair[0]
		var up = int(campaign.upgrades.get(slot, 0))
		var b = _button(str(pair[1]) + " +%d  ·  " % up + ("已满级" if up >= 3 else "%d 星晶" % [10, 20, 35][up]), func(): upgrade_requested.emit(slot); refresh_pause(), Vector2(0, 46))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = up >= 3 or campaign.crystals < [10, 20, 35][mini(up, 2)]
		artifacts.add_child(b)
	pause_content.add_child(_button("免费重置强化 · 返还全部投入", func(): reset_upgrades_requested.emit(); refresh_pause(), Vector2(0, 46)))

func _build_supplies_content() -> void:
	pause_content.add_child(_label("让小龙的星光继续发亮", 24, GOLD))
	pause_content.add_child(_paragraph("补给只在暂停中使用；队伍共享生命。点亮星灯会恢复生命，并将红星果补足至 2 个。"))
	pause_content.add_child(_button("红星果 × %d   ·   恢复队伍生命" % campaign.fruits, func(): fruit_requested.emit(); refresh_pause(), Vector2(0, 58)))
	pause_content.add_child(_label("战斗龙术", 22, CYAN))
	pause_content.add_child(_paragraph("战斗期间右侧小键保持当前龙术。脱战并面向机关时，才会切换成互动。"))
	for skill in campaign.available_skills():
		var id = str(skill)
		var selected = campaign.selected_skill == id
		var b = _button(("◆ 当前  " if selected else "选择  ") + campaign.skill_name(id), func(): skill_requested.emit(id); refresh_pause(), Vector2(0, 50))
		if selected:
			b.add_theme_color_override("font_color", GOLD)
		pause_content.add_child(b)
	pause_content.add_child(_paragraph("源晶能力随故事获得。通关依靠实战、障碍冲刺、攻击封印和护送；没有站位摇铃式的解锁要求。", 16))

func _build_settings_content() -> void:
	pause_content.add_child(_label("按自己的步调冒险", 24, GOLD))
	_build_audio_settings()
	for pair in [["gentle", "小小守护者", "更充足的生命与较低伤害，适合练习走位和招式。"], ["explorer", "星灯探险家 · 推荐", "新版默认难度。妖怪攻击提高，利用掩体和收招窗口。"], ["brave", "勇敢冒险家", "更高伤害与更快陷阱节奏，适合熟悉协作后挑战。"]]:
		var id: String = pair[0]
		var b = _button(("◆ " if campaign.difficulty == id else "") + str(pair[1]), func(): difficulty_requested.emit(id); refresh_pause(), Vector2(0, 44))
		pause_content.add_child(b)
		pause_content.add_child(_paragraph(pair[2], 16))
	pause_content.add_child(_label("两只拇指，就能出发", 22, CYAN))
	pause_content.add_child(_paragraph("左下浮动摇杆移动；右下大键攻击，小键使用龙术或互动。点左上头像切换旺仔与小馒头。战斗时，小技能键不会被机关抢占。", 18, CREAM))
	pause_content.add_child(_label("三段连击，各有节奏", 21, CYAN))
	pause_content.add_child(_paragraph("旺仔使用近战剑盾：起手斩、横扫、第三式盾震。小馒头发射远程星矢，第三式附带星爆干扰。连续轻点同一个攻击键衔接下一式；星矢和近战都能击破试炼靶标。", 17))
	pause_content.add_child(_paragraph("每次未避开的妖怪攻击，至少扣除最大生命的四分之一，自动格挡和护甲不能把它降到此数以下。观察起手、移出预警区域，再抓住收招反击；主动水罩和受击保护仍然有效。", 17))
	pause_content.add_child(_label("把整片区域慢慢走遍", 21, CYAN))
	pause_content.add_child(_paragraph("轻点右上小地图展开区域；星纹目标分散在不同位置，可自由选择路线。支路藏着宝箱，营地会恢复生命并记录重生位置。观察机关的运动与间隔，寻找安全的绕行路线或关闭开关。", 17))
	pause_content.add_child(_paragraph("电脑操作：WASD / 方向键移动 · J 连击 · K 技能或互动 · Tab 切换 · M 区域地图 · Esc 暂停或继续。", 17))
	pause_content.add_child(_paragraph("倒下会回到最近星灯；不扣等级、晶石或装备。普通妖怪在休息后刷新。", 17))
	pause_content.add_child(_button("重新开始冒险…", func(): show_dialog("重新开始冒险", "这会重新开始主线旅程，并清除当前的本地冒险进度。", "确认重新开始", func(): new_game_requested.emit()), Vector2(0, 44)))

func _build_audio_settings() -> void:
	pause_content.add_child(_label("音乐与剧情朗读", 22, CYAN))
	if is_instance_valid(audio_controller) and audio_controller.has_method("settings"):
		var values = audio_controller.call("settings")
		if values is Dictionary:
			for key in _audio_values:
				if values.has(key):
					_audio_values[key] = values[key]
	for pair in [["music", "背景音乐"], ["sfx", "动作音效"], ["voice", "剧情语音"]]:
		var kind: String = pair[0]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		pause_content.add_child(row)
		var caption = _label(str(pair[1]), 18, CREAM)
		caption.custom_minimum_size = Vector2(110, 44)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(caption)
		var slider = HSlider.new()
		slider.name = kind.capitalize() + "Volume"
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = clampf(float(_audio_values.get(kind + "_volume", 1.0)), 0.0, 1.0)
		slider.custom_minimum_size = Vector2(240, 44)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.focus_mode = Control.FOCUS_NONE
		row.add_child(slider)
		var amount = _label("%d%%" % roundi(slider.value * 100), 18, GOLD)
		amount.custom_minimum_size = Vector2(62, 44)
		amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amount)
		slider.value_changed.connect(func(value: float):
			_audio_values[kind + "_volume"] = value
			amount.text = "%d%%" % roundi(value * 100)
			audio_setting_changed.emit(kind, value))
	var voice = _button("", func(): pass, Vector2(0, 46))
	voice.name = "VoiceEnabled"
	voice.text = "剧情朗读：" + ("开启" if bool(_audio_values.voice_enabled) else "关闭")
	voice.pressed.connect(func():
		_audio_values.voice_enabled = not bool(_audio_values.voice_enabled)
		voice.text = "剧情朗读：" + ("开启" if bool(_audio_values.voice_enabled) else "关闭")
		audio_setting_changed.emit("voice_enabled", bool(_audio_values.voice_enabled)))
	pause_content.add_child(voice)
	pause_content.add_child(_paragraph("剧情语音随窗口播放，可随时暂停、重听或跳过；继续旅程无需等待朗读结束。", 16))
	pause_content.add_child(HSeparator.new())

func show_dialog(title: String, body: String, button_text: String, callback: Callable, story_id: String = "", narration_text: String = "") -> void:
	_hide_update_result()
	_cancel_touch_controls()
	_release_stick()
	# Replacing a modal preserves the pause state from before the first modal.
	if not dialog_screen.visible:
		was_paused = get_tree().paused
	_stop_story_audio()
	_dialog_serial += 1
	var serial = _dialog_serial
	get_tree().paused = true
	dialog_callback = callback
	for child in dialog_screen.get_children():
		if child is PanelContainer:
			dialog_screen.remove_child(child)
			child.queue_free()
	var panel = PanelContainer.new()
	panel.name = "DialogPanel"
	panel.add_theme_stylebox_override("panel", _style(DEEP, GOLD, 24, 2))
	dialog_screen.add_child(panel)
	var is_story = not story_id.is_empty()
	var height = 488.0 if is_story else 410.0
	_anchor_rect(panel, Control.PRESET_CENTER, Vector2(-410, -height / 2), Vector2(820, height))
	panel.custom_minimum_size = Vector2(820, 0)
	var margin = MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	panel.add_child(margin)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 14 if is_story else 18)
	margin.add_child(v)
	v.add_child(_label("✦  星光手记", 16, CYAN))
	var heading = _label(title, 30, GOLD)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.max_lines_visible = 2
	v.add_child(heading)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 152 if is_story else 172)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var text = _paragraph(body, 22, CREAM)
	text.add_theme_constant_override("line_spacing", 8)
	scroll.add_child(text)
	if is_story:
		_active_story_id = story_id
		var audio_row = HBoxContainer.new()
		audio_row.name = "StoryAudioControls"
		audio_row.add_theme_constant_override("separation", 12)
		v.add_child(audio_row)
		_story_audio_label = _label("准备朗读…", 16, MUTED)
		_story_audio_label.name = "NarrationState"
		_story_audio_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_story_audio_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_story_audio_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		audio_row.add_child(_story_audio_label)
		_story_toggle_button = _button("播放朗读", func(): narration_toggle_requested.emit(), Vector2(142, 46))
		_story_toggle_button.name = "NarrationToggle"
		audio_row.add_child(_story_toggle_button)
		_story_replay_button = _button("重新朗读", func(): narration_replay_requested.emit(), Vector2(142, 46))
		_story_replay_button.name = "NarrationReplay"
		audio_row.add_child(_story_replay_button)
		set_story_audio_state("idle")
	var actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	v.add_child(actions)
	if title == "重新开始冒险":
		actions.add_child(_button("保留当前旅程", func():
			if serial == _dialog_serial: _dismiss_dialog(false), Vector2(190, 48)))
	if is_story:
		var skip = _button("跳过剧情", func(): _close_dialog_if_current(serial), Vector2(150, 48))
		skip.name = "SkipStory"
		actions.add_child(skip)
	var advance = _button(button_text, func(): _close_dialog_if_current(serial), Vector2(190, 48))
	advance.name = "ContinueDialog"
	actions.add_child(advance)
	dialog_screen.show()
	if is_story:
		story_opened.emit(story_id, narration_text if not narration_text.is_empty() else body)

func set_story_audio_state(state: String) -> void:
	story_audio_state = state
	if _active_story_id.is_empty() or not is_instance_valid(_story_audio_label):
		return
	var labels = {"idle": "准备朗读", "playing": "正在朗读…", "paused": "朗读已暂停", "finished": "朗读已结束", "unavailable": "本段暂无语音，可继续旅程", "disabled": "剧情朗读已关闭"}
	_story_audio_label.text = str(labels.get(state, "准备朗读"))
	_story_toggle_button.text = "暂停朗读" if state == "playing" else ("继续朗读" if state == "paused" else "播放朗读")
	var unavailable = state in ["unavailable", "disabled"]
	_story_toggle_button.disabled = unavailable
	_story_replay_button.disabled = unavailable

func _stop_story_audio() -> void:
	if _active_story_id.is_empty():
		return
	_active_story_id = ""
	story_audio_state = "idle"
	_story_audio_label = null
	_story_toggle_button = null
	_story_replay_button = null
	story_closed.emit()

func _close_dialog_if_current(serial: int) -> void:
	if serial == _dialog_serial:
		_close_dialog()

func _dismiss_dialog(run_callback: bool, restore_pause: bool = true) -> void:
	var visible_modal = dialog_screen.visible
	var callback = dialog_callback
	dialog_callback = Callable()
	_dialog_serial += 1
	dialog_screen.hide()
	if visible_modal and restore_pause:
		get_tree().paused = was_paused
	_stop_story_audio()
	if visible_modal and run_callback and callback.is_valid():
		callback.call()

func _close_dialog() -> void:
	_dismiss_dialog(true)

func toast(message: String) -> void:
	toast_label.text = message
	toast_time = 3.7
	toast_panel.modulate.a = 1.0
	toast_panel.show()

func _process(delta: float) -> void:
	if toast_time > 0:
		toast_time -= delta
		toast_panel.modulate.a = minf(1.0, toast_time * 2)
		if toast_time <= 0:
			toast_panel.hide()

func _draw_joystick() -> void:
	if stick_id < 0 and not mouse_stick:
		stick_origin = Vector2(142, root.size.y - 142)
	joystick.draw_circle(stick_origin + Vector2(0, 5), 77, Color("061c2899"))
	joystick.draw_circle(stick_origin, 74, Color("183f4677"))
	joystick.draw_arc(stick_origin, 74, 0, TAU, 80, Color("e6c783aa"), 2.0, true)
	joystick.draw_arc(stick_origin, 58, 0, TAU, 64, Color("abdac933"), 1.0, true)
	joystick.draw_circle(stick_origin + stick_offset, 31, Color("f0dfb49e"))
	joystick.draw_arc(stick_origin + stick_offset, 31, 0, TAU, 40, GOLD, 1.5, true)
	joystick.draw_circle(stick_origin + stick_offset - Vector2(5, 6), 20, Color("fff3cf22"))
	if ui_font != null:
		joystick.draw_string(ui_font, stick_origin + Vector2(-16, 104), "移动", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, CREAM)

func _input(event: InputEvent) -> void:
	# The UI continues processing while the simulation is paused.
	if update_screen.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if event.keycode == KEY_ESCAPE: _hide_update_result()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and dialog_screen.visible and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_close_dialog()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if dialog_screen.visible:
			get_viewport().set_input_as_handled()
			return
		if pause_screen.visible:
			resume_requested.emit()
		elif hud_visible:
			_release_stick()
			pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	# Godot's mouse emulation is disabled so each finger retains its own identity.
	# Dispatch button touch events explicitly; the movement finger can remain held.
	if event is InputEventScreenTouch:
		if not event.pressed and touch_sliders.has(event.index):
			var slider = touch_sliders[event.index]
			touch_sliders.erase(event.index)
			if not event.canceled and is_instance_valid(slider) and slider.is_visible_in_tree():
				_touch_slider_value(slider, event.position)
			get_viewport().set_input_as_handled()
			return
		if not event.pressed and (touch_buttons.has(event.index) or touch_scrolls.has(event.index)):
			var b = touch_buttons.get(event.index)
			var was_dragging = touch_scrolls.get(event.index, {}).get("dragging", false)
			touch_buttons.erase(event.index)
			touch_scrolls.erase(event.index)
			if is_instance_valid(b):
				b.set_pressed_no_signal(false)
				if event.canceled and b == context_button: _release_context(true)
				b.button_up.emit()
				if not event.canceled and not was_dragging and is_instance_valid(b) and b.action_mode == BaseButton.ACTION_MODE_BUTTON_RELEASE and b.is_visible_in_tree() and not b.disabled and b.get_global_rect().has_point(event.position):
					b.pressed.emit()
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			var slider = _find_touch_slider(_touch_surface(), event.position)
			if slider != null:
				touch_sliders[event.index] = slider
				_touch_slider_value(slider, event.position)
				get_viewport().set_input_as_handled()
				return
			var scroller = _find_touch_scroller(_touch_surface(), event.position)
			if scroller != null:
				touch_scrolls[event.index] = {"node": scroller, "origin": event.position, "initial": scroller.scroll_vertical, "dragging": false}
			var b = _touch_button_at(event.position)
			if b != null:
				touch_buttons[event.index] = b
				b.set_pressed_no_signal(true)
				b.button_down.emit()
				if is_instance_valid(b) and b.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS and b.is_visible_in_tree() and not b.disabled:
					b.pressed.emit()
				get_viewport().set_input_as_handled()
				return
			if scroller != null:
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventScreenDrag and touch_sliders.has(event.index):
		var slider = touch_sliders[event.index]
		if is_instance_valid(slider) and slider.is_visible_in_tree():
			_touch_slider_value(slider, event.position)
		get_viewport().set_input_as_handled()
		return
	elif event is InputEventScreenDrag and (touch_buttons.has(event.index) or touch_scrolls.has(event.index)):
		var was_dragging = false
		if touch_scrolls.has(event.index):
			var scroll_state = touch_scrolls[event.index]
			if event.position.distance_to(scroll_state.origin) > 12:
				scroll_state.dragging = true
			was_dragging = scroll_state.dragging
			if was_dragging and is_instance_valid(scroll_state.node):
				scroll_state.node.scroll_vertical = scroll_state.initial + int(scroll_state.origin.y - event.position.y)
		var b = touch_buttons.get(event.index)
		if is_instance_valid(b):
			b.set_pressed_no_signal(not was_dragging and b.get_global_rect().has_point(event.position))
		get_viewport().set_input_as_handled()
		return
	if not hud_visible or pause_screen.visible or dialog_screen.visible or get_tree().paused:
		return
	var screen = root.size
	if event is InputEventScreenTouch:
		if event.pressed and stick_id == -1 and event.position.x < screen.x * 0.42 and event.position.y > screen.y * 0.48:
			stick_id = event.index
			stick_origin = _clamp_stick(event.position)
			_update_stick(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == stick_id:
			_release_stick()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == stick_id:
		_update_stick(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and stick_id == -1 and event.position.x < screen.x * 0.42 and event.position.y > screen.y * 0.48:
			mouse_stick = true
			stick_origin = _clamp_stick(event.position)
			_update_stick(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and mouse_stick:
			_release_stick()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and mouse_stick:
		_update_stick(event.position)
		get_viewport().set_input_as_handled()

func _touch_button_at(point: Vector2) -> Button:
	return _find_touch_button(_touch_surface(), point)

func _find_touch_slider(node: Node, point: Vector2) -> HSlider:
	if node is Control and (not node.is_visible_in_tree() or (node.clip_contents and not node.get_global_rect().has_point(point))):
		return null
	for child in node.get_children():
		var slider = _find_touch_slider(child, point)
		if slider != null:
			return slider
	if node is HSlider and node.editable and node.get_global_rect().has_point(point):
		return node
	return null

func _touch_slider_value(slider: HSlider, point: Vector2) -> void:
	var rect = slider.get_global_rect()
	var grabber = slider.get_theme_icon("grabber")
	var inset = maxf(8.0, float(grabber.get_width()) * 0.5) if grabber != null else 8.0
	var fraction = clampf((point.x - rect.position.x - inset) / maxf(1.0, rect.size.x - inset * 2), 0.0, 1.0)
	slider.value = lerpf(slider.min_value, slider.max_value, fraction)

func _touch_surface() -> Control:
	var surface = hud
	if update_screen.visible:
		surface = update_screen
	elif dialog_screen.visible:
		surface = dialog_screen
	elif pause_screen.visible:
		surface = pause_screen
	elif title_screen.visible:
		surface = title_screen
	return surface

func _find_touch_scroller(node: Node, point: Vector2) -> ScrollContainer:
	if node is Control and (not node.is_visible_in_tree() or (node.clip_contents and not node.get_global_rect().has_point(point))):
		return null
	for child in node.get_children():
		var scroller = _find_touch_scroller(child, point)
		if scroller != null:
			return scroller
	if node is ScrollContainer and node.get_global_rect().has_point(point):
		return node
	return null

func _find_touch_button(node: Node, point: Vector2) -> Button:
	if node is Control:
		if not node.is_visible_in_tree():
			return null
		if node.clip_contents and not node.get_global_rect().has_point(point):
			return null
	var children = node.get_children()
	children.reverse()
	for child in children:
		var match_button = _find_touch_button(child, point)
		if match_button != null:
			return match_button
	if node is Button and not node.disabled and node.mouse_filter != Control.MOUSE_FILTER_IGNORE and node.get_global_rect().has_point(point):
		return node
	return null

func _cycle_difficulty() -> void:
	var modes = ["gentle", "explorer", "brave"]
	var next = (modes.find(campaign.difficulty) + 1) % modes.size()
	difficulty_requested.emit(modes[next])
	_update_difficulty_choice()

func _update_difficulty_choice() -> void:
	var names = {"gentle": "小小守护者", "explorer": "星灯探险家 · 推荐", "brave": "勇敢冒险家"}
	difficulty_choice.text = names.get(campaign.difficulty, "星灯探险家 · 推荐") + "   ↻"

func _clamp_stick(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 80, root.size.x * 0.4), clampf(p.y, root.size.y * 0.52, root.size.y - 92))

func _update_stick(p: Vector2) -> void:
	stick_offset = (p - stick_origin).limit_length(48)
	var next_direction = stick_offset / 48.0
	if next_direction.length() < 0.12:
		next_direction = Vector2.ZERO
	if direction != next_direction:
		direction = next_direction
		move_changed.emit(direction)
	joystick.queue_redraw()

func _release_stick() -> void:
	stick_id = -1
	mouse_stick = false
	stick_offset = Vector2.ZERO
	direction = Vector2.ZERO
	move_changed.emit(Vector2.ZERO)
	if is_instance_valid(joystick): joystick.queue_redraw()

func _press_context() -> void:
	if _context_is_down: return
	_context_is_down = true
	context_pressed.emit()

func _release_context(cancelled: bool = false) -> void:
	if not _context_is_down: return
	_context_is_down = false
	if cancelled: context_cancelled.emit()
	else: context_released.emit()

func _cancel_touch_controls() -> void:
	var held = touch_buttons.values()
	touch_buttons.clear(); touch_scrolls.clear(); touch_sliders.clear()
	# Cancel before button_up, which otherwise commits a normal interaction.
	_release_context(true)
	for button in held:
		if is_instance_valid(button):
			button.set_pressed_no_signal(false)
			button.button_up.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_stick()
		_cancel_touch_controls()
