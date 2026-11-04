extends SceneTree

const Director = preload("res://scripts/enemy_director.gd")
var checks: int = 0
var failures: Array = []
var game: TestGame
var director

class TestCampaign:
	extends RefCounted
	var systems: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/systems.json"))
	var difficulty: String = "brave"
	var boss_phases: Dictionary = {}
	var stage: int = 5
	var saves: int = 0
	func save_game() -> bool:
		saves+=1
		return true

class TestUI:
	extends RefCounted
	var messages: Array = []
	func toast(value: String) -> void:messages.append(value)

class TestWorld:
	extends Node2D
	var walls: Array = []
	var path_calls: int = 0
	var move_calls: int = 0
	func is_walkable(p: Vector2) -> bool:
		for wall in walls:
			if wall.has_point(p):return false
		return true
	func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
		var steps: int = maxi(1,int(ceilf(from.distance_to(to)/5)))
		for i in range(steps+1):
			if not is_walkable(from.lerp(to,float(i)/steps)):return false
		return true
	func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
		path_calls+=1
		if has_line_of_sight(from,to):return PackedVector2Array([from,to])
		return PackedVector2Array([from,Vector2(from.x,-30),Vector2(to.x,-30),to])
	func move_actor(from: Vector2, displacement: Vector2, _radius: float = 20.0) -> Vector2:
		move_calls+=1
		if has_line_of_sight(from,from+displacement):return from+displacement
		return from

class TestGame:
	extends Node2D
	var campaign = TestCampaign.new()
	var world = TestWorld.new()
	var player = Sprite2D.new()
	var partner = Sprite2D.new()
	var ui = TestUI.new()
	var facing: Vector2 = Vector2.RIGHT
	var elapsed: float = 0.0
	var hp: float = 1000.0
	var hits: Array = []
	var defeated: Array = []
	var effects: Array = []
	func _ready() -> void:
		add_child(world);add_child(player);add_child(partner)
	func _sprite(_path: String, p: Vector2, scale_value: float) -> Sprite2D:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.position=p;sprite.scale=Vector2.ONE*scale_value;sprite.offset=Vector2(0,-200)
		add_child(sprite)
		return sprite
	func _hurt(amount: float, source: Vector2, _unblockable: bool = false, _source_kind: String = "environment") -> void:
		hp-=amount;hits.append({"amount":amount,"source":source})
	func _effect(p: Vector2, color: Color, kind: String, life: float, radius: float) -> void:
		effects.append([p,color,kind,life,radius])
	func _enemy_defeated(e: Dictionary) -> void:defeated.append(e.uid)


func _initialize() -> void:call_deferred("_run")


func _run() -> void:
	game=TestGame.new();root.add_child(game)
	director=Director.new();director.setup(game)
	_test_species_and_poses()
	_test_locked_geometry()
	_test_projectiles()
	_test_navigation_and_los()
	_test_bosses()
	_test_interrupt_and_rewards()
	_test_pause()
	director.clear()
	game.queue_free()
	await process_frame
	_check(director._game()==null,"director weak reference releases destroyed scene")
	director=null
	if failures.is_empty():
		print("ENEMY DIRECTOR TESTS PASSED: %d checks"%checks)
		call_deferred("quit",0)
	else:
		for failure in failures:printerr("FAIL: "+str(failure))
		printerr("ENEMY DIRECTOR TESTS: %d failures / %d checks"%[failures.size(),checks])
		call_deferred("quit",1)


func _fresh(id: String, boss: bool = false) -> Dictionary:
	director.clear();game.world.walls.clear();game.hits.clear();game.defeated.clear()
	game.campaign.boss_phases.clear();game.campaign.difficulty="brave"
	game.player.position=Vector2(440,300)
	return director.spawn(id,Vector2(300,300),boss,2)


func _windup(e: Dictionary) -> void:
	e.state="chase";e.cooldown=0.0
	director.update(0.01)


func _finish_tell(e: Dictionary) -> void:director.update(float(e.warning)+0.01)


func _test_species_and_poses() -> void:
	var expected: Dictionary = {"shadow_blob":"leap","crystal_thief":"dash","wind_gremlin":"gust","moon_bubble":"ring","thorn_treant":"root_fan","windmill_guardian":"wind_lanes","stone_shell_guardian":"charge","lantern_devourer":"shadow_orbs"}
	for id in expected:
		var e: Dictionary = _fresh(id,id in ["thorn_treant","windmill_guardian","stone_shell_guardian","lantern_devourer"])
		_windup(e)
		_check(e.state=="windup" and e.attack_style==expected[id],"%s uses its own attack style"%id)
		_check(e.warning>=(1.3 if e.boss else 0.8),"%s telegraph meets readable duration"%id)
		_check(e.sprite.scale!=e.base_scale or e.sprite.rotation!=0 or e.sprite.offset!=e.base_offset,"%s has a distinct preparation pose"%id)
		_check(e.objective_index==2 and e.hp>0,"%s keeps encounter contract fields"%id)
	var gentle: Dictionary = _fresh("shadow_blob")
	game.campaign.difficulty="gentle";_windup(gentle)
	_check(is_equal_approx(gentle.tell_duration,1.2),"gentle difficulty extends normal tells by0.3seconds")
	_check(director.spawn("not-a-species",Vector2.ZERO).is_empty(),"unknown species safely rejected")


