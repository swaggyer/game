extends Control
## Vector terrain contours and soft exploration cloud, without a pixel grid.
var owner_ref:WeakRef
var expanded=false
var bounds=Rect2(100,100,3400,2400)
var font:Font
var overview:Dictionary={}
var marker_canvas:Control
var fog:ColorRect
var fog_texture:ImageTexture
var last_explored=-1
const LAND=Color("739d74")
const WATER=Color("488499")

func setup(game:Node2D,large:bool=false)->void:
	owner_ref=weakref(game);expanded=large;font=load("res://assets/ui.ttf")
	mouse_filter=Control.MOUSE_FILTER_IGNORE;texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	custom_minimum_size=Vector2(790,400) if expanded else Vector2(220,175)
	if not is_instance_valid(fog):
		fog=ColorRect.new();fog.mouse_filter=Control.MOUSE_FILTER_IGNORE;fog.z_index=0
		var effect=ShaderMaterial.new();effect.shader=load("res://scripts/map_fog.gdshader");fog.material=effect;add_child(fog)
		marker_canvas=Control.new();marker_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;marker_canvas.z_index=0;marker_canvas.draw.connect(_draw_markers);add_child(marker_canvas)
	rebuild();set_process(true)

func rebuild()->void:
	var g=owner_ref.get_ref()
	if not g:return
	bounds=g.world.WORLD_RECT;overview=g.world.get_overview();last_explored=-1
	_update_fog();queue_redraw()

func _process(_delta:float)->void:
	if not owner_ref or not owner_ref.get_ref():return
	_update_fog();marker_canvas.queue_redraw()
	var rect=_map_rect();fog.position=rect.position;fog.size=rect.size

func _update_fog()->void:
	var g=owner_ref.get_ref()
	if not g or g.explored.size()==last_explored:return
	last_explored=g.explored.size()
	var bitmap=Image.create(17,12,false,Image.FORMAT_RGBA8);bitmap.fill(Color.BLACK)
	for cell in g.explored:
		if cell>=0 and cell<204:bitmap.set_pixel(int(cell)%17,int(cell)/17,Color.WHITE)
	if fog_texture:fog_texture.update(bitmap)
	else:fog_texture=ImageTexture.create_from_image(bitmap)
	fog.material.set_shader_parameter("exploration",fog_texture)

func _map_rect()->Rect2:
	var available=Vector2(maxf(1,size.x-20),maxf(1,size.y-(58 if expanded else 50)))
	var fitted=bounds.size*minf(available.x/bounds.size.x,available.y/bounds.size.y)
	return Rect2(Vector2(10+(available.x-fitted.x)*0.5,30),fitted)

func _point(p:Vector2)->Vector2:
	var rect=_map_rect();return rect.position+(p-bounds.position)/bounds.size*rect.size

func _shape(shape:Dictionary,color:Color,outline:bool=false)->void:
	var vertices=PackedVector2Array()
	match str(shape.shape):
		"rect":
			var rect:Rect2=shape.rect
			for p in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:vertices.append(_point(p))
		"ellipse":
			for i in range(96):vertices.append(_point(shape.p+Vector2(cos(i*TAU/96),sin(i*TAU/96))*shape.radius))
		"polygon":
			for p in shape.points:vertices.append(_point(p))
	if vertices.size()<3:return
	draw_colored_polygon(vertices,color)
	if outline:
		vertices.append(vertices[0]);draw_polyline(vertices,color.lightened(0.22),1.4 if expanded else 0.8,true)

func _smooth_path(points:PackedVector2Array)->PackedVector2Array:
	var result=PackedVector2Array()
	for i in range(points.size()-1):
		var a=points[maxi(0,i-1)];var b=points[i];var c=points[i+1];var d=points[mini(points.size()-1,i+2)]
		for step in range(12):result.append(_point(b.cubic_interpolate(c,a,d,float(step)/12)))
	if not points.is_empty():result.append(_point(points[-1]))
	return result

