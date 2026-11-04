extends SceneTree
## Actual scene + actual trap/enemy directors, with isolated test-only saves.
var game:Node2D
var checks=0
var failures:Array=[]
const SAVE="user://main-trials-v12-test.json"

func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL: "+message)

func run()->void:
	_clean()
	root.size=Vector2i(1280,720)
	game=load("res://scenes/main.tscn").instantiate()
	game.campaign.save_path=SAVE
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._start(false);_close_dialogs()
	_test_course_timeout_retry()
	_test_seal_aim_and_segment()
	_test_escort_cancellation()
	_test_escort_two_ambush_route()
	_test_death_during_course_trap()
	_test_death_rest_stage_cleanup()
	paused=false
	game.main_trials.clear();game.enemy_director.clear()
	for audio in [game.attack_sound,game.chime_sound,game.music]:audio.stop()
	game.hero_actions.game=null
	game.queue_free();await process_frame;await process_frame
	_clean()
	if failures.is_empty():print("MAIN TRIALS V1.2 TESTS PASSED: %d checks"%checks)
	else:printerr("MAIN TRIALS V1.2 FAILED: %d / %d"%[failures.size(),checks])
	quit(0 if failures.is_empty() else 1)

func _fresh_stage(index:int)->void:
	_close_dialogs()
	game.stage_info.clear();game.world_saves.erase(str(index));game._load_stage(index);_close_dialogs()
	game.enemy_director.clear();game._sync_enemies();game.hero_actions.reset()
	game.invulnerable=0;game.shield_time=0;game.hp=game.campaign.max_hp()

func _close_dialogs()->void:
	for i in range(3):
		if not game.ui.dialog_screen.visible:break
		game.ui._close_dialog()
	paused=false

func _resources()->Array:return [game.campaign.xp,game.campaign.crystals,game.campaign.gold,game.campaign.progress]
func _escort_units()->Array:return game.enemy_director.enemies.filter(func(e):return e.has("main_escort"))
func _live_escort()->Array:return _escort_units().filter(func(e):return e.hp>0)
func _escort_uids()->Array:return _escort_units().map(func(e):return int(e.uid))

func _test_course_timeout_retry()->void:
	_fresh_stage(0)
	var trial=game.main_trials;var d:Dictionary=trial.states[0]
	check(d.kind=="course" and d.route.size()==4,"authored first course has four actual safe flag gates")
	check(trial.begin(0),"course starts through real director")
	trial.update(.20);var remaining=float(d.time)
	check(not trial.begin(0) and is_equal_approx(d.time,remaining),"repeated start cannot refill active course timer")
	d.time=.01;trial.update(.02)
	check(trial.active_index==-1 and d.failed and not game.objective_done[0],"timeout fails course without completing story goal")
	check(trial.local_traps.traps.is_empty() and trial.local_traps.darts.is_empty(),"failed course removes local hazards")
	check(trial.begin(0) and d.gate==0 and d.time==d.limit,"failed course immediately retries with a fresh clock")
	for p in d.route:
		game.player.position=p;trial.update(.01)
	check(game.objective_done[0] and trial.active_index==-1,"retry succeeds only after traversing every flag in order")

func _test_seal_aim_and_segment()->void:
	var trial=game.main_trials;var d:Dictionary=trial.states[2]
	check(d.kind=="seal" and d.targets.size()==3,"three actual destructible seal targets are present")
	# Arrange only the target positions within an actual open patch. This isolates
	# targeting order while keeping world LOS and the actual hit/damage functions.
	var center:Vector2=game.spawn_position
	var origin=center+Vector2(-90,0)
	for j in range(3):
		d.targets[j].p=center+Vector2(90*(2-j),0);d.targets[j].origin=d.targets[j].p;d.targets[j].sprite.position=d.targets[j].p
		check(game.world.has_line_of_sight(origin,d.targets[j].p),"seal targeting fixture is genuinely visible in the live world")
	var initial:float=d.targets[2].hp
	check(trial.hit_cone(origin,Vector2.LEFT,120,1,.35)==0 and d.targets[2].hp==initial,"melee aimed away cannot damage nearby seals")
	check(trial.hit_cone(origin,Vector2.RIGHT,120,1,.35)==1 and d.targets[2].hp==initial-1,"melee cone hits only the visible target within real reach")
	check(trial.hit_segment(origin,center+Vector2(240,0),2) and d.targets[2].hp==initial-3,"projectile hits nearest seal along its swept path, regardless of target array order")
	check(d.targets[0].hp==d.targets[0].max_hp and d.targets[1].hp==d.targets[1].max_hp,"single projectile cannot damage farther seals behind the first")
	var health=trial.snapshot()[2].targets.duplicate()
	check(trial.hit_cone(origin,Vector2.RIGHT,500,-50)==0 and trial.snapshot()[2].targets==health,"invalid damage cannot heal or alter seals")
	paused=true;check(not trial.hit_segment(origin,center+Vector2(240,0),100),"paused world cannot damage seal targets");paused=false
	for target in d.targets:
		trial.hit_segment(target.p-Vector2(20,0),target.p+Vector2(20,0),1000)
	trial.update(0)
	check(game.objective_done[2],"breaking all three cores finishes the authored seal goal")

