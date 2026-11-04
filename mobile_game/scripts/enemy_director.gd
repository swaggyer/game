extends RefCounted
## Species-specific combat, navigation and telegraphed geometry. Owns no strong
## reference to the scene, so a scene change releases this director normally.

const SPECIES = ["shadow_blob", "crystal_thief", "wind_gremlin", "moon_bubble", "thorn_treant", "windmill_guardian", "stone_shell_guardian", "lantern_devourer"]
const TELL_NAMES = {"leap":"缩身 · 跃击", "dash":"侧步 · 冲刺", "gust":"转帽 · 风弹", "bubble_volley":"鼓泡 · 三连泡", "ring":"膨胀 · 水环", "root_fan":"举枝 · 根刺", "slam":"抬臂 · 重砸", "sweep":"挥枝 · 横扫", "wind_lanes":"转帆 · 风道", "charge":"收甲 · 直冲", "armor_sweep":"展甲 · 旋扫", "shadow_orbs":"移影 · 暗星", "devourer_volley":"吞光 · 星弹", "safe_sector":"裂隙 · 寻找安全扇区"}
const ORANGE = Color(1.0,0.68,0.38)
const CYAN = Color(0.5,0.95,0.9)
var enemies: Array = []
var projectiles: Array = []
var _owner_ref: WeakRef
var _clock: float = 0.0
var _next_uid: int = 0
var _hit_groups: Dictionary = {}


func setup(game: Node2D) -> void:
	_owner_ref = weakref(game)


func _game() -> Node2D:
	return _owner_ref.get_ref() if _owner_ref != null else null


func spawn(id: String, p: Vector2, boss: bool = false, objective_index: int = -1) -> Dictionary:
	var game: Node2D = _game()
	if game == null or not SPECIES.has(id):return {}
	var data: Dictionary = {}
	for row in game.campaign.systems.get("enemies", []):
		if str(row.get("id", "")) == id:
			data = row.duplicate(true);break
	if data.is_empty():return {}
	if boss and id == "moon_bubble":data = data.get("eliteVariant",data).duplicate(true)
	var maximum: float = float(data.get("hp",40))
	var thresholds: Array = _thresholds(id)
	var phase: int = clampi(int(game.campaign.boss_phases.get(str(game.campaign.stage),0)),0,thresholds.size()) if boss else 0
	var fraction: float = float(thresholds[phase-1]) if phase>0 else 1.0
	var scale_value: float = 0.78 if boss else 0.38
	var sprite: Sprite2D = game._sprite("res://assets/enemies/"+id+"_preview.png",p,scale_value)
	_next_uid += 1
	var e: Dictionary = {
		"id":id,"uid":_next_uid,"name":data.get("name",id),"sprite":sprite,
		"hp":maximum*fraction,"max_hp":maximum,"attack":float(data.get("attack",8)),
		"xp":int(data.get("xp",10)),"crystals":int(data.get("crystals",2)),"boss":boss,
		"origin":p,"phase":phase,"objective_index":objective_index,"vulnerable":0.0,
		"warning":0.0,"aim":p,"state":"patrol","state_time":0.0,"timer":1.0,
		"cooldown":1.2,"memory":0.0,"last_seen":p,"path":PackedVector2Array(),
		"path_index":0,"path_age":0.0,"path_target":p,"sequence":0,"attack_serial":0,
		"attack_style":"","attack_origin":p,"direction":Vector2.RIGHT,"attack_length":240.0,
		"radius":70.0,"half_width":30.0,"spread":0.35,"action_time":0.0,"action_duration":0.5,
		"tell_duration":1.0,"hit":false,"fired":false,"notified":false,"pose":"idle",
		"base_scale":sprite.scale,"base_offset":sprite.offset,"flash":0.0,"hint_time":0.0,
		"teleport_target":p,"safe_angle":0.0,"previous_radius":0.0,"leash":820.0 if boss else 560.0
	}
	enemies.append(e)
	return e


func _thresholds(id: String) -> Array:
	match id:
		"lantern_devourer":return [0.70,0.35]
		"stone_shell_guardian", "moon_bubble":return [0.60]
		"thorn_treant", "windmill_guardian":return [0.55]
	return []