func _test_locked_geometry() -> void:
	var e: Dictionary = _fresh("shadow_blob")
	_windup(e)
	var aim: Vector2 = e.aim
	director.update(0.55)
	_check(game.hits.is_empty(),"shadow crouch does not deal early damage")
	game.player.position=aim+Vector2(0,190)
	_finish_tell(e)
	_check(e.aim==aim,"jump target remains locked after player dodges")
	director.update(0.8)
	_check(game.hits.is_empty(),"moving away from locked jump circle avoids damage")
	_check(e.state=="recover","jump has a genuine recovery state")
	_check(e.sprite.offset==e.base_offset and e.sprite.scale==e.base_scale,"jump restores its base pose after landing")
	e=_fresh("shadow_blob");_windup(e);_finish_tell(e);director.update(0.9)
	_check(game.hits.size()==1,"staying in jump circle causes exactly one hit")
	e=_fresh("crystal_thief");_windup(e)
	game.player.position+=Vector2(0,100)
	_finish_tell(e);director.update(0.8)
	_check(game.hits.is_empty(),"thief triangular dash can be dodged sideways")
	e=_fresh("crystal_thief");_windup(e);_finish_tell(e)
	var start: Vector2 = e.sprite.position
	director.update(0.08)
	_check(e.sprite.position.distance_to(start)>10,"thief dash travels through space instead of teleporting")
	director.update(0.8)
	_check(game.hits.size()==1,"dash line hits once per attack despite multiple simulation steps")


func _test_projectiles() -> void:
	var e: Dictionary = _fresh("wind_gremlin")
	game.player.position=Vector2(670,300)
	_windup(e);_finish_tell(e)
	_check(director.projectiles.size()==3,"wind gremlin emits a three-projectile cone")
	_check(game.hits.is_empty(),"wind projectiles have travel time before hitting distant player")
	var first: Vector2 = director.projectiles[0].p
	director.update(0.1)
	_check(director.projectiles[0].p.distance_to(first)>20,"projectile position advances with delta")
	director.update(1.7)
	_check(game.hits.size()==1,"same burst cannot hit player repeatedly")
	director.clear()
	_check(director.projectiles.is_empty() and director.enemies.is_empty(),"stage clear removes entities and traveling projectiles")
	e=_fresh("moon_bubble");e.sequence=1
	game.player.position=Vector2(600,300)
	_windup(e);_finish_tell(e)
	_check(e.attack_style=="bubble_volley" and director.projectiles.size()==3,"moon bubble alternates shockwave with slower bubbles")
	_check(director.projectiles[0].velocity.length()<170,"bubbles are slower than wind projectiles")
	e=_fresh("wind_gremlin");game.player.position=Vector2(650,300)
	_windup(e);_finish_tell(e)
	var hp: float = e.hp
	_check(director.reflect_near(Vector2(400,300),180)==3,"shield can reflect nearby traveling burst")
	director.update(0.7)
	_check(e.hp<hp and game.hits.is_empty(),"reflected projectiles damage enemy and protect the player")
	e=_fresh("wind_gremlin");game.player.position=Vector2(650,300)
	_windup(e);_finish_tell(e)
	game.world.walls=[Rect2(410,100,60,400)]
	director.update(1.8)
	_check(game.hits.is_empty(),"walls stop projectile hits through cover")
	_check(director.projectiles.is_empty(),"wall impacts clean up projectiles")


func _test_navigation_and_los() -> void:
	var e: Dictionary = _fresh("shadow_blob")
	game.player.position=Vector2(650,300)
	game.world.walls=[Rect2(410,100,60,400)]
	var before: int = game.world.path_calls
	e.memory=3.0;e.last_seen=game.player.position;e.state="chase";e.cooldown=0.0
	director.update(0.4)
	_check(game.world.path_calls>before and e.path.size()>2,"remembered target uses navigation detour around wall")
	_check(e.warning==0 and game.hits.is_empty(),"occluded target cannot trigger a melee windup through wall")
	_check(director.nearest_target(game.player.position,800).is_empty(),"player auto-targeting rejects enemies behind cover")
	game.world.walls.clear()
	_check(not director.nearest_target(game.player.position,800).is_empty(),"visible target can be selected")
	game.player.position=Vector2(-900,-900);e.sprite.position=e.origin+Vector2(700,0);e.state="chase"
	var distance: float = e.sprite.position.distance_to(e.origin)
	director.update(0.4)
	_check(e.state=="return" and e.sprite.position.distance_to(e.origin)<distance,"leash returns enemy instead of chasing across the map")
	_check(not director.in_combat(game.player.position,600),"distant leashed enemy does not hold combat forever")