func _test_escort_cancellation()->void:
	_fresh_stage(2)
	var trial=game.main_trials;var before=_resources()
	check(trial.begin(0) and _live_escort().size()==2,"escort creates exactly the first two-unit ambush")
	var ids=_escort_uids();var d:Dictionary=trial.states[0]
	var sentinel=game.enemy_director.spawn("moon_bubble",game.spawn_position,false,-999)
	for e in _live_escort():game.enemy_director._burst(e,[0.0],150,12,3,"star")
	game.enemy_director._burst(sentinel,[0.0],150,12,3,"bubble")
	var initial_count=game.enemy_director.enemies.size()
	d.cart_index=1;d.cart_distance=15
	check(not trial.begin(0) and game.enemy_director.enemies.size()==initial_count and d.cart_distance==15,"active escort start cannot duplicate waves or reset cart progress")
	trial.cancel()
	check(_escort_units().is_empty() and _resources()==before,"cancel despawns escort enemies without reward callbacks")
	check(game.enemy_director.projectiles.all(func(q):return not int(q.owner_uid) in ids),"cancel removes only projectiles owned by cancelled escort units")
	check(sentinel.hp>0 and game.enemy_director.enemies.has(sentinel) and game.enemy_director.projectiles.any(func(q):return q.owner_uid==sentinel.uid),"cancel preserves unrelated living enemies and their projectiles")
	check(d.cart.position==d.p and d.cart_index==0 and d.cart_distance==0 and trial.active_index==-1,"cancel restores cart and local run state")
	check(trial.begin(0) and _live_escort().size()==2,"cancelled escort retries with exactly one clean first wave")
	for e in _live_escort():game.enemy_director._burst(e,[0.0],150,12,3,"star")
	var retry_ids=_escort_uids();var rewards=_resources();trial.clear()
	check(trial.states.is_empty() and _escort_units().is_empty() and _resources()==rewards,"clear cleans active escort units without granting resources")
	check(game.enemy_director.projectiles.all(func(q):return not int(q.owner_uid) in retry_ids),"clear removes retry-wave projectiles")

func _kill_wave()->void:
	for e in _live_escort().duplicate():game.enemy_director.damage(e,100000,"melee")

func _test_escort_two_ambush_route()->void:
	_fresh_stage(2)
	var trial=game.main_trials;var d:Dictionary=trial.states[0]
	check(d.cart_path.size()>=2 and d.cart_total>0,"escort has an actual routed path with measured distance")
	trial.begin(0);var start:Vector2=d.cart.position
	game.player.position=game.world.nearest_safe(start+Vector2(30,40));trial.update(.12)
	check(d.cart.position==start,"living ambush units physically stop the escort cart")
	_kill_wave()
	game.player.position=game.world.nearest_safe(start+Vector2(500,0))
	if game.player.position.distance_to(start)>330:
		trial.update(.12);check(d.cart.position==start,"cart waits when the player leaves the escort radius")
	var second_wave=false;var followed_safely=true;var steps=0
	while trial.active_index>=0 and steps<1200:
		game.player.position=game.world.nearest_safe(d.cart.position+Vector2(30,40))
		var old:Vector2=d.cart.position;trial.update(.12);steps+=1
		if old.distance_to(d.cart.position)>15.01 or not game.world.is_walkable(d.cart.position,14):followed_safely=false
		if d.ambush==2 and not second_wave:
			second_wave=true
			check(_live_escort().size()==2 and d.cart_distance>=d.cart_total*.5,"second two-unit ambush appears at achieved route midpoint")
			var held:Vector2=d.cart.position;trial.update(.12)
			check(d.cart.position==held,"second ambush stops cart until its actual units are defeated")
			_kill_wave()
	check(second_wave,"escort always runs both ambushes, including short waypoint paths")
	check(followed_safely,"cart movement stays bounded and respects live world collision throughout its route")
	check(steps<1200 and game.objective_done[0] and trial.active_index==-1,"escort finishes after both waves and routed destination arrival")
	check(_escort_units().is_empty(),"successful escort removes completed-wave runtime enemies")

