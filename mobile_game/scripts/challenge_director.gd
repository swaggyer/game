extends RefCounted
## Optional chapter-scoped microlevels: timed routes, waves, plate relays,
## moving projectile targets and a physical, path-following escort cart.
## Rewards are independent of main-quest completion and granted exactly once.

const DATA_PATH="res://data/challenges_v12.json"
const GOLD=Color("#f0ce7d")
const TEAL=Color("#9dd9c5")
const CORAL=Color("#f28a66")
const TYPE_NAMES={"race":"限时穿门","waves":"三波战斗","pressure":"踏板光栅","targets":"移动靶场","escort":"护送粮车"}
var challenges:Array=[]
var chapter:=0
var last_result:Dictionary={}
var _owner_ref:WeakRef
var _document:Dictionary={}
var _active:Dictionary={}
var _clock:=0.0
var _feedback_time:=0.0
var _avoid:Array=[]

func setup(game:Node2D) -> void:
	_owner_ref=weakref(game)
	var decoded=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_document=decoded if decoded is Dictionary else {}

func _game() -> Node2D:
	return _owner_ref.get_ref() if _owner_ref else null

func configure(chapter_index:int,saved:Dictionary={}) -> void:
	cancel()
	chapter=clampi(chapter_index,0,6)
	challenges.clear();last_result.clear();_avoid.clear()
	var entries:Array=_document.get("chapters",[])
	if chapter>=entries.size():return
	var source:Dictionary=entries[chapter]
	for point in source.get("avoid",[]):_avoid.append(_vector(point))
	var completed:Array=saved.get("completed",[]) if saved.get("completed",[]) is Array else []
	var best:Dictionary=saved.get("best_times",{}) if saved.get("best_times",{}) is Dictionary else {}
	var medals:Dictionary=saved.get("medals",{}) if saved.get("medals",{}) is Dictionary else {}
	for raw:Dictionary in source.get("challenges",[]):
		var c:Dictionary=raw.duplicate(true)
		var desired:=_vector(raw.get("p",[500,500]))
		c.p=_safe_center(desired)
		var offset:Vector2=c.p-desired
		var points:Array=[]
		for point in raw.get("points",[]):points.append(_safe(_vector(point)+offset))
		c.points=points;c.index=challenges.size();c.completed=c.id in completed
		c.active=false;c.step=0;c.progress=0;c.status="ready"
		c.reward={"xp":24,"crystals":10}
		var best_value=best.get(c.id,0.0)
		c.best_time=float(best_value) if (best_value is int or best_value is float) and is_finite(float(best_value)) and float(best_value)>0 and float(best_value)<3600 else 0.0
		c.medal=str(medals.get(c.id,"")) if str(medals.get(c.id,"")) in ["gold","silver","bronze"] else ""
		challenges.append(c)

func _vector(value:Variant) -> Vector2:
	if value is Vector2:return value
	if value is Array and value.size()>=2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):return Vector2(float(value[0]),float(value[1]))
	return Vector2(500,500)

func _safe(p:Vector2) -> Vector2:
	var g:=_game()
	return g.world.nearest_safe(p) if g else p

func _safe_center(desired:Vector2) -> Vector2:
	var g:=_game()
	if not g:return desired
	var mandatory:Array=[]
	for property:Dictionary in g.world.get_property_list():
		if property.name=="_objective_sets":
			for group:Array in g.world.get("_objective_sets"):mandatory.append_array(group)
	var safe_points:Array=g.world.definition.get("camps",[]).duplicate()
	safe_points.append(g.world.definition.get("spawn",Vector2.ZERO));safe_points.append(g.world.definition.get("lamp",Vector2.ZERO))
	for ring in range(5):
		var count:=1 if ring==0 else 12
		for i in range(count):
			var candidate:=desired+Vector2.from_angle(i*TAU/count)*ring*85.0
			if not g.world.is_walkable(candidate,34):continue
			var clear:=true
			for p:Vector2 in mandatory:
				if p.distance_to(candidate)<185:clear=false;break
			if not clear:continue
			for p:Vector2 in safe_points:
				if p.distance_to(candidate)<190:clear=false;break
			if not clear:continue
			for p:Vector2 in _avoid:
				if p.distance_to(candidate)<155:clear=false;break
			if clear:return candidate
	return _safe(desired)