func clear() -> void:
	for e in enemies:
		if is_instance_valid(e.sprite):e.sprite.queue_free()
	enemies.clear();projectiles.clear();_hit_groups.clear()


func update(delta: float) -> void:
	var game: Node2D = _game()
	if game == null:return
	if game.is_inside_tree() and game.get_tree().paused:return
	if delta <= 0:
		for e in enemies:
			if e.hp>0:_phase(e)
		return
	# Small simulation steps prevent a fast charge or an expanding ring from
	# tunnelling through a player during an occasional slow rendered frame.
	var remaining: float = minf(delta,2.0)
	while remaining>0.00001:
		var step: float = minf(remaining,0.04)
		remaining-=step;_clock+=step
		for e in enemies.duplicate():
			if e.hp>0 and is_instance_valid(e.sprite):_tick_enemy(e,step)
			if game.is_inside_tree() and game.get_tree().paused:return
		_tick_projectiles(step)
		if game.is_inside_tree() and game.get_tree().paused:return
	for key in _hit_groups.keys():
		if _clock-float(_hit_groups[key])>12.0:_hit_groups.erase(key)


func in_combat(p: Vector2, range_value: float = 600.0) -> bool:
	for e in enemies:
		if e.hp>0 and e.sprite.position.distance_to(p)<range_value and (e.state!="return" or e.boss) and (e.boss or e.memory>0 or _los(e.sprite.position,p)):
			return true
	return false


func nearest_target(p: Vector2, range_value: float, forward: Vector2 = Vector2.ZERO) -> Dictionary:
	var best: Dictionary = {}
	var distance: float = range_value
	for e in enemies:
		if e.hp<=0 or not is_instance_valid(e.sprite):continue
		var offset: Vector2 = e.sprite.position-p
		var d: float = offset.length()
		if d>distance or not _los(p,e.sprite.position):continue
		if forward.length()>0.1 and d>40 and forward.normalized().dot(offset.normalized()) < -0.15:continue
		distance=d;best=e
	return best


func _phase(e: Dictionary) -> void:
	if not e.boss:return
	var phase: int = 0
	for threshold in _thresholds(e.id):
		if e.hp/e.max_hp<=float(threshold)+0.00001:phase+=1
	if phase<=e.phase:return
	e.phase=phase
	var game: Node2D = _game()
	game.campaign.boss_phases[str(game.campaign.stage)]=phase
	game.campaign.save_game()
	game.ui.toast("%s · 第 %d 阶段，进度已保存"%[e.name,phase+1])
	expose(e,2.0)


func _tick_enemy(e: Dictionary, delta: float) -> void:
	var game: Node2D = _game()
	e.vulnerable=maxf(0,e.vulnerable-delta);e.cooldown=maxf(0,e.cooldown-delta)
	e.flash=maxf(0,e.flash-delta);e.hint_time=maxf(0,e.hint_time-delta)
	_phase(e)
	match str(e.state):
		"windup":
			e.warning=maxf(0,e.warning-delta)
			if e.warning<=0:_begin_action(e)
		"action":_action(e,delta)
		"recover", "stunned":
			e.state_time-=delta
			if e.state_time<=0:e.state="chase";e.pose="idle"
		_:
			var p: Vector2 = e.sprite.position
			var distance: float = p.distance_to(game.player.position)
			var visible: bool = distance<610 and _los(p,game.player.position)
			if visible:e.memory=3.5;e.last_seen=game.player.position
			else:e.memory=maxf(0,e.memory-delta)
			if game.player.position.distance_to(e.origin)>e.leash+200 or p.distance_to(e.origin)>e.leash:
				e.state="return";e.memory=0
			if e.state=="return":
				_move(e,e.origin,100.0,delta)
				if e.sprite.position.distance_to(e.origin)<35:e.state="patrol";e.cooldown=1.4
			elif visible or e.memory>0:
				e.state="chase"
				var attack_range: float = _attack_range(e)
				if visible and distance<attack_range and e.cooldown<=0:
					_prepare(e)
				elif not e.boss or e.id=="stone_shell_guardian":
					var destination: Vector2 = e.last_seen
					if visible and e.id=="crystal_thief":
						var side: Vector2 = p.direction_to(destination).orthogonal()
						destination+=side*(90 if int(e.sequence)%2==0 else -90)
					if distance>_preferred_range(e) or not visible:
						_move(e,destination,83.0 if e.id=="crystal_thief" else 64.0,delta)
					elif e.id=="crystal_thief":_move(e,destination,52.0,delta)
			else:
				e.state="patrol"
				if not e.boss:
					var patrol: Vector2 = e.origin+Vector2(cos(_clock*0.24+e.uid),sin(_clock*0.3+e.uid))*55
					_move(e,patrol,28.0,delta)
	_pose(e)
	e.timer=e.cooldown
	e.sprite.z_index=int(e.sprite.position.y)