func _test_bosses() -> void:
	var e: Dictionary = _fresh("thorn_treant",true)
	for pattern in ["root_fan","slam","sweep"]:
		e.state="chase";e.cooldown=0;_windup(e)
		_check(e.attack_style==pattern,"treant cycles distinct %s geometry"%pattern)
		e.state="recover";e.state_time=0
	e=_fresh("thorn_treant",true);_windup(e)
	game.player.position=e.attack_origin+Vector2.from_angle(0.325)*225
	_finish_tell(e);director.update(1.2)
	_check(game.hits.is_empty(),"root fan leaves a traversable gap between its locked lanes")
	e=_fresh("stone_shell_guardian",true);_windup(e)
	_finish_tell(e);director.update(0.8)
	_check(e.state=="recover" and e.vulnerable>3,"stone charge opens an extended armor-break recovery")
	e=_fresh("windmill_guardian",true);e.phase=1;_windup(e);_finish_tell(e)
	_check(director.projectiles.size()==6,"second-phase windmill creates two distinct gust lanes")
	e=_fresh("lantern_devourer",true)
	game.campaign.saves=0
	e.hp=e.max_hp*0.68;director.update(0)
	_check(e.phase==1 and game.campaign.boss_phases.get("5")==1 and game.campaign.saves==1,"devourer phase threshold saves once")
	director.update(0)
	_check(game.campaign.saves==1,"repeated updates do not duplicate phase saves")
	director.clear()
	e=director.spawn("lantern_devourer",Vector2(300,300),true)
	_check(e.phase==1 and is_equal_approx(e.hp/e.max_hp,0.70),"boss reload resumes exact70percent phase boundary")
	e.hp=e.max_hp*0.34;director.update(0)
	_check(e.phase==2,"devourer has a third phase")
	director.clear();e=director.spawn("lantern_devourer",Vector2(300,300),true)
	_check(is_equal_approx(e.hp/e.max_hp,0.35),"third phase reload uses35percent rather than generic thirds")
	game.player.position=Vector2(440,300);_windup(e)
	_check(e.attack_style=="safe_sector" and e.warning>=1.5,"last phase announces a readable safe-sector ring")
	game.player.position=e.attack_origin+Vector2.from_angle(e.safe_angle)*240
	_finish_tell(e);director.update(1.5)
	_check(game.hits.is_empty(),"clearly marked safe sector avoids final ring")
	e=_fresh("lantern_devourer",true);_windup(e)
	var start: Vector2 = e.sprite.position
	_finish_tell(e)
	_check(e.sprite.position!=start and director.projectiles.size()==4,"first devourer phase teleports then launches slow shadow orbs")


func _test_interrupt_and_rewards() -> void:
	var e: Dictionary = _fresh("shadow_blob");_windup(e)
	_check(director.interrupt(e,1.5),"bell or wind can interrupt ordinary monster")
	_check(e.state=="stunned" and e.warning==0 and e.sprite.scale==e.base_scale,"interrupt cancels tell and restores pose")
	director.update(0.8)
	_check(game.hits.is_empty(),"cancelled attack cannot land during stun")
	var hp: float = e.hp
	director.damage(e,6,"melee")
	_check(e.hp==hp-6,"normal enemy takes full weapon damage")
	director.damage(e,999,"fire");director.damage(e,999,"fire")
	_check(game.defeated.size()==1 and e.state=="dead","defeat callback and drops are emitted exactly once")
	_check(e.sprite.scale==e.base_scale and e.sprite.rotation==0 and e.sprite.offset==e.base_offset,"defeat restores initial pose before fading")
	e=_fresh("thorn_treant",true)
	hp=e.hp;director.damage(e,20,"melee")
	_check(e.hp==hp-5,"closed boss armor reduces damage to25percent without softlock")
	director.expose(e,3.0);hp=e.hp;director.damage(e,20,"melee")
	_check(e.hp==hp-20,"exposed boss core takes full damage")
	_check(not director.interrupt(e,1.0),"boss cannot be stun-locked by bell")


func _test_pause() -> void:
	var e: Dictionary = _fresh("wind_gremlin");_windup(e);_finish_tell(e)
	var warning: float = e.warning
	var time: float = e.action_time
	var position: Vector2 = director.projectiles[0].p
	paused=true;director.update(1.0)
	_check(e.warning==warning and e.action_time==time and director.projectiles[0].p==position,"pause freezes windups actions and traveling projectiles")
	paused=false


func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:failures.append(message)
