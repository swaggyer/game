extends SceneTree
## Isolated optional-level tests. No production save is loaded or written.
const World=preload("res://scripts/open_world.gd")
const ChallengeDirector=preload("res://scripts/challenge_director.gd")
const Campaign=preload("res://scripts/campaign.gd")
var checks:=0
var failures:Array[String]=[]
var game:TestGame
var director
var saved_chapters:Dictionary={}

class TestUI:
	extends RefCounted
	var messages:Array=[]
	func toast(message:String)->void:messages.append(message)

class TestEnemies:
	extends RefCounted
	var enemies:Array=[]
	var projectiles:Array=[]
	var owner_ref:WeakRef
	var serial:=0
	func setup(game:Node2D)->void:owner_ref=weakref(game)
	func spawn(id:String,p:Vector2,boss:bool=false,index:int=-1)->Dictionary:
		serial+=1
		var sprite:=Sprite2D.new();sprite.position=p
		owner_ref.get_ref().add_child(sprite)
		var result:={"id":id,"p":p,"hp":10.0,"uid":serial,"sprite":sprite,"boss":boss,"objective_index":index,"notified":false}
		enemies.append(result)
		return result
	func clear()->void:
		for e:Dictionary in enemies:
			if is_instance_valid(e.sprite):e.sprite.queue_free()
		enemies.clear();projectiles.clear()

class TestGame:
	extends Node2D
	var campaign=Campaign.new()
	var world=World.new()
	var player=Sprite2D.new()
	var ui=TestUI.new()
	var enemy_director=TestEnemies.new()
	var active:=true
	var invulnerable:=0.0
	var shield_time:=0.0
	var hp:=1000.0
	var hits:Array=[]
	var saves:=0
	var effects:Array=[]
	func _ready()->void:
		add_child(world);add_child(player);enemy_director.setup(self)
	func _hurt(amount:float,p:Vector2,_unblockable:bool=false,source_kind:String="environment")->void:
		hp-=amount;hits.append({"amount":amount,"p":p,"kind":source_kind})
	func _effect(p:Vector2,color:Color,kind:String,life:float,radius:float)->void:effects.append([p,color,kind,life,radius])
	func _save_all()->void:saves+=1

func _initialize()->void:call_deferred("_run")

func _run()->void:
	game=TestGame.new();root.add_child(game)
	director=ChallengeDirector.new();director.setup(game)
	_test_all_definitions_and_wins()
	_test_replay_and_saved_records()
	_test_fail_retry_and_pause()
	_test_scoped_cleanup_and_death()
	_test_projectile_geometry()
	_test_pulses_and_plate_edges()
	_test_corrupt_snapshot()
	paused=false
	director.cancel();game.enemy_director.clear();director=null
	game.queue_free();await process_frame;await process_frame
	if failures.is_empty():
		print("V12 CHALLENGE TESTS PASSED: %d checks"%checks);quit(0)
	else:
		for failure in failures:printerr("FAIL: "+failure)
		printerr("V12 CHALLENGE TESTS FAILED: %d / %d"%[failures.size(),checks]);quit(1)

func _fresh(chapter:int,stage:int=0,saved:Dictionary={})->void:
	director.cancel();game.enemy_director.clear()
	game.world.configure(chapter,stage)
	director.configure(chapter,saved)
	game.hits.clear();game.invulnerable=0;game.shield_time=0;game.campaign.difficulty="explorer"

