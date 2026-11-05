extends Node2D
const Campaign=preload("res://scripts/campaign.gd")
const OpenWorld=preload("res://scripts/open_world.gd")
const MobileUI=preload("res://scripts/mobile_ui.gd")
const EnemyDirector=preload("res://scripts/enemy_director.gd")
const HeroActions=preload("res://scripts/hero_actions.gd")
const TrapDirector=preload("res://scripts/trap_director.gd")
const AreaMap=preload("res://scripts/area_map.gd")
const DamageRules=preload("res://scripts/damage_rules.gd")
const MainTrials=preload("res://scripts/main_trials.gd")
const Challenges=preload("res://scripts/challenge_director.gd")
const Locomotion=preload("res://scripts/locomotion.gd")
const AudioDirector=preload("res://scripts/audio_director.gd")
var campaign=Campaign.new()
var world:Node2D
var ui:CanvasLayer
var camera:Camera2D
var player:Sprite2D
var partner:Sprite2D
var dragon:Sprite2D
var enemy_director=EnemyDirector.new()
var main_trials=MainTrials.new()
var challenge_director=Challenges.new()
var locomotion=Locomotion.new()
var hero_actions=HeroActions.new()
var trap_director=TrapDirector.new()
var enemies:Array=[]
var points:Array=[]
var spawn_position=Vector2(500,2000)
var lamp_position=Vector2(1800,1300)
var camp_positions:Array=[]
var chest_positions:Array=[]
var claimed_chests:Array=[]
var explored:Array=[]
var checkpoint_position=Vector2.ZERO
var last_safe_position=Vector2.ZERO
var objective_done:Array=[false,false,false]
var objectives:Array=[]
var objective_sprites:Array=[]
var chest_sprites:Array=[]
var camp_sprites:Array=[]
var lamp_sprite:Sprite2D
var objective_definitions:Array=[]
var done=0
var hp=143.0
var facing=Vector2.RIGHT
var move_input=Vector2.ZERO
var elapsed=0.0
var attack_cd=0.0
var skill_cd=0.0
var invulnerable=0.0
var shield_time=0.0
var wind_time=0.0
var pending_skill:Dictionary={}
var active=false
var changing_stage=false
var stage_info:Dictionary={}
var context_latch:Dictionary={}
var effects:Array=[]
var textures:Dictionary={}
var world_saves:Dictionary={}
var challenge_saves:Dictionary={}
var font:Font
var combat_overlay:Node2D
var mini_map:Control
var map_button:Button
var attack_sound:AudioStreamPlayer
var chime_sound:AudioStreamPlayer
var music:AudioStreamPlayer
var audio_director=AudioDirector.new()
var music_combat_hold=0.0
var save_tick=0.0
var map_tick=0.0
var bell_cooldown=0.0
var companion_paths:Dictionary={}
var companion_path_tick=0.0
var puzzle_hold:Dictionary={}
var encounter_spawned:Array=[]
var guide_path=PackedVector2Array()
var guide_target=-2
var battle_waves:Dictionary={}
var hud_tick=0.0
var guide_origin=Vector2.INF
var guide_destination=Vector2.INF
var autosave_thread:Thread

func _ready() -> void:
	Input.use_accumulated_input=false
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	font=load("res://assets/ui.ttf")
	objective_definitions=JSON.parse_string(FileAccess.get_file_as_string("res://data/objectives.json"))
	world=OpenWorld.new();add_child(world);world.configure(0,0)
	camera=Camera2D.new();camera.zoom=Vector2(0.95,0.95)
	camera.position_smoothing_enabled=true;camera.position_smoothing_speed=12
	camera.limit_left=100;camera.limit_top=100;camera.limit_right=3500;camera.limit_bottom=2500
	add_child(camera)
	player=_sprite("res://assets/actors/wangzai_front.png",world.definition.spawn,0.65)
	partner=_sprite("res://assets/actors/xiaomantou_front.png",player.position+Vector2(-65,35),0.60)
	dragon=_sprite("res://assets/enemies/little_dragon_right.png",player.position+Vector2(-125,5),0.42)
	combat_overlay=Node2D.new();combat_overlay.z_index=4000;combat_overlay.draw.connect(_draw_overlay);add_child(combat_overlay)
	ui=MobileUI.new();add_child(ui);campaign.load_save();ui.setup(campaign)
	_connect_ui();_setup_audio()
	enemy_director.setup(self);hero_actions.setup(self);enemies=enemy_director.enemies
	main_trials.setup(self);challenge_director.setup(self);locomotion.setup(self)
	map_button=ui._button("",_show_area_map,Vector2(220,175));map_button.name="AreaMapButton"
	ui.hud.add_child(map_button);ui._anchor_rect(map_button,Control.PRESET_TOP_RIGHT,Vector2(-246,108),Vector2(220,175))
	mini_map=AreaMap.new();map_button.add_child(mini_map);mini_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.show_title();player.hide();partner.hide();dragon.hide();map_button.hide()
	if "--smoke" in OS.get_cmdline_user_args():
		_start(false);ui.show_hud();get_tree().paused=false

