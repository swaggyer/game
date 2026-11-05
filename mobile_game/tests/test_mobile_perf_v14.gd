extends SceneTree
const Locomotion=preload("res://scripts/locomotion.gd")
const Hero=preload("res://scripts/hero_actions.gd")
const Enemies=preload("res://scripts/enemy_director.gd")
const Audio=preload("res://scripts/audio_director.gd")
const Campaign=preload("res://scripts/campaign.gd")
var checks:int=0
var failures:Array[String]=[]

class World extends Node2D:
	var paths:int=0
	var los_blocked:bool=false
	var narrow_corner:bool=false
	func has_line_of_sight(_a:Vector2,_b:Vector2)->bool:return not los_blocked
	func find_path(a:Vector2,b:Vector2)->PackedVector2Array:
		paths+=1
		return PackedVector2Array([a,Vector2(a.x,70),Vector2(b.x,70),b]) if narrow_corner else PackedVector2Array([a,b])
	func move_actor(p:Vector2,motion:Vector2,_radius:float=20)->Vector2:
		return p if narrow_corner and p.y<50 and absf(motion.x)>0.1 else p+motion
	func is_walkable(_p:Vector2,_radius:float=20)->bool:return true
class QuietUI extends RefCounted:
	func toast(_text:String)->void:pass
class Owner extends Node2D:
	var campaign=Campaign.new()
	var world=World.new()
	var player=Sprite2D.new()
	var partner=Sprite2D.new()
	var attack_sound=AudioStreamPlayer.new()
	var chime_sound=AudioStreamPlayer.new()
	var facing=Vector2.RIGHT
	var invulnerable:float=0.0
	var ui=QuietUI.new()
	func _ready()->void:
		for child:Node in [world,player,partner,attack_sound,chime_sound]:add_child(child)
	func _sprite(_path:String,p:Vector2,_scale:float)->Sprite2D:
		var sprite:Sprite2D=Sprite2D.new();sprite.position=p;add_child(sprite);return sprite
	func _effect(_p:Vector2,_color:Color,_kind:String,_life:float,_radius:float)->void:pass
	func _hurt(_damage:float,_source:Vector2,_unblockable:bool=false,_kind:String="environment")->void:pass
	func _enemy_defeated(_enemy:Dictionary)->void:pass

func _initialize()->void:call_deferred("_run")

func _run()->void:
	var owner=Owner.new();root.add_child(owner)
	var walk=Locomotion.new();walk.setup(owner)
	var cached:int=walk._textures.size()
	_check(cached>=216,"all locomotion frames are loaded before input")
	for actor:String in ["wangzai","xiaomantou","little_dragon"]:
		for direction:int in range(8):
			for frame:int in range(8):
				walk.animate(owner.player,actor,Vector2.from_angle(direction*PI/4),16.0,1.0/60.0)
	_check(walk._textures.size()==cached,"all24 directions and192 gait steps reuse warm textures")
	var hero=Hero.new();hero.setup(owner);cached=hero._textures.size()
	_check(cached>=96,"all combat frames are loaded before the first attack")
	for character:int in range(2):
		hero._character=character
		for direction:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			hero._facing=direction
			for combo:int in range(3):
				hero.combo=combo
				for phase:int in range(4):hero._set_pose(phase)
	_check(hero._textures.size()==cached,"all96 combat poses reuse warm textures")
	var enemies=Enemies.new();enemies.setup(owner)
	var enemy:Dictionary=enemies.spawn("shadow_blob",Vector2.ZERO)
	for frame:int in range(120):enemies._move(enemy,Vector2(300,0),64.0,1.0/60.0)
	_check(owner.world.paths==0 and enemy.sprite.position.x>100,"clear sight moves correctly without any A* request")
	owner.world.los_blocked=true;owner.world.paths=0;enemy.path_age=0
	for frame:int in range(120):enemies._move(enemy,Vector2(500,0),64.0,1.0/60.0)
	_check(owner.world.paths>0 and owner.world.paths<=5,"blocked sight reuses a bounded-rate A* path")
	owner.world.los_blocked=false;owner.world.narrow_corner=true;owner.world.paths=0
	enemy.sprite.position=Vector2.ZERO;enemy.path_age=0;enemy.direct_blocked=0
	for frame:int in range(120):enemies._move(enemy,Vector2(200,0),64.0,1.0/60.0)
	_check(owner.world.paths>0 and enemy.sprite.position.y>50,"body collision on a clear centre ray falls back to a detour instead of softlocking")
	owner.world.narrow_corner=false;owner.player.position=Vector2(2000,0)
	enemy.sprite.position=Vector2.ZERO;enemy.state="patrol";enemy.memory=0;enemy.dormant_time=0
	enemies.update(0.04)
	_check(enemy.sprite.position==Vector2.ZERO,"distant non-combat patrol can skip a visual tick")
	enemies.update(0.20)
	_check(is_equal_approx(enemy.cooldown,1.4),"distant patrol still advances accumulated return simulation")
	enemy.state="windup";enemy.warning=1.0;enemy.tell_duration=1.0
	enemies.update(0.04)
	_check(is_equal_approx(enemy.warning,0.96),"already committed enemy tell remains full-rate at any distance")
	var audio=Audio.new();audio.settings_path="user://perf-v14-audio-settings.json";audio.setup(owner);audio.set_process(false)
	var source_ids:Dictionary={}
	for path:String in audio._music_sources:source_ids[path]=audio._music_sources[path].get_instance_id()
	_check(source_ids.size()>=4,"title regional battle and boss audio sources are warmed during loading")
	for frame:int in range(12):
		audio.set_music_context(["title","battle","boss","explore"][frame%4])
	for path:String in source_ids:_check(audio._music_sources[path].get_instance_id()==source_ids[path],"context changes retain the same decoded source resource: "+path.get_file())
	audio.stop_music();enemies.clear();hero.game=null;walk.game=null
	owner.queue_free();await process_frame;await process_frame
	audio=null;hero=null;walk=null;enemies=null;owner=null
	await create_timer(0.1,true).timeout
	for failure:String in failures:printerr("FAIL: "+failure)
	print("MOBILE V1.4 PERFORMANCE REGRESSION %s: %d checks"%["PASSED" if failures.is_empty() else "FAILED",checks])
	quit(0 if failures.is_empty() else 1)

func _check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)