func _test_all_definitions_and_wins()->void:
	var ids:Array=[]
	var types:Array=[]
	for chapter in range(7):
		_fresh(chapter)
		_check(director.challenges.size()==3,"region%d has three optional microlevels"%chapter)
		var main_snapshot:Array=game.campaign.completed.duplicate()
		for c:Dictionary in director.challenges:
			_check(not c.id in ids,"challenge id is unique: "+c.id);ids.append(c.id)
			if not c.type in types:types.append(c.type)
			_check(game.world.is_walkable(c.p,30),c.id+" marker has physical clearance")
			_check(not game.world.find_path(game.world.definition.spawn,c.p).is_empty(),c.id+" marker reachable from region entrance")
			for group:Array in game.world._objective_sets:
				for point:Vector2 in group:_check(c.p.distance_to(point)>=185,c.id+" does not cover a main objective")
			for point:Vector2 in game.world.definition.camps:_check(c.p.distance_to(point)>=190,c.id+" does not cover a safe camp")
			for trap:Dictionary in game.world.definition.hazards:_check(c.p.distance_to(trap.p)>=155,c.id+" does not cover a world trap emitter")
			for point:Vector2 in c.points:
				_check(game.world.is_walkable(point,20),c.id+" authored gate/target lies on playable ground")
				_check(not game.world.find_path(c.p,point).is_empty(),c.id+" gate/target is connected to starting marker")
			var xp:int=game.campaign.xp;var crystals:int=game.campaign.crystals
			game.player.position=c.p
			_check(director.start(c.id),c.id+" begins through nearby marker")
			match str(c.type):
				"race":_finish_route(c)
				"pressure":_finish_plates(c)
				"targets":_finish_targets(c)
				"waves":_finish_waves(c)
				"escort":_finish_escort(c)
			_check(c.completed and not c.active,c.id+" has a real winning condition")
			_check(director.last_result.get("success",false),c.id+" records success result")
			_check(game.campaign.xp==xp+24 and game.campaign.crystals==crystals+10,c.id+" one-time fixed reward")
			_check(game.campaign.completed==main_snapshot,c.id+" never completes or gates main story")
		_check(director.completed_ids().size()==3,"region%d all optional levels retain medals"%chapter)
		saved_chapters[chapter]=director.snapshot().duplicate(true)
	_check(ids.size()==21 and types.size()==5,"twenty-one designed challenges use five substantive mechanic types")
	_check(game.campaign.xp==504 and game.campaign.crystals==210,"all optional first clears total504XP210crystals")

func _finish_route(c:Dictionary)->void:
	for gate:Vector2 in c.points:
		game.player.position=gate;director.update(0.02)

func _finish_plates(c:Dictionary)->void:
	for plate:Vector2 in c.points:
		game.player.position=plate;director.update(0.02)

func _finish_targets(c:Dictionary)->void:
	var initial:Vector2=c.targets[0].p
	director.update(0.6)
	_check(c.targets[0].p!=initial,c.id+" target actually moves over time")
	_check(director.hit_targets(c.p,Vector2.RIGHT,1000,"melee",100,PI)==0,c.id+" melee or idle bell animation cannot solve projectile range")
	for number in range(1,c.targets.size()+1):
		for target:Dictionary in c.targets:
			if int(target.number)!=number:continue
			for hit in range(int(c.get("target_hits",1))):
				var p:Vector2=target.p
				_check(director.hit_target_segment(p-Vector2(8,0),p+Vector2(8,0),8,"projectile")==1,c.id+" swept projectile contacts current target")
			_check(int(c.step)==number,c.id+" ordered target%d advances progress (actual%d)"%[number,int(c.step)])
			break

func _kill_wave()->void:
	for enemy:Dictionary in game.enemy_director.enemies.duplicate():
		if not enemy.get("challenge",false) or enemy.hp<=0:continue
		enemy.hp=0
		var before:int=director.active_info().progress
		_check(director.enemy_defeated(enemy),"tagged optional enemy callback consumed")
		director.enemy_defeated(enemy)
		_check(int(director.active_info().progress)==before+1,"duplicate enemy callback never doubles challenge kill credit")

func _finish_waves(c:Dictionary)->void:
	for wave in range(3):
		director.update(2.0)
		_check(c.wave==wave+1 and c.wave_active,c.id+" spawns real wave%d"%(wave+1))
		_check(director._remaining()>=2,c.id+" wave has multiple attackable enemies")
		for enemy:Dictionary in game.enemy_director.enemies:
			if enemy.get("challenge_id","")==c.id:_check(int(enemy.objective_index)<-999,c.id+" enemies cannot count toward main goals")
		_kill_wave();director.update(0.02)