func _connect_ui() -> void:
	ui.move_changed.connect(func(v):move_input=v)
	ui.attack_pressed.connect(_attack);ui.context_pressed.connect(_context_press);ui.context_released.connect(_context_release)
	ui.context_cancelled.connect(func():context_latch.clear())
	ui.switch_requested.connect(_switch);ui.pause_requested.connect(_pause);ui.resume_requested.connect(_resume)
	ui.start_requested.connect(_start);ui.new_game_requested.connect(func():_start(false))
	ui.stage_requested.connect(func(i):
		if i>=0 and i<21 and i<=campaign.progress:_resume();_load_stage(i))
	ui.equip_requested.connect(func(slot,id):
		if campaign.equip(slot,id):hp=minf(hp,campaign.max_hp());_save_all();ui.toast("装备已更换")
		ui.refresh_pause())
	ui.upgrade_requested.connect(func(slot):
		ui.toast("强化成功" if campaign.upgrade(slot) else "星晶不足，或强化已满")
		hp=minf(hp,campaign.max_hp());_save_all();ui.refresh_pause())
	ui.reset_upgrades_requested.connect(func():campaign.reset_upgrades();hp=minf(hp,campaign.max_hp());_save_all();ui.refresh_pause())
	ui.fruit_requested.connect(func():
		var before=hp;hp=campaign.heal_item(hp);_save_all();ui.refresh_pause();ui.toast("恢复 %d 点生命"%int(hp-before) if hp>before else "生命已满，或红星果不足"))
	ui.skill_requested.connect(func(id):
		if id in campaign.available_skills():campaign.selected_skill=id;_save_all();ui.refresh_pause())
	ui.difficulty_requested.connect(func(id):campaign.difficulty=id;hp=minf(hp,campaign.max_hp());_save_all();ui.refresh_pause())
	ui.story_opened.connect(func(id,text):audio_director.play_story(id,text))
	ui.story_closed.connect(func():audio_director.stop_narration())
	ui.narration_toggle_requested.connect(func():
		if audio_director.narration_state=="playing":audio_director.pause_narration()
		elif audio_director.narration_state=="paused":audio_director.resume_narration()
		else:audio_director.replay_narration())
	ui.narration_replay_requested.connect(func():audio_director.replay_narration())
	ui.audio_setting_changed.connect(func(kind,value):
		if kind=="voice_enabled":audio_director.set_enabled("voice",bool(value))
		else:audio_director.set_volume(kind,float(value)))

func _setup_audio() -> void:
	attack_sound=AudioStreamPlayer.new();chime_sound=AudioStreamPlayer.new()
	add_child(attack_sound);add_child(chime_sound)
	attack_sound.stream=load("res://assets/audio/attack.wav");attack_sound.volume_db=-15
	chime_sound.stream=load("res://assets/audio/chime.wav");chime_sound.volume_db=-14
	audio_director.setup(self);music=audio_director.music_player;ui.audio_controller=audio_director
	audio_director.narration_state_changed.connect(ui.set_story_audio_state)
	audio_director.narration_finished.connect(func(_id):ui.set_story_audio_state("finished"))
	ui.title_screen.visibility_changed.connect(func():
		if ui.title_screen.visible:audio_director.stop_narration();audio_director.set_music_context("title"))
	audio_director.set_music_context("title")

func _start(continue_game:bool) -> void:
	get_tree().paused=false
	if continue_game:
		campaign.load_save();_load_world_saves()
	else:
		var difficulty=campaign.difficulty;campaign.reset_game();campaign.difficulty=difficulty;world_saves.clear();challenge_saves.clear();_write_world_saves()
	stage_info.clear();active=true;ui.show_hud();map_button.show();_load_stage(campaign.stage)

func _load_stage(index:int) -> void:
	if active and not stage_info.is_empty():_store_stage_state()
	changing_stage=true;hero_actions.reset();main_trials.clear();enemy_director.clear();enemies=enemy_director.enemies;effects.clear();pending_skill.clear();locomotion.reset()
	for s in objective_sprites+chest_sprites+camp_sprites:
		if is_instance_valid(s):s.queue_free()
	objective_sprites.clear();chest_sprites.clear();camp_sprites.clear()
	if is_instance_valid(lamp_sprite):lamp_sprite.queue_free()
	campaign.stage=index;stage_info=campaign.stage_data(index);world.configure(int(index/3),index%3)
	music_combat_hold=0;audio_director.stop_narration();audio_director.set_region(int(index/3))
	points=world.definition.objectives.duplicate();spawn_position=world.definition.spawn;lamp_position=world.definition.lamp
	camp_positions=world.definition.camps.duplicate();chest_positions=world.definition.chests.duplicate()
	checkpoint_position=spawn_position;last_safe_position=spawn_position;objective_done=[false,false,false]
	claimed_chests=[];explored=[];puzzle_hold.clear();encounter_spawned.clear();companion_paths.clear();guide_path.clear();guide_target=-2;battle_waves.clear()
	objectives=[]
	for i in range(3):
		var a=objective_definitions[index][i].split("|")
		var pad=_crate_pad(points[i])
		objectives.append({"label":a[0],"asset":a[1],"kind":a[2],"p":points[i],"crate_p":points[i],"pad":pad,"orientation":0,"target_orientation":(index+i+1)%4})
	var raw_saved=world_saves.get(str(index),{})
	var saved:Dictionary=raw_saved if raw_saved is Dictionary else {}
	if not saved.is_empty():
		claimed_chests=_bounded_indices(saved.get("chests",[]),chest_positions.size());explored=_bounded_indices(saved.get("explored",[]),204)
		checkpoint_position=world.nearest_safe(_decode_vector(saved.get("checkpoint",[]),spawn_position))
		if not index in campaign.completed:
			for i in range(3):
				objective_done[i]=i in _bounded_indices(saved.get("goals",[]),3)
				var ps=saved.get("puzzles",[])
				if ps is Array and i<ps.size() and ps[i] is Dictionary:
					objectives[i].crate_p=world.nearest_safe(_decode_vector(ps[i].get("crate",[]),points[i]))
					var rotation_value=ps[i].get("rotation",0)
					objectives[i].orientation=clampi(int(rotation_value),0,3) if (rotation_value is int or rotation_value is float) and is_finite(float(rotation_value)) else 0
	done=objective_done.count(true)
	for i in range(3):
		var s=_sprite("res://assets/props/"+objectives[i].asset+".png",objectives[i].crate_p if objectives[i].kind=="push" else points[i],0.35)
		s.modulate=Color(0.6,0.9,0.78,0.45) if objective_done[i] else Color.WHITE;objective_sprites.append(s)
	for i in range(chest_positions.size()):chest_sprites.append(_sprite("res://assets/props/chest_open.png" if i in claimed_chests else "res://assets/props/chest_closed.png",chest_positions[i],0.3))
	for p in camp_positions:camp_sprites.append(_sprite("res://assets/props/star_lantern_lit.png",p,0.32))
	lamp_sprite=_sprite("res://assets/props/star_lantern_lit.png" if done==3 else "res://assets/props/star_lantern_unlit.png",lamp_position,0.55)
	trap_director.setup(self,world.definition.hazards,_bounded_indices(saved.get("traps",[]),100))
	main_trials.configure(saved.get("trials",[]) if saved.get("trials",[]) is Array else [])
	var region_saved=challenge_saves.get(str(int(index/3)),{})
	challenge_director.configure(int(index/3),region_saved if region_saved is Dictionary else {})
	player.position=checkpoint_position;partner.position=world.nearest_safe(player.position+Vector2(-70,40));dragon.position=world.nearest_safe(player.position+Vector2(-125,0))
	player.show();partner.show();dragon.show();hp=campaign.max_hp();invulnerable=1.5;skill_cd=0;attack_cd=0;shield_time=0;wind_time=0;context_latch.clear()
	camera.position=player.position+Vector2(55,-30);camera.reset_smoothing()
	_spawn_patrols();_ensure_encounters();_discover();mini_map.setup(self,false)
	changing_stage=false;_save_all();_update_hud()
	if index%3==0 and done==0:
		ui.show_dialog(stage_info.chapter_name,stage_info.chapter_summary+"\n\n本次实战目标：\n• "+objectives[0].label+"\n• "+objectives[1].label+"\n• "+objectives[2].label+"\n\n地图另有3项可反复尝试的挑战。妖怪命中至少扣除最大生命的四分之一，注意走位与预警。","出发闯关",func():pass,"intro_%d"%int(index/3),stage_info.chapter_summary)
	else:ui.toast(stage_info.name+" · 轻点右侧地图查看区域")
	queue_redraw();combat_overlay.queue_redraw()

