extends SceneTree
## Current actual-main integration. Fixtures shorten enemy HP only; courses,
## carts, attacks, projectiles, seal collisions and saves use production code.
const SAVE="user://full-game-v12-test.json"
var game:Node2D
var checks:int=0
var failures:Array=[]
var story_kinds:Dictionary={}
var tested_two_waves:int=0

func _initialize()->void:call_deferred("_run")

func _run()->void:
	_clean()
	var scene:PackedScene=load("res://scenes/main.tscn")
	game=scene.instantiate();game.campaign.save_path=SAVE;root.add_child(game);await process_frame
	game.set_process(false)
	_check(paused and game.ui.title_screen.visible,"current main opens paused title")
	_test_portrait_mapping()
	game._start(false);_close()
	if not "--story-only" in OS.get_cmdline_user_args():
		_test_actual_damage()
		_test_primary_retry()
		_test_seal_routes_and_saves()
		_test_optional_and_v3_persistence()
		_test_v2_migration()
	if not "--preflight" in OS.get_cmdline_user_args():await _test_all_story_groups()
	paused=false
	for audio in [game.attack_sound,game.chime_sound,game.music]:audio.stop()
	game.hero_actions.game=null;game.queue_free();await process_frame;await process_frame
	_clean()
	if failures.is_empty():
		print("V1.2 FULL GAME TESTS PASSED: %d checks; 63 active goals / 21 story groups; %d two-wave battles"%[checks,tested_two_waves]);call_deferred("quit",0)
	else:
		for failure in failures:printerr("FAIL: "+str(failure))
		printerr("V1.2 FULL GAME TESTS: %d failures / %d checks"%[failures.size(),checks]);call_deferred("quit",1)

func _test_portrait_mapping()->void:
	for i in range(2):
		var images=game.ui.portraits[i].get_children().filter(func(n):return n is TextureRect)
		var expected:String="wangzai.png" if i==0 else "xiaomantou.png"
		_check(not images.is_empty() and images[0].texture!=null and images[0].texture.resource_path.ends_with("portraits_v12/"+expected),"anime portrait keeps correct hero mapping: "+expected)

func _test_actual_damage()->void:
	game.enemy_director.clear();game._sync_enemies()
	for mode in ["gentle","explorer","brave"]:
		for upgraded in [false,true]:
			game.campaign.difficulty=mode;game.campaign.xp=11400 if upgraded else 0
			game.campaign.equipped={"weapon":"training_sword","armor":"starlight_guard_cloak" if upgraded else "travel_cloak","accessory":"twin_star_brooch" if upgraded else ""}
			game.campaign.upgrades={"weapon":0,"armor":3 if upgraded else 0,"accessory":3 if upgraded else 0,"shield":3,"bell":0}
			game.hero_actions.reset();game.hp=game.campaign.max_hp();game.shield_time=0;game.invulnerable=0;game.facing=Vector2.RIGHT
			var maximum:float=game.hp
			game._hurt(14,game.player.position+Vector2(100,0),false,"enemy")
			_check(maximum-game.hp==ceilf(maximum*0.25),"rootquarter minimum survives%s higharmor=%s and front shield"%[mode,upgraded])
			var hp:float=game.hp;game.hero_actions.reset();game._switch(1-game.campaign.active_character)
			game._hurt(64,game.player.position,true,"enemy")
			_check(game.hp==hp and game.invulnerable>0,"root shared grace survives character switch")
			game.invulnerable=0;game.shield_time=4;game._hurt(64,game.player.position,true,"enemy")
			_check(game.hp==hp,"active water protection avoids enemyquarter minimum")
			game.shield_time=0;game.invulnerable=0;game.hp=maximum
			var multiplier:float=0.65 if mode=="gentle" else (0.85 if mode=="explorer" else 1.0)
			game._hurt(12,game.player.position,true,"environment")
			_check(maximum-game.hp==maxf(1,roundf(12*multiplier)-game.campaign.defense()),"root environment damage excluded from enemy floor")
	game._start(false);_close();game.enemy_director.clear();game._sync_enemies();game.campaign.difficulty="explorer"
	for id in ["shadow_blob","wind_gremlin"]:
		game.enemy_director.clear();game._sync_enemies();game.player.position=game.spawn_position
		game.hp=game.campaign.max_hp();game.invulnerable=0;game.shield_time=0;game.hero_actions.reset()
		var e:Dictionary=game.enemy_director.spawn(id,game.world.nearest_safe(game.spawn_position+Vector2(145,0)))
		e.cooldown=0;game._sync_enemies()
		_tick(2.4)
		_check(game.hp==game.campaign.max_hp()-ceilf(game.campaign.max_hp()*0.25),"actual%s attack routes enemy tag into root quarter resolver"%id)
	game._start(false);_close()

