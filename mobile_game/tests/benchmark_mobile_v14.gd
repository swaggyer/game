extends SceneTree
## Same trace runs against a frozen source snapshot and the revised project.
## Native window frame intervals include rendering; headless is CPU-only evidence.
class CountedWorld extends "res://scripts/open_world.gd":
	var path_calls:int=0
	var los_calls:int=0
	var move_calls:int=0
	func find_path(a:Vector2,b:Vector2)->PackedVector2Array:
		path_calls+=1
		return super.find_path(a,b)
	func has_line_of_sight(a:Vector2,b:Vector2)->bool:
		los_calls+=1
		return super.has_line_of_sight(a,b)
	func move_actor(p:Vector2,motion:Vector2,radius:float=20)->Vector2:
		move_calls+=1
		return super.move_actor(p,motion,radius)

var game:Node2D
var world:CountedWorld
var result:Dictionary={}

func _initialize()->void:call_deferred("_run")

func _run()->void:
	Engine.max_fps=0
	root.size=Vector2i(1280,720)
	if DisplayServer.get_name()!="headless":DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	result={"label":OS.get_environment("STARLAN_BENCH_LABEL"),"godot":Engine.get_version_info().string,
		"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"resolution":"1280x720","device":"desktop Windows; NOT an Android device","scenarios":[]}
	var t:int=Time.get_ticks_usec()
	game=load("res://scenes/main.tscn").instantiate()
	game.campaign.save_path="user://benchmark-v14/campaign.json"
	game.audio_director.settings_path="user://benchmark-v14/audio.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://benchmark-v14"))
	root.add_child(game);game.set_process(false)
	result.ready_ms=(Time.get_ticks_usec()-t)/1000.0
	var previous:Node=game.world
	world=CountedWorld.new();game.add_child(world);game.world=world
	game.remove_child(previous);previous.queue_free()
	await process_frame;await process_frame
	game._start(false)
	if game.ui.dialog_screen.visible:game.ui._close_dialog()
	paused=false
	t=Time.get_ticks_usec();game._attack();result.first_attack_ms=(Time.get_ticks_usec()-t)/1000.0
	game.hero_actions.reset()
	var music_times:Dictionary={}
	for context:String in ["battle","boss","explore","title","battle","explore"]:
		t=Time.get_ticks_usec();game.audio_director.set_music_context(context)
		music_times[context+"_"+str(music_times.size())]=(Time.get_ticks_usec()-t)/1000.0
	result.music_switch_ms=music_times
	game.audio_director.set_music_context("explore")
	var frame_count:int=90 if "--quick" in OS.get_cmdline_user_args() else 180
	for stage:int in [0,4,12]:
		t=Time.get_ticks_usec();game._load_stage(stage)
		var load_ms:float=(Time.get_ticks_usec()-t)/1000.0
		if game.ui.dialog_screen.visible:game.ui._close_dialog()
		paused=false;game.invulnerable=999.0
		world.path_calls=0;world.los_calls=0;world.move_calls=0
		for index:int in range(8):await process_frame
		var cpu:Array[float]=[];var frames:Array[float]=[];var draws:Array[float]=[]
		var base:Vector2=game.player.position
		for index:int in range(frame_count):
			game.move_input=Vector2.from_angle(float(index)*TAU/120.0)
			if index%45==0:game._attack()
			game.invulnerable=999.0
			t=Time.get_ticks_usec();game._process(1.0/60.0)
			cpu.append((Time.get_ticks_usec()-t)/1000.0)
			var frame_start:int=Time.get_ticks_usec()
			await process_frame
			frames.append((Time.get_ticks_usec()-frame_start)/1000.0+cpu.back())
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			if paused:
				if game.ui.dialog_screen.visible:game.ui._close_dialog()
				paused=false
		result.scenarios.append({"stage":stage,"frames":frame_count,"stage_load_ms":load_ms,
			"frame_ms":_stats(frames),"main_cpu_ms":_stats(cpu),"draw_calls":_stats(draws),
			"astar_calls":world.path_calls,"los_calls":world.los_calls,"move_calls":world.move_calls,
			"walk_cached":game.locomotion._textures.size(),"attack_cached":game.hero_actions._textures.size(),
			"achieved_distance":game.player.position.distance_to(base)})
		print("BENCH stage%d frame median %.3fms p95 %.3fms; main CPU median %.3fms; A* %d LOS %d"%[stage,_stats(frames).median,_stats(frames).p95,_stats(cpu).median,world.path_calls,world.los_calls])
	game.audio_director.stop_music();game.audio_director.stop_narration();paused=false
	game.hero_actions.game=null;game.locomotion.game=null
	game.queue_free();await process_frame;await process_frame
	game=null;world=null
	var output:String=OS.get_environment("STARLAN_BENCH_OUTPUT")
	if not output.is_empty():
		var file:FileAccess=FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t"));file.close()
	print("MOBILE V1.4 DESKTOP BENCHMARK ",JSON.stringify(result))
	quit(0)

func _stats(values:Array[float])->Dictionary:
	var sorted:Array[float]=values.duplicate();sorted.sort()
	var total:float=0.0
	for value:float in sorted:total+=value
	return {"median":sorted[int(sorted.size()*0.5)],"p95":sorted[mini(sorted.size()-1,int(sorted.size()*0.95))],
		"p99":sorted[mini(sorted.size()-1,int(sorted.size()*0.99))],"maximum":sorted.back(),"mean":total/sorted.size()}
