extends RefCounted
## Active story trials: timed obstacle courses, destructible seals and escorted carts.
const Traps=preload("res://scripts/trap_director.gd")
var owner_ref:WeakRef
var states:Array=[]
var active_index=-1
var local_traps=Traps.new()
var clock=0.0
var _run_serial=0
var _updating_local_traps=false
var _clear_traps_pending=false
var _escort_uids:Dictionary={}

func setup(game:Node2D)->void:owner_ref=weakref(game)
func configure(saved:Array=[])->void:
	clear();var g=owner_ref.get_ref()
	for i in range(3):
		var kind=str(g.objectives[i].kind);var p:Vector2=g.points[i]
		var d={"index":i,"kind":kind,"p":p,"active":false,"gate":0,"time":0.0,"limit":0.0,"route":PackedVector2Array(),"targets":[],"cart":null,"cart_path":PackedVector2Array(),"cart_index":0,"cart_distance":0.0,"cart_total":0.0,"ambush":0,"failed":false}
		if kind=="course":
			var goals=[p+Vector2(280,-180),p+Vector2(440,190),p+Vector2(-160,280),p]
			var previous=p;var length=0.0
			for q in goals:
				var goal:Vector2=g.world.nearest_safe(q);var path:PackedVector2Array=g.world.find_path(previous,goal)
				if path.is_empty():continue
				for j in range(1,path.size()):length+=path[j-1].distance_to(path[j])
				d.route.append(goal);previous=goal
			d.limit=maxf(16,length/205.0*1.8+7)
		elif kind=="seal":
			for j in range(3):
				var q=g.world.nearest_safe(p+Vector2.from_angle(j*TAU/3)*105)
				var maximum=maxf(12,12+int(g.campaign.stage/3)*6)
				var hp=maximum
				if i<saved.size() and saved[i] is Dictionary:
					var health=saved[i].get("targets",[])
					if health is Array and j<health.size() and (health[j] is int or health[j] is float):hp=clampf(float(health[j]),0,maximum)
				var sprite=g._sprite("res://assets/props/crystal_space.png",q,0.17)
				sprite.modulate=Color(0.6,1,0.8,0.15) if hp<=0 else Color(0.88,0.75,1)
				d.targets.append({"origin":q,"p":q,"hp":hp,"max_hp":maximum,"sprite":sprite,"phase":j*2.1})
		elif kind=="escort":
			var destination=g.camp_positions[0]
			var best=INF
			for camp in g.camp_positions:
				var distance=p.distance_to(camp)
				if distance>300 and distance<best:best=distance;destination=camp
			d.cart_path=g.world.find_path(p,destination)
			if d.cart_path.size()>20:
				# A story escort is a short local encounter, not a slow cross-map walk.
				d.cart_path=d.cart_path.slice(0,mini(d.cart_path.size(),22))
			for j in range(1,d.cart_path.size()):d.cart_total+=d.cart_path[j-1].distance_to(d.cart_path[j])
			var cart=g._sprite("res://assets/props/supply_basket.png",p,0.24);d.cart=cart
		states.append(d)
	local_traps.setup(g,[])

func clear()->void:
	cancel()
	for d in states:
		for target in d.targets:
			if is_instance_valid(target.sprite):target.sprite.queue_free()
		if is_instance_valid(d.cart):d.cart.queue_free()
	states.clear();active_index=-1;clock=0.0

func snapshot()->Array:
	var result=[]
	for d in states:
		var health=[]
		for target in d.targets:health.append(target.hp)
		result.append({"targets":health})
	return result

func begin(index:int)->bool:
	var g=owner_ref.get_ref()
	if index<0 or index>=states.size() or g.objective_done[index]:return false
	var d=states[index]
	if not d.kind in ["course","escort","seal"]:return false
	if active_index>=0 and active_index!=index:g.ui.toast("先完成当前闯关，或到营地休息后重新开始");return false
	if active_index==index and d.active:
		g.ui.toast("当前试炼仍在进行 · 继续穿过旗门，或靠近粮车引导")
		return false
	if d.kind=="seal":g.ui.toast("直接攻击三颗紫色封印核心，远程星矢也能命中");return true
	if (d.kind=="course" and d.route.is_empty()) or (d.kind=="escort" and d.cart_path.size()<2):
		g.ui.toast("暂时找不到安全路线，请回到营地后重试")
		return false
	# A retry starts one clean run; removed ambushes never pass through damage or
	# enemy-defeated callbacks and therefore cannot award cancellation resources.
	_cleanup_escort_enemies(index)
	_run_serial+=1
	d.active=true;d.failed=false;d.gate=0;d.time=d.limit;d.cart_index=0;d.cart_distance=0.0;d.ambush=0;active_index=index
	if d.kind=="course":
		var descriptors=[]
		if g.campaign.stage>0 and d.route.size()>=3:
			descriptors=[{"kind":"spikes","p":d.route[1],"phase":0.0},{"kind":"firejet","p":g.world.nearest_safe(d.route[2]+Vector2(-160,0)),"rotation":0.0,"phase":1.3}]
		local_traps.setup(g,descriptors)
		for trap in local_traps.traps:trap["hide_lever"]=true
		g.ui.toast("障碍冲刺开始！依次穿过四面旗门，观察地刺与喷焰")
	else:
		d.cart.position=d.p;g.ui.toast("护送开始：靠近粮车引导，清除拦路妖怪")
		_spawn_escort_ambush(d)
	return true