func nearest_available(p:Vector2) -> Dictionary:
	if not _active.is_empty():return {}
	var nearest:Dictionary={}
	var distance:=135.0
	for c:Dictionary in challenges:
		var d:float=p.distance_to(c.p)
		if d<distance:nearest=c;distance=d
	return nearest

func interaction_at(p:Vector2) -> Dictionary:
	if not _active.is_empty():
		if _active.type=="escort" and _active.get("waiting_lever",false) and p.distance_to(_active.lever)<135:
			return {"id":_active.id,"p":_active.lever,"label":"解除粮车制动","action":"lever"}
		return {}
	var c:=nearest_available(p)
	if c.is_empty():return {}
	return {"id":c.id,"p":c.p,"label":("再挑战 · " if c.completed else "挑战 · ")+str(c.name),"action":"start"}

func handle_interaction(p:Vector2) -> bool:
	var action:=interaction_at(p)
	if action.is_empty():return false
	if action.action=="start":return start(action.id)
	if action.action=="lever" and not _active.is_empty():
		_active.waiting_lever=false;_active.moving=true
		_cart_path(_active)
		_toast("制动已松开 · 跟上粮车，去下一处安全点")
		return true
	return false

func start(id:String) -> bool:
	var g:=_game()
	if not g or not _active.is_empty() or not g.active or (g.is_inside_tree() and g.get_tree().paused):return false
	var c:=_find(id)
	if c.is_empty() or g.player.position.distance_to(c.p)>170:return false
	c.active=true;c.status="running";c.step=0;c.progress=0;c.elapsed=0.0;c.penalty=0.0
	c.limit=float(c.time_limit)*(1.18 if g.campaign.difficulty=="gentle" else 1.0)
	c.remaining=c.limit;c.pulse_hits={};c.last_plate=-1;c.wave=0;c.wave_active=false;c.spawn_delay=1.4
	c.targets=[];c.pulses=[];c.moving=false;c.waiting_lever=false;c.needs_wave=true
	_active=c;last_result.clear();_feedback_time=0
	if c.type in ["race","pressure"]:c.pulses=_make_pulses(c)
	elif c.type=="targets":
		var order:Array=c.get("target_order",[0,1,2,3,4])
		for i in range(c.points.size()):
			var target_number:=i+1
			for ordinal in range(order.size()):
				if int(order[ordinal])==i:target_number=ordinal+1;break
			c.targets.append({"base":c.points[i],"p":c.points[i],"hits":0,"done":false,"flash":0.0,"number":target_number})
	elif c.type=="escort":
		c.cart_p=c.p;c.route_index=1;c.cart_path=PackedVector2Array();c.cart_path_index=0;c.lever=c.p
	_toast(str(c.name)+" · "+str(c.description))
	_effect(c.p,TEAL,"ring",0.8,100)
	return true

func _find(id:String) -> Dictionary:
	for c:Dictionary in challenges:
		if c.id==id:return c
	return {}

func _make_pulses(c:Dictionary) -> Array:
	var g:=_game()
	var pulses:Array=[]
	var count:=mini(int(c.get("hazard_count",2)),maxi(0,c.points.size()-1))
	for i in range(count):
		var a:Vector2=c.points[i]
		var b:Vector2=c.points[i+1]
		var path:PackedVector2Array=g.world.find_path(a,b)
		var midpoint:Vector2=path[int(path.size()/2)] if path.size()>0 else _safe(a.lerp(b,0.5))
		var axis:=a.direction_to(b).orthogonal()
		var left:Vector2=g.world.move_actor(midpoint,-axis*88,5)
		var right:Vector2=g.world.move_actor(midpoint,axis*88,5)
		pulses.append({"a":left,"b":right,"p":midpoint,"phase":i*1.13,"state":"warning","cycle":0})
	return pulses

