extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var failures=[];var count=0
	for hero in ["wangzai","xiaomantou"]:
		for combo in range(3):
			for direction in ["front","back","left","right"]:
				for phase in range(4):
					var path="res://assets/actions/%s_attack_%d_%s_%d.png"%[hero,combo,direction,phase]
					var texture=load(path)
					if not texture is Texture2D:failures.append(path)
					else:count+=1
	var environment_count=0
	var manifest_path="res://assets/environment_v11/manifest.json"
	if not FileAccess.file_exists(manifest_path):failures.append("HQ environment runtime manifest not packed")
	else:
		var manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if manifest is Dictionary and manifest.get("assets") is Dictionary:
			for asset in manifest.assets.values():
				var texture=load(asset.image)
				if texture is Texture2D and texture.get_width()==700:environment_count+=1
				else:failures.append("HQ image missing: "+str(asset.image))
	if environment_count!=12:failures.append("expected 12 HQ environment textures")
	var walk_count=0
	var walk_manifest="res://assets/locomotion_v12/manifest.json"
	if not FileAccess.file_exists(walk_manifest):failures.append("locomotion runtime manifest not packed")
	else:
		var walk=JSON.parse_string(FileAccess.get_file_as_string(walk_manifest))
		for actor in walk.get("actors",{}).values():
			for paths in actor.directions.values():
				for path in paths:
					if load("res://assets/locomotion_v12/"+path) is Texture2D:walk_count+=1
					else:failures.append("missing walk texture: "+path)
			for path in actor.idle.values():
				if load("res://assets/locomotion_v12/"+path) is Texture2D:walk_count+=1
				else:failures.append("missing idle texture: "+path)
	if walk_count!=216:failures.append("expected 216 locomotion textures")
	for hero in ["wangzai","xiaomantou"]:
		if not load("res://assets/portraits_v12/"+hero+".png") is Texture2D:failures.append("anime portrait not packed: "+hero)
	if not FileAccess.file_exists("res://data/challenges_v12.json"):failures.append("21 map challenges not packed")
	var game=load("res://scenes/main.tscn").instantiate()
	game.campaign.save_path="user://packed-qa.json";root.add_child(game)
	await process_frame
	game._start(false)
	if game.ui.dialog_screen.visible:game.ui._close_dialog()
	if not game.active or game.world.WORLD_RECT.size!=Vector2(3400,2400):failures.append("open world entry")
	if game.campaign.difficulty!="explorer":failures.append("new default difficulty not packed")
	if game.campaign.systems.enemies[0].attack!=14:failures.append("new enemy damage not packed")
	if game.challenge_director.challenges.size()!=3:failures.append("region challenges not configured")
	game.invulnerable=0;game.shield_time=0;game.hp=game.campaign.max_hp()
	var previous_hp=game.hp
	game._hurt(1,game.player.position+Vector2(50,0),false,"enemy")
	if previous_hp-game.hp<ceil(game.campaign.max_hp()*0.25):failures.append("quarter HP enemy damage floor not packed")
	game.hero_actions.start_attack();game.hero_actions.update(0.16,Vector2.ZERO)
	game._update_hud()
	if not game.hero_actions.busy or game.player.texture.get_width()!=240:failures.append("packed bone pose not applied")
	if DisplayServer.get_name()!="headless":
		game.set_process(false)
		for i in range(12):await process_frame
		await RenderingServer.frame_post_draw
		var png=OS.get_environment("STARLAN_QA_PNG")
		if not png.is_empty():root.get_texture().get_image().save_png(png)
	game.hero_actions.game=null;game.locomotion.game=null;game.queue_free();await process_frame;await process_frame
	if failures.is_empty():print("PACKED BUILD VERIFIED: %d combat textures, %d HQ environment textures, %d locomotion textures, 2 anime portraits, 21 challenges, quarter HP hits, live main scene"%[count,environment_count,walk_count]);quit(0)
	else:
		for failure in failures:printerr("PACKED FAILURE: "+str(failure))
		quit(1)