func _draw()->void:
	if overview.is_empty():return
	var style=StyleBoxFlat.new();style.bg_color=Color("143b40ee");style.border_color=Color("cebd87");style.set_border_width_all(1);style.set_corner_radius_all(12)
	draw_style_box(style,Rect2(Vector2.ZERO,size));var rect=_map_rect()
	draw_rect(rect,LAND)
	var water:Array=overview.get("water_geometry",[]);var islands:Array=overview.get("land_cutouts",[])
	for shape in water:_shape(shape,WATER,true)
	for shape in islands:_shape(shape,LAND,true)
	if not islands.is_empty():
		for i in range(1,water.size()):_shape(water[i],WATER,true)
	for path in overview.get("paths",[]):
		var smooth=_smooth_path(path)
		if smooth.size()>1:draw_polyline(smooth,Color("d5cfaa"),3.2 if expanded else 1.35,true)
	for shape in overview.get("geometry",[]):_shape(shape,Color("69785f"),true)
	for bridge in overview.get("bridges",[]):
		var box:Rect2=bridge.rect;var a=_point(box.position);var b=_point(box.end)
		draw_style_box(_box(Color("dcc79c"),2),Rect2(a,b-a))
	draw_rect(rect,Color("d1c99d"),false,1.2)
	var g=owner_ref.get_ref()
	draw_string(font,Vector2(12,21),"区域地图 · "+str(g.stage_info.get("region","星灯岛")),HORIZONTAL_ALIGNMENT_LEFT,-1,19 if expanded else 14,Color("f0d49a"))
	draw_string(font,Vector2(10,size.y-10),"◆主线   ⚑挑战   ▰宝箱   ○营地   上北" if expanded else "轻点展开 · 自由探索",HORIZONTAL_ALIGNMENT_LEFT,-1,14 if expanded else 12,Color("bbd4bd"))

func _box(color:Color,radius:int)->StyleBoxFlat:
	var style=StyleBoxFlat.new();style.bg_color=color;style.set_corner_radius_all(radius);return style

func _draw_markers()->void:
	var g=owner_ref.get_ref() if owner_ref else null
	if not g:return
	var c=marker_canvas
	for i in range(g.points.size()):
		var p=_point(g.points[i]);var color=Color("a7e7c7") if g.objective_done[i] else Color("ffdda1")
		c.draw_circle(p,6 if expanded else 4,Color("274b45"));c.draw_circle(p,4.2 if expanded else 2.8,color)
		if expanded:c.draw_string(font,p+Vector2(8,3),("✓ " if g.objective_done[i] else "目标 ")+str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
	for challenge in g.challenge_director.challenges:
		var p=_point(challenge.p)
		var color=Color("6aa48d") if challenge.get("completed",false) else Color("86dcff")
		c.draw_line(p+Vector2(-3,5),p+Vector2(-3,-5),color,1.5,true)
		c.draw_colored_polygon(PackedVector2Array([p+Vector2(-2,-5),p+Vector2(5,-2),p+Vector2(-2,0)]),color)
		if expanded:c.draw_string(font,p+Vector2(8,3),("✓ " if challenge.get("completed",false) else "挑战 · ")+str(challenge.name),HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
	for i in range(g.chest_positions.size()):
		var p=_point(g.chest_positions[i])
		if g.is_discovered(g.chest_positions[i]):c.draw_style_box(_box(Color("648876") if i in g.claimed_chests else Color("e6b76e"),1),Rect2(p-Vector2(3.5,2.5),Vector2(7,5)))
	for p in g.camp_positions:c.draw_arc(_point(p),5,0,TAU,24,Color("c8f3d6"),1.5,true)
	c.draw_circle(_point(g.lamp_position),5,Color("fff0bf"))
	for enemy in g.enemies:
		if enemy.hp>0 and enemy.sprite.position.distance_to(g.player.position)<600:c.draw_circle(_point(enemy.sprite.position),3,Color("f39379"))
	var current=_point(g.player.position);c.draw_circle(current,7,Color(0.08,0.20,0.22,0.5))
	c.draw_colored_polygon(PackedVector2Array([current+Vector2.from_angle(g.facing.angle())*8,current+Vector2.from_angle(g.facing.angle()+2.5)*6,current+Vector2.from_angle(g.facing.angle()-2.5)*6]),Color("fff2c4"))
	if expanded:
		for zone in g.world.definition.get("zones",[]):c.draw_string(font,_point(zone.p)+Vector2(-35,-16),zone.name,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("e1edd0"))