func update(delta:float) -> void:
	var g:=_game()
	if not g or not g.active or delta<=0 or (g.is_inside_tree() and g.get_tree().paused):return
	_clock+=delta;_feedback_time=maxf(0,_feedback_time-delta)
	if _active.is_empty():return
	var c:Dictionary=_active
	c.elapsed+=delta;c.remaining=maxf(0,c.limit-c.elapsed-c.penalty)
	if c.remaining<=0:_fail("时间到了。回到旗标即可马上重试。");return
	if c.type in ["waves","targets","pressure"] and g.player.position.distance_to(c.p)>900:
		_fail("离开了挑战范围，本次尝试已重置。");return
	match str(c.type):
		"race":_tick_race(c)
		"pressure":_tick_pressure(c)
		"waves":_tick_waves(c,delta)
		"targets":_tick_targets(c,delta)
		"escort":_tick_escort(c,delta)
	if not _active.is_empty() and c.type in ["race","pressure"]:_tick_pulses(c)

func _tick_race(c:Dictionary) -> void:
	var g:=_game()
	if int(c.step)>=c.points.size():return
	var gate:Vector2=c.points[int(c.step)]
	if g.player.position.distance_to(gate)<64:
		c.step+=1;c.progress=c.step;_effect(gate,TEAL,"ring",0.55,85)
		if c.step>=c.points.size():_win()

func _tick_pressure(c:Dictionary) -> void:
	var g:=_game()
	var inside:=-1
	for i in range(c.points.size()):
		if g.player.position.distance_to(c.points[i])<46:inside=i;break
	if inside<0:c.last_plate=-1;return
	if inside==int(c.last_plate):return
	c.last_plate=inside
	if inside==int(c.step):
		c.step+=1;c.progress=c.step;_effect(c.points[inside],TEAL,"burst",0.5,75)
		if c.step>=c.points.size():_win()
	elif inside>=int(c.step):
		c.step=0;c.progress=0;c.penalty+=0.8
		_toast("顺序断开 · 从数字1重新跑起，踩入就会触发")

func _tick_pulses(c:Dictionary) -> void:
	var g:=_game()
	for i in range(c.pulses.size()):
		var pulse:Dictionary=c.pulses[i]
		var t:float=c.elapsed+pulse.phase
		var phase:=fmod(t,3.5)
		pulse.cycle=int(t/3.5)
		pulse.state="warning" if phase<0.95 else ("active" if phase<1.60 else "rest")
		if pulse.state!="active":continue
		var nearest:=Geometry2D.get_closest_point_to_segment(g.player.position,pulse.a,pulse.b)
		var key:="%d:%d"%[i,pulse.cycle]
		if g.player.position.distance_to(nearest)<22 and not c.pulse_hits.has(key) and g.world.has_line_of_sight(pulse.p,g.player.position):
			c.pulse_hits[key]=true
			if _hazard_hurt(12,pulse.p):
				c.penalty+=1.2
				_toast("碰到脉冲光栅 · 时间 +1.2秒。等光线退回再穿过")

func _hazard_hurt(amount:float,p:Vector2) -> bool:
	var g:=_game()
	if not g:return false
	if float(g.get("invulnerable"))>0 or float(g.get("shield_time"))>0:return false
	var safe_points:Array=g.world.definition.get("camps",[]).duplicate()
	safe_points.append(g.world.definition.get("spawn",Vector2.ZERO))
	for safe:Vector2 in safe_points:
		if g.player.position.distance_to(safe)<140:return false
	g._hurt(amount,p,true,"environment")
	return true

func _tick_targets(c:Dictionary,delta:float) -> void:
	var g:=_game()
	for i in range(c.targets.size()):
		var target:Dictionary=c.targets[i]
		target.flash=maxf(0,float(target.flash)-delta)
		if target.done:continue
		var candidate:Vector2=target.base+Vector2(sin(c.elapsed*(0.85+i*0.08)+i*1.9)*42,cos(c.elapsed*0.65+i)*23)
		target.p=candidate if g.world.is_walkable(candidate,30) else target.base