func cancel()->void:
	_run_serial+=1
	if active_index>=0:
		var d=states[active_index];d.active=false;d.failed=true;d.gate=0;d.time=0.0;d.cart_index=0;d.cart_distance=0.0;d.ambush=0
		if is_instance_valid(d.cart):d.cart.position=d.p
	active_index=-1
	_cleanup_escort_enemies()
	_clear_local_traps()

func _clear_local_traps()->void:
	# A lethal dart calls game._hurt()->cancel() from inside Traps._tick().
	# Defer mutating its arrays until that active iterator has returned.
	if _updating_local_traps:
		_clear_traps_pending=true
		return
	local_traps.traps.clear();local_traps.darts.clear();_clear_traps_pending=false

func _cleanup_escort_enemies(index:int=-1)->void:
	var g=owner_ref.get_ref() if owner_ref!=null else null
	if not g or g.get("enemy_director")==null:return
	var uids:Array=[]
	for uid in _escort_uids.keys():
		if index<0 or int(_escort_uids[uid])==index:uids.append(int(uid));_escort_uids.erase(uid)
	for i in range(g.enemy_director.enemies.size()-1,-1,-1):
		var enemy:Dictionary=g.enemy_director.enemies[i]
		if not enemy.has("main_escort") or (index>=0 and int(enemy.main_escort)!=index):continue
		var uid=int(enemy.get("uid",-1))
		if uid>=0 and not uid in uids:uids.append(uid)
		enemy.hp=0;enemy["notified"]=true;enemy["state"]="dead"
		if is_instance_valid(enemy.get("sprite")):enemy.sprite.queue_free()
		g.enemy_director.enemies.remove_at(i)
	for i in range(g.enemy_director.projectiles.size()-1,-1,-1):
		if int(g.enemy_director.projectiles[i].get("owner_uid",-2)) in uids:g.enemy_director.projectiles.remove_at(i)
	if g.has_method("_sync_enemies"):g._sync_enemies()

func update(delta:float)->void:
	var g=owner_ref.get_ref()
	if not g or not g.active or g.get_tree().paused:return
	clock+=delta
	for d in states:
		if g.objective_done[d.index]:continue
		if d.kind=="seal":
			var living=0
			for target in d.targets:
				if target.hp<=0:continue
				living+=1
				var offset=Vector2(cos(clock*0.9+target.phase)*14,sin(clock*1.1+target.phase)*10)
				var candidate:Vector2=target.origin+offset
				target.p=candidate if g.world.is_walkable(candidate,10) else target.origin
				target.sprite.position=target.p;target.sprite.z_index=int(target.p.y)
			if living==0:g._finish_objective(d.index)
	if active_index<0:return
	var d=states[active_index]
	if d.kind=="course":
		var index=active_index;var serial=_run_serial
		d.time-=delta
		_updating_local_traps=true;local_traps.update(delta);_updating_local_traps=false
		if _clear_traps_pending:_clear_local_traps()
		# Death can cancel this course, restore HP and relocate the player during
		# local_traps.update(). Never finish a stale gate or emit a timeout after it.
		if active_index!=index or serial!=_run_serial or not d.active or not g.active or g.get_tree().paused:return
		if d.time<=0:
			cancel();g.ui.toast("超时了，回旗门可立即重试；观察陷阱停歇再冲刺");return
		if d.gate<d.route.size() and g.player.position.distance_to(d.route[d.gate])<58:
			d.gate+=1;g._effect(g.player.position,Color("ffe6ad"),"ring",0.45,75)
			if d.gate>=d.route.size():d.active=false;active_index=-1;_clear_local_traps();g._finish_objective(d.index)
	elif d.kind=="escort":
		var blocked=false
		for e in g.enemies:
			if e.hp>0 and is_instance_valid(e.get("sprite")) and e.sprite.position.distance_to(d.cart.position)<300:blocked=true
		if blocked or g.player.position.distance_to(d.cart.position)>330:return
		while d.cart_index<d.cart_path.size() and d.cart.position.distance_to(d.cart_path[d.cart_index])<15:d.cart_index+=1
		if d.cart_index>=d.cart_path.size():
			if d.ambush<2:_spawn_escort_ambush(d);return
			d.active=false;active_index=-1;_cleanup_escort_enemies(d.index);g._finish_objective(d.index);return
		var previous:Vector2=d.cart.position
		var displacement:Vector2=(d.cart_path[d.cart_index]-previous).limit_length(maxf(0,125*delta))
		d.cart.position=g.world.move_actor(previous,displacement,14)
		d.cart_distance+=previous.distance_to(d.cart.position)
		d.cart.z_index=int(d.cart.position.y)
		if d.ambush<2 and d.cart_distance>=d.cart_total*.5:_spawn_escort_ambush(d)

