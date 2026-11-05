extends RefCounted
## Material-led trap art. Only draws; trap geometry and timing remain in the
## director. Every animation derives from that director's simulation clock.

var _unit_circle:=PackedVector2Array()
func _init()->void:
	for i in range(25):_unit_circle.append(Vector2.from_angle(i*TAU/24))

const STONE = Color("738174")
const IRON = Color("45565a")
const BRASS = Color("ac8750")
const LIGHT = Color("d1d5bc")
const SHADOW = Color(0.015,0.035,0.035,0.36)

func draw_trap(c:Node2D,d:Dictionary,time:float,speed:float) -> void:
	var t:float=maxf(0,time*speed+float(d.phase))
	c.draw_set_transform(d.p)
	match str(d.kind):
		"spikes":_spikes(c,d,t,time)
		"firejet":
			c.draw_set_transform(d.p,d.rotation);_firejet(c,d,t,time)
		"pendulum":_pendulum(c,d,time)
		"shooter":
			c.draw_set_transform(d.p,d.rotation);_shooter(c,d,t,time)
		"whirlpool":_whirlpool(c,d,t,time)
		"collapse":_collapse(c,d,time)
	c.draw_set_transform(Vector2.ZERO)
	if not d.get("hide_lever",false):_lever(c,d)

func draw_arrow(c:Node2D,d:Dictionary) -> void:
	var direction:Vector2=d.v.normalized()
	var normal:Vector2=direction.orthogonal()
	var p:Vector2=d.p
	c.draw_line(p-direction*35+Vector2(3,5),p+Vector2(3,5),SHADOW,4,true)
	c.draw_line(p-direction*46,p-direction*15,Color(0.79,0.78,0.59,0.16),2,true)
	c.draw_line(p-direction*31,p,Color("4d3e31"),4,true)
	c.draw_line(p-direction*31,p,Color("d8bf91"),1.7,true)
	for sign_value in [-1.0,1.0]:
		var n:Vector2=normal*sign_value
		c.draw_colored_polygon(PackedVector2Array([p-direction*31,p-direction*21+n*8,p-direction*10+n*2,p-direction*23]),Color("b5c3b4") if sign_value<0 else Color("697f78"))
		c.draw_line(p-direction*28,p-direction*14+n*4,Color("e1d9b9"),0.8,true)
	var tip:Vector2=p+direction*10
	c.draw_colored_polygon(PackedVector2Array([tip,p-direction*7+normal*6,p-direction*2,p-direction*7-normal*6]),Color("556b6e"))
	c.draw_colored_polygon(PackedVector2Array([tip,p-direction*7-normal*6,p-direction*2]),Color("c7d3ce"))
	c.draw_line(p-direction*1,tip,Color("eff0d8"),1,true)