func hit_targets(origin:Vector2,direction:Vector2,reach:float,kind:String,damage:float=1.0,half_angle:float=0.55) -> int:
	if _active.is_empty() or _active.type!="targets" or damage<=0:return 0
	if not kind in ["projectile","echo","ranged"]:
		if _feedback_time<=0:_toast("切换小馒头，用星矢弹击中靶心");_feedback_time=2
		return 0
	var g:=_game()
	var best:=-1
	var nearest:=reach
	for i in range(_active.targets.size()):
		var t:Dictionary=_active.targets[i]
		if t.done:continue
		var offset:Vector2=t.p-origin
		if offset.length()>nearest:continue
		if offset.length()>1 and absf(wrapf(offset.angle()-direction.angle(),-PI,PI))>half_angle:continue
		if not g.world.has_line_of_sight(origin,t.p):continue
		best=i;nearest=offset.length()
	return _target_hit(best) if best>=0 else 0

func hit_target_segment(from:Vector2,to:Vector2,radius:float=12.0,kind:String="projectile") -> int:
	if _active.is_empty() or _active.type!="targets" or not kind in ["projectile","echo","ranged"]:return 0
	var g:=_game()
	var best:=-1
	var nearest:=INF
	for i in range(_active.targets.size()):
		var target:Dictionary=_active.targets[i]
		if target.done:continue
		var p:Vector2=target.p
		var closest:=Geometry2D.get_closest_point_to_segment(p,from,to)
		if closest.distance_to(p)>radius+24 or not g.world.has_line_of_sight(from,p):continue
		var distance:=from.distance_squared_to(closest)
		if distance<nearest:best=i;nearest=distance
	return _target_hit(best) if best>=0 else 0

func _target_hit(index:int) -> int:
	if _active.is_empty() or index<0 or index>=_active.targets.size():return 0
	var c:Dictionary=_active
	var target:Dictionary=c.targets[index]
	target.flash=0.23
	if int(target.number)!=int(c.step)+1:
		if _feedback_time<=0:_toast("先击中亮起的数字%d号靶"%(int(c.step)+1));_feedback_time=1.5
		return 1
	target.hits+=1
	_effect(target.p,GOLD,"ring",0.35,45)
	if target.hits>=int(c.get("target_hits",1)):
		target.done=true;c.step+=1;c.progress=c.step
		if c.step>=c.targets.size():_win()
	return 1

func _spawn_wave(c:Dictionary) -> void:
	var g:=_game()
	var wave_index:=int(c.wave)
	if wave_index>=c.waves.size():return
	var ids:Array=c.waves[wave_index]
	var center:Vector2=c.cart_p if c.type=="escort" else c.p
	c.wave+=1;c.wave_active=true
	if c.type=="waves":c.step=c.wave
	for i in range(ids.size()):
		var angle:float=i*TAU/maxi(1,ids.size())+wave_index*0.93
		var p:=_safe(center+Vector2.from_angle(angle)*205)
		var e:Dictionary=g.enemy_director.spawn(str(ids[i]),p,false,-1000-int(c.index))
		if e.is_empty():continue
		e["challenge"]=true;e["challenge_id"]=c.id;e["challenge_wave"]=c.wave
		e["state"]="chase";e["memory"]=5.0;e["last_seen"]=g.player.position;e["leash"]=1050.0
		e["cooldown"]=1.35
	_toast("%s · 第%d/3波，先看起手再反击"%[c.name,c.wave])

func _remaining() -> int:
	var g:=_game()
	if not g or _active.is_empty():return 0
	var result:=0
	for e:Dictionary in g.enemy_director.enemies:
		if e.get("challenge_id","")==_active.id and float(e.get("hp",0))>0:result+=1
	return result

func enemy_defeated(enemy:Dictionary) -> bool:
	if not enemy.get("challenge",false):return false
	if enemy.get("challenge_counted",false):return true
	enemy.challenge_counted=true
	if not _active.is_empty() and enemy.get("challenge_id","")==_active.id:_active.progress+=1
	return true