func _spawn_patrols() -> void:
	for descriptor in world.definition.patrols:
		enemy_director.spawn(descriptor.id,descriptor.p,false,-1)

func _sync_enemies()->void:enemies=enemy_director.enemies

func _ensure_encounters() -> void:
	for i in range(3):
		if objective_done[i] or i in encounter_spawned:continue
		var kind=objectives[i].kind
		if kind=="boss":
			if not objective_done[0] or not objective_done[1]:continue
			var ids=stage_info.get("enemies",[])
			enemy_director.spawn(ids[0] if ids.size()>0 else "thorn_treant",world.nearest_safe(points[i]+Vector2(75,-40)),true,i)
			encounter_spawned.append(i)
		elif kind=="battle":
			battle_waves[i]=0
			for j in range(2+(1 if campaign.stage>3 else 0)):
				enemy_director.spawn("shadow_blob" if j<2 else "wind_gremlin",world.nearest_safe(points[i]+Vector2((j-1)*100,-65)),false,i)
			encounter_spawned.append(i)
	enemies=enemy_director.enemies

func _enemy_defeated(e:Dictionary) -> void:
	if challenge_director.enemy_defeated(e):return
	if not e.boss and str(e.get("challenge_id","" )).is_empty():
		campaign.xp=mini(11400,campaign.xp+int(e.xp));campaign.crystals+=int(e.crystals)
	ui.toast(e.name+"已净化");_effect(e.sprite.position,Color("9fe2be"),"burst",0.9,95)
	if chime_sound.stream:chime_sound.play()
	var index=int(e.get("objective_index",-1))
	if index>=0 and index<objectives.size():
		var remains=false
		for other in enemies:
			if int(other.get("objective_index",-1))==index and other.hp>0:remains=true
		if not remains:
			if objectives[index].kind=="battle" and int(battle_waves.get(index,0))<1:
				battle_waves[index]=1;ui.toast("第一波已清除 · 第二波正在接近！")
				for j in range(2):enemy_director.spawn("shadow_blob" if j==0 else "crystal_thief",world.nearest_safe(points[index]+Vector2(-100+j*200,-90)),false,index)
			else:_finish_objective(index)