func _attack_range(e: Dictionary) -> float:
	if e.boss:return 610.0
	return {"shadow_blob":240.0,"crystal_thief":360.0,"wind_gremlin":470.0,"moon_bubble":340.0}.get(e.id,300.0)


func _preferred_range(e: Dictionary) -> float:
	return {"shadow_blob":145.0,"crystal_thief":220.0,"wind_gremlin":300.0,"moon_bubble":230.0}.get(e.id,260.0)


func _move(e: Dictionary, destination: Vector2, speed: float, delta: float) -> void:
	var game: Node2D = _game()
	e.path_age-=delta
	if e.path_age<=0 or e.path_target.distance_to(destination)>60:
		e.path=game.world.find_path(e.sprite.position,destination)
		e.path_index=0;e.path_age=0.55;e.path_target=destination
	var waypoint: Vector2 = destination
	var path: PackedVector2Array = e.path
	while e.path_index<path.size() and e.sprite.position.distance_to(path[e.path_index])<22:e.path_index+=1
	if e.path_index<path.size():waypoint=path[e.path_index]
	elif not _los(e.sprite.position,destination):return
	var displacement: Vector2 = (waypoint-e.sprite.position).limit_length(speed*delta)
	e.sprite.position=game.world.move_actor(e.sprite.position,displacement,28.0 if e.boss else 18.0)
	if displacement.length()>0.1:e.direction=displacement.normalized()


func _prepare(e: Dictionary) -> void:
	var game: Node2D = _game()
	e.attack_serial+=1;e.hit=false;e.fired=false;e.action_time=0.0;e.previous_radius=0.0
	e.attack_origin=e.sprite.position;e.aim=game.player.position;e.direction=e.attack_origin.direction_to(e.aim)
	if e.direction.length()<0.5:e.direction=Vector2.RIGHT
	e.attack_length=minf(_attack_range(e),e.attack_origin.distance_to(e.aim)+110)
	e.radius=70.0;e.half_width=30.0;e.spread=0.35;e.action_duration=0.5
	var tell: float = 1.0
	match str(e.id):
		"shadow_blob":
			e.attack_style="leap";tell=0.9;e.action_duration=0.48;e.radius=68.0
			e.aim=e.attack_origin+e.direction*minf(240,e.attack_origin.distance_to(e.aim))
		"crystal_thief":e.attack_style="dash";tell=1.0;e.action_duration=0.40;e.half_width=34.0
		"wind_gremlin":e.attack_style="gust";tell=1.1;e.action_duration=0.48;e.attack_length=480.0
		"moon_bubble":
			e.attack_style="ring" if int(e.sequence)%2==0 else "bubble_volley"
			tell=1.5 if e.boss else 1.2;e.action_duration=1.15;e.radius=320.0 if e.boss else 235.0
		"thorn_treant":
			e.attack_style=["root_fan","slam","sweep"][int(e.sequence)%3]
			tell=1.65;e.action_duration=0.95;e.radius=130.0;e.attack_length=430.0;e.spread=0.65
			if e.attack_style=="sweep":e.attack_length=295.0;e.spread=1.1
		"windmill_guardian":
			e.attack_style="wind_lanes";tell=1.5;e.action_duration=0.8;e.attack_length=600.0;e.half_width=48.0
			e.spread=0.48 if e.phase>0 else 0.0
			e.direction=e.direction.rotated(float(int(e.sequence)%3-1)*0.32)
		"stone_shell_guardian":
			e.attack_style="armor_sweep" if e.phase>0 and int(e.sequence)%2==1 else "charge"
			tell=1.4;e.action_duration=0.65;e.attack_length=minf(540,e.attack_length+150);e.half_width=62.0
			if e.attack_style=="armor_sweep":e.action_duration=1.3;e.attack_length=240.0
		"lantern_devourer":
			e.attack_style=["shadow_orbs","devourer_volley","safe_sector"][clampi(e.phase,0,2)]
			tell=1.8;e.action_duration=1.35;e.radius=430.0;e.attack_length=640.0
			e.safe_angle=e.direction.angle()+PI*0.5
			e.teleport_target=_teleport_position(e)
			if e.attack_style=="shadow_orbs":e.direction=e.teleport_target.direction_to(e.aim)
	if game.campaign.difficulty=="gentle":tell+=0.3
	e.tell_duration=tell;e.warning=tell;e.state="windup";e.pose=e.attack_style
	e.cooldown=tell+e.action_duration+1.3
	e.sequence+=1