func _tick_waves(c:Dictionary,delta:float) -> void:
	if c.wave_active:
		if _remaining()>0:return
		c.wave_active=false
		if int(c.wave)>=c.waves.size():_win();return
		c.spawn_delay=1.8
		_toast("这一波净化完成 · 下一波即将到来")
	else:
		c.spawn_delay-=delta
		if c.spawn_delay<=0:_spawn_wave(c)

func _tick_escort(c:Dictionary,delta:float) -> void:
	var g:=_game()
	if g.player.position.distance_to(c.cart_p)>950:_fail("离粮车太远了。回旗标重新组织巡游。");return
	if c.wave_active:
		if _remaining()>0:return
		c.wave_active=false;c.waiting_lever=true;c.moving=false
		c.lever=_safe(c.cart_p+Vector2(80,60))
		_toast("伏击已清除 · 到车旁拉杆解除制动，继续护送")
		return
	if c.needs_wave:
		c.spawn_delay-=delta
		if c.spawn_delay<=0:c.needs_wave=false;_spawn_wave(c)
		return
	if c.waiting_lever or not c.moving:return
	if g.player.position.distance_to(c.cart_p)>310:return
	var path:PackedVector2Array=c.cart_path
	while int(c.cart_path_index)<path.size() and c.cart_p.distance_to(path[int(c.cart_path_index)])<15:c.cart_path_index+=1
	if int(c.cart_path_index)<path.size():
		var target:Vector2=path[int(c.cart_path_index)]
		c.cart_p=g.world.move_actor(c.cart_p,(target-c.cart_p).limit_length(82*delta),24)
	var destination:Vector2=c.points[int(c.route_index)]
	if c.cart_p.distance_to(destination)>32:return
	c.step=int(c.route_index);c.route_index+=1
	if int(c.route_index)>=c.points.size():_win();return
	if int(c.wave)<c.waves.size():c.needs_wave=true;c.moving=false;c.spawn_delay=1.1
	else:_cart_path(c)

func _cart_path(c:Dictionary) -> void:
	var g:=_game()
	if int(c.route_index)>=c.points.size():return
	c.cart_path=g.world.find_path(c.cart_p,c.points[int(c.route_index)])
	c.cart_path_index=0

func constrain_motion(from:Vector2,to:Vector2,radius:float=20.0) -> Vector2:
	if _active.is_empty() or _active.type!="escort":return to
	if to.distance_to(_active.cart_p)<48+radius and from.distance_to(_active.cart_p)>=48+radius:return from
	return to

func _cleanup_enemies(id:String) -> void:
	var g:=_game()
	if not g:return
	var uids:Array=[]
	for i in range(g.enemy_director.enemies.size()-1,-1,-1):
		var enemy:Dictionary=g.enemy_director.enemies[i]
		if enemy.get("challenge_id","")!=id:continue
		uids.append(int(enemy.get("uid",-1)))
		enemy.hp=0;enemy["notified"]=true;enemy["state"]="dead"
		if is_instance_valid(enemy.get("sprite")):enemy.sprite.queue_free()
		g.enemy_director.enemies.remove_at(i)
	for i in range(g.enemy_director.projectiles.size()-1,-1,-1):
		if int(g.enemy_director.projectiles[i].get("owner_uid",-2)) in uids:g.enemy_director.projectiles.remove_at(i)

func _win() -> void:
	if _active.is_empty():return
	var c:Dictionary=_active
	var elapsed:float=c.elapsed+c.penalty
	var first:bool=not c.completed
	var medal:="gold" if elapsed<=c.limit*0.60 else ("silver" if elapsed<=c.limit*0.82 else "bronze")
	if c.best_time<=0 or elapsed<float(c.best_time):c.best_time=elapsed;c.medal=medal
	c.completed=true;c.status="completed";c.active=false
	if first:
		var g:=_game()
		g.campaign.xp=mini(11400,int(g.campaign.xp)+24);g.campaign.crystals+=10
	last_result={"id":c.id,"success":true,"first_clear":first,"time":elapsed,"medal":medal}
	_cleanup_enemies(c.id)
	_effect(c.p,TEAL,"burst",1.2,150)
	_active={}
	_toast(str(c.name)+"完成 · "+_medal_name(medal)+(" · 经验+24 星晶+10" if first else " · 已记录本次成绩"))
	_persist()