func _unsafe_hazard_position()->Vector2:
	for p in game.points:
		for offset in [Vector2(0,0),Vector2(240,0),Vector2(0,240),Vector2(-240,0)]:
			var q:Vector2=game.world.nearest_safe(p+offset)
			if q.distance_to(game.spawn_position)<180:continue
			var safe=false
			for camp in game.camp_positions:
				if q.distance_to(camp)<150:safe=true
			if not safe:return q
	return game.points[1]

func _test_death_during_course_trap()->void:
	_fresh_stage(1)
	var trial=game.main_trials;var d:Dictionary=trial.states[1]
	check(trial.begin(1),"hazard course begins in authored combat chapter")
	var hazard=_unsafe_hazard_position();game.player.position=hazard;game.hp=1;game.invulnerable=0;game.shield_time=0
	# The respawn point is also the final flag: an unguarded update used to
	# continue after _hurt()->cancel() and finish this stale course after death.
	d.route=PackedVector2Array([game.checkpoint_position]);d.gate=0;d.time=.01
	trial.local_traps.setup(game,[{"kind":"spikes","p":hazard,"phase":0.0}]);trial.local_traps.clock=1.10
	var resources=_resources();trial.update(.04)
	check(paused and game.ui.dialog_screen.visible and game.hp==game.campaign.max_hp(),"real local trap damage invokes actual death and respawn dialog")
	check(trial.active_index==-1 and d.failed and not game.objective_done[1],"death cancellation prevents stale final gate completion")
	check(trial.local_traps.traps.is_empty() and trial.local_traps.darts.is_empty(),"death safely drains local trap arrays after their in-progress tick")
	check(_resources()==resources and not "超时" in game.ui.toast_label.text,"post-death update grants no reward or misleading timeout message")
	_close_dialogs();check(trial.begin(1),"course remains retryable after actual death")
	game.player.position=hazard;game.hp=1;game.invulnerable=0;game.shield_time=0
	d.route=PackedVector2Array([game.checkpoint_position]);d.gate=0;d.time=5
	trial.local_traps.setup(game,[]);trial.local_traps.clock=0
	trial.local_traps.darts.append({"p":hazard-Vector2(10,0),"v":Vector2(430,0),"life":2.0,"source":hazard-Vector2(60,0)})
	trial.update(.04)
	check(paused and trial.active_index==-1 and not game.objective_done[1],"lethal local dart cancels instead of continuing into respawn flag")
	check(trial.local_traps.darts.is_empty() and trial.local_traps.traps.is_empty(),"local dart callback can cancel without invalidating its active array iterator")
	_close_dialogs();trial.cancel()

func _test_death_rest_stage_cleanup()->void:
	_fresh_stage(2);var trial=game.main_trials
	trial.begin(0)
	for e in _live_escort():game.enemy_director._burst(e,[0.0],150,12,3,"star")
	var ids=_escort_uids();var resources=_resources();game.hp=1;game.invulnerable=0;game.shield_time=0
	var projectile:Dictionary=game.enemy_director.projectiles.back()
	projectile.p=game.player.position-Vector2(10,0);projectile.velocity=Vector2(430,0)
	game.enemy_director._tick_projectiles(.04)
	check(_escort_units().is_empty() and game.enemy_director.projectiles.all(func(q):return not int(q.owner_uid) in ids),"actual death cleans escort units and their projectiles")
	check(_resources()==resources,"actual escort death cleanup never awards cancellation experience or crystals")
	_close_dialogs();trial.begin(0)
	for e in _live_escort():game.enemy_director._burst(e,[0.0],150,12,3,"star")
	ids=_escort_uids();game._rest(game.camp_positions[0])
	check(_escort_units().is_empty() and game.enemy_director.projectiles.all(func(q):return not int(q.owner_uid) in ids),"actual camp rest removes active escort waves and owned projectiles")
	game.enemy_director.clear();game._sync_enemies();trial.begin(0)
	for e in _live_escort():game.enemy_director._burst(e,[0.0],150,12,3,"star")
	ids=_escort_uids();game._load_stage(3);_close_dialogs()
	check(_escort_units().is_empty() and game.enemy_director.projectiles.all(func(q):return not int(q.owner_uid) in ids),"actual stage change cannot retain an escort ambush or projectile")

func _clean()->void:
	for base in [SAVE,SAVE+".world.json"]:
		for path in [base,base+".bak",base+".tmp"]:
			if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
