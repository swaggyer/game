extends SceneTree
var game:Node2D
func _initialize()->void:call_deferred("run")
func close_story()->void:
	if game.ui.dialog_screen.visible:game.ui._close_dialog()
	paused=false
func frame(path:String)->void:
	game._update_hud();game.queue_redraw();game.combat_overlay.queue_redraw();game.mini_map.queue_redraw()
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	var shot=root.get_texture().get_image()
	shot.save_png("res://docs/"+path)
func pose()->void:
	game.partner.position=game.world.nearest_safe(game.player.position+Vector2(-75,40))
	game.dragon.position=game.world.nearest_safe(game.player.position+Vector2(-125,15))
	game.locomotion.animate(game.player,"wangzai",Vector2.DOWN,23,0.1)
	game.locomotion.animate(game.partner,"xiaomantou",Vector2.DOWN,29,0.1)
	game.locomotion.animate(game.dragon,"little_dragon",Vector2.RIGHT,35,0.1)
	game.camera.position=game.player.position+Vector2(65,-75);game.camera.reset_smoothing();game._discover()
func run()->void:
	game=load("res://scenes/main.tscn").instantiate();game.campaign.save_path="user://visual-v12.json";root.add_child(game)
	await process_frame
	game._start(false);close_story();game.set_process(false)
	game.player.position=game.world.nearest_safe(Vector2(1300,1450));pose()
	await frame("v12-village.png")
	var shot=root.get_texture().get_image();var crop=shot.get_region(Rect2i(12,10,380,132));crop.resize(1140,396,Image.INTERPOLATE_LANCZOS);crop.save_png("res://docs/v12-portraits-hud.png")
	game.main_trials.begin(0);var state=game.main_trials.states[0]
	game.player.position=game.world.nearest_safe(state.route[0]+Vector2(-60,60));pose()
	await frame("v12-main-course.png")
	game.main_trials.cancel();game._show_area_map();await frame("v12-map.png");game._resume()
	for i in range(3):game.campaign.complete_stage(i)
	game._load_stage(3);close_story();game.set_process(false)
	var challenge=game.challenge_director.challenges[0];game.player.position=challenge.p;pose();game.challenge_director.start(challenge.id)
	await frame("v12-forest-challenge.png")
	for audio in [game.attack_sound,game.chime_sound,game.music]:audio.stop()
	game.hero_actions.game=null;game.locomotion.game=null;game.queue_free();await process_frame;await process_frame
	print("V12_NATIVE_SCREENSHOTS_SAVED");quit(0)