func _process(delta:float) -> void:
	elapsed+=delta
	if not active:return
	attack_cd=maxf(0,attack_cd-delta);skill_cd=maxf(0,skill_cd-delta);invulnerable=maxf(0,invulnerable-delta)
	shield_time=maxf(0,shield_time-delta);wind_time=maxf(0,wind_time-delta);bell_cooldown=maxf(0,bell_cooldown-delta)
	var key=Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	var motion=move_input if move_input.length()>0.05 else key.limit_length()
	if motion.length()>0.05 and not hero_actions.busy:facing=motion.normalized()
	motion=hero_actions.update(delta,motion)
	var displacement=motion*(250 if wind_time>0 else 205)*delta
	var old_player_position=player.position
	var candidate=world.move_actor(player.position,displacement)
	if shield_time>0 and world.WORLD_RECT.grow(-30).has_point(player.position+displacement) and not world.is_obstacle(player.position+displacement,22):candidate=player.position+displacement
	player.position=challenge_director.constrain_motion(player.position,_crate_collision(player.position,candidate))
	if world.is_walkable(player.position) and not trap_director.danger_at(player.position):last_safe_position=player.position
	elif shield_time<=0 and world.is_water(player.position):player.position=world.nearest_safe(last_safe_position);_hurt(12,player.position,true)
	if not hero_actions.busy and not hero_actions.supporting_player():locomotion.animate(player,"wangzai" if campaign.active_character==0 else "xiaomantou",facing,old_player_position.distance_to(player.position),delta)
	player.modulate=Color(1,0.75,0.7,0.68) if invulnerable>0 and int(elapsed*14)%2==0 else Color.WHITE
	_update_companions(delta);camera.position=player.position+Vector2(40,-30)
	enemy_director.update(delta);trap_director.update(delta);main_trials.update(delta);challenge_director.update(delta)
	_update_music_context(delta)
	if not pending_skill.is_empty():
		pending_skill.time-=delta
		if pending_skill.time<=0:
			var id=pending_skill.id;pending_skill.clear();_resolve_skill(id)
	for i in range(effects.size()-1,-1,-1):
		effects[i].life-=delta
		if effects[i].life<=0:effects.remove_at(i)
	map_tick+=delta;save_tick+=delta
	if map_tick>0.4:map_tick=0;_discover();_update_guide()
	if save_tick>12:save_tick=0;_queue_autosave()
	hud_tick-=delta
	if hud_tick<=0:hud_tick=0.1;_update_hud()
	queue_redraw();combat_overlay.queue_redraw()

func _crate_collision(old:Vector2,next:Vector2) -> Vector2:
	for i in range(3):
		if objectives[i].kind=="push" and not objective_done[i] and next.distance_to(objectives[i].crate_p)<42:return old
	return next

func _update_music_context(delta:float)->void:
	if _combat():
		music_combat_hold=3.0
		var boss_near=false
		for enemy in enemies:
			if enemy.hp>0 and enemy.boss and enemy.sprite.position.distance_to(player.position)<700:boss_near=true;break
		audio_director.set_music_context("boss" if boss_near else "battle")
	else:
		music_combat_hold=maxf(0,music_combat_hold-delta)
		if music_combat_hold<=0:audio_director.set_music_context("explore")

func _update_companions(delta:float) -> void:
	companion_path_tick-=delta
	var positions=[player.position-facing*75+Vector2(-25,30),partner.position+Vector2(-65,-5)]
	if companion_path_tick<=0:
		companion_path_tick=0.65
		for pair in [[partner,"partner",positions[0]],[dragon,"dragon",positions[1]]]:
			var target:Vector2=pair[2]
			companion_paths[pair[1]]=PackedVector2Array() if world.has_line_of_sight(pair[0].position,target) else world.find_path(pair[0].position,world.nearest_safe(target))
	for pair in [[partner,"partner",positions[0]],[dragon,"dragon",positions[1]]]:
		var s:Sprite2D=pair[0];var target:Vector2=pair[2]
		var old_position=s.position
		if not world.has_line_of_sight(s.position,target):
			var path:PackedVector2Array=companion_paths.get(pair[1],PackedVector2Array())
			while path.size()>0 and s.position.distance_to(path[0])<25:path.remove_at(0)
			companion_paths[pair[1]]=path
			if path.size()>0:target=path[0]
		var direction=s.position.direction_to(target);var moving=s.position.distance_to(target)>25
		if moving:s.position=world.move_actor(s.position,direction*225*delta,15)
		if s==partner:
			if not hero_actions.supporting():locomotion.animate(s,"wangzai" if campaign.active_character==1 else "xiaomantou",direction,old_position.distance_to(s.position),delta)
		else:
			locomotion.animate(s,"little_dragon",direction,old_position.distance_to(s.position),delta)
		s.z_index=int(s.position.y)

func _animate_actor(s:Sprite2D,character:int,moving:bool,direction:Vector2) -> void:
	locomotion.animate(s,"wangzai" if character==0 else "xiaomantou",direction,0.0,0.0)

func _input(event:InputEvent) -> void:
	if not active or get_tree().paused:return
	if event is InputEventKey and not event.echo:
		if event.pressed and event.keycode==KEY_J:_attack()
		if event.keycode==KEY_K:
			if event.pressed:_context_press()
			else:_context_release()
		if event.pressed and event.keycode==KEY_TAB:_switch(1-campaign.active_character)
		if event.pressed and event.keycode==KEY_M:_show_area_map()

func _attack() -> void:
	if not active or get_tree().paused or not pending_skill.is_empty():return
	if hero_actions.start_attack():attack_cd=0.18

func _combat() -> bool:
	return enemy_director.in_combat(player.position,570)

func _context_action() -> Dictionary:
	if _combat():return {"kind":"skill","id":campaign.selected_skill,"label":campaign.skill_name(campaign.selected_skill)}
	if player.position.distance_to(lamp_position)<135 and done>=3:return {"kind":"complete","p":lamp_position,"label":"点亮星灯"}
	for p in [spawn_position]+camp_positions:
		if player.position.distance_to(p)<110:return {"kind":"rest","p":p,"label":"星灯休息"}
	for i in range(chest_positions.size()):
		if not i in claimed_chests and player.position.distance_to(chest_positions[i])<110:return {"kind":"chest","index":i,"p":chest_positions[i],"label":"打开宝箱"}
	var lever=trap_director.nearby_lever(player.position)
	if lever>=0:return {"kind":"trap","index":lever,"p":trap_director.traps[lever].lever,"label":"关闭机关"}
	var challenge=challenge_director.interaction_at(player.position)
	if not challenge.is_empty():return {"kind":"challenge","id":challenge.id,"action":challenge.action,"p":challenge.p,"label":challenge.label}
	var best=145.0;var chosen=-1
	for i in range(3):
		if not _goal_available(i):continue
		var p:Vector2=objectives[i].crate_p if objectives[i].kind=="push" else points[i]
		var distance=player.position.distance_to(p)
		if distance<best and (distance<55 or facing.dot(player.position.direction_to(p))>-0.05):best=distance;chosen=i
	if chosen>=0:
		var kind=objectives[chosen].kind
		return {"kind":"objective","index":chosen,"p":objectives[chosen].crate_p if kind=="push" else points[chosen],"label":_action_label(kind)}
	return {"kind":"skill","id":campaign.selected_skill,"label":campaign.skill_name(campaign.selected_skill)}

