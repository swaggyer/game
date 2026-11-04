extends SceneTree

const Actions = preload("res://scripts/hero_actions.gd")
const Campaign = preload("res://scripts/campaign.gd")

class TestWorld extends Node2D:
	var blocked = false
	func has_line_of_sight(_a:Vector2,_b:Vector2)->bool:return not blocked
	func move_actor(p:Vector2,offset:Vector2,_radius:float=20)->Vector2:return p+offset

class TestDirector extends RefCounted:
	var enemies:Array=[]
	var hits:Array=[]
	var interrupts=0
	func nearest_target(p:Vector2,reach:float,forward:Vector2=Vector2.ZERO)->Dictionary:
		for e in enemies:
			if e.hp>0 and p.distance_to(e.sprite.position)<reach and (forward==Vector2.ZERO or forward.dot(p.direction_to(e.sprite.position))>0):return e
		return {}
	func damage(e:Dictionary,amount:float,kind:String="melee")->bool:
		e.hp-=amount;hits.append({"damage":amount,"kind":kind});return true
	func interrupt(_e:Dictionary,_duration:float)->void:interrupts+=1
	func expose(_e:Dictionary,_duration:float)->void:pass

class TestGame extends Node2D:
	var campaign=Campaign.new()
	var enemy_director=TestDirector.new()
	var world=TestWorld.new()
	var player=Sprite2D.new()
	var partner=Sprite2D.new()
	var dragon=Sprite2D.new()
	var attack_sound=AudioStreamPlayer.new()
	var facing=Vector2.RIGHT
	var invulnerable=0.0
	func _effect(_p:Vector2,_color:Color,_kind:String,_life:float,_radius:float)->void:pass

var game
var actions
var enemy

func _initialize():call_deferred("run")

func reset_target(character:int=0):
	actions.reset()
	game.campaign.active_character=character
	game.world.blocked=false
	game.facing=Vector2.RIGHT
	game.player.position=Vector2(1000,1000)
	enemy.sprite.position=Vector2(1120,1000)
	enemy.hp=100.0
	game.enemy_director.hits.clear()
	game.enemy_director.interrupts=0

func run():
	game=TestGame.new();root.add_child(game)
	game.add_child(game.world);game.add_child(game.player);game.add_child(game.partner);game.add_child(game.dragon);game.add_child(game.attack_sound)
	var enemy_sprite=Sprite2D.new();game.add_child(enemy_sprite)
	enemy={"sprite":enemy_sprite,"hp":100.0,"boss":false}
	game.enemy_director.enemies.append(enemy)
	actions=Actions.new();actions.setup(game)
	reset_target()
	assert(actions.start_attack())
	assert(enemy.hp==100.0,"damage must not occur on button press")
	var movement=actions.update(0.14,Vector2.RIGHT)
	assert(movement.length()<1 and movement.length()>0,"windup allows reduced movement")
	assert(enemy.hp==100.0,"damage waits for contact")
	actions.update(0.02,Vector2.ZERO)
	assert(enemy.hp<100 and game.enemy_director.hits.size()==1,"melee hits at contact")
	actions.update(0.50,Vector2.ZERO)
	assert(game.enemy_director.hits.size()==1 and not actions.busy,"one hit per attack")
	assert(actions.start_attack() and actions.combo==1,"timely next press advances combo")
	actions.update(0.38,Vector2.ZERO)
	assert(actions.start_attack(),"input buffers in recovery")
	actions.update(0.15,Vector2.ZERO)
	assert(actions.busy and actions.combo==2 and actions.state=="windup","buffer chains once into shield finisher")
	actions.update(0.29,Vector2.ZERO)
	assert(game.enemy_director.interrupts==1,"shield contact interrupts")
	actions.update(0.7,Vector2.ZERO)
	actions.update(0.9,Vector2.ZERO)
	assert(actions.start_attack() and actions.combo==0,"combo expires without repeated input")
	reset_target(1)
	assert(actions.start_attack())
	actions.update(0.24,Vector2.ZERO)
	assert(actions.projectiles.is_empty() and enemy.hp==100,"bell has real windup")
	actions.update(0.02,Vector2.ZERO)
	assert(actions.projectiles.size()==1 and enemy.hp==100,"bell contact launches projectile, not instant damage")
	actions.update(0.10,Vector2.ZERO)
	assert(enemy.hp==100,"note needs travel time")
	actions.update(0.10,Vector2.ZERO)
	assert(enemy.hp<100 and game.enemy_director.hits.size()==1 and actions.projectiles.is_empty(),"swept projectile collision hits once")
	reset_target(0)
	game.world.blocked=true
	actions.start_attack();actions.update(0.30,Vector2.ZERO)
	assert(enemy.hp==100,"melee cannot strike through walls")
	reset_target(1)
	actions.start_attack();actions.update(0.26,Vector2.ZERO)
	game.world.blocked=true
	actions.update(0.10,Vector2.ZERO)
	assert(actions.projectiles.is_empty() and enemy.hp==100,"walls absorb echo projectile")
	reset_target(0)
	assert(actions.start_skill_visual("fire"))
	actions.update(0.24,Vector2.ZERO)
	assert(actions.state=="skill_windup")
	actions.update(0.02,Vector2.ZERO)
	assert(actions.state=="skill_release" and enemy.hp==100,"skill visuals never duplicate root skill damage")
	actions.update(0.40,Vector2.ZERO)
	assert(not actions.busy)
	print("PASS hero actions: delayed contact, one-hit melee, buffered bounded combo, shield interrupt, real projectile travel/collision, wall blocking, skill timing")
	actions=null;game.queue_free()
	await process_frame
	quit(0)
