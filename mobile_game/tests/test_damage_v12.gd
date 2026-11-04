extends SceneTree
const Rules=preload("res://scripts/damage_rules.gd")
const Campaign=preload("res://scripts/campaign.gd")
const Director=preload("res://scripts/enemy_director.gd")
const VERSIONS=[
	["shadow_blob",false],["crystal_thief",false],["wind_gremlin",false],
	["moon_bubble",false],["moon_bubble",true],["thorn_treant",true],
	["windmill_guardian",true],["stone_shell_guardian",true],["lantern_devourer",true]]
var checks:int=0
var failures:Array=[]
var owner:DamageOwner
var director

class ClearWorld:
	extends Node2D
	func is_walkable(_p:Vector2,_radius:float=20)->bool:return true
	func find_path(a:Vector2,b:Vector2)->PackedVector2Array:return PackedVector2Array([a,b])
	func has_line_of_sight(_a:Vector2,_b:Vector2)->bool:return true
	func move_actor(p:Vector2,motion:Vector2,_radius:float=20)->Vector2:return p+motion
class QuietUI:
	extends RefCounted
	func toast(_text:String)->void:pass
class DamageOwner:
	extends Node2D
	var campaign=Campaign.new()
	var world=ClearWorld.new()
	var player=Sprite2D.new()
	var partner=Sprite2D.new()
	var ui=QuietUI.new()
	var hp:float=110
	var invulnerable:float=0
	var shield_time:float=0
	var facing=Vector2.LEFT
	var elapsed:float=0
	var hits:Array=[]
	var attempts:Array=[]
	var defeated:Array=[]
	func _ready()->void:
		add_child(world);add_child(player);add_child(partner)
	func _sprite(_path:String,p:Vector2,size_scale:float)->Sprite2D:
		var sprite=Sprite2D.new();sprite.position=p;sprite.scale=Vector2.ONE*size_scale;sprite.offset=Vector2(0,-200);add_child(sprite);return sprite
	func _hurt(base_damage:float,source:Vector2,unblockable:bool=false,source_kind:String="environment")->void:
		attempts.append(source_kind)
		if hp<=0 or invulnerable>0 or shield_time>0:return
		var guard:bool=not unblockable and facing.dot(player.position.direction_to(source))>0.25
		var resolved:float=Rules.enemy_damage(campaign.max_hp(),base_damage,campaign.defense(),campaign.difficulty,guard,int(campaign.upgrades.shield)) if source_kind=="enemy" else Rules.environment_damage(base_damage,campaign.defense(),campaign.difficulty)
		hp=maxf(0,hp-resolved);invulnerable=1.0;hits.append({"amount":resolved,"kind":source_kind,"maximum":campaign.max_hp(),"hp_after":hp,"guard":guard})
	func _effect(_p:Vector2,_color:Color,_kind:String,_life:float,_radius:float)->void:pass
	func _enemy_defeated(e:Dictionary)->void:defeated.append(e.uid)

func _initialize()->void:call_deferred("_run")

func _run()->void:
	owner=DamageOwner.new();root.add_child(owner);director=Director.new();director.setup(owner)
	_static_contract()
	await _matrix()
	_shared_grace_and_four_hits()
	_protection_and_reflection()
	director.clear();owner.queue_free();await process_frame;await process_frame
	director=null
	if failures.is_empty():
		print("V1.2 DAMAGE TESTS PASSED: %d checks; 324 actual AI hit cases across 4 levels, 3 difficulties, 3 loadouts, 9 enemy variants"%checks)
		call_deferred("quit",0)
	else:
		for failure in failures:printerr("FAIL: "+str(failure))
		printerr("V1.2 DAMAGE TESTS: %d failures / %d checks"%[failures.size(),checks]);call_deferred("quit",1)

func _static_contract()->void:
	_check(Rules.enemy_damage(110,14,3,"explorer",false)==28,"110maxHP rounds minimum27.5 up to28")
	_check(Rules.enemy_damage(143,14,3,"gentle",true,3)==36,"gentle difficulty and max shield cannot lower quarter floor")
	_check(Rules.enemy_damage(205,14,999,"brave",true,3)==52,"high defense and high level still cost ceiling of quarter maxHP")
	_check(Rules.enemy_damage(110,200,3,"explorer",false)==167,"normal resolved damage above floor remains unchanged")
	_check(Rules.enemy_damage(110,200,3,"explorer",true,0)==42,"front guard still mitigates high damage when result exceeds floor")
	_check(Rules.enemy_damage(110,200,3,"explorer",true,3)==28,"upgraded automatic shield bottoms out at quarter maxHP")
	_check(Rules.environment_damage(14,3,"explorer")==9,"environment helper has no quarter minimum")
	_check(Rules.environment_damage(12,7,"gentle")==1,"fall damage keeps ordinary minimum1")
	_check(Rules.environment_damage(20,3,"brave")==17,"trap damage retains its original difficulty/defense formula")