func _fail(reason:String) -> void:
	if _active.is_empty():return
	var id:String=_active.id
	last_result={"id":id,"success":false,"reason":reason}
	cancel()
	_toast(reason)

func cancel(reason:String="") -> void:
	if _active.is_empty():return
	var c:Dictionary=_active
	_cleanup_enemies(c.id)
	c.active=false;c.step=0;c.progress=0;c.status="ready"
	_active={}
	if not reason.is_empty():_toast(reason)

func reset_on_death() -> void:
	_fail("本次挑战已重置 · 已有勋章和主线进度保留，可立即重试")

func completed_ids() -> Array:
	var result:Array=[]
	for c:Dictionary in challenges:
		if c.completed:result.append(str(c.id))
	return result

func snapshot() -> Dictionary:
	var medals:Dictionary={};var best:Dictionary={}
	for c:Dictionary in challenges:
		if not c.completed:continue
		medals[c.id]=c.medal;best[c.id]=c.best_time
	return {"version":1,"chapter":chapter,"completed":completed_ids(),"medals":medals,"best_times":best}

func active_label() -> String:
	if _active.is_empty():return ""
	var c:Dictionary=_active
	var detail:=""
	match str(c.type):
		"race":detail="风门 %d/%d"%[mini(int(c.step)+1,c.points.size()),c.points.size()]
		"pressure":detail="踩入数字 %d/%d"%[mini(int(c.step)+1,c.points.size()),c.points.size()]
		"targets":detail="星矢靶 %d/%d"%[mini(int(c.step)+1,c.targets.size()),c.targets.size()]
		"waves":detail="第%d/3波 · 剩余%d只"%[maxi(1,int(c.wave)),_remaining()]
		"escort":detail="解除车旁制动" if c.waiting_lever else ("伏击 · 剩余%d只"%_remaining() if c.wave_active else "跟上粮车 · 路标%d/%d"%[c.route_index,c.points.size()-1])
	return "%s · %s · %.1f秒"%[c.name,detail,float(c.remaining)]

func active_info() -> Dictionary:
	return _active

func _medal_name(value:String) -> String:
	return {"gold":"金星勋章","silver":"银星勋章","bronze":"铜星勋章"}.get(value,"星灯勋章")

func _persist() -> void:
	var g:=_game()
	if g and g.has_method("_save_all"):g._save_all()

func _toast(message:String) -> void:
	var g:=_game()
	if g:g.ui.toast(message)

func _effect(p:Vector2,color:Color,kind:String,life:float,radius:float) -> void:
	var g:=_game()
	if g:g._effect(p,color,kind,life,radius)

