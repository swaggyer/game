extends RefCounted
const TrapVisuals = preload("res://scripts/trap_visuals.gd")
var visuals = TrapVisuals.new()
## Six actual, timed hazards. Visual warnings and collision use the same geometry.
const NAMES = {"spikes":"星刺地板", "firejet":"间歇喷焰", "pendulum":"古钟摆锤", "shooter":"星矢机关", "whirlpool":"月潮漩涡", "collapse":"龟裂石板"}
var traps: Array = []
var darts: Array = []
var clock = -1.2
var owner_ref: WeakRef

func setup(game: Node2D, descriptors: Array, disabled: Array = []) -> void:
	owner_ref=weakref(game);traps.clear();darts.clear();clock=-1.2
	for i in range(descriptors.size()):
		var d=descriptors[i].duplicate(true)
		d["kind"]=str(d.get("kind","spikes"));d["p"]=d.get("p",Vector2.ZERO)
		d["rotation"]=float(d.get("rotation",0));d["phase"]=float(d.get("phase",i*0.8))
		d["disabled"]=i in disabled;d["index"]=i;d["last_cycle"]=-1
		d["state"]="rest";d["timer"]=0.0;d["triggered"]=false;d["previous_weight"]=d.p
		var lever=d.p+Vector2(-130,85)
		if not game.world.is_walkable(lever):lever=game.world.nearest_safe(lever)
		d["lever"]=lever;traps.append(d)

func disarm(index: int) -> bool:
	if index<0 or index>=traps.size() or traps[index].disabled:return false
	traps[index].disabled=true
	var g=owner_ref.get_ref()
	if g:
		g._effect(traps[index].p,Color(0.4,1,0.8),"ring",0.7,120)
		g.ui.toast(NAMES.get(traps[index].kind,"机关")+"已停止")
	return true

func disabled_indices() -> Array:
	var result=[]
	for d in traps:
		if d.disabled:result.append(int(d.index))
	return result

func nearby_lever(p: Vector2) -> int:
	var best=100.0;var result=-1
	for d in traps:
		var distance=p.distance_to(d.lever)
		if not d.disabled and distance<best:best=distance;result=d.index
	return result

func update(delta: float) -> void:
	var remaining=minf(delta,2.0)
	while remaining>0.00001:
		var step=minf(remaining,0.04);remaining-=step;_tick(step)

func _tick(delta:float) -> void:
	var g=owner_ref.get_ref()
	if not g or not g.active or g.get_tree().paused:return
	clock+=delta
	if clock<0:return
	var speed=0.84 if g.campaign.difficulty=="gentle" else (1.0 if g.campaign.difficulty=="explorer" else 1.12)
	for d in traps:
		if d.disabled:continue
		var t=clock*speed+d.phase
		match d.kind:
			"spikes":
				var phase=fmod(t,3.8)
				d.state="warning" if phase<1.05 else ("active" if phase<1.8 else "rest")
				if d.state=="active" and _in_spikes(g.player.position,d.p):_damage(g,16,d.p)
			"firejet":
				var phase=fmod(t,4.8)
				d.state="warning" if phase<1.4 else ("active" if phase<2.65 else "rest")
				if d.state=="active" and _in_cone(g.player.position,d.p,d.rotation,370,0.27) and g.world.has_line_of_sight(d.p,g.player.position):_damage(g,20,d.p)
			"pendulum":
				d.state="active"
				var angle=sin(t*1.65)*1.15+d.rotation+PI/2
				var q=d.p+Vector2.from_angle(angle)*175
				var old:Vector2=d.previous_weight
				if old!=d.p and Geometry2D.get_closest_point_to_segment(g.player.position,old,q).distance_to(g.player.position)<45:_damage(g,22,q)
				d.previous_weight=q
			"shooter":
				var phase=fmod(t,4.0);var cycle=int(t/4.0)
				d.state="warning" if phase<1.25 else ("active" if phase<1.55 else "rest")
				if d.state=="active" and d.last_cycle!=cycle:
					d.last_cycle=cycle
					for angle in [-0.13,0.0,0.13]:
						darts.append({"p":d.p,"v":Vector2.from_angle(d.rotation+angle)*430,"life":2.1,"source":d.p})
			"whirlpool":
				var phase=fmod(t,5.5)
				d.state="warning" if phase<1.5 else ("active" if phase<3.8 else "rest")
				var distance=g.player.position.distance_to(d.p)
				if d.state=="active" and distance<145 and g.invulnerable<=0:
					g.player.position=g.world.move_actor(g.player.position,g.player.position.direction_to(d.p)*75*delta)
					if distance<56:_damage(g,18,d.p)
			"collapse":
				var occupied=Rect2(d.p-Vector2(78,60),Vector2(156,120)).has_point(g.player.position)
				if d.state=="rest" and occupied:d.state="warning";d.timer=1.1
				if d.state in ["warning","active","recover"]:
					d.timer-=delta*speed
					if d.timer<=0:
						if d.state=="warning":d.state="active";d.timer=2.3
						elif d.state=="active":d.state="recover";d.timer=2.0
						else:d.state="rest"
				if d.state=="active" and occupied and g.invulnerable<=0:
					_damage(g,15,d.p);g.player.position=g.world.nearest_safe(g.last_safe_position)
					g.ui.toast("石板坍塌！裂纹出现后及时离开")
	for i in range(darts.size()-1,-1,-1):
		var d=darts[i];var old:Vector2=d.p;var next:Vector2=old+d.v*delta;d.life-=delta
		if d.life<=0 or not g.world.is_walkable(next,4) or not g.world.has_line_of_sight(old,next):darts.remove_at(i);continue
		d.p=next
		if Geometry2D.get_closest_point_to_segment(g.player.position,old,next).distance_to(g.player.position)<25:
			_damage(g,16,d.source);darts.remove_at(i)