func _spikes(c:Node2D,d:Dictionary,t:float,time:float) -> void:
	_plinth(c,Vector2(105,85),STONE,9)
	_beveled_panel(c,Rect2(-96,-76,192,152),Color("38484a"),5)
	for x in [-88.0,88.0]:
		for y in [-67.0,67.0]:_bolt(c,Vector2(x,y),4.5)
	for row in range(3):
		c.draw_line(Vector2(-88,-53+row*43),Vector2(88,-53+row*43),Color(0.75,0.82,0.75,0.08),1,true)
	var extension:float=0.0
	if not d.disabled and time>=0:
		var phase:float=fposmod(t,3.8)
		if d.state=="active":extension=smoothstep(1.05,1.13,phase)*(1-smoothstep(1.71,1.8,phase))
		elif d.state=="warning":extension=0.05+0.025*sin(time*18)
	if d.state=="warning" and not d.disabled:_etched_corners(c,Vector2(99,79),Color(0.95,0.66,0.27,0.5+0.15*sin(time*12)))
	for row in range(3):
		for col in range(5):
			var q:Vector2=Vector2((col-2)*35,(row-1)*43)
			_ellipse(c,q+Vector2(0,3),Vector2(13,7),Color("1b292b"))
			_ellipse_outline(c,q,Vector2(12,6),Color("627573"),1.6)
			c.draw_arc(q,10,PI,TAU,16,Color("a7b0a1"),1.3,true)
			if extension>0.015:
				var height:float=46*extension
				_ellipse(c,q+Vector2(6+height*0.16,5),Vector2(9+height*0.15,5),Color(0.015,0.035,0.04,0.38))
				var tip:Vector2=q+Vector2(0,-height)
				c.draw_colored_polygon(PackedVector2Array([q+Vector2(-9,4),tip,q+Vector2(9,4),q+Vector2(0,8)]),Color("5c7072"))
				c.draw_colored_polygon(PackedVector2Array([q+Vector2(-9,4),tip,q+Vector2(-1,5)]),Color("c1ccbf"))
				c.draw_colored_polygon(PackedVector2Array([q+Vector2(-1,5),tip,q+Vector2(9,4)]),Color("71868a"))
				c.draw_line(tip,q+Vector2(-1,4),Color("e4e9d5"),1.2,true)
			elif d.state=="warning" and not d.disabled:
				_ellipse(c,q,Vector2(6,3),Color(1,0.48,0.14,0.18+sin(time*10)*0.07))
	_moss(c,Vector2(-103,-64),1.0);_moss(c,Vector2(91,75),0.7)

func _firejet(c:Node2D,d:Dictionary,t:float,time:float) -> void:
	var active:bool=d.state=="active" and not d.disabled and time>=0
	var warning:bool=d.state=="warning" and not d.disabled and time>=0
	if active:
		for i in range(7):_ellipse(c,Vector2(183,7),Vector2(170-i*16,40-i*4),Color(1,0.40,0.08,0.017))
	_plinth(c,Vector2(51,39),Color("74776b"),10)
	for x in [-40.0,32.0]:
		for y in [-28.0,28.0]:_bolt(c,Vector2(x,y),4)
	# Copper barrel: dark lower face, brushed upper ridge and cast mounting bands.
	_beveled_panel(c,Rect2(-35,-20,77,40),Color("815e3c"),4)
	c.draw_rect(Rect2(-29,-16,65,13),Color("b38c54"))
	c.draw_rect(Rect2(-24,-13,58,4),Color("d2b37a"))
	c.draw_rect(Rect2(-28,8,63,8),Color("5e4634"))
	for x in [-23.0,25.0]:
		c.draw_rect(Rect2(x,-22,8,44),Color("4f5b52"))
		c.draw_line(Vector2(x+1,-21),Vector2(x+1,20),Color("a8b2a0"),1.8,true)
		_bolt(c,Vector2(x+4,-13),3)
	_ellipse(c,Vector2(42,1),Vector2(9,23),Color("3e3d32"))
	_ellipse(c,Vector2(44,0),Vector2(8,19),Color("d0a268"))
	_ellipse(c,Vector2(46,0),Vector2(5.8,15.5),Color("242a29"))
	_ellipse_outline(c,Vector2(44,0),Vector2(8,19),Color("eed3a0"),1.2)
	for y in [-7.0,0.0,7.0]:c.draw_line(Vector2(43,y),Vector2(48,y),Color("0f191c"),2,true)
	if warning:
		var charge:float=clampf(fposmod(t,4.8)/1.4,0,1)
		_flame_ribbon(c,time,46,75+charge*35,5+charge*8,Color(0.95,0.65,0.25,0.75),0.2)
		for sign_value in [-1.0,1.0]:
			var direction:Vector2=Vector2.from_angle(sign_value*0.35)
			for i in range(3):c.draw_line(direction*(125+i*75),direction*(150+i*75),Color(0.86,0.68,0.36,0.23),1.5,true)
	if active:
		_flame_ribbon(c,time,45,369,102,Color(0.92,0.22,0.055,0.16),0.7)
		_flame_ribbon(c,time+0.05,45,361,83,Color(1,0.40,0.06,0.72),0.4)
		_flame_ribbon(c,time+0.12,45,334,59,Color(1,0.68,0.16,0.90),0.2)
		_flame_ribbon(c,time+0.2,45,277,32,Color(1,0.87,0.45,0.94),0.1)
		_flame_ribbon(c,time+0.3,45,190,13,Color(1,0.97,0.79,0.98),0.0)
		for i in range(8):
			var age:float=fposmod(time*0.68+i*0.139,1)
			var smoke:Vector2=Vector2(300+age*104,sin(i*2.17+time*1.8)*(14+age*42))
			_ellipse(c,smoke,Vector2(13+age*19,7+age*10),Color(0.23,0.26,0.24,(1-age)*0.08))
			var ember:Vector2=Vector2(90+age*266,sin(i*3.4+time*8)*(9+age*43))
			c.draw_line(ember-Vector2(5,0),ember,Color(1,0.9,0.49,(1-age)*0.8),1.4,true)
	_moss(c,Vector2(-44,31),0.7)