func _test_primary_retry()->void:
	game.player.position=game.points[0];game.invulnerable=999;game._interact_goal(0)
	var course:Dictionary=game.main_trials.states[0]
	_check(game.main_trials.active_index==0 and course.route.size()==4,"main course starts four ordered physical gates")
	game.player.position=course.route[-1];game.main_trials.update(0.04)
	_check(course.gate==0,"course final gate cannot bypass first gates")
	course.time-=2;var remaining:float=course.time;game.main_trials.begin(0)
	_check(course.time==remaining,"repeated start cannot reset running course timer")
	course.time=0.01;game.main_trials.update(0.04)
	_check(game.main_trials.active_index==-1 and course.failed and not game.objective_done[0],"course timeout fails safely without story completion")
	_check(game.main_trials.local_traps.traps.is_empty(),"failed course removes its local hazards")
	_check(game.main_trials.begin(0) and course.gate==0 and not course.failed,"failed course retries from first gate")
	game._rest(game.spawn_position)
	_check(game.main_trials.active_index==-1,"camp rest cancels active main course")
	game._load_stage(2);_close();game.invulnerable=999
	_kill_near(game.points[0],600)
	game.player.position=game.points[0];game._interact_goal(0)
	var escort:Dictionary=game.main_trials.states[0]
	var count:int=_escort_alive(0)
	_check(count==2 and escort.ambush==1,"main escort begins first real ambush")
	game.main_trials.begin(0)
	_check(_escort_alive(0)==count,"repeated escort start cannot duplicate ambushers")
	game.main_trials.cancel()
	_check(game.main_trials.active_index==-1 and _escort_alive(0)==0,"cancelled escort removes its enemy group")
	game.player.position=game.points[0];game.main_trials.begin(0)
	_check(_escort_alive(0)==2,"retry starts one fresh escort ambush")
	game.hp=1;game.invulnerable=0;game.shield_time=0;game._hurt(9999,game.player.position,true,"environment")
	_check(paused and game.main_trials.active_index==-1 and _escort_alive(0)==0,"death cancels escort without accumulating ambushers")
	_close();game._start(false);_close()

func _test_seal_routes_and_saves()->void:
	game.invulnerable=999
	var state:Dictionary=game.main_trials.states[2]
	_check(state.targets.size()==3,"seal objective creates three physical targets")
	var first:Dictionary=state.targets[0]
	_strike_target(first,0)
	_check(first.hp<=0 and not game.objective_done[2],"actual melee contact breaks one seal without completing remaining seals")
	game._save_all();game._load_stage(0);_close();game.invulnerable=999
	state=game.main_trials.states[2]
	_check(state.targets[0].hp==0 and state.targets[1].hp>0,"v3 save restores individual broken seal state")
	var second:Dictionary=state.targets[1]
	var hp:float=second.hp
	_strike_target(second,1,false)
	_check(second.hp<hp,"actual ranged projectile routes into primary seal collision")
	game._start(false);_close()

func _test_optional_and_v3_persistence()->void:
	game.invulnerable=999
	var race:Dictionary=game.challenge_director.challenges.filter(func(c):return c.type=="race")[0]
	game.player.position=race.p;game._context_press();game._context_release()
	_check(game.challenge_director.active_info().get("id","")==race.id,"context button starts actual optional race")
	var resources:Array=[game.campaign.xp,game.campaign.crystals]
	_finish_race(race)
	_check(race.completed and game.campaign.xp==resources[0]+24 and game.campaign.crystals==resources[1]+10,"optional race rewards once without story completion")
	_check(game.done==0,"optional challenge cannot silently complete main objectives")
	game.player.position=race.p;game.challenge_director.start(race.id);_finish_race(race)
	_check(game.campaign.xp==resources[0]+24 and game.campaign.crystals==resources[1]+10,"optional race replay cannot duplicate reward")
	var target_trial:Dictionary=game.challenge_director.challenges.filter(func(c):return c.type=="targets")[0]
	game.player.position=target_trial.p;game.challenge_director.start(target_trial.id)
	var active:Dictionary=game.challenge_director.active_info()
	var target:Dictionary=_next_optional_target(active)
	var before:int=int(active.step)
	_strike_target(target,0,false)
	_check(int(active.step)==before,"melee cannot substitute for optional ranged target challenge")
	var optional_before:Array=[game.campaign.xp,game.campaign.crystals]
	for attempt in range(15):
		if game.challenge_director.active_info().is_empty():break
		active=game.challenge_director.active_info();target=_next_optional_target(active)
		_strike_target(target,1,false)
	_check(target_trial.completed and game.campaign.xp==optional_before[0]+24 and game.campaign.crystals==optional_before[1]+10,"real hero projectiles complete ordered optional moving targets")
	game._save_all()
	var document=JSON.parse_string(FileAccess.get_file_as_string(game._world_path()))
	_check(document.version==3 and document.challenges.get("0",{}).get("completed",[]).has(race.id),"world v3 writes chapter-scoped challenge medals alongside stage data")
	game.stage_info.clear();game._load_world_saves();game._load_stage(1);_close()
	var restored:Dictionary=game.challenge_director.challenges.filter(func(c):return c.id==race.id)[0]
	_check(restored.completed and restored.best_time>0 and not restored.medal.is_empty(),"optional completion and medal persist into another stage of same chapter: "+str([restored.completed,restored.best_time,restored.medal,game.challenge_saves]))
	game._start(false);_close()