func _teleport_position(e: Dictionary) -> Vector2:
	var game: Node2D = _game()
	for attempt in range(6):
		var candidate: Vector2 = e.origin+Vector2.from_angle(float(e.sequence)*1.7+attempt*1.05)*170
		if game.world.is_walkable(candidate) and candidate.distance_to(e.aim)>=220 and _los(candidate,e.aim):return candidate
	return e.sprite.position


func _begin_action(e: Dictionary) -> void:
	e.state="action";e.warning=0.0;e.action_time=0.0
	match str(e.attack_style):
		"gust":_burst(e,[-0.23,0.0,0.23],245.0,16.0,3.1,"wind")
		"bubble_volley":_burst(e,[-0.35,0.0,0.35],158.0,22.0,4.3,"bubble")
		"wind_lanes":
			var lanes: Array = [-0.48,0.48] if e.phase>0 else [0.0]
			for lane in lanes:
				_burst(e,[float(lane)-0.07,float(lane),float(lane)+0.07],195.0,20.0,4.0,"gust")
		"shadow_orbs":
			var game: Node2D = _game()
			game._effect(e.sprite.position,Color(0.7,0.55,1),"ring",0.8,90)
			e.sprite.position=e.teleport_target;e.attack_origin=e.teleport_target
			_burst(e,[-0.40,-0.13,0.13,0.40],150.0,24.0,5.0,"shadow")
		"devourer_volley":_burst(e,[-0.45,-0.22,0.0,0.22,0.45],185.0,23.0,4.5,"star")


func _burst(e: Dictionary, angles: Array, speed: float, radius: float, life: float, kind: String) -> void:
	for angle in angles:
		var velocity: Vector2 = e.direction.rotated(float(angle))*speed
		projectiles.append({"p":e.attack_origin+velocity.normalized()*38,"previous":e.attack_origin,
			"velocity":velocity,"radius":radius,"life":life,"owner_uid":e.uid,"serial":e.attack_serial,
			"damage":e.attack,"kind":kind,"returned":false,"age":0.0})