func _flame_ribbon(c:Node2D,time:float,start:float,end:float,width:float,color:Color,wobble:float) -> void:
	var upper:PackedVector2Array=PackedVector2Array()
	var lower:PackedVector2Array=PackedVector2Array()
	for i in range(19):
		var f:float=float(i)/18
		var x:float=lerpf(start,end,f)
		var breadth:float=width*pow(maxf(0,sin(f*PI)),0.7)*(0.22+f*0.78)
		var ripple:float=sin(f*31-time*27)*breadth*0.12+sin(f*14+time*15)*wobble*4
		upper.append(Vector2(x,-breadth+ripple))
		lower.append(Vector2(x,breadth+ripple))
	var polygon:PackedVector2Array=upper
	for i in range(lower.size()-2,0,-1):polygon.append(lower[i])
	c.draw_colored_polygon(polygon,color)

func _pendulum(c:Node2D,d:Dictionary,time:float) -> void:
	var q:Vector2=d.previous_weight-d.p
	if time<0 or q.length()<50:q=Vector2(0,175)
	# Scuffed floor records the actual swept arc without a giant warning graphic.
	for i in range(12):
		var a:float=d.rotation+0.42+i*0.205
		c.draw_arc(Vector2.ZERO,175,a,a+0.08,5,Color(0.72,0.66,0.46,0.10),3,true)
	_plinth(c,Vector2(39,29),Color("6f7d70"),10)
	_ellipse(c,Vector2(0,-8),Vector2(23,19),Color("35474a"))
	_ellipse_outline(c,Vector2(0,-8),Vector2(22,18),Color("a38f60"),4)
	for a in range(6):_bolt(c,Vector2.from_angle(a*TAU/6)*18+Vector2(0,-8),3.2)
	var start:Vector2=Vector2(0,-10)
	var chain_end:Vector2=q+Vector2(0,-10)
	var angle:float=start.angle_to_point(chain_end)-PI/2
	c.draw_line(start+Vector2(4,6),chain_end+Vector2(4,6),SHADOW,6,true)
	var links:int=maxi(3,int(start.distance_to(chain_end)/10))
	for i in range(links):
		var p:Vector2=start.lerp(chain_end,float(i)/maxi(1,links-1))
		var radius:Vector2=Vector2(3.9 if i%2==0 else 2.4,6.6)
		_ellipse_outline(c,p,radius,Color("253338"),3.2,angle)
		_ellipse_outline(c,p+Vector2(-0.8,-0.8),radius,Color("9ba89c"),1.1,angle)
	_ellipse(c,q+Vector2(9,24),Vector2(47,16),Color(0.01,0.025,0.03,0.28))
	var ball:Vector2=q+Vector2(0,-8)
	for i in range(8):
		var a:float=i*TAU/8+0.2
		var outward:Vector2=Vector2.from_angle(a)
		var side:Vector2=outward.orthogonal()*6
		var base:Vector2=ball+outward*28
		var tip:Vector2=ball+outward*43
		c.draw_colored_polygon(PackedVector2Array([base-side,tip,base+side]),Color("46595e"))
		c.draw_colored_polygon(PackedVector2Array([base-side,tip,base]),Color("bdc9c1"))
	for i in range(17):
		var f:float=float(i)/16
		c.draw_circle(ball+Vector2(-7,-9)*f,32-f*17,Color("24363c").lerp(Color("a6b6ad"),f*0.82))
	_ellipse_outline(c,ball+Vector2(0,4),Vector2(30,12),Color("3c5258"),5)
	c.draw_arc(ball+Vector2(0,4),30,PI+0.25,TAU-0.2,20,Color(0.72,0.79,0.72,0.35),1.5,true)
	for offset in [Vector2(-23,0),Vector2(22,8)]:_bolt(c,ball+offset,3.3)
	_ellipse(c,ball+Vector2(-11,-15),Vector2(7,3.2),Color(0.94,0.98,0.87,0.5))
	_moss(c,Vector2(-31,24),0.7)