func _finish_escort(c:Dictionary)->void:
	var guard:=0
	var first_position:Vector2=c.cart_p
	while c.active and guard<1600:
		guard+=1
		if c.wave_active:
			_kill_wave();director.update(0.02)
		elif c.waiting_lever:
			game.player.position=c.lever
			_check(director.interaction_at(c.lever).get("action")=="lever",c.id+" clearing ambush exposes actual brake lever")
			_check(director.handle_interaction(c.lever),c.id+" brake must be manually released")
		elif c.needs_wave:
			game.player.position=game.world.nearest_safe(c.cart_p+Vector2(-80,25));director.update(1.5)
		else:
			game.player.position=game.world.nearest_safe(c.cart_p+Vector2(-80,25));director.update(0.16)
	_check(guard<1600,c.id+" escort has no navigation deadlock")
	_check((c.cart_p as Vector2).distance_to(first_position)>700,c.id+" cart physically travels a substantial route")
	_check(c.wave==3,c.id+" route contains three separate ambush battles")

func _test_replay_and_saved_records()->void:
	var xp:int=game.campaign.xp;var crystals:int=game.campaign.crystals
	var centers:Array=[]
	_fresh(0,0,saved_chapters[0])
	for c:Dictionary in director.challenges:centers.append(c.p)
	_fresh(0,2,saved_chapters[0])
	_check(director.completed_ids().size()==3,"chapter-scoped rewards and medals survive other main-quest group")
	for i in range(3):_check(director.challenges[i].p==centers[i],"optional marker remains fixed across the chapter's three main groups")
	var c:Dictionary=director.challenges[0]
	game.player.position=c.p
	_check(director.interaction_at(c.p).label.begins_with("再挑战"),"completed level offers immediate replay")
	_check(director.start(c.id),"completed optional levels remain playable after story completion")
	_finish_route(c)
	_check(not director.last_result.first_clear,"replay reports no new first-clear reward")
	_check(game.campaign.xp==xp and game.campaign.crystals==crystals,"replays cannot farm optional completion reward")
	_check(c.best_time>0 and c.medal in ["gold","silver","bronze"],"timed replay retains valid best-time medal")

func _test_fail_retry_and_pause()->void:
	_fresh(0)
	var c:Dictionary=director.challenges[0]
	game.player.position=c.p+Vector2(500,0)
	_check(not director.start(c.id),"distant marker cannot start challenge remotely")
	game.player.position=c.p;director.start(c.id)
	var elapsed:float=c.elapsed
	paused=true;director.update(99);paused=false
	_check(c.active and c.elapsed==elapsed,"paused world freezes challenge timer and hazards")
	var reward:Array=[game.campaign.xp,game.campaign.crystals]
	director.update(99)
	_check(not c.active and not c.completed and not director.last_result.success,"timeout is a failure rather than an automatic reward")
	_check(reward==[game.campaign.xp,game.campaign.crystals],"failure never removes or grants progression resources")
	game.player.position=c.p
	_check(director.start(c.id),"failure can be retried immediately")
	_check(not director.start(director.challenges[1].id),"one optional level runs at a time")
	director.cancel()
	_check(not c.active and c.step==0,"cancel resets active attempt")

func _test_scoped_cleanup_and_death()->void:
	_fresh(0)
	var ordinary:Dictionary=game.enemy_director.spawn("shadow_blob",Vector2(500,500),false,1)
	game.enemy_director.projectiles.append({"owner_uid":ordinary.uid,"kind":"main-story"})
	var c:Dictionary=director.challenges[1]
	game.player.position=c.p;director.start(c.id);director.update(1.5)
	var tagged:Dictionary={}
	for enemy:Dictionary in game.enemy_director.enemies:
		if enemy.get("challenge",false):tagged=enemy;break
	game.enemy_director.projectiles.append({"owner_uid":tagged.uid,"kind":"optional"})
	director.reset_on_death()
	_check(not c.active and not c.completed,"death resets optional attempt while preserving incomplete status")
	_check(game.enemy_director.enemies.size()==1 and game.enemy_director.enemies[0]==ordinary,"optional cleanup leaves main-story enemies untouched")
	_check(game.enemy_director.projectiles.size()==1 and game.enemy_director.projectiles[0].kind=="main-story","optional cleanup removes only owned projectiles")
	_check(ordinary.hp==10 and not ordinary.notified,"cleanup does not kill or reward unrelated enemies")
	_check(not director.enemy_defeated(ordinary),"ordinary enemy callback remains available to main story")