func _goal_available(i:int) -> bool:
	return not objective_done[i] and (objectives[i].kind!="boss" or (objective_done[0] and objective_done[1]))

func _action_label(kind:String) -> String:
	return {"push":"推动木箱","mirror":"转动镜台","valve":"调节水闸","course":"启动闯关","seal":"攻击封印","escort":"护送出发","boss":"迎战首领","battle":"净化影团"}.get(kind,"互动")

func _context_press() -> void:
	if active and not get_tree().paused and context_latch.is_empty():
		context_latch=_context_action().duplicate(true)
		if context_latch.kind=="skill":_cast(context_latch.id)

func _context_release() -> void:
	if context_latch.is_empty():return
	var action=context_latch.duplicate(true);context_latch.clear()
	if not active or get_tree().paused:return
	# Skills start on press; release only clears the latch, without a second cast.
	if action.kind=="skill":return
	var action_point:Vector2=action.get("p",player.position)
	if _combat() or player.position.distance_to(action_point)>165 or not world.has_line_of_sight(player.position,action_point):return
	match action.kind:
		"complete":_complete_stage()
		"rest":_rest(action.p)
		"chest":_open_chest(action.index)
		"trap":
			if trap_director.disarm(action.index):_save_all()
		"challenge":
			if main_trials.active_index>=0:ui.toast("先完成当前主线试炼，或到营地休息后取消")
			elif action.action=="lever":challenge_director.handle_interaction(player.position);_save_all()
			else:challenge_director.start(action.id);_save_all()
		"objective":_interact_goal(action.index)

func _interact_goal(index:int) -> void:
	if not _goal_available(index):return
	var objective=objectives[index];var kind=objective.kind
	match kind:
		"course","seal","escort":
			if not challenge_director.active_label().is_empty():ui.toast("先完成当前地图挑战，或到营地休息后取消")
			else:main_trials.begin(index)
		"battle","boss":ui.toast("观察妖怪起手式，净化后星纹会接通")
		"push":
			var direction=player.position.direction_to(objective.crate_p)
			objective.crate_p=world.move_actor(objective.crate_p,direction*55,25)
			objective_sprites[index].position=objective.crate_p;objective_sprites[index].z_index=int(objective.crate_p.y)
			if objective.crate_p.distance_to(objective.pad)<48:_finish_objective(index)
			else:ui.toast("绕到木箱另一侧，把它推上金色压板");_save_all()
		"mirror":
			objective.orientation=(objective.orientation+1)%4
			hero_actions.play_support("shield",points[index])
			if objective.orientation==objective.target_orientation:_finish_objective(index)
			else:ui.toast("镜面转动了 · 把光束对准金色星纹");_save_all()
		"valve":
			var expected=0
			while expected<3 and objective_done[expected]:expected+=1
			if index!=expected:ui.toast("水闸顺序：荷叶 ① → 月牙 ② → 星星 ③");_effect(points[index],Color("eebc72"),"ring",0.7,75)
			else:_effect(points[index],Color("91dce2"),"burst",1,180);_finish_objective(index)

func _finish_objective(index:int=-1) -> void:
	if index<0:index=_nearest_goal()
	if index<0 or index>=3 or objective_done[index]:return
	objective_done[index]=true;done=objective_done.count(true);objective_sprites[index].modulate=Color(0.5,0.9,0.75,0.4)
	_effect(points[index],Color("a4e6b8"),"burst",1,145);_ensure_encounters();_save_all()
	if chime_sound.stream:chime_sound.play()
	if done>=3:
		lamp_sprite.texture=_texture("res://assets/props/star_lantern_lit.png");ui.toast("区域星脉已接通！前往地图上的星灯结算")
	else:ui.toast("已完成 %d / 3 · 继续探索其他星纹"%done)
	guide_target=-2

func _rest(p:Vector2) -> void:
	main_trials.cancel();challenge_director.reset_on_death()
	checkpoint_position=world.nearest_safe(p+Vector2(70,0));last_safe_position=checkpoint_position
	hp=campaign.max_hp();campaign.fruits=maxi(2,campaign.fruits);shield_time=0
	for i in range(3):
		if objectives[i].kind=="push" and not objective_done[i]:objectives[i].crate_p=points[i];objective_sprites[i].position=points[i]
	hero_actions.reset();enemy_director.clear();enemies=enemy_director.enemies;encounter_spawned.clear();_spawn_patrols();_ensure_encounters()
	_save_all();ui.toast("星灯营地已记录 · 生命恢复、红星果补足，远处妖怪重新活动")

func _crate_pad(p:Vector2) -> Vector2:
	for direction in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
		var clear=true
		for step in range(-2,8):
			if not world.is_walkable(p+direction*step*25,28):clear=false;break
		if clear:return p+direction*165
	return world.nearest_safe(p+Vector2(120,0))