func _shooter(c:Node2D,d:Dictionary,t:float,time:float) -> void:
	_plinth(c,Vector2(45,35),Color("788574"),9)
	_ellipse(c,Vector2.ZERO,Vector2(31,25),Color("303e3d"))
	_ellipse_outline(c,Vector2.ZERO,Vector2(30,24),Color("9c8253"),3)
	_beveled_panel(c,Rect2(-37,-10,83,20),Color("80613d"),4)
	for y in [-5.0,0.0,5.0]:c.draw_line(Vector2(-32,y),Vector2(41,y+sin(y)*1.5),Color("b29664"),1,true)
	for x in [-22.0,28.0]:
		c.draw_rect(Rect2(x,-12,7,24),Color("425552"));c.draw_line(Vector2(x,-12),Vector2(x,11),Color("a8b5a2"),1.2,true)
	var top:PackedVector2Array=PackedVector2Array([Vector2(-5,-44),Vector2(11,-36),Vector2(20,-23),Vector2(25,-9),Vector2(25,9),Vector2(20,23),Vector2(11,36),Vector2(-5,44)])
	c.draw_polyline(top,Color("283c3e"),10,true)
	c.draw_polyline(top,Color("876c43"),6,true)
	c.draw_polyline(top,Color("c0a777"),2,true)
	var charge:float=clampf(fposmod(t,4.0)/1.25,0,1) if d.state=="warning" and not d.disabled else 0.0
	var draw_back:Vector2=Vector2(-12-charge*15,0)
	c.draw_polyline(PackedVector2Array([Vector2(-5,-44),draw_back,Vector2(-5,44)]),Color("e0d2a4"),1.3,true)
	_bolt(c,Vector2(22,0),5)
	c.draw_line(Vector2(-24,0),Vector2(53,0),Color("e4d4a7"),2.1,true)
	c.draw_colored_polygon(PackedVector2Array([Vector2(63,0),Vector2(50,-6),Vector2(53,0),Vector2(50,6)]),Color("bcc9bd"))
	for side in [-1.0,1.0]:c.draw_line(Vector2(-25,0),Vector2(-35,side*7),Color("b9c6b5"),3,true)
	if d.state=="warning" and not d.disabled and time>=0:
		for i in range(6):
			var x:float=120+i*85
			c.draw_line(Vector2(x-7,-3),Vector2(x+6,0),Color(0.92,0.72,0.36,0.24),1.2,true)
			c.draw_line(Vector2(x+6,0),Vector2(x-7,3),Color(0.92,0.72,0.36,0.24),1.2,true)
		_ellipse(c,Vector2(-20,-16),Vector2(4,3),Color(1,0.64,0.26,0.5+charge*0.35))
	_moss(c,Vector2(-37,29),0.6)