func _test_projectile_geometry()->void:
	_fresh(0)
	var c:Dictionary=director.challenges[2]
	game.player.position=c.p;director.start(c.id)
	for target:Dictionary in c.targets:target.done=true
	var target:Dictionary=c.targets[0]
	target.done=false;target.number=1;target.p=Vector2(1430,750);target.base=target.p
	_check(director.hit_target_segment(Vector2(1010,750),Vector2(1480,750),12)==0,"actual house blocks ranged target hit across a swept segment")
	_check(target.hits==0,"wall-blocked projectile never increments target progress")
	_check(director.hit_target_segment(Vector2(1400,810),Vector2(1450,810),8)==0,"nearby projectile outside target radius misses")
	_check(director.hit_target_segment(Vector2(1410,750),Vector2(1450,750),8)==1,"visible projectile actually intersects target circle")
	director.cancel()
	game.player.position=c.p;director.start(c.id)
	var wrong:Dictionary=c.targets[1]
	_check(int(wrong.number)!=1,"test selects an unlit target")
	var p:Vector2=wrong.p
	_check(director.hit_target_segment(p-Vector2(8,0),p+Vector2(8,0),8)==1 and c.step==0,"wrong target absorbs arrow but cannot advance ordered range")
	director.cancel()

func _test_pulses_and_plate_edges()->void:
	_fresh(1)
	var c:Dictionary=director.challenges[0]
	game.player.position=c.p;director.start(c.id)
	game.player.position=c.points[2];director.update(0.01)
	_check(c.step==0,"walking onto wrong pressure plate resets sequence")
	game.player.position=c.p+Vector2(300,0);director.update(0.01)
	game.player.position=c.points[0];director.update(0.01)
	_check(c.step==1,"correct plate triggers immediately on entry")
	director.update(0.4)
	_check(c.step==1,"standing still on plate never completes remaining steps")
	var pulse:Dictionary=c.pulses[0]
	game.player.position=pulse.p;c.elapsed=1.05-float(pulse.phase)
	game.invulnerable=0;var before:=game.hits.size()
	director.update(0.02)
	_check(pulse.state=="active" and game.hits.size()==before+1,"telegraphed relay beam has real capsule damage")
	_check(game.hits.back().kind=="environment","challenge hazard uses environment source rather than reduced enemy damage")
	director.update(0.04)
	_check(game.hits.size()==before+1,"same beam cycle cannot repeatedly damage or penalize")
	_check(c.penalty>=1.2,"beam collision creates visible time penalty")
	director.cancel()

func _test_corrupt_snapshot()->void:
	_fresh(0,0,{"completed":"bad","medals":4,"best_times":[]})
	_check(director.completed_ids().is_empty(),"invalid persisted container fields are ignored")
	var id:String=director.challenges[0].id
	_fresh(0,0,{"completed":[id,"unknown-id"],"medals":{id:"invented"},"best_times":{id:-100}})
	_check(director.completed_ids()==[id],"only real chapter IDs restore completion")
	_check(director.challenges[0].medal=="" and director.challenges[0].best_time==0,"invalid medal and record fields are bounded")
	_check(director.snapshot().version==1 and director.snapshot().chapter==0,"snapshot is explicitly versioned and chapter-scoped")

func _check(condition:bool,message:String)->void:
	checks+=1
	if not condition:failures.append(message)