func _spawn_escort_ambush(d:Dictionary)->void:
	var g=owner_ref.get_ref();d.ambush+=1
	for j in range(2):
		var p=g.world.nearest_safe(d.cart.position+Vector2(135+j*75,-100+j*70))
		var e=g.enemy_director.spawn("shadow_blob" if j==0 else "crystal_thief",p,false,-200-d.index)
		if e.is_empty():continue
		e["main_escort"]=d.index
		var uid=int(e.get("uid",-1))
		if uid>=0:_escort_uids[uid]=d.index
	if g.has_method("_sync_enemies"):g._sync_enemies()

func hit_cone(origin:Vector2,direction:Vector2,reach:float,damage:float,half_angle:float=0.8)->int:
	var g=owner_ref.get_ref();var count=0
	if not g or not g.active or g.get_tree().paused or damage<=0 or not is_finite(damage):return 0
	for d in states:
		if d.kind!="seal" or g.objective_done[d.index]:continue
		for target in d.targets:
			var offset:Vector2=target.p-origin
			if target.hp>0 and offset.length()<reach and (offset.length()<35 or absf(wrapf(offset.angle()-direction.angle(),-PI,PI))<=half_angle) and g.world.has_line_of_sight(origin,target.p):_damage_target(target,damage);count+=1
	return count

func hit_segment(a:Vector2,b:Vector2,damage:float)->bool:
	var g=owner_ref.get_ref()
	if not g or not g.active or g.get_tree().paused or damage<=0 or not is_finite(damage):return false
	var chosen:Dictionary={};var first=INF;var segment=b-a
	for d in states:
		if d.kind!="seal" or g.objective_done[d.index]:continue
		for target in d.targets:
			if target.hp<=0:continue
			var closest=Geometry2D.get_closest_point_to_segment(target.p,a,b)
			if closest.distance_to(target.p)>=38:continue
			var fraction=clampf((target.p-a).dot(segment)/maxf(0.00001,segment.length_squared()),0,1)
			if fraction<first and g.world.has_line_of_sight(a,closest):chosen=target;first=fraction
	if not chosen.is_empty():_damage_target(chosen,damage);return true
	return false

func _damage_target(target:Dictionary,amount:float)->void:
	var g=owner_ref.get_ref();target.hp=maxf(0,target.hp-amount)
	g._effect(target.p+Vector2(0,-35),Color("d6b4ff"),str(int(amount)),0.5,0)
	if target.hp<=0:target.sprite.modulate=Color(0.7,1,0.8,0.15);g._effect(target.p,Color("c7a6ff"),"burst",0.7,90)
	if g.has_method("_save_all"):g._save_all()

func active_label()->String:
	if active_index<0:return ""
	var d=states[active_index]
	return "障碍冲刺 %d / %d · 剩余 %.1f 秒"%[d.gate,d.route.size(),maxf(0,d.time)] if d.kind=="course" else "护送粮车 · 靠近引导，清除拦路妖怪"

func draw(canvas:Node2D,font:Font)->void:
	var g=owner_ref.get_ref()
	if not g:return
	local_traps.draw(canvas,font)
	for d in states:
		if g.objective_done[d.index]:continue
		if d.kind=="course" and d.active:
			for i in range(d.route.size()):
				var p:Vector2=d.route[i];var color=Color("a4d4ba") if i<d.gate else (Color("ffe4a0") if i==d.gate else Color("87a9b4"))
				canvas.draw_line(p+Vector2(-44,0),p+Vector2(-44,-95),Color("75664c"),5,true)
				canvas.draw_line(p+Vector2(44,0),p+Vector2(44,-95),Color("75664c"),5,true)
				canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-42,-94),p+Vector2(42,-94),p+Vector2(30,-73),p+Vector2(-30,-73)]),color)
				canvas.draw_string(font,p+Vector2(-8,-78),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("153d42"))
				if i==d.gate:canvas.draw_arc(p,55,0,TAU,40,color,2,true)
		if d.kind=="seal":
			for target in d.targets:
				if target.hp>0:
					canvas.draw_arc(target.p,35,0,TAU,32,Color("cbb3ed"),2,true)
					canvas.draw_rect(Rect2(target.p+Vector2(-24,-70),Vector2(48,4)),Color("253946"))
					canvas.draw_rect(Rect2(target.p+Vector2(-24,-70),Vector2(48*target.hp/target.max_hp,4)),Color("cb9df4"))
		if d.kind=="escort" and is_instance_valid(d.cart):
			var p:Vector2=d.cart.position
			for x in [-25,25]:canvas.draw_circle(p+Vector2(x,0),10,Color("493b2e"));canvas.draw_circle(p+Vector2(x,0),4,Color("a69773"))
			if d.active:
				canvas.draw_string(font,p+Vector2(-60,-90),"靠近护送 / 击退拦路妖怪",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("f4dca1"))