func _action(e: Dictionary, delta: float) -> void:
	var game: Node2D = _game()
	var previous: float = e.action_time
	e.action_time=minf(e.action_duration,e.action_time+delta)
	var t: float = e.action_time/e.action_duration
	match str(e.attack_style):
		"leap":
			var desired: Vector2 = e.attack_origin.lerp(e.aim,t)
			e.sprite.position=game.world.move_actor(e.sprite.position,desired-e.sprite.position,18.0)
			if t>=1.0 and e.sprite.position.distance_to(game.player.position)<e.radius:_hit_player(e,e.sprite.position)
		"dash", "charge":
			var old: Vector2 = e.sprite.position
			var desired: Vector2 = e.attack_origin+e.direction*e.attack_length*t
			e.sprite.position=game.world.move_actor(old,desired-old,30.0 if e.boss else 18.0)
			var collision_width: float = e.half_width*(0.25+0.75*t) if e.attack_style=="dash" else e.half_width
			if _segment_distance(game.player.position,old,e.sprite.position)<collision_width:_hit_player(e,old)
			if desired.distance_to(e.sprite.position)>45:e.action_time=e.action_duration
		"ring", "safe_sector":
			var current_radius: float = lerpf(22.0,e.radius,t)
			var old_radius: float = lerpf(22.0,e.radius,previous/e.action_duration)
			var offset: Vector2 = game.player.position-e.attack_origin
			var safe: bool = e.attack_style=="safe_sector" and absf(wrapf(offset.angle()-e.safe_angle,-PI,PI))<0.58
			if not safe and offset.length()>=old_radius-22 and offset.length()<=current_radius+22:_hit_player(e,e.attack_origin)
			e.previous_radius=current_radius
		"root_fan":
			for angle in [-0.65,0.0,0.65]:
				var tip: Vector2 = e.attack_origin+e.direction.rotated(angle)*e.attack_length*t
				if _segment_distance(game.player.position,e.attack_origin,tip)<27:_hit_player(e,e.attack_origin)
		"slam":
			if t>=0.55 and game.player.position.distance_to(e.aim)<e.radius:_hit_player(e,e.attack_origin)
		"sweep":
			var direction: Vector2 = e.direction.rotated(lerpf(-1.1,1.1,t))
			if _sector_hit(game.player.position,e.attack_origin,direction,e.attack_length,0.22):_hit_player(e,e.attack_origin)
		"armor_sweep":
			for i in range(3):
				var direction: Vector2 = e.direction.rotated(float(i)*TAU/3+t*1.0)
				if game.player.position.distance_to(e.attack_origin)>65 and _sector_hit(game.player.position,e.attack_origin,direction,e.attack_length,0.16):_hit_player(e,e.attack_origin)
	if e.action_time>=e.action_duration:_recover(e)


func _recover(e: Dictionary) -> void:
	e.state="recover";e.warning=0.0;e.pose="idle"
	e.state_time=2.6 if e.attack_style=="charge" else (2.0 if e.boss else 1.1)
	e.cooldown=e.state_time+0.5
	if e.boss:e.vulnerable=maxf(e.vulnerable,3.5 if e.attack_style=="charge" else 2.2)
	_reset_pose(e)


func _hit_player(e: Dictionary, source: Vector2, serial: int = -1) -> void:
	var game: Node2D = _game()
	var attack_serial: int = int(e.attack_serial) if serial<0 else serial
	var key: String = "%d:%d"%[e.uid,attack_serial]
	if _hit_groups.has(key) or not _los(source,game.player.position):return
	_hit_groups[key]=_clock;e.hit=true
	game._hurt(e.attack,source,false,"enemy")


func _tick_projectiles(delta: float) -> void:
	var game: Node2D = _game()
	# Death or challenge completion can cancel its projectiles from a hit
	# callback. Keep dictionary identity, never a stale mutable-array index.
	for q:Dictionary in projectiles.duplicate():
		if not projectiles.has(q):continue
		q.life-=delta;q.age+=delta
		var owner: Dictionary = _by_uid(int(q.owner_uid))
		if owner.is_empty() or owner.hp<=0:q.life=0
		var old: Vector2 = q.p
		var displacement: Vector2 = q.velocity*delta
		q.previous=old;q.p+=displacement
		if not _los(old,q.p):q.life=0
		if q.life>0:
			if q.returned:
				for e in enemies.duplicate():
					if e.hp>0 and _segment_distance(e.sprite.position,old,q.p)<q.radius+28:
						damage(e,q.damage*2+8,"shield");expose(e,3.0);q.life=0;break
			elif _segment_distance(game.player.position,old,q.p)<q.radius+16:
				_hit_player(owner,old,int(q.serial));q.life=0
		if q.life<=0:projectiles.erase(q)
		if game.is_inside_tree() and game.get_tree().paused:return


func reflect_near(p: Vector2, radius: float = 120.0) -> int:
	var count: int = 0
	for q in projectiles:
		if q.returned or q.p.distance_to(p)>radius:continue
		var target: Dictionary = _by_uid(int(q.owner_uid))
		if target.is_empty() or target.hp<=0:continue
		q.returned=true;q.velocity=q.p.direction_to(target.sprite.position)*300.0
		q.life=3.0;count+=1
	return count


