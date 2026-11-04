extends SceneTree
const Traps=preload("res://scripts/trap_director.gd")
var checks=0
var failures=[]
class TestWorld extends Node2D:
	const WORLD_RECT=Rect2(100,100,3400,2400)
	var wall=false
	func is_walkable(p:Vector2,_radius:float=20)->bool:return WORLD_RECT.has_point(p) and not (wall and p.x>1240)
	func nearest_safe(p:Vector2)->Vector2:return p
	func has_line_of_sight(_a:Vector2,b:Vector2)->bool:return not (wall and b.x>1240)
	func move_actor(p:Vector2,motion:Vector2,_radius:float=20)->Vector2:return p+motion
class TestCampaign extends RefCounted:
	var difficulty="explorer"
class TestUI extends RefCounted:
	func toast(_text:String)->void:pass
class TestGame extends Node2D:
	var world=TestWorld.new()
	var campaign=TestCampaign.new()
	var ui=TestUI.new()
	var player=Sprite2D.new()
	var active=true
	var invulnerable=0.0
	var hp=200.0
	var spawn_position=Vector2(300,2100)
	var camp_positions=[Vector2(500,2100)]
	var last_safe_position=Vector2(1000,1500)
	var hits=0
	func _hurt(amount:float,_source:Vector2,_unblockable:bool=false)->void:
		if invulnerable<=0:hp-=amount;hits+=1;invulnerable=1
	func _effect(_p:Vector2,_c:Color,_k:String,_t:float,_r:float)->void:pass
var game:TestGame
var director:RefCounted
var origin=Vector2(1200,1000)
func _initialize()->void:call_deferred("run")
func fresh(kind:String,rotation:float=0)->void:
	game.hp=200;game.hits=0;game.invulnerable=0;game.player.position=origin;game.world.wall=false
	director.setup(game,[{"kind":kind,"p":origin,"rotation":rotation,"phase":0}]);director.clock=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)
func run()->void:
	game=TestGame.new();root.add_child(game);game.add_child(game.world);game.add_child(game.player)
	director=Traps.new();fresh("spikes")
	director.clock=-1.2;director.update(0.8);check(game.hits==0,"entry grace does not deal damage")
	director.clock=0;director.update(0.8);check(game.hits==0 and director.traps[0].state=="warning","spikes have visible warning before damage")
	director.update(0.35);check(game.hits==1 and director.danger_at(origin),"raised spikes use floor geometry")
	game.invulnerable=0;game.player.position=origin+Vector2(140,0);director.update(0.1);check(game.hits==1,"spike side route is safe")
	check(director.disarm(0),"lever disables active trap");game.player.position=origin;director.update(2);check(game.hits==1,"disabled spike never deals damage")
	check(director.disabled_indices()==[0],"disabled indices support persistence")
	fresh("firejet",PI/2);game.player.position=origin+Vector2(0,140);director.update(1.25);check(game.hits==0,"flame warning is harmless")
	director.update(0.3);check(game.hits==1,"rotated flame cone hits its forward lane")
	game.invulnerable=0;game.player.position=origin+Vector2(140,0);director.update(0.2);check(game.hits==1,"flame side position avoids cone")
	fresh("shooter");game.player.position=origin+Vector2(180,0);director.update(1.1);check(game.hits==0 and director.darts.is_empty(),"arrow tower waits before firing")
	director.update(0.65);check(game.hits==1,"traveling swept arrows hit in lane after warning")
	fresh("shooter");game.player.position=origin+Vector2(180,170);director.update(1.9);check(game.hits==0,"arrow volley can be dodged sideways")
	fresh("shooter");game.world.wall=true;game.player.position=origin+Vector2(250,0);director.update(2);check(game.hits==0 and director.darts.is_empty(),"walls stop trap arrows")
	fresh("pendulum");director.update(0.04);game.player.position=director.traps[0].previous_weight;game.invulnerable=0;director.update(0.04);check(game.hits==1,"moving pendulum weight has swept contact collision")
	game.player.position=origin+Vector2(0,-120);game.invulnerable=0;director.update(0.1);check(game.hits==1,"pendulum has a safe upper side")
	fresh("collapse");director.update(0.5);check(director.traps[0].state=="warning" and game.hits==0,"collapse floor cracks before opening")
	game.player.position=origin+Vector2(180,0);director.update(0.8);check(game.hits==0 and director.traps[0].state=="active","moving off cracked floor avoids fall")
	game.player.position=origin;director.update(0.04);check(game.hits==1 and game.player.position==game.last_safe_position,"opened tile returns fallen player to last safe ground")
	director.update(2);director.update(2);director.update(0.6);check(director.traps[0].state=="rest","collapse tile reforms after safe recovery interval")
	fresh("whirlpool");game.player.position=origin+Vector2(110,0);director.update(1.4);check(is_equal_approx(game.player.position.x,origin.x+110),"whirlpool warning does not pull")
	director.update(0.5);check(game.player.position.x<origin.x+110,"active whirlpool pulls toward its centre")
	game.player.position=origin+Vector2(30,0);game.invulnerable=0;director.update(0.1);check(game.hits==1,"whirlpool inner core damages")
	fresh("spikes");game.spawn_position=origin;director.update(1.2);check(game.hits==0,"camp safe zone overrides hazard damage");game.spawn_position=Vector2(300,2100)
	var before=director.clock;paused=true;director.update(1);check(director.clock==before,"paused world freezes trap phase")
	paused=false;game.player.position=director.traps[0].lever;check(director.nearby_lever(game.player.position)==0,"visible lever is interactable")
	director.disarm(0);check(director.nearby_lever(game.player.position)==-1,"disabled lever cannot trigger repeatedly")
	director=null;game.queue_free();await process_frame
	if failures.is_empty():print("TRAP TESTS PASSED: %d checks"%checks);quit(0)
	else:
		for message in failures:printerr("FAIL: "+message)
		quit(1)