func _whirlpool(c:Node2D,d:Dictionary,_t:float,time:float) -> void:
	var active:bool=d.state=="active" and not d.disabled and time>=0
	var warning:bool=d.state=="warning" and not d.disabled and time>=0
	var speed:float=1.8 if active else (0.75 if warning else 0.22)
	if d.disabled:speed=0.08
	# Transparent outer water blends into the painted riverbed; depth darkens
	# continuously towards the funnel, rather than opaque concentric outlines.
	for i in range(22):
		var f:float=float(i)/21
		var color:Color=Color("45838b").lerp(Color("102e3c") if active else Color("24545e"),f)
		color.a=0.11+f*0.35
		c.draw_circle(Vector2.ZERO,146-f*130,color)
	for arm in range(3):
		var points:PackedVector2Array=PackedVector2Array()
		var foam:PackedVector2Array=PackedVector2Array()
		for i in range(43):
			var f:float=float(i)/42
			var radius:float=20+f*123
			var a:float=arm*TAU/3-f*TAU*1.38+time*speed
			var p:Vector2=Vector2.from_angle(a)*radius
			points.append(p)
			if i>21:foam.append(p+Vector2.from_angle(a+PI/2)*2)
		c.draw_polyline(points,Color(0.18,0.53,0.59,0.65 if active else 0.35),7 if active else 4,true)
		c.draw_polyline(points,Color(0.47,0.79,0.78,0.50 if active else 0.24),2,true)
		c.draw_polyline(foam,Color(0.83,0.94,0.83,0.68 if active else 0.34),2.2,true)
	for i in range(15):
		var f:float=fposmod(time*0.1+i*0.073,1)
		var a:float=i*2.39+time*speed*0.55
		var p:Vector2=Vector2.from_angle(a)*(37+f*105)
		var radius:float=1.5+f*2.2
		c.draw_arc(p,radius,0,TAU,12,Color(0.78,0.91,0.82,0.42),1,true)
		c.draw_circle(p+Vector2(-0.7,-0.9),0.9,Color(0.93,0.98,0.86,0.65))
	if active:
		c.draw_circle(Vector2.ZERO,15,Color(0.015,0.10,0.15,0.7))
		c.draw_arc(Vector2(0,-2),18,0.4,PI+0.1,24,Color(0.35,0.68,0.71,0.7),2,true)
	if warning:
		for i in range(4):c.draw_arc(Vector2.ZERO,145,i*PI/2+0.1,i*PI/2+0.28,6,Color(0.94,0.78,0.41,0.42),2,true)