func interrupt(e: Dictionary, duration: float = 1.2) -> bool:
	if e.is_empty() or e.hp<=0:return false
	if e.boss:
		expose(e,minf(duration,1.5));return false
	e.state="stunned";e.state_time=maxf(0.3,duration);e.warning=0.0;e.pose="idle"
	e.cooldown=e.state_time+0.6
	for q in projectiles:
		if q.owner_uid==e.uid:q.life=0
	_reset_pose(e)
	return true


func expose(e: Dictionary, duration: float = 3.0) -> void:
	if e.is_empty() or e.hp<=0:return
	e.vulnerable=maxf(e.vulnerable,duration)


func damage(e: Dictionary, amount: float, kind: String = "melee") -> bool:
	if e.is_empty() or e.hp<=0 or amount<=0:return false
	var game: Node2D = _game()
	if game == null:return false
	if kind in ["bell","wind"]:interrupt(e,1.2)
	if kind=="shield":expose(e,2.5)
	var dealt: float = amount
	if e.boss and e.vulnerable<=0:
		dealt=maxf(1,amount*0.25)
		if e.hint_time<=0:
			game.ui.toast("核心护甲尚未打开 · 躲开招式，抓住收招或第三段重击")
			e.hint_time=3.0
	e.hp=maxf(0,e.hp-dealt);e.flash=0.16
	_reset_pose(e)
	game._effect(e.sprite.position+Vector2(0,-80),Color(1,0.88,0.56),str(int(ceilf(dealt))),0.75,0)
	if e.hp<=0:
		e.state="dead";e.warning=0.0;e.vulnerable=0.0;e.pose="idle"
		_reset_pose(e);e.sprite.modulate=Color(0.5,1,0.85,0.14)
		for q in projectiles:
			if q.owner_uid==e.uid:q.life=0
		game._effect(e.sprite.position,Color(0.4,0.95,0.82),"burst",1.0,110)
		if not e.notified:e.notified=true;game._enemy_defeated(e)
	else:_phase(e)
	return true


func _by_uid(uid: int) -> Dictionary:
	for e in enemies:
		if int(e.uid)==uid:return e
	return {}


func _los(from: Vector2, to: Vector2) -> bool:
	var game: Node2D = _game()
	return game != null and game.world.has_line_of_sight(from,to)


func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(p,a,b).distance_to(p)


func _sector_hit(p: Vector2, origin: Vector2, direction: Vector2, radius: float, half_angle: float) -> bool:
	var offset: Vector2 = p-origin
	return offset.length()<radius and (offset.length()<30 or absf(wrapf(offset.angle()-direction.angle(),-PI,PI))<half_angle)


func _reset_pose(e: Dictionary) -> void:
	if not is_instance_valid(e.sprite):return
	e.sprite.scale=e.base_scale;e.sprite.offset=e.base_offset;e.sprite.rotation=0.0


func _pose(e: Dictionary) -> void:
	_reset_pose(e)
	var s: Sprite2D = e.sprite
	if e.state=="windup":
		var t: float = 1-e.warning/e.tell_duration
		match str(e.id):
			"shadow_blob":s.scale=e.base_scale*Vector2(1.15+t*0.12,0.82-t*0.12)
			"crystal_thief":s.rotation=-0.20*signf(e.direction.x);s.scale=e.base_scale*Vector2(0.9,1.06)
			"wind_gremlin":s.rotation=sin(_clock*15)*0.07;s.scale=e.base_scale*Vector2(1.05,0.95)
			"moon_bubble":s.scale=e.base_scale*(1.04+t*0.23)
			"thorn_treant":s.rotation=sin(_clock*8)*0.035;s.scale=e.base_scale*Vector2(1.0,1.0+t*0.07)
			"windmill_guardian":s.rotation=sin(_clock*10)*0.08
			"stone_shell_guardian":s.scale=e.base_scale*Vector2(1.12,0.84);s.rotation=-signf(e.direction.x)*0.12
			"lantern_devourer":s.offset=e.base_offset+Vector2(0,-sin(_clock*4)*12);s.scale=e.base_scale*(1+t*0.08)
	elif e.state=="action":
		var t: float = e.action_time/e.action_duration
		if e.attack_style=="leap":s.offset=e.base_offset+Vector2(0,-sin(t*PI)*120)
		elif e.attack_style in ["dash","charge"]:s.rotation=signf(e.direction.x)*0.22;s.scale=e.base_scale*Vector2(1.12,0.92)
		elif e.attack_style=="sweep":s.rotation=lerpf(-0.17,0.17,t)
		elif e.attack_style in ["gust","wind_lanes"]:s.rotation=sin(t*TAU)*0.15
	elif e.state=="stunned":s.rotation=sin(_clock*13)*0.10
	if e.flash>0:s.modulate=Color(1.6,1.35,0.8)
	elif e.state=="stunned":s.modulate=Color(0.65,0.95,1)
	else:s.modulate=Color.WHITE


