extends SceneTree
const Campaign=preload("res://scripts/campaign.gd")
const SAVE="user://balance-v11-test.json"
var game:Node2D
var checks:int=0
var failures:Array=[]

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	_clean()
	var fresh=Campaign.new()
	_check(fresh.difficulty=="explorer" and fresh.max_hp()==110,"fresh campaign defaults to explorer and110HP")
	fresh.difficulty="gentle";fresh.reset_game()
	_check(fresh.difficulty=="explorer","reset defaults to explorer")
	var scene:PackedScene=load("res://scenes/main.tscn")
	game=scene.instantiate();game.campaign.save_path=SAVE;root.add_child(game);await process_frame
	game.set_process(false)
	_check("星灯探险家" in game.ui.difficulty_choice.text and "推荐" in game.ui.difficulty_choice.text,"title recommends actual explorer default")
	game._start(false);_close()
	_check(game.campaign.difficulty=="explorer" and game.hp==110,"actual main scene starts explorer with110HP")
	var specifications:Array=[
		["shadow_blob",false,14,30],["crystal_thief",false,18,45],
		["wind_gremlin",false,24,60],["moon_bubble",false,28,85],
		["moon_bubble",true,38,650],["thorn_treant",true,28,300],
		["windmill_guardian",true,36,460],["stone_shell_guardian",true,48,900],
		["lantern_devourer",true,64,1350]]
	game.enemy_director.clear();game.enemies=game.enemy_director.enemies;game.campaign.boss_phases.clear()
	for spec in specifications:
		var e:Dictionary=game.enemy_director.spawn(spec[0],game.spawn_position+Vector2(170,0),spec[1])
		_check(not e.is_empty() and e.attack==spec[2],"%s %s uses actual raised attack%d"%[spec[0],"elite/boss" if spec[1] else "normal",spec[2]])
		_check(e.max_hp==spec[3] and e.hp==spec[3],"%s HP unchanged at%d"%[spec[0],spec[3]])
	game.enemy_director.clear();game.enemies=game.enemy_director.enemies
	game.player.position=game.spawn_position;game.facing=Vector2.LEFT
	game.hp=game.campaign.max_hp();game.invulnerable=0;game.shield_time=0;game.hero_actions.reset()
	var blob:Dictionary=game.enemy_director.spawn("shadow_blob",game.world.nearest_safe(game.player.position+Vector2(120,0)))
	blob.cooldown=0;game.enemy_director.update(0.01)
	_check(blob.state=="windup" and blob.warning>=0.8,"stronger blob still gives readable warning")
	game.enemy_director.update(0.5)
	_check(game.hp==110,"raised attack never damages before windup")
	game.enemy_director.update(blob.warning+0.02);game.enemy_director.update(0.6)
	_check(game.hp==101,"actual blob leap resolves explorer14×0.85 minus3defense as9damage")
	var baseline:int=maxi(1,int(roundf(6*0.85))-3)
	_check(baseline==2 and (110-game.hp)/baseline==4.5,"early unblocked hit is4.5times the v1baseline")
	game.enemy_director.clear();game.enemies=game.enemy_director.enemies
	game.player.position=game.spawn_position;game.facing=Vector2.RIGHT;game.hp=110;game.invulnerable=0
	game._hurt(14,game.player.position+Vector2(100,0))
	_check(game.hp==107,"front shield retains75percent mitigation with rounding9to3")
	_check(is_equal_approx(game.invulnerable,1.0),"one-second shared invulnerability remains")
	game.hero_actions.reset();game._switch(1);game._hurt(64,game.player.position+Vector2(100,0))
	_check(game.hp==107,"hero switch does not reset invulnerability under stronger attack")
	for spec in [["gentle",143,6],["explorer",110,9],["brave",110,11]]:
		game.campaign.difficulty=spec[0];game.hp=game.campaign.max_hp();game.invulnerable=0;game.shield_time=0
		game._hurt(14,game.player.position-Vector2(100,0),true)
		_check(game.campaign.max_hp()==spec[1] and game.hp==float(spec[1]-spec[2]),"%s preserves its life and damage multipliers"%spec[0])
	# Save migration must preserve an explicit old difficulty instead of forcing
	# everyone onto the new default.
	for mode in ["gentle","explorer","brave"]:
		game.campaign.difficulty=mode;game.campaign.save_game()
		var restored=Campaign.new();restored.save_path=SAVE
		_check(restored.load_save() and restored.difficulty==mode,"existing%s save keeps chosen difficulty"%mode)
	game.campaign.difficulty="invalid-old-value";game.campaign.save_game()
	var fallback=Campaign.new();fallback.save_path=SAVE;fallback.load_save()
	_check(fallback.difficulty=="explorer","invalid saved difficulty falls back to new explorer default")
	var run=Campaign.new();var total:int=0
	for i in range(21):
		var reward:Dictionary=run.complete_stage(i)
		_check(reward.first_clear,"stage%d has no added level-grind gate"%i)
		total+=int(reward.xp)
	_check(total==11400 and run.xp==11400 and run.level()==20,"main quest budget remains11400XP and guarantees level20")
	game.campaign.xp=11400;game.campaign.difficulty="explorer";game.campaign.equipped={"weapon":"training_sword","armor":"travel_cloak","accessory":""}
	game.campaign.upgrades={"weapon":0,"armor":0,"accessory":0,"shield":0,"bell":0}
	game.hp=game.campaign.max_hp();game.invulnerable=0;game.shield_time=0;game.hero_actions.reset()
	_check(game.campaign.max_hp()==205 and game.campaign.defense()==7,"level20 starting cloak still provides205HP and7defense")
	game._hurt(64,game.player.position-Vector2(100,0),true)
	_check(game.hp==158,"late boss hit deals47damage and does not one-shot an unupgraded level20 team")
	game.hero_actions.game=null;game.queue_free();await process_frame;await process_frame
	_clean()
	if failures.is_empty():
		print("V1.1 BALANCE TESTS PASSED: %d checks"%checks);call_deferred("quit",0)
	else:
		for failure in failures:printerr("FAIL: "+str(failure))
		printerr("V1.1 BALANCE TESTS: %d failures / %d checks"%[failures.size(),checks]);call_deferred("quit",1)

func _close() -> void:
	for i in range(3):
		if game.ui.dialog_screen.visible:game.ui._close_dialog()

func _check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message)

func _clean() -> void:
	for base in [SAVE,SAVE+".world.json"]:
		for suffix in ["",".bak",".tmp"]:
			var path:String=ProjectSettings.globalize_path(base+suffix)
			if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
