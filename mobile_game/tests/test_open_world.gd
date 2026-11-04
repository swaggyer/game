extends SceneTree
## Run only with a workspace APPDATA; this suite never loads the gameplay or player save.

const World = preload("res://scripts/open_world.gd")
var failures:Array[String]=[]
var checks:=0
var world:Node2D
var signatures:Array=[]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world=World.new()
	root.add_child(world)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_regions()
		world.queue_free()
		await process_frame
		quit(0)
		return
	for chapter in range(7):
		for stage in range(3):
			world.configure(chapter,stage)
			await process_frame
			_check_definition(chapter,stage)
			_check_navigation(chapter,stage)
			_check_hazards(chapter,stage)
			if stage==0:signatures.append(_topology_signature())
	_check(signatures.size()==7,"seven topology samples exist")
	for a in range(signatures.size()):
		for b in range(a+1,signatures.size()):
			_check(signatures[a]!=signatures[b],"regions %d and %d have distinct solid/water topology"%[a,b])
	_check_collision_examples()
	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("OPEN WORLD TESTS PASSED: %d checks"%checks)
		quit(0)
	else:
		for failure in failures:printerr("FAIL: "+failure)
		printerr("OPEN WORLD TESTS FAILED: %d failures / %d checks"%[failures.size(),checks])
		quit(1)

func _check_definition(chapter:int,stage:int) -> void:
	var d:Dictionary=world.definition
	var label:="region %d stage %d"%[chapter,stage]
	_check(d.has_all(["spawn","lamp","objectives","zones","chests","camps","patrols","hazards"]),label+" descriptor has all gameplay fields")
	_check(d.objectives.size()==3 and d.chests.size()==4 and d.camps.size()==2,label+" three objectives, four exploration chests and two camps")
	_check(d.zones.size()>=5,label+" multiple named zones")
	var overview:Dictionary=world.get_overview()
	_check(overview.bounds==Rect2(100,100,3400,2400),label+" fixed open-world bounds")
	_check(overview.paths.size()>=3,label+" multiple path loops and cross-connections")
	_check(not world.is_walkable(Vector2(50,50)),label+" outside region is blocked")
	if chapter==6 or (chapter==0 and stage==0):
		_check(d.hazards.is_empty() and d.patrols.is_empty(),label+" story introduction / epilogue is safe")
	else:
		_check(d.patrols.size()>=4,label+" several exploration patrols")

func _check_navigation(chapter:int,stage:int) -> void:
	var d:Dictionary=world.definition
	var label:="region %d stage %d"%[chapter,stage]
	var points:Array=[d.spawn,d.lamp]
	points.append_array(d.objectives)
	points.append_array(d.chests)
	points.append_array(d.camps)
	for i in range(points.size()):
		var target:Vector2=points[i]
		_check(world.is_walkable(target,24),label+" required point %d has actor clearance at %s"%[i,str(target)])
		var path:PackedVector2Array=world.find_path(d.spawn,target)
		_check(not path.is_empty(),label+" required point %d reachable from spawn"%i)
		if not path.is_empty():
			_check(path[path.size()-1].distance_to(target)<2,label+" navigation reaches exact point %d"%i)
			var safe:=true
			for j in range(path.size()-1):
				for fraction in [0.0,0.25,0.5,0.75,1.0]:
					if not world.is_walkable(path[j].lerp(path[j+1],fraction),20):safe=false
			_check(safe,label+" path to point %d stays clear of geometry at actor radius"%i)
	# Objectives can be visited in any order, not only along a linear scripted route.
	for a in range(3):
		for b in range(3):
			if a!=b:_check(not world.find_path(d.objectives[a],d.objectives[b]).is_empty(),label+" objective %d -> %d connected"%[a,b])
	var rescued:Vector2=world.nearest_safe(Vector2(0,0))
	_check(world.is_walkable(rescued,20),label+" nearest_safe returns traversable position")
	var open_cells:=0
	for y in range(350,2300,250):
		for x in range(350,3300,250):
			if world.is_walkable(Vector2(x,y),20):open_cells+=1
	_check(open_cells>=35,label+" broad explorable area extends beyond a single road")

func _check_hazards(chapter:int,stage:int) -> void:
	var d:Dictionary=world.definition
	var label:="region %d stage %d"%[chapter,stage]
	var safe_points:Array=[d.spawn,d.lamp]
	safe_points.append_array(d.objectives);safe_points.append_array(d.camps)
	for hazard:Dictionary in d.hazards:
		_check(hazard.kind in ["spikes","firejet","pendulum","shooter","whirlpool","collapse"],label+" known trap kind")
		_check(world.is_walkable(hazard.p,20),label+" trap is on playable ground")
		for safe:Vector2 in safe_points:
			_check(safe.distance_to(hazard.p)>=160,label+" trap does not cover required objective or safe camp")
	for patrol:Dictionary in d.patrols:
		_check(world.is_walkable(patrol.p,20),label+" patrol start is on traversable ground: "+str(patrol.p))

func _topology_signature() -> String:
	var result:=""
	for y in range(300,2400,150):
		for x in range(300,3400,150):result+="1" if world.is_walkable(Vector2(x,y),20) else "0"
	return result

func _check_collision_examples() -> void:
	world.configure(0,0)
	_check(world.is_obstacle(Vector2(1230,750)),"village house has a physical footprint")
	_check(not world.has_line_of_sight(Vector2(1000,750),Vector2(1450,750)),"house blocks enemy line of sight")
	var stopped:Vector2=world.move_actor(Vector2(1010,750),Vector2(520,0),20)
	_check(stopped.x<1090 and world.is_walkable(stopped),"long frame cannot tunnel through a house")
	_check(world.is_water(Vector2(2770,1960)) and not world.is_walkable(Vector2(2770,1960)),"village pond blocks ordinary movement")
	_check(not world.is_obstacle(Vector2(2770,1960)),"water ability may cross pond without treating it as a house")
	world.configure(3,0)
	_check(world.is_water(Vector2(1800,300)),"water region has real water between islands")
	_check(not world.is_water(Vector2(1750,700)) and world.is_walkable(Vector2(1750,700)),"visible upper bridge is a traversable water opening")
	_check(not world.is_walkable(Vector2(1750,500)),"water beside bridge cannot be walked across")
	world.configure(4,0)
	_check(world.is_obstacle(Vector2(1205,600)),"ruin wall is solid")
	_check(world.is_walkable(Vector2(1205,1170)),"ruin doorway remains open")
	world.configure(6,0)
	_check(world.is_water(Vector2(1570,1150)),"island inner pool is solid away from bridge")
	_check(world.is_walkable(Vector2(1800,1320)),"star pool bridge reaches central ceremony platform")

func _check(condition:bool,message:String) -> void:
	checks+=1
	if not condition:failures.append(message)

func _capture_regions() -> void:
	root.size=Vector2i(1280,900)
	root.content_scale_size=Vector2i(1280,900)
	var camera:=Camera2D.new()
	camera.position=Vector2(1800,1300)
	camera.zoom=Vector2.ONE*0.34
	root.add_child(camera)
	for chapter in range(7):
		world.configure(chapter,1)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path:="res://docs/open-region-%d.png"%chapter
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("REGION CAPTURE: "+path)
	camera.queue_free()