func draw(canvas: Node2D, font: Font) -> void:
	for e in enemies:
		if e.hp<=0 or not is_instance_valid(e.sprite):continue
		var p: Vector2 = e.sprite.position
		var width: float = 180 if e.boss else 68
		var high: float = 245 if e.boss else 115
		canvas.draw_rect(Rect2(p+Vector2(-width/2,-high),Vector2(width,8)),Color(0.02,0.07,0.1,0.85))
		canvas.draw_rect(Rect2(p+Vector2(-width/2,-high),Vector2(width*e.hp/e.max_hp,8)),CYAN if e.vulnerable>0 else ORANGE)
		if font != null:
			if e.boss:canvas.draw_string(font,p+Vector2(-width/2,-high-10),"%s · %d"%[e.name,e.phase+1],HORIZONTAL_ALIGNMENT_LEFT,-1,20,CYAN)
			if e.state=="windup":canvas.draw_string(font,p+Vector2(-62,-high-30),str(TELL_NAMES.get(e.attack_style,"!")),HORIZONTAL_ALIGNMENT_LEFT,-1,17,ORANGE)
			elif e.state=="recover" and e.boss:canvas.draw_string(font,p+Vector2(-52,-high-28),"核心显露",HORIZONTAL_ALIGNMENT_LEFT,-1,18,CYAN)
		if e.state=="windup":_draw_tell(canvas,e,font)
		elif e.state=="action":_draw_action(canvas,e)
	for q in projectiles:
		var color: Color = CYAN if q.returned else (Color(0.75,0.58,1) if q.kind in ["shadow","star"] else Color(0.63,0.86,1))
		canvas.draw_line(q.p-q.velocity.normalized()*34,q.p,color*Color(1,1,1,0.45),4,true)
		canvas.draw_circle(q.p,q.radius,color*Color(1,1,1,0.22))
		canvas.draw_arc(q.p,q.radius,0,TAU,24,color,2,true)
		canvas.draw_circle(q.p,maxf(3,q.radius*0.30),color)


func _draw_tell(canvas: Node2D, e: Dictionary, font: Font) -> void:
	var origin: Vector2 = e.attack_origin
	var progress: float = 1-e.warning/e.tell_duration
	var color: Color = ORANGE
	match str(e.attack_style):
		"leap", "slam":
			canvas.draw_circle(e.aim,e.radius,Color(1,0.55,0.3,0.10))
			canvas.draw_arc(e.aim,e.radius,0,TAU,48,color,2,true)
			canvas.draw_arc(e.aim,e.radius+7,-PI/2,-PI/2+maxf(0.02,progress*TAU),48,color,4,true)
			_arrow(canvas,origin,e.aim,color,2)
		"dash":
			var end: Vector2 = origin+e.direction*e.attack_length
			var normal: Vector2 = e.direction.orthogonal()*e.half_width
			canvas.draw_colored_polygon(PackedVector2Array([origin-normal*0.25,origin+normal*0.25,end+normal,end-normal]),color*Color(1,1,1,0.12))
			canvas.draw_line(origin-normal*0.25,end-normal,color,2,true)
			canvas.draw_line(origin+normal*0.25,end+normal,color,2,true)
			_arrow(canvas,origin,end,color,2)
		"charge":_lane(canvas,origin,e.direction,e.attack_length,e.half_width,color)
		"root_fan":
			for angle in [-0.65,0.0,0.65]:_lane(canvas,origin,e.direction.rotated(angle),e.attack_length,27,color)
		"wind_lanes":
			for angle in ([-0.48,0.48] if e.phase>0 else [0.0]):_lane(canvas,origin,e.direction.rotated(angle),e.attack_length,70,color)
		"ring":
			for radius in [e.radius*0.4,e.radius*0.7,e.radius]:canvas.draw_arc(origin,radius,0,TAU,64,color*Color(1,1,1,0.55),2,true)
		"safe_sector":
			canvas.draw_arc(origin,e.radius,e.safe_angle+0.58,e.safe_angle+TAU-0.58,64,color,3,true)
			for angle in [e.safe_angle-0.58,e.safe_angle+0.58]:canvas.draw_line(origin,origin+Vector2.from_angle(angle)*e.radius,CYAN,3,true)
			if font != null:canvas.draw_string(font,origin+Vector2.from_angle(e.safe_angle)*260+Vector2(-20,0),"安全",HORIZONTAL_ALIGNMENT_LEFT,-1,22,CYAN)
		"armor_sweep":
			for i in range(3):_cone(canvas,origin,e.direction.rotated(i*TAU/3+0.5),e.attack_length,0.67,color)
		_:
			if e.attack_style=="shadow_orbs":
				origin=e.teleport_target;canvas.draw_arc(origin,55,0,TAU,32,Color(0.75,0.6,1),3,true)
			_cone(canvas,origin,e.direction,e.attack_length,1.32 if e.attack_style=="sweep" else 0.48,color)