func _matrix()->void:
	var armors:Array=["travel_cloak","moon_water_coat","starlight_guard_cloak"]
	for level in [1,5,10,20]:
		for difficulty in ["gentle","explorer","brave"]:
			for loadout in range(3):
				owner.campaign.xp=30*(level-1)*level;owner.campaign.difficulty=difficulty
				owner.campaign.equipped={"weapon":"training_sword","armor":armors[loadout],"accessory":"twin_star_brooch" if loadout==2 else ""}
				owner.campaign.upgrades={"weapon":0,"armor":loadout+1 if loadout>0 else 0,"accessory":3 if loadout==2 else 0,"shield":loadout+1 if loadout>0 else 0,"bell":0}
				for variant in VERSIONS:
					var e:Dictionary=_fresh(variant[0],variant[1])
					e.cooldown=0
					_advance(0.01)
					var label:String="L%d %s gear%d %s%s"%[level,difficulty,loadout,variant[0],"elite" if variant[1] else ""]
					_check(e.state=="windup" and owner.hits.is_empty(),label+" prepares without early damage")
					for tick in range(200):
						if not owner.hits.is_empty():break
						_advance(0.04)
					_check(not owner.hits.is_empty(),label+" actual attack geometry reaches stationary target")
					if not owner.hits.is_empty():
						var hit:Dictionary=owner.hits[0]
						_check(hit.kind=="enemy" and hit.amount>=ceilf(owner.campaign.max_hp()*0.25),label+" landed hit tagged enemy and costs at least quarter maxHP")
					await process_frame

func _fresh(id:String,boss:bool=false)->Dictionary:
	director.clear();owner.hits.clear();owner.attempts.clear();owner.defeated.clear();owner.campaign.boss_phases.clear()
	owner.player.position=Vector2(420,300);owner.facing=Vector2.LEFT;owner.hp=owner.campaign.max_hp();owner.invulnerable=0;owner.shield_time=0
	return director.spawn(id,Vector2(300,300),boss)

func _advance(delta:float)->void:
	owner.invulnerable=maxf(0,owner.invulnerable-delta);owner.shield_time=maxf(0,owner.shield_time-delta);director.update(delta)

func _shared_grace_and_four_hits()->void:
	owner.campaign.reset_game()
	var e:Dictionary=_fresh("shadow_blob")
	e.attack_serial=1;director._hit_player(e,e.sprite.position)
	_check(owner.hp==82,"quarter damage uses maximum110 not current82HP")
	e.attack_serial=2;owner.campaign.active_character=1;director._hit_player(e,e.sprite.position)
	_check(owner.hp==82 and owner.hits.size()==1,"switching hero cannot bypass shared one-second invulnerability")
	_advance(0.5);e.attack_serial=3;director._hit_player(e,e.sprite.position)
	_check(owner.hp==82,"new attack still blocked during one-second grace")
	owner.invulnerable=0.0;e.attack_serial=4;director._hit_player(e,e.sprite.position)
	_check(owner.hp==54,"second unavoided hit still costs28 rather than quarter of remaining health")
	owner.invulnerable=0;e.attack_serial=5;director._hit_player(e,e.sprite.position)
	owner.invulnerable=0;e.attack_serial=6;director._hit_player(e,e.sprite.position)
	_check(owner.hp==0 and owner.hits.size()==4,"four unavoided minimum-strength enemy hits exhaust maximum HP")
	_check(owner.hits.all(func(hit):return hit.amount==28),"every minimum hit uses fixed maximum-health basis")
	# The actual repeating AI also respects the floor, without manually dispatching.
	e=_fresh("shadow_blob");e.cooldown=0
	for tick in range(600):
		if owner.hp<=0:break
		_advance(0.04)
	_check(owner.hp==0 and owner.hits.size()==4,"actual repeated blob attacks can defeat fresh team in four landed hits")

func _protection_and_reflection()->void:
	var e:Dictionary=_fresh("wind_gremlin")
	owner.shield_time=10;e.cooldown=0
	for tick in range(100):_advance(0.04)
	_check(owner.hp==owner.campaign.max_hp() and owner.hits.is_empty(),"active water protection legitimately avoids quarter-floor hits")
	_check(owner.attempts.has("enemy"),"protection case was actually attacked through enemy dispatch")
	e=_fresh("shadow_blob");e.cooldown=0;_advance(0.01)
	owner.player.position+=Vector2(0,220)
	for tick in range(60):_advance(0.04)
	_check(owner.hits.is_empty(),"dodging the locked leap still avoids all damage")
	e=_fresh("wind_gremlin");owner.player.position=Vector2(620,300);e.cooldown=0;_advance(0.01);_advance(e.warning+0.01)
	var hp:float=e.hp
	director.reflect_near(Vector2(400,300),250)
	for tick in range(30):_advance(0.04)
	_check(e.hp<hp and owner.hits.is_empty(),"reflected projectile harms its enemy without charging team quarter HP")
	owner.campaign.xp=11400;owner.campaign.difficulty="explorer";owner.campaign.equipped={"weapon":"training_sword","armor":"travel_cloak","accessory":""};owner.campaign.upgrades={"weapon":0,"armor":0,"accessory":0,"shield":0,"bell":0}
	owner.hp=owner.campaign.max_hp();owner.invulnerable=0;owner.shield_time=0;owner.hits.clear()
	owner._hurt(12,owner.player.position,true,"environment")
	_check(owner.hits[0].amount==3 and owner.hp==202,"level20 explorer fall remains3damage rather than52quarter floor")

func _check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)