func _open_chest(index:int) -> void:
	if index<0 or index>=chest_positions.size() or index in claimed_chests:return
	claimed_chests.append(index);chest_sprites[index].texture=_texture("res://assets/props/chest_open.png")
	campaign.xp=mini(11400,campaign.xp+20);campaign.crystals+=6+int(campaign.stage/3);campaign.fruits=mini(5,campaign.fruits+1)
	_effect(chest_positions[index],Color("f5d28c"),"burst",0.9,90);_save_all();ui.toast("探索宝箱 · 经验 +20 · 星晶 +%d · 红星果 +1"%(6+int(campaign.stage/3)))

func _cast(id:String) -> void:
	if skill_cd>0 or hero_actions.busy or not id in campaign.available_skills():return
	skill_cd=6;pending_skill={"id":id,"time":0.32};hero_actions.start_skill_visual(id)

func _resolve_skill(id:String) -> void:
	if id=="water":shield_time=4;ui.toast("月水护罩 · 抵挡伤害，也可短暂踏水")
	elif id=="space":
		var before=player.position;player.position=world.nearest_safe(player.position+facing*300)
		_effect(before,Color("b8a9ed"),"ring",0.8,110);invulnerable=maxf(invulnerable,0.8)
	elif id=="wind":
		wind_time=4
		_hit_challenge_targets(player.position,facing,330,12+2*campaign.level(),"wind",PI)
		for e in enemies:
			if e.hp>0 and player.position.distance_to(e.sprite.position)<330 and world.has_line_of_sight(player.position,e.sprite.position):
				enemy_director.damage(e,12+2*campaign.level(),"wind");enemy_director.interrupt(e,1.5)
	else:
		_hit_challenge_targets(player.position,facing,310,(12+2*(campaign.level()-1))*(1 if id=="spark" else 1.7),"fire",0.95)
		for e in enemies:
			if e.hp>0 and player.position.distance_to(e.sprite.position)<310 and world.has_line_of_sight(player.position,e.sprite.position):
				var angle=absf(wrapf(player.position.direction_to(e.sprite.position).angle()-facing.angle(),-PI,PI))
				if angle<0.95:enemy_director.damage(e,(12+2*(campaign.level()-1))*(1 if id=="spark" else 1.7),"fire")
	_effect(player.position,Color("f8c07e") if id in ["spark","fire"] else Color("9edce1"),"burst",0.9,220)
	if chime_sound.stream:chime_sound.play()

func _hurt(damage:float,source:Vector2,unblockable:bool=false,source_kind:String="environment") -> void:
	if invulnerable>0 or shield_time>0:return
	var guarded=not unblockable and facing.dot(player.position.direction_to(source))>0.25
	var amount=DamageRules.enemy_damage(campaign.max_hp(),damage,campaign.defense(),campaign.difficulty,guarded,int(campaign.upgrades.shield)) if source_kind=="enemy" else DamageRules.environment_damage(damage,campaign.defense(),campaign.difficulty)
	if guarded:hero_actions.play_support("shield",source)
	hp-=amount;invulnerable=1.0;_effect(player.position+Vector2(0,-110),Color("f39b7a"),"-%d"%int(amount),0.85,0)
	if hp<=0:
		main_trials.cancel();challenge_director.reset_on_death();locomotion.reset()
		hp=campaign.max_hp();player.position=world.nearest_safe(checkpoint_position);last_safe_position=player.position;invulnerable=3
		partner.position=world.nearest_safe(player.position+Vector2(-65,35));dragon.position=world.nearest_safe(player.position+Vector2(-115,0))
		hero_actions.reset();pending_skill.clear();campaign.fruits=maxi(2,campaign.fruits)
		_save_all();ui.show_dialog("星灯仍在等你","回到最近的营地。已完成的机关、宝箱、首领阶段和全部装备都保留。\n观察敌人起手，避开标记范围，再抓住收招空隙。","再试一次",func():pass)

func _complete_stage() -> void:
	if done<3 or changing_stage:return
	changing_stage=true;var index=campaign.stage;var reward=campaign.complete_stage(index)
	hp=campaign.max_hp();campaign.fruits=maxi(2,campaign.fruits);_save_all()
	var body=stage_info.success+"\n\n"+stage_info.reward
	if reward.first_clear:body+="\n\n经验 +%d · 队伍 Lv.%d"%[int(reward.xp),campaign.level()]
	if index<20:ui.show_dialog("星灯已点亮 · "+stage_info.name,body,"继续下一段旅程",func():changing_stage=false;_load_stage(index+1),"clear_%d"%index,stage_info.success)
	else:
		var closing="七章冒险已完成。地图中保留所有区域，可继续寻宝、挑战妖怪和探索未走过的角落。"
		ui.show_dialog("回家的门，也为朋友敞开",body+"\n\n"+closing,"回到约定之灯",func():changing_stage=false;_resume(),"ending",stage_info.success+"\n\n"+closing)

func _switch(index:int) -> void:
	if not active or get_tree().paused or hero_actions.busy:return
	campaign.active_character=clampi(index,0,1);hero_actions.reset();_save_all()
	ui.toast("旺仔 · 星盾三连斩 / 第三式盾震" if index==0 else "小馒头 · 远程星矢 / 第三式星爆")

func _pause() -> void:
	if not active:return
	move_input=Vector2.ZERO;context_latch.clear();_save_all();get_tree().paused=true;ui.show_pause();audio_director.set_music_context("pause")

func _resume() -> void:
	ui.hide_pause();get_tree().paused=false;move_input=Vector2.ZERO;context_latch.clear()
	audio_director.set_music_context("explore")
	_update_music_context(0)

func _show_area_map() -> void:
	if not active:return
	_pause()
	for child in ui.pause_content.get_children():ui.pause_content.remove_child(child);child.queue_free()
	ui.pause_content.add_child(ui._label("自由探索 · "+str(stage_info.region),24,Color("ead29a")))
	var map=AreaMap.new();ui.pause_content.add_child(map);map.setup(self,true)
	ui.pause_content.add_child(ui._paragraph("金色为主线，蓝色为地图挑战。营地恢复与记录重生点；首领在前两项实战关卡完成后现身。",17))