func _draw_action(canvas: Node2D, e: Dictionary) -> void:
	var t: float = e.action_time/e.action_duration
	match str(e.attack_style):
		"ring":canvas.draw_arc(e.attack_origin,lerpf(22,e.radius,t),0,TAU,64,ORANGE,8,true)
		"safe_sector":canvas.draw_arc(e.attack_origin,lerpf(22,e.radius,t),e.safe_angle+0.58,e.safe_angle+TAU-0.58,64,ORANGE,10,true)
		"root_fan":
			for angle in [-0.65,0.0,0.65]:canvas.draw_line(e.attack_origin,e.attack_origin+e.direction.rotated(angle)*e.attack_length*t,Color(0.7,0.85,0.45),12,true)
		"slam":canvas.draw_arc(e.aim,e.radius,0,TAU,48,ORANGE,8,true)
		"sweep":_cone(canvas,e.attack_origin,e.direction.rotated(lerpf(-1.1,1.1,t)),e.attack_length,0.20,ORANGE)
		"armor_sweep":
			for i in range(3):_cone(canvas,e.attack_origin,e.direction.rotated(i*TAU/3+t),e.attack_length,0.14,ORANGE)


func _arrow(canvas: Node2D, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	canvas.draw_line(a,b,color,width,true)
	var direction: Vector2 = a.direction_to(b)
	canvas.draw_line(b,b-direction.rotated(0.55)*18,color,width,true)
	canvas.draw_line(b,b-direction.rotated(-0.55)*18,color,width,true)


func _lane(canvas: Node2D, origin: Vector2, direction: Vector2, length_value: float, half_width: float, color: Color) -> void:
	var normal: Vector2 = direction.orthogonal()*half_width
	var end: Vector2 = origin+direction*length_value
	canvas.draw_colored_polygon(PackedVector2Array([origin-normal,origin+normal,end+normal,end+direction*16,end-normal]),color*Color(1,1,1,0.12))
	_arrow(canvas,origin,end,color,2)
	canvas.draw_line(origin-normal,end-normal,color*Color(1,1,1,0.6),1.5,true)
	canvas.draw_line(origin+normal,end+normal,color*Color(1,1,1,0.6),1.5,true)


func _cone(canvas: Node2D, origin: Vector2, direction: Vector2, radius: float, half_angle: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([origin])
	for i in range(19):points.append(origin+direction.rotated(lerpf(-half_angle,half_angle,float(i)/18))*radius)
	canvas.draw_colored_polygon(points,color*Color(1,1,1,0.08))
	canvas.draw_arc(origin,radius,direction.angle()-half_angle,direction.angle()+half_angle,24,color,2,true)
	canvas.draw_line(origin,points[1],color,1.5,true);canvas.draw_line(origin,points[-1],color,1.5,true)