func _finish_race(c:Dictionary)->void:
	for i in range(c.points.size()):
		if game.challenge_director.active_info().is_empty():break
		game.player.position=c.points[i];game.challenge_director.update(0.04)

func _next_optional_target(c:Dictionary)->Dictionary:
	for t in c.targets:
		if int(t.number)==int(c.step)+1:return t
	return c.targets[0]

func _test_v2_migration()->void:
	game.campaign.xp=47;game.campaign.crystals=13;game.campaign.save_game()
	var old:Dictionary={"version":2,"stages":{"0":{"goals":[0,1,2],"puzzles":[{"rotation":3}],"chests":[0],"explored":[1,2],"checkpoint":[game.spawn_position.x,game.spawn_position.y],"traps":[]}}}
	var file=FileAccess.open(game._world_path(),FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
	game.stage_info.clear();game._load_world_saves();game._load_stage(0);_close()
	_check(game.done==0 and game.objective_done==[false,false,false],"legacy v2 stand-task completion resets for new active trials")
	_check(game.claimed_chests.has(0) and game.campaign.xp==47 and game.campaign.crystals==13,"v2 migration preserves chest ownership and all campaign resources: "+str([game.claimed_chests,game.campaign.xp,game.campaign.crystals]))
	var migrated=JSON.parse_string(FileAccess.get_file_as_string(game._world_path()))
	_check(migrated.version==3,"loading legacy world record rewrites valid v3 format")
	game._start(false);_close()

func _test_all_story_groups()->void:
	game.set_process(false)
	for stage in range(21):
		if game.campaign.stage!=stage:game._load_stage(stage)
		_close();game.invulnerable=999;game.move_input=Vector2.ZERO
		_check(game.objectives.size()==3,"stage%d has three active story goals"%stage)
		for goal in game.objectives:
			story_kinds[goal.kind]=true
			_check(goal.kind in ["course","seal","escort","battle","boss","push","mirror","valve"],"stage%d has no passive shield/bell waiting objective"%stage)
		var order:Array=[0,1,2]
		if game.objectives[0].kind!="valve" and game.objectives[2].kind!="boss":order=[2,0,1]
		if game.objectives[0].kind=="valve":
			game._interact_goal(2);_check(not game.objective_done[2],"water valves retain deliberate order")
		for index in order:
			_complete_goal(index)
			_check(game.objective_done[index],"stage%d goal%d %s finishes through actual mechanic"%[stage,index,game.objectives[index].kind])
		_check(game.done==3,"stage%d completes all three primary trials"%stage)
		_kill_near(game.lamp_position,610)
		game.player.position=game.lamp_position;game._context_press();game._context_release()
		_check(game.campaign.completed.has(stage),"stage%d lantern grants real story completion"%stage)
		_close();await process_frame
	_check(game.campaign.completed.size()==21 and game.campaign.level()==20,"all21 groups and63activeobjectives reach ending at level20")
	_check(story_kinds.size()==8 and tested_two_waves>0,"campaign exercises all eight active goal styles and two-wave battles")
	var snapshot:Array=[game.campaign.xp,game.campaign.crystals,game.campaign.gold]
	game._complete_stage();_close()
	_check(snapshot==[game.campaign.xp,game.campaign.crystals,game.campaign.gold],"completed ending cannot duplicate source rewards")

func _complete_goal(index:int)->void:
	if game.objective_done[index]:return
	var kind:String=game.objectives[index].kind
	if kind=="battle":_finish_battle(index);return
	if kind=="boss":
		for e in game.enemies.duplicate():
			if e.hp>0 and int(e.objective_index)==index:_defeat(e)
		return
	_kill_near(game.points[index],600)
	game.player.position=game.points[index];game.facing=Vector2.RIGHT
	match kind:
		"course":
			game._interact_goal(index)
			var state:Dictionary=game.main_trials.states[index]
			for i in range(state.route.size()+1):
				if game.objective_done[index]:break
				if state.gate>=state.route.size():break
				game.player.position=state.route[state.gate];game.main_trials.update(0.04)
		"seal":
			var state:Dictionary=game.main_trials.states[index]
			for target in state.targets:
				for attempt in range(5):
					if target.hp<=0:break
					_strike_target(target,0)
			game.main_trials.update(0.04)
		"escort":_finish_escort(index)
		"push":
			for attempt in range(7):
				if game.objective_done[index]:break
				var objective:Dictionary=game.objectives[index];var direction:Vector2=objective.crate_p.direction_to(objective.pad)
				game.player.position=game.world.nearest_safe(objective.crate_p-direction*75);game.facing=direction;game._interact_goal(index)
		"mirror":
			for attempt in range(4):
				if game.objective_done[index]:break
				game._interact_goal(index)
		"valve":game._interact_goal(index)
	game.hero_actions.reset();game.pending_skill.clear()

func _finish_battle(index:int)->void:
	var saw_second:bool=int(game.battle_waves.get(index,0))>=1
	for wave in range(3):
		if game.objective_done[index]:break
		var alive:Array=[]
		for e in game.enemies:
			if e.hp>0 and int(e.objective_index)==index:alive.append(e)
		for e in alive:
			if e.hp>0:_defeat(e)
		if int(game.battle_waves.get(index,0))>=1:
			saw_second=true
			if wave==0 and not game.objective_done[index]:_check(_objective_alive(index)>0,"first primary wave produces a separate second wave")
	_check(saw_second and game.objective_done[index],"primary battle requires both waves")
	tested_two_waves+=1

func _finish_escort(index:int)->void:
	game.player.position=game.points[index];game._interact_goal(index)
	var state:Dictionary=game.main_trials.states[index]
	_check(state.cart_path.size()>1,"story escort owns a real navigation route")
	for step in range(2000):
		if game.objective_done[index] or game.main_trials.active_index<0:break
		_kill_near(state.cart.position,310)
		if game.objective_done[index]:break
		game.player.position=game.world.nearest_safe(state.cart.position+Vector2(-70,55));game.move_input=Vector2.ZERO
		_tick(0.08)
	_check(state.ambush>=2,"story escort encounters both planned ambushes")

func _strike_target(target:Dictionary,character:int,assert_windup:bool=true)->void:
	game.hero_actions.reset();game.pending_skill.clear();game.campaign.active_character=character;game.invulnerable=999
	var p:Vector2=target.p
	game.player.position=game.world.nearest_safe(p+Vector2(-75 if character==0 else -150,0));game.facing=game.player.position.direction_to(p)
	var previous:float=float(target.get("hp",0));var done_before:bool=bool(target.get("done",false))
	game._attack();_tick(0.08)
	if assert_windup:_check(target.get("hp",previous)==previous,"primary seal takes no damage before actual attack contact")
	_tick(0.72)
	if assert_windup:_check(float(target.get("hp",previous))<previous or previous<=0,"actual hero contact reaches primary seal target")
	game.hero_actions.reset()

func _defeat(enemy:Dictionary)->void:
	if enemy.hp<=0:return
	enemy.hp=1;enemy.vulnerable=10
	for attempt in range(4):
		if enemy.hp<=0:break
		game.hero_actions.reset();game.pending_skill.clear();game.campaign.active_character=0;game.invulnerable=999
		var candidate:Vector2=enemy.sprite.position+Vector2.from_angle(PI+attempt*PI/2)*25
		game.player.position=candidate if game.world.is_walkable(candidate) else game.world.nearest_safe(candidate)
		game.facing=game.player.position.direction_to(enemy.sprite.position)
		game._attack();_tick(0.70)
	_check(enemy.hp<=0,"actual melee contact defeats combat fixture")
	game.hero_actions.reset()

func _kill_near(p:Vector2,radius:float)->void:
	for e in game.enemies.duplicate():
		if e.hp>0 and e.sprite.position.distance_to(p)<radius:_defeat(e)

func _escort_alive(index:int)->int:
	var count:int=0
	for e in game.enemies:
		if e.hp>0 and int(e.get("main_escort",-1))==index:count+=1
	return count

func _objective_alive(index:int)->int:
	var count:int=0
	for e in game.enemies:
		if e.hp>0 and int(e.objective_index)==index:count+=1
	return count

func _tick(duration:float)->void:
	var remaining:float=duration
	while remaining>0.00001:
		var delta:float=minf(0.04,remaining);remaining-=delta
		if not paused:game._process(delta)

func _close()->void:
	for i in range(5):
		if not game.ui.dialog_screen.visible:break
		game.ui._close_dialog()

func _check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)

func _clean()->void:
	for base in [SAVE,SAVE+".world.json"]:
		for suffix in ["",".bak",".tmp"]:
			var p:String=ProjectSettings.globalize_path(base+suffix)
			if FileAccess.file_exists(p):DirAccess.remove_absolute(p)
