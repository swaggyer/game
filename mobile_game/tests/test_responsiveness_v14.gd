extends SceneTree
const SAVE="user://responsiveness-v14.json"
var failures:Array=[]
var checks=0
func _initialize()->void:call_deferred("_run")
func _run()->void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.campaign.save_path=SAVE;root.add_child(game);await process_frame
	game._start(false)
	if game.ui.dialog_screen.visible:game.ui._close_dialog()
	game.set_process(false)
	game.player.position=Vector2(800,2000)
	game.enemy_director.clear();game._sync_enemies()
	game.enemy_director.spawn("shadow_blob",game.player.position+Vector2(130,0),false,-1);game._sync_enemies()
	game._context_press()
	_check(not game.pending_skill.is_empty(),"combat skill starts on press without waiting for release")
	var cooldown=game.skill_cd
	game._context_release()
	_check(game.context_latch.is_empty() and game.skill_cd==cooldown,"release clears capture without casting twice")
	game._update_guide();var path=game.guide_path
	game.player.position+=Vector2(1,0);game._update_guide()
	_check(game.guide_path==path,"stationary/nearby player reuses guide route")
	game.campaign.crystals=17;game._queue_autosave()
	game.campaign.crystals=23;game._save_all()
	var saved=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	_check(saved.crystals==23,"critical save cannot be overwritten by an older worker snapshot")
	_check(game.autosave_thread==null,"completed worker joined before synchronous writes")
	game.campaign.crystals=31;game._queue_autosave();game._finish_autosave()
	saved=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	_check(saved.crystals==31,"background autosave persists an isolated snapshot")
	var world_saved=JSON.parse_string(FileAccess.get_file_as_string(SAVE+".world.json"))
	_check(world_saved.version==3 and world_saved.stages.has("0"),"autosave retains current world schema")
	game.campaign.crystals=37;game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	saved=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	_check(saved.crystals==37,"mobile app backgrounding flushes current progress")
	_check(not Input.use_accumulated_input,"input is delivered without per-frame accumulation")
	game.hero_actions.game=null;game.queue_free();await process_frame;await process_frame
	for base in [SAVE,SAVE+".world.json"]:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(base+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(base+suffix))
	for failure in failures:printerr(failure)
	print("RESPONSIVENESS V14: %d checks; %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