func draw(canvas:Node2D,font:Font) -> void:
	var g:=_game()
	if not g or not g.active:return
	for c:Dictionary in challenges:
		if g.player.position.distance_to(c.p)>1050:continue
		var color:=TEAL if c.completed else GOLD
		canvas.draw_circle(c.p,39,Color(0.08,0.20,0.20,0.72),true,-1,true)
		canvas.draw_arc(c.p,41,0,TAU,64,color,2.1,true)
		canvas.draw_line(c.p+Vector2(-7,-18),c.p+Vector2(-7,18),color,3,true)
		canvas.draw_colored_polygon(PackedVector2Array([c.p+Vector2(-6,-18),c.p+Vector2(19,-12),c.p+Vector2(-6,-4)]),color)
		if font:
			canvas.draw_string(font,c.p+Vector2(-72,-66),("✓ " if c.completed else "✦ ")+str(c.name),HORIZONTAL_ALIGNMENT_LEFT,-1,18,color)
			canvas.draw_string(font,c.p+Vector2(-53,66),TYPE_NAMES.get(c.type,"挑战"),HORIZONTAL_ALIGNMENT_LEFT,-1,15,color)
	if _active.is_empty():return
	var c:Dictionary=_active
	if c.type in ["race","pressure"]:
		for i in range(c.points.size()):
			var p:Vector2=c.points[i]
			var color:=TEAL if i<int(c.step) else (GOLD if i==int(c.step) else Color("#739288"))
			if c.type=="race":
				canvas.draw_arc(p,52,0,TAU,64,Color(color,0.8),3,true)
				for side in [-1,1]:
					canvas.draw_line(p+Vector2(side*50,-22),p+Vector2(side*50,22),color,6,true)
			else:
				canvas.draw_circle(p,39,Color("#3b514a"),true,-1,true)
				canvas.draw_arc(p,41,0,TAU,48,color,3,true)
			if font:canvas.draw_string(font,p+Vector2(-7,7),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,24,color)
		for pulse:Dictionary in c.pulses:_draw_pulse(canvas,pulse)
	elif c.type=="targets":
		for target:Dictionary in c.targets:
			var p:Vector2=target.p
			var color:=TEAL if target.done else (GOLD if int(target.number)==int(c.step)+1 else Color("#84988d"))
			if target.flash>0:color=Color.WHITE
			canvas.draw_line(p+Vector2(0,24),p+Vector2(0,43),Color("#806c4a"),7,true)
			canvas.draw_circle(p,27,Color("#304b45"),true,-1,true)
			canvas.draw_arc(p,27,0,TAU,64,color,4,true)
			canvas.draw_arc(p,16,0,TAU,48,color,1.8,true)
			if target.done:canvas.draw_line(p+Vector2(-8,0),p+Vector2(-1,8),color,3,true);canvas.draw_line(p+Vector2(-1,8),p+Vector2(12,-8),color,3,true)
			elif font:canvas.draw_string(font,p+Vector2(-7,8),str(target.number),HORIZONTAL_ALIGNMENT_LEFT,-1,23,color)
	elif c.type=="escort":
		_draw_cart(canvas,c)
		if c.waiting_lever:
			var p:Vector2=c.lever
			canvas.draw_circle(p,18,Color("#284d48"),true,-1,true)
			canvas.draw_line(p,p+Vector2(12,-24),GOLD,5,true)
			canvas.draw_arc(p,25,0,TAU,32,GOLD,1.5,true)
			if font:canvas.draw_string(font,p+Vector2(-40,-43),"解除制动",HORIZONTAL_ALIGNMENT_LEFT,-1,16,GOLD)

func _draw_pulse(canvas:Node2D,pulse:Dictionary) -> void:
	var color:=GOLD if pulse.state=="warning" else (CORAL if pulse.state=="active" else Color("#68867e"))
	for p:Vector2 in [pulse.a,pulse.b]:
		canvas.draw_circle(p,12,Color("#3d514c"),true,-1,true)
		canvas.draw_arc(p,12,0,TAU,32,color,2,true)
	if pulse.state=="active":
		canvas.draw_line(pulse.a,pulse.b,Color(color,0.18),23,true)
		canvas.draw_line(pulse.a,pulse.b,color,6,true)
	elif pulse.state=="warning":
		for i in range(7):canvas.draw_line((pulse.a as Vector2).lerp(pulse.b,i/7.0),(pulse.a as Vector2).lerp(pulse.b,(i+0.5)/7.0),color,2,true)

func _draw_cart(canvas:Node2D,c:Dictionary) -> void:
	var p:Vector2=c.cart_p
	canvas.draw_style_box(_box(Color("#59432d")),Rect2(p-Vector2(43,26),Vector2(86,54)))
	canvas.draw_style_box(_box(Color("#af8c54")),Rect2(p-Vector2(39,31),Vector2(78,45)))
	for x in [-35,35]:
		canvas.draw_circle(p+Vector2(x,19),11,Color("#3c4540"),true,-1,true)
		canvas.draw_arc(p+Vector2(x,19),11,0,TAU,32,GOLD,2,true)
	for x in [-21,0,21]:canvas.draw_line(p+Vector2(x,-27),p+Vector2(x,10),Color("#80673e"),2,true)
	canvas.draw_circle(p+Vector2(0,-12),13,Color("#f0d899"),true,-1,true)
	canvas.draw_arc(p,58,0,TAU,48,Color(TEAL,0.6),1.5,true)

func _box(color:Color) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=color;box.set_corner_radius_all(5)
	return box