func _collapse(c:Node2D,d:Dictionary,time:float) -> void:
	_plinth(c,Vector2(89,71),Color("718176"),9)
	var fallen:bool=d.state=="active" and not d.disabled
	var recovering:bool=d.state=="recover" and not d.disabled
	if fallen or recovering:
		_beveled_panel(c,Rect2(-78,-60,156,120),Color("11252b"),8)
		c.draw_colored_polygon(PackedVector2Array([Vector2(-78,-60),Vector2(78,-60),Vector2(65,-39),Vector2(-65,-39)]),Color("455e58"))
		c.draw_colored_polygon(PackedVector2Array([Vector2(-78,-60),Vector2(-65,-39),Vector2(-65,44),Vector2(-78,60)]),Color("344b48"))
		c.draw_colored_polygon(PackedVector2Array([Vector2(-78,60),Vector2(-65,44),Vector2(65,44),Vector2(78,60)]),Color("0c1b23"))
		for i in range(6):
			var p:Vector2=Vector2(-62+i*25,47+sin(i*2.1)*4)
			c.draw_colored_polygon(PackedVector2Array([p,p+Vector2(9,-10),p+Vector2(15,2)]),Color("52685f"))
	var tile_alpha:float=1.0
	var drop:float=0.0
	if fallen:
		var progress:float=clampf((2.3-float(d.timer))/0.45,0,1)
		tile_alpha=1-progress;drop=progress*29
	elif recovering:
		var progress:float=clampf(1-float(d.timer)/2.0,0,1)
		tile_alpha=progress;drop=(1-progress)*15
	if tile_alpha>0.015:
		for row in range(2):
			for col in range(3):
				var center:Vector2=Vector2(-51+col*51,-29+row*58+drop)
				var shake:float=sin(time*29+row+col)*1.2 if d.state=="warning" and not d.disabled else 0.0
				var rect:Rect2=Rect2(center+Vector2(-24.5+shake,-27),Vector2(49,54))
				var color:Color=Color("8a9684").darkened(float((row+col)%3)*0.035);color.a=tile_alpha
				_beveled_panel(c,rect,color,3)
				c.draw_line(rect.position+Vector2(6,12),rect.position+Vector2(32,9),Color(0.76,0.80,0.68,0.15*tile_alpha),1,true)
				if not d.disabled:
					var crack:PackedVector2Array=PackedVector2Array([center+Vector2(-17,-23),center+Vector2(-2,-7),center+Vector2(-9,4),center+Vector2(9,17),center+Vector2(5,27)])
					c.draw_polyline(crack,Color(0.10,0.19,0.18,tile_alpha),3 if d.state=="warning" else 1.3,true)
					c.draw_line(center+Vector2(-2,-7),center+Vector2(17,-13),Color(0.15,0.24,0.21,tile_alpha),1.3,true)
	if d.state=="warning" and not d.disabled:_etched_corners(c,Vector2(80,62),Color(0.9,0.64,0.29,0.55))
	_moss(c,Vector2(-83,42),0.8);_moss(c,Vector2(77,-60),0.6)

func _lever(c:Node2D,d:Dictionary) -> void:
	c.draw_set_transform(d.lever)
	_plinth(c,Vector2(25,19),Color("7b8978"),7)
	_beveled_panel(c,Rect2(-17,-18,34,25),Color("4c5c56"),3)
	for x in [-12.0,12.0]:_bolt(c,Vector2(x,1),3)
	c.draw_line(Vector2(-11,-6),Vector2(-11,-23),Color("645538"),5,true)
	c.draw_line(Vector2(10,-6),Vector2(10,-23),Color("a98b54"),5,true)
	var base:Vector2=Vector2(0,-17)
	var tip:Vector2=Vector2(-19,-37) if d.disabled else Vector2(13,-54)
	c.draw_line(base+Vector2(4,4),tip+Vector2(4,4),SHADOW,6,true)
	c.draw_line(base,tip,Color("574935"),6,true)
	c.draw_line(base+Vector2(-1,-1),tip+Vector2(-1,-1),Color("d0b276"),2.3,true)
	var side:Vector2=(tip-base).orthogonal().normalized()*10
	c.draw_line(tip-side,tip+side,Color("354f49"),8,true)
	c.draw_line(tip-side+Vector2(-1,-1),tip+side+Vector2(-1,-1),Color("86a99a"),2,true)
	_bolt(c,base,5.5)
	var indicator:Color=Color("8fd8ba") if d.disabled else Color("d6aa5e")
	_ellipse(c,Vector2(-12,-13),Vector2(4.3,3),Color("1c302c"))
	_ellipse(c,Vector2(-12,-14),Vector2(3,2),indicator)
	c.draw_set_transform(Vector2.ZERO)

func _plinth(c:Node2D,half:Vector2,color:Color,depth:float) -> void:
	_ellipse(c,Vector2(7,depth+half.y*0.32),Vector2(half.x+10,half.y*0.82),SHADOW)
	var top:PackedVector2Array=_chamfer(Rect2(-half,half*2),7)
	var low:PackedVector2Array=PackedVector2Array()
	for p in top:low.append(p+Vector2(0,depth))
	c.draw_colored_polygon(low,color.darkened(0.44))
	c.draw_colored_polygon(top,color)
	c.draw_line(Vector2(-half.x+7,-half.y),Vector2(half.x-7,-half.y),color.lightened(0.30),2,true)
	c.draw_line(Vector2(-half.x,-half.y+7),Vector2(-half.x,half.y-7),color.lightened(0.14),1.5,true)
	c.draw_line(Vector2(-half.x+7,half.y),Vector2(half.x-7,half.y),color.darkened(0.22),2,true)
	for i in range(8):
		var p:Vector2=Vector2(sin(i*8.13)*half.x*0.88,cos(i*4.27)*half.y*0.88)
		c.draw_line(p,p+Vector2(3+i%3,0.6),color.darkened(0.12),1,true)