func _damage(g: Node2D, amount: float, source: Vector2) -> void:
	if _safe_area(g.player.position,g):return
	g._hurt(amount,source,true)

func _safe_area(p: Vector2,g: Node2D) -> bool:
	if p.distance_to(g.spawn_position)<145:return true
	for camp in g.camp_positions:
		if p.distance_to(camp)<120:return true
	return false

func _in_spikes(p:Vector2,origin:Vector2) -> bool:
	return Rect2(origin-Vector2(95,75),Vector2(190,150)).grow(10).has_point(p)

func _in_cone(p:Vector2,origin:Vector2,rotation_value:float,length:float,half_angle:float) -> bool:
	var v=p-origin
	return v.length()<length and absf(wrapf(v.angle()-rotation_value,-PI,PI))<half_angle+0.08

func danger_at(p:Vector2) -> bool:
	for d in traps:
		if d.disabled or d.state!="active":continue
		match d.kind:
			"spikes":
				if _in_spikes(p,d.p):return true
			"firejet":
				if _in_cone(p,d.p,d.rotation,370,0.27):return true
			"pendulum":
				if p.distance_to(d.previous_weight)<55:return true
			"whirlpool":
				if p.distance_to(d.p)<145:return true
			"collapse":
				if Rect2(d.p-Vector2(78,60),Vector2(156,120)).has_point(p):return true
	return false

func draw(canvas: Node2D,font: Font) -> void:
	if owner_ref == null:return
	var g:Node2D=owner_ref.get_ref()
	if not g:return
	var speed:float=0.84 if g.campaign.difficulty=="gentle" else (1.0 if g.campaign.difficulty=="explorer" else 1.12)
	for d in traps:
		if d.p.distance_to(g.player.position)>1150:continue
		visuals.draw_trap(canvas,d,clock,speed)
		if font != null and g.player.position.distance_to(d.p)<400 and not d.disabled:
			var offset:Vector2=Vector2(-58,-137 if d.kind=="spikes" else -78)
			var text:String=("! " if d.state=="warning" else "")+str(NAMES.get(d.kind,"机关"))
			canvas.draw_string(font,d.p+offset+Vector2(1,2),text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(0.02,0.05,0.05,0.85))
			canvas.draw_string(font,d.p+offset,text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("d7c698") if d.state=="warning" else Color("c0d0c1"))
		if font != null and g.player.position.distance_to(d.lever)<240:
			var text:String="已关闭" if d.disabled else "拉杆"
			canvas.draw_string(font,d.lever+Vector2(-22,-70),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("9dd4b9") if d.disabled else Color("d2bd8e"))
	for d in darts:
		if d.p.distance_to(g.player.position)<1300:visuals.draw_arrow(canvas,d)
