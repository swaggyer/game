extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.campaign.save_path="user://title-v15-test.json";root.add_child(game)
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	var output=OS.get_environment("STARLAN_QA_PNG")
	if not output.is_empty():root.get_texture().get_image().save_png(output)
	if not game.ui.update_check_button.is_visible_in_tree():quit(1);return
	print("PACKED TITLE V15: update button and installed version visible")
	game.hero_actions.game=null;game.locomotion.game=null;game.queue_free();await process_frame;await process_frame;quit()
