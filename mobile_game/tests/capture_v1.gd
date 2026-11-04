extends SceneTree
var game:Node2D
func _initialize()->void:call_deferred("run")
func frame(path:String)->void:
	game.queue_redraw();game.combat_overlay.queue_redraw()
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/"+path)
func close_story()->void:
	if game.ui.dialog_screen.visible:game.ui._close_dialog()
	paused=false
func run()->void:
	game=load("res://scenes/main.tscn").instantiate();game.campaign.save_path="user://visual-capture.json";root.add_child(game)
	await process_frame
	await frame("v1-title.png")
	game._start(false);close_story();game.set_process(false)
	game.player.position=game.world.nearest_safe(Vector2(1300,1450));game.partner.position=game.player.position+Vector2(-80,45);game.dragon.position=game.player.position+Vector2(-125,0)
	game.camera.position=game.player.position+Vector2(65,-40);game.camera.reset_smoothing();game._discover();game._update_hud()
	await frame("v1-village.png")
	game._show_area_map();await frame("v1-region-map.png");game._resume()
	for i in range(3):game.campaign.complete_stage(i)
	game._load_stage(3);close_story()
	var enemy=game.enemies[0]
	game.player.position=game.world.nearest_safe(enemy.sprite.position+Vector2(-115,45));game.facing=game.player.position.direction_to(enemy.sprite.position)
	game.partner.position=game.world.nearest_safe(game.player.position+Vector2(-90,55));game.dragon.position=game.world.nearest_safe(game.player.position+Vector2(-140,20))
	game.camera.position=game.player.position+Vector2(100,-70);game.camera.reset_smoothing();game.invulnerable=0
	game.hero_actions.start_attack();game.hero_actions.update(0.16,Vector2.ZERO);game._update_hud()
	await frame("v1-wangzai-combat.png")
	game.hero_actions.reset();game.campaign.active_character=1;game._animate_actor(game.player,1,false,game.facing)
	game._animate_actor(game.partner,0,false,game.facing)
	game.hero_actions.start_attack();game.hero_actions.update(0.29,Vector2.ZERO);game._update_hud()
	await frame("v1-xiaomantou-combat.png")
	for i in range(3,6):game.campaign.complete_stage(i)
	game._load_stage(6);close_story()
	var hazard=game.trap_director.traps[0]
	game.player.position=game.world.nearest_safe(hazard.p+Vector2(-190,130));game.partner.position=game.world.nearest_safe(game.player.position+Vector2(-70,35));game.dragon.position=game.world.nearest_safe(game.player.position+Vector2(-115,0))
	game.camera.position=hazard.p+Vector2(25,-20);game.camera.reset_smoothing();game.trap_director.clock=0;game.trap_director.update(1.65);game._update_hud()
	await frame("v1-traps.png")
	print("V1_SCREENSHOTS_SAVED")
	for audio in [game.attack_sound,game.chime_sound,game.music]:audio.stop()
	game.queue_free();await process_frame;quit()