func _nearest_goal() -> int:
	var best=INF;var chosen=-1
	for i in range(3):
		if _goal_available(i):
			var distance=player.position.distance_to(points[i])
			if distance<best:best=distance;chosen=i
	return chosen

func _update_guide() -> void:
	var next=_nearest_goal()
	var target=points[next] if next>=0 else lamp_position
	if guide_target==next and player.position.distance_squared_to(guide_origin)<6400 and target.distance_squared_to(guide_destination)<1:return
	guide_path=world.find_path(player.position,target);guide_target=next
	guide_origin=player.position;guide_destination=target

func _update_hud() -> void:
	if objectives.is_empty():return
	var index=_nearest_goal();var action=context_latch if not context_latch.is_empty() else _context_action()
	var goal="区域探索 %d / 3 · "%done+(str(objectives[index].label) if index>=0 else "前往星灯，完成旅程")
	var detail="自由选择路线 · 宝箱 %d / %d · M 展开区域地图"%[claimed_chests.size(),chest_positions.size()]
	if _combat():detail="未躲开一次敌击至少损失25%最大生命 · 抓住收招反击"
	if index>=0 and objectives[index].kind=="push" and player.position.distance_to(points[index])<280:detail="从木箱侧面推动，把它压到金色踏板上"
	var challenge_label=challenge_director.active_label()
	var primary_label=main_trials.active_label()
	if not primary_label.is_empty():goal=primary_label;detail="跑过旗门 / 观察陷阱停歇；护送时清除拦路妖怪"
	if not challenge_label.is_empty():goal=challenge_label;detail="当前地图挑战 · 可到营地取消，失败后立即重试"
	ui.update_hud(hp,campaign.max_hp(),goal,detail,action.label,skill_cd if action.kind=="skill" else 0,"%s · %d / 21"%[stage_info.name,campaign.stage+1])

func _discover() -> void:
	var cell=Vector2i((player.position-world.WORLD_RECT.position)/world.WORLD_RECT.size*Vector2(17,12))
	for y in range(maxi(0,cell.y-1),mini(12,cell.y+2)):
		for x in range(maxi(0,cell.x-1),mini(17,cell.x+2)):
			if not y*17+x in explored:explored.append(y*17+x)

func is_discovered(p:Vector2) -> bool:
	var cell=Vector2i((p-world.WORLD_RECT.position)/world.WORLD_RECT.size*Vector2(17,12))
	return cell.y*17+cell.x in explored

func _store_stage_state() -> void:
	if stage_info.is_empty():return
	var goals=[];var puzzles=[]
	for i in range(3):
		if objective_done[i]:goals.append(i)
		puzzles.append({"crate":[objectives[i].crate_p.x,objectives[i].crate_p.y],"rotation":objectives[i].orientation})
	world_saves[str(stage_info.index)]={"goals":goals,"puzzles":puzzles,"chests":claimed_chests.duplicate(),"explored":explored.duplicate(),"checkpoint":[checkpoint_position.x,checkpoint_position.y],"traps":trap_director.disabled_indices()}
	world_saves[str(stage_info.index)]["trials"]=main_trials.snapshot()
	challenge_saves[str(int(stage_info.index/3))]=challenge_director.snapshot()

func _world_path() -> String:
	return campaign.save_path+".world.json"

func _save_all() -> void:
	_finish_autosave()
	if active:_store_stage_state()
	campaign.save_game();_write_world_saves()

func _queue_autosave() -> void:
	if autosave_thread!=null and autosave_thread.is_alive():return
	_finish_autosave()
	if active:_store_stage_state()
	var document:Dictionary={"version":3,"stages":world_saves,"challenges":challenge_saves}.duplicate(true)
	autosave_thread=Thread.new()
	var result=autosave_thread.start(_autosave_snapshot.bind(campaign.save_document(),ProjectSettings.globalize_path(campaign.save_path),document))
	if result!=OK:autosave_thread=null;save_tick=11

static func _autosave_snapshot(campaign_document:Dictionary,path:String,world_document:Dictionary) -> bool:
	if not Campaign.write_save_document(campaign_document,path):return false
	return _write_world_document(path+".world.json",world_document)

func _finish_autosave() -> void:
	if autosave_thread!=null and autosave_thread.is_started():
		if autosave_thread.wait_to_finish():campaign.has_save=true
	autosave_thread=null

func _exit_tree() -> void:
	_finish_autosave()

func _notification(what:int) -> void:
	if what==NOTIFICATION_APPLICATION_PAUSED and active:_save_all()

func _write_world_saves() -> void:
	_write_world_document(ProjectSettings.globalize_path(_world_path()),{"version":3,"stages":world_saves,"challenges":challenge_saves})

static func _write_world_document(p:String,document:Dictionary) -> bool:
	var f=FileAccess.open(p+".tmp",FileAccess.WRITE)
	if not f:return false
	f.store_string(JSON.stringify(document));f.flush()
	var error=f.get_error();f.close()
	if error!=OK:return false
	if FileAccess.file_exists(p):DirAccess.copy_absolute(ProjectSettings.globalize_path(p),ProjectSettings.globalize_path(p+".bak"))
	return DirAccess.rename_absolute(p+".tmp",p)==OK