func _beveled_panel(c:Node2D,rect:Rect2,color:Color,bevel:float) -> void:
	c.draw_colored_polygon(_chamfer(rect,bevel),color.darkened(0.30))
	var inner:Rect2=rect.grow(-bevel)
	c.draw_colored_polygon(_chamfer(inner,maxf(1,bevel*0.5)),color)
	c.draw_line(rect.position+Vector2(bevel,1),rect.position+Vector2(rect.size.x-bevel,1),color.lightened(0.34),1.5,true)
	c.draw_line(rect.position+Vector2(1,bevel),rect.position+Vector2(1,rect.size.y-bevel),color.lightened(0.18),1,true)
	c.draw_line(rect.position+Vector2(bevel,rect.size.y-1),rect.end-Vector2(bevel,1),color.darkened(0.36),1.5,true)

func _chamfer(r:Rect2,b:float) -> PackedVector2Array:
	return PackedVector2Array([r.position+Vector2(b,0),r.position+Vector2(r.size.x-b,0),r.position+Vector2(r.size.x,b),r.end-Vector2(0,b),r.end-Vector2(b,0),r.position+Vector2(b,r.size.y),r.position+Vector2(0,r.size.y-b),r.position+Vector2(0,b)])

func _bolt(c:Node2D,p:Vector2,radius:float) -> void:
	c.draw_circle(p+Vector2(1,1.8),radius+0.7,Color(0.02,0.04,0.035,0.45))
	var polygon:PackedVector2Array=PackedVector2Array()
	for i in range(6):polygon.append(p+Vector2.from_angle(i*TAU/6)*radius)
	c.draw_colored_polygon(polygon,Color("809084"))
	c.draw_arc(p,radius-0.6,PI,TAU,9,Color("d7dbbf"),1,true)
	c.draw_line(p-Vector2(radius*0.5,0),p+Vector2(radius*0.5,0),Color("35433e"),1.1,true)

func _etched_corners(c:Node2D,half:Vector2,color:Color) -> void:
	for x in [-1.0,1.0]:
		for y in [-1.0,1.0]:
			var p:Vector2=Vector2(half.x*x,half.y*y)
			c.draw_line(p,p-Vector2(x*15,0),color,1.4,true)
			c.draw_line(p,p-Vector2(0,y*13),color,1.4,true)

func _moss(c:Node2D,p:Vector2,size:float) -> void:
	for i in range(6):
		var q:Vector2=p+Vector2(sin(i*3.7)*12,cos(i*2.6)*5)*size
		_ellipse(c,q,Vector2(4+i%3,2.5)*size,Color("435d40").lightened(i*0.018))
		c.draw_line(q,q+Vector2(-2,-2)*size,Color("87996b"),1,true)

func _ellipse(c:Node2D,p:Vector2,radius:Vector2,color:Color) -> void:
	# Native ellipse preserves the current trap transform and builds its geometry
	# in C++; no24-element GDScript polygon or48trigonometric calls per oval.
	c.draw_ellipse(p,radius.x,radius.y,color,true,-1,false)

func _ellipse_outline(c:Node2D,p:Vector2,radius:Vector2,color:Color,width:float,rotation:float=0) -> void:
	var points:=PackedVector2Array()
	var basis:=Transform2D(rotation,Vector2.ZERO)
	for unit:Vector2 in _unit_circle:points.append(p+basis*(unit*radius))
	c.draw_polyline(points,color,width,true)