func _load_world_saves() -> void:
	world_saves.clear()
	challenge_saves.clear()
	var damaged=false
	var restored=false
	for path in [_world_path(),_world_path()+".bak"]:
		if not FileAccess.file_exists(path):continue
		var d=JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and (d.get("version") is int or d.get("version") is float) and (float(d.version)==2.0 or float(d.version)==3.0) and d.get("stages") is Dictionary:
			var invalid_entry=false
			for key in d.stages:
				if str(key).is_valid_int() and int(str(key))>=0 and int(str(key))<21 and d.stages[key] is Dictionary:
					if not world_saves.has(str(key)):
						var entry:Dictionary=d.stages[key].duplicate(true)
						if d.version==2:entry["goals"]=[];entry["puzzles"]=[]
						world_saves[str(key)]=entry
				else:invalid_entry=true
			if d.get("challenges") is Dictionary:
				for key in d.challenges:
					if str(key).is_valid_int() and int(str(key))>=0 and int(str(key))<7 and d.challenges[key] is Dictionary and not challenge_saves.has(str(key)):challenge_saves[str(key)]=d.challenges[key]
			if path.ends_with(".bak"):restored=true
			if not invalid_entry:break
			damaged=true
		else:damaged=true
	if restored:ui.toast("区域记录已从备份恢复")
	elif damaged:ui.toast("部分区域记录损坏，已保留可读取的探索进度")

func _bounded_indices(values:Variant,limit:int) -> Array:
	var result=[]
	if values is Array:
		for value in values:
			if (value is int or value is float) and is_finite(float(value)) and float(value)==int(value) and value>=0 and value<limit and not int(value) in result:result.append(int(value))
	return result

func _decode_vector(value:Variant,fallback:Vector2) -> Vector2:
	if value is Array and value.size()==2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		var p=Vector2(value[0],value[1])
		if is_finite(p.x) and is_finite(p.y) and world.WORLD_RECT.has_point(p):return p
	return fallback

func _sprite(path:String,p:Vector2,size_scale:float) -> Sprite2D:
	var s=Sprite2D.new();s.texture=_texture(path);s.position=p;s.scale=Vector2.ONE*size_scale
	if s.texture:s.offset.y=-s.texture.get_height()*0.5
	s.z_index=int(p.y);add_child(s);return s

func _texture(path:String) -> Texture2D:
	if not textures.has(path):textures[path]=load(path) if ResourceLoader.exists(path) else null
	return textures[path]

func _effect(p:Vector2,color:Color,kind:String,life:float,radius:float) -> void:
	effects.append({"p":p,"color":color,"kind":kind,"life":life,"max_life":life,"radius":radius})

func _hit_challenge_targets(origin:Vector2,direction:Vector2,reach:float,damage:float,kind:String="melee",half_angle:float=0.8)->int:
	return main_trials.hit_cone(origin,direction,reach,damage,half_angle)+challenge_director.hit_targets(origin,direction,reach,kind,damage,half_angle)

func _hit_challenge_projectile(a:Vector2,b:Vector2,damage:float,kind:String="projectile")->bool:
	if main_trials.hit_segment(a,b,damage):return true
	return challenge_director.hit_target_segment(a,b,12,kind)>0

func _draw() -> void:
	if not active or objectives.is_empty():return
	for actor in [player,partner,dragon]:
		draw_set_transform(actor.position,0,Vector2(1,0.35));draw_circle(Vector2.ZERO,28,Color(0.01,0.05,0.06,0.45));draw_set_transform(Vector2.ZERO)
	for i in range(3):
		var p:Vector2=points[i];var color=Color("8dbea0") if objective_done[i] else Color("e8ce86")
		draw_arc(p,65,0,TAU,48,Color(color,0.7),2,true)
		if not objective_done[i]:draw_string(font,p+Vector2(-10,9),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,24,color)
		if objectives[i].kind=="push":
			draw_rect(Rect2(objectives[i].pad-Vector2(36,28),Vector2(72,56)),Color(color,0.3));draw_rect(Rect2(objectives[i].pad-Vector2(36,28),Vector2(72,56)),color,false,2)
		if objectives[i].kind=="mirror":
			var target=p+Vector2.from_angle(objectives[i].target_orientation*PI/2)*130
			draw_arc(target,20,0,TAU,20,color,2,true)
			draw_line(p,p+Vector2.from_angle(objectives[i].orientation*PI/2)*130,Color("abebce"),4,true)
	if guide_path.size()>1:
		for i in range(1,mini(guide_path.size(),10)):
			var p=guide_path[i]
			if p.distance_to(player.position)>60:draw_circle(p,2.5,Color(0.9,0.88,0.6,0.4))

func _draw_overlay() -> void:
	if not active:return
	trap_director.draw(combat_overlay,font);enemy_director.draw(combat_overlay,font);hero_actions.draw(combat_overlay,font)
	main_trials.draw(combat_overlay,font);challenge_director.draw(combat_overlay,font)
	if shield_time>0:combat_overlay.draw_arc(player.position+Vector2(0,-50),80,0,TAU,48,Color("9bdef0"),2.5,true)
	for i in range(3):
		if player.position.distance_to(points[i])<440:
			combat_overlay.draw_string(font,points[i]+Vector2(-75,-135),("✓ " if objective_done[i] else str(i+1)+" ")+str(objectives[i].label),HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("f0d39b"))
	for effect in effects:
		var f=effect.life/effect.max_life;var color:Color=effect.color;color.a*=minf(1,f*2)
		if effect.kind in ["ring","burst"]:
			var radius=maxf(2,effect.radius*(1-f));combat_overlay.draw_arc(effect.p,radius,0,TAU,40,color,2+2*f,true)
			for i in range(6):combat_overlay.draw_circle(effect.p+Vector2.from_angle(i*TAU/6+elapsed)*radius,3*f,color)
		else:combat_overlay.draw_string(font,effect.p+Vector2(0,-40*(1-f)),effect.kind,HORIZONTAL_ALIGNMENT_CENTER,-1,23,color)
