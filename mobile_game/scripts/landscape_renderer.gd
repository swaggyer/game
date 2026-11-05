extends Node2D
## High-resolution canvas materials and smooth vector geography. No gameplay geometry.

const NOISE_PATH="res://assets/environment_v11/landscape_noise_v131.png"
const MEADOW=preload("res://shaders/meadow.gdshader")
const WATER=preload("res://shaders/water.gdshader")
const SOIL=preload("res://shaders/soil_path.gdshader")
const SHADOW=preload("res://shaders/soft_shadow.gdshader")
const FOAM=preload("res://shaders/shore_foam.gdshader")
const DECK=preload("res://shaders/bridge_deck.gdshader")
const FOLIAGE=preload("res://shaders/foliage.gdshader")
const THEMES=[
	{"shade":"#638448","sun":"#a6bd69","soil":"#b6a06d","earth":"#897247","water":"#267f92","shallows":"#81c5ac","air":"#5d7b49"},
	{"shade":"#365f49","sun":"#7c9f63","soil":"#9f9c72","earth":"#6e7450","water":"#226c7a","shallows":"#76b2a2","air":"#345b42"},
	{"shade":"#7f974e","sun":"#c0c97c","soil":"#c0ad78","earth":"#968150","water":"#3d92a0","shallows":"#9aceb3","air":"#829552"},
	{"shade":"#689b68","sun":"#b6c98b","soil":"#babc8f","earth":"#8a9369","water":"#2a8b9d","shallows":"#95d1b4","air":"#307d8d"},
	{"shade":"#738363","sun":"#b7bd8e","soil":"#bab699","earth":"#8a8970","water":"#447f8a","shallows":"#9dbfb0","air":"#6e7b63"},
	{"shade":"#556555","sun":"#979b71","soil":"#a39b89","earth":"#767465","water":"#665b84","shallows":"#a9a3bf","air":"#4d5660"},
	{"shade":"#6d9a8e","sun":"#bdd1a1","soil":"#d0cba4","earth":"#9aa483","water":"#396885","shallows":"#9dc7bb","air":"#354e68"}
]
var _world_ref:WeakRef
var _theme:Dictionary
var _chapter:=0
var _materials:Array[ShaderMaterial]=[]
var _clock:=0.0
var _tick:=0.0
var _grass:ShaderMaterial
var _water_material:ShaderMaterial
var _path_material:ShaderMaterial
var _shadow_material:ShaderMaterial
var _foliage_material:ShaderMaterial
var _foam_material:ShaderMaterial
var _white:ImageTexture
var _noise_lattice:Texture2D
var _details:Node2D
var _rails:Node2D
var _land_geometry:Array=[]
var _water_geometry:Array=[]
var _bridges:Array=[]
var _flowers:Array=[]
var _tufts:Array=[]
var _reeds:Array=[]
var _lilies:Array=[]
var _cliffs:Array=[]
var _animated_materials:Array[ShaderMaterial]=[]
var detail_mesh_count:=0
var detail_triangle_count:=0

## Build colored triangles once. Canvas AA primitives otherwise require thousands
## of individual GLES draw calls, including flowers outside the camera view.
class DetailBatch:
	extends RefCounted
	var vertices:=PackedVector3Array()
	var colors:=PackedColorArray()
	var indices:=PackedInt32Array()
	var transform:=Transform2D.IDENTITY
	func vertex(p:Vector2,c:Color)->int:
		var index:=vertices.size();vertices.append(Vector3(p.x,p.y,0));colors.append(c);return index
	func triangle(a:Vector2,b:Vector2,c:Vector2,color:Color)->void:
		var base:=vertices.size();vertex(a,color);vertex(b,color);vertex(c,color);indices.append_array(PackedInt32Array([base,base+1,base+2]))
	func draw_set_transform(p:Vector2,rotation:float=0,scale:Vector2=Vector2.ONE)->void:
		transform=Transform2D(rotation,scale,0,p)
	func draw_line(a:Vector2,b:Vector2,color:Color,width:float=1,antialiased:bool=false)->void:
		a=transform*a;b=transform*b
		if a.is_equal_approx(b):return
		var normal:Vector2=(b-a).orthogonal().normalized()
		var half:Vector2=normal*maxf(0.35,width*0.5)
		triangle(a-half,b-half,b+half,color);triangle(a-half,b+half,a+half,color)
		if antialiased:
			var clear:=Color(color,0);var fringe:=normal*0.8
			for side in [-1.0,1.0]:
				var x:Vector2=a+half*side;var y:Vector2=b+half*side;var base:=vertices.size()
				vertex(x,color);vertex(y,color);vertex(y+fringe*side,clear);vertex(x+fringe*side,clear)
				indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
	func draw_polyline(points:PackedVector2Array,color:Color,width:float=1,antialiased:bool=false)->void:
		for i in range(points.size()-1):draw_line(points[i],points[i+1],color,width,antialiased)
	func draw_circle(p:Vector2,radius:float,color:Color,filled:bool=true,width:float=-1,antialiased:bool=false)->void:
		if not filled:draw_arc(p,radius,0,TAU,32,color,width,antialiased);return
		var center:Vector2=transform*p
		var size:float=radius*maxf(transform.x.length(),transform.y.length())
		var count:=clampi(int(ceil(size*2.0)),12,64)
		var middle:=vertex(center,color)
		var clear:=Color(color,0)
		var inner:=PackedInt32Array();var outer:=PackedInt32Array()
		for i in range(count):
			var point:Vector2=transform*(p+Vector2.from_angle(i*TAU/count)*radius)
			inner.append(vertex(point,color))
			if antialiased:outer.append(vertex(point+(point-center).normalized()*0.8,clear))
		for i in range(count):
			var next:=(i+1)%count
			indices.append_array(PackedInt32Array([middle,inner[i],inner[next]]))
			if antialiased:indices.append_array(PackedInt32Array([inner[i],outer[i],outer[next],inner[i],outer[next],inner[next]]))
	func draw_arc(p:Vector2,radius:float,start:float,end:float,count:int,color:Color,width:float=1,antialiased:bool=false)->void:
		var points:=PackedVector2Array()
		for i in range(count):points.append(p+Vector2.from_angle(lerpf(start,end,float(i)/maxi(1,count-1)))*radius)
		draw_polyline(points,color,width,antialiased)
	func draw_colored_polygon(points:PackedVector2Array,color:Color)->void:
		var triangles:=Geometry2D.triangulate_polygon(points);var base:=vertices.size()
		for p:Vector2 in points:vertex(transform*p,color)
		for index in triangles:indices.append(base+index)
	func mesh()->ArrayMesh:
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
		var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return result


func configure(world:Node2D) -> void:
	_world_ref=weakref(world)
	_chapter=world.chapter
	_theme=THEMES[_chapter]
	_materials.clear();_animated_materials.clear()
	_land_geometry=world._land
	_water_geometry=world._water
	_bridges=world._bridges
	_flowers=world._flowers
	_tufts=world._tufts
	_reeds=world._reeds
	_lilies=world._lilies
	var white_image:=Image.create(2,2,false,Image.FORMAT_RGBA8)
	white_image.fill(Color.WHITE)
	_white=ImageTexture.create_from_image(white_image)
	var horizon:=Rect2(-3600,-2600,10800,7800)
	var background:=_polygon(PackedVector2Array([horizon.position,Vector2(horizon.end.x,horizon.position.y),horizon.end,Vector2(horizon.position.x,horizon.end.y)]),horizon,null,-30)
	background.color=Color(_theme.air).darkened(0.18)
	_grass=_material(MEADOW)
	_grass.set_shader_parameter("grass_shadow",Color(_theme.shade))
	_grass.set_shader_parameter("grass_sun",Color(_theme.sun))
	_grass.set_shader_parameter("cloud_strength",0.17 if _chapter!=1 else 0.25)
	_path_material=_material(SOIL)
	_path_material.set_shader_parameter("soil_shadow",Color(_theme.earth))
	_path_material.set_shader_parameter("soil_light",Color(_theme.soil))
	_path_water_parameters(world)
	_shadow_material=_material(SHADOW)
	_shadow_material.set_shader_parameter("shadow_color",Color(0.12,0.21,0.14,0.30 if _chapter!=1 else 0.34))
	_foliage_material=_material(FOLIAGE)
	_foam_material=_material(FOAM)
	# Grass continues beyond the invisible play bounds instead of sitting inside a board frame.
	if _land_geometry.is_empty():_polygon(_rounded_rect(world.WORLD_RECT.grow(400),100),world.WORLD_RECT.grow(400),_grass,-12)
	for i in range(_water_geometry.size()):
		if i>0 and not _land_geometry.is_empty():continue
		_add_water(_water_geometry[i],-10 if _land_geometry.is_empty() else -11)
	for land:Dictionary in _land_geometry:
		var bounds:=_shape_bounds(land)
		_polygon(_shape_points(land),bounds,_grass,-9)
		_shore(land,true,-8)
	if not _land_geometry.is_empty():
		for i in range(1,_water_geometry.size()):_add_water(_water_geometry[i],-7)
	for i in range(world._paths.size()):
		_build_path(world._paths[i],float(world._path_widths[i]),i)
	for bridge:Dictionary in _bridges:_build_bridge(bridge)
	for data:Dictionary in world._art_props:
		var height:float=data.height
		var tree:bool=str(data.id).begins_with("tree")
		_add_shadow(data.p,Vector2(height*(0.89 if tree else 0.57),height*(0.35 if tree else 0.22)),Vector2(height*0.19,6))
	for data:Dictionary in world._structures:
		_add_shadow(data.p,Vector2(data.size.x*1.12,data.size.y*0.92),Vector2(data.size.x*0.17,7))
	for data in world._shrubs:
		_add_shadow(data[0],Vector2(73,27)*float(data[1]),Vector2(8,4))
	for geometry:Dictionary in world._solids:
		if geometry.shape=="polygon":_cliffs.append(geometry.points)
	_details=Node2D.new()
	_details.name="PaintedGrassAndWildflowers"
	_details.z_index=6
	
	add_child(_details)
	_rails=Node2D.new()
	_rails.name="BridgeJoineryAndStoneCoping"
	_rails.z_index=13
	
	add_child(_rails)
	_build_batched_details()
	var rail_batch:=DetailBatch.new();_draw_bridge_details(rail_batch);_commit_batch(rail_batch,_rails,"BatchedBridgeJoinery")
	queue_redraw()

func _material(shader:Shader) -> ShaderMaterial:
	var result:=ShaderMaterial.new()
	result.shader=shader
	if shader in [MEADOW,WATER,SOIL,DECK]:
		# Direct image fallback also lets isolated headless tests run before editor import.
		if not _noise_lattice:
			if ResourceLoader.exists(NOISE_PATH):_noise_lattice=load(NOISE_PATH)
			else:_noise_lattice=ImageTexture.create_from_image(Image.load_from_file(NOISE_PATH))
		result.set_shader_parameter("noise_lattice",_noise_lattice)
	_materials.append(result)
	if shader in [MEADOW,WATER,SOIL,FOAM,FOLIAGE]:_animated_materials.append(result)
	return result

func foliage_material() -> ShaderMaterial:
	return _foliage_material

func _process(delta:float) -> void:
	_clock+=delta;_tick+=delta
	if _tick<0.066:return
	_tick=0
	for mat:ShaderMaterial in _animated_materials:mat.set_shader_parameter("clock",_clock)

func _draw() -> void:
	pass

func _polygon(points:PackedVector2Array,bounds:Rect2,mat:Material,depth:int) -> Polygon2D:
	var poly:=Polygon2D.new()
	poly.name="SmoothLandscapeSurface"
	poly.polygon=points
	var uv:=PackedVector2Array()
	# Polygon2D UVs are texture pixels, unlike shader UVs. Our white texture is 2x2.
	for p:Vector2 in points:uv.append((p-bounds.position)/bounds.size*2.0)
	poly.uv=uv
	poly.texture=_white
	poly.color=Color.WHITE
	poly.antialiased=true
	poly.material=mat
	poly.z_index=depth
	add_child(poly)
	return poly

func _shape_bounds(shape:Dictionary) -> Rect2:
	if shape.shape=="rect":return shape.rect
	if shape.shape=="ellipse":return Rect2(shape.p-shape.radius,shape.radius*2)
	var points:PackedVector2Array=shape.points
	var r:=Rect2(points[0],Vector2.ZERO)
	for p:Vector2 in points:r=r.expand(p)
	return r

func _shape_points(shape:Dictionary) -> PackedVector2Array:
	if shape.shape=="rect":return _rounded_rect(shape.rect,13)
	if shape.shape=="polygon":return shape.points
	var points:=PackedVector2Array()
	for i in range(144):
		var a:=i*TAU/144
		points.append(shape.p+Vector2(cos(a),sin(a))*shape.radius)
	return points

func _rounded_rect(r:Rect2,radius:float) -> PackedVector2Array:
	var points:=PackedVector2Array()
	var centers:=[r.position+Vector2(radius,radius),Vector2(r.end.x-radius,r.position.y+radius),r.end-Vector2(radius,radius),Vector2(r.position.x+radius,r.end.y-radius)]
	for corner in range(4):
		for i in range(13):
			var angle:float=-PI+corner*PI/2+i*PI/24
			points.append(centers[corner]+Vector2.from_angle(angle)*radius)
	return points

func _add_water(shape:Dictionary,depth:int) -> void:
	var visual:Dictionary=shape.duplicate()
	# The ocean continues past the camera limits; the walkable islets remain exact.
	if not _land_geometry.is_empty() and shape.shape=="rect":visual.rect=(shape.rect as Rect2).grow(420)
	var mat:=_material(WATER)
	mat.set_shader_parameter("deep_color",Color(_theme.water))
	mat.set_shader_parameter("shallow_color",Color(_theme.shallows))
	mat.set_shader_parameter("foam_color",Color("#e6f0d4"))
	mat.set_shader_parameter("shape_kind",0 if shape.shape=="ellipse" else (1 if shape.shape=="rect" else 2))
	mat.set_shader_parameter("shape_size",_shape_bounds(visual).size)
	mat.set_shader_parameter("magical",1.0 if _chapter in [5,6] else 0.0)
	_polygon(_shape_points(visual),_shape_bounds(visual),mat,depth)
	if _land_geometry.is_empty() or shape.shape!="rect":_shore(shape,false,depth+1)

func _shore(shape:Dictionary,is_island:bool,depth:int) -> void:
	var points:=_shape_points(shape)
	var bank:=Line2D.new()
	bank.points=points;bank.closed=true
	bank.width=21 if is_island else 16
	bank.default_color=Color(_theme.earth).lightened(0.04)
	bank.antialiased=true;bank.joint_mode=Line2D.LINE_JOINT_ROUND;bank.round_precision=12
	bank.z_index=depth
	add_child(bank)
	var sand:=Line2D.new()
	sand.points=points;sand.closed=true;sand.width=6
	sand.default_color=Color(_theme.soil).lightened(0.13)
	sand.antialiased=true;sand.z_index=depth+1
	add_child(sand)
	var foam:=Line2D.new()
	foam.points=points;foam.closed=true;foam.width=3.2
	foam.default_color=Color(0.90,0.97,0.85,0.66)
	foam.antialiased=true;foam.z_index=depth+2;foam.material=_foam_material
	add_child(foam)

func _curved(points:PackedVector2Array) -> PackedVector2Array:
	var current:=points.duplicate()
	for iteration in range(2):
		var result:=PackedVector2Array()
		result.append(current[0])
		for i in range(current.size()-1):
			result.append(current[i].lerp(current[i+1],0.25))
			result.append(current[i].lerp(current[i+1],0.75))
		result.append(current[current.size()-1])
		current=result
	return current

func _path_water_parameters(world:Node2D) -> void:
	var waters:=PackedVector4Array()
	var kinds:=PackedFloat32Array()
	var lands:=PackedVector4Array()
	var bridges:=PackedVector4Array()
	var polygon:=PackedVector2Array()
	for shape:Dictionary in world._water:
		if shape.shape=="polygon":polygon=(shape.points as PackedVector2Array).duplicate();continue
		if shape.shape=="ellipse":waters.append(Vector4(shape.p.x,shape.p.y,shape.radius.x,shape.radius.y));kinds.append(0)
		else:
			var r:Rect2=shape.rect
			waters.append(Vector4(r.get_center().x,r.get_center().y,r.size.x/2,r.size.y/2));kinds.append(1)
	for shape:Dictionary in world._land:lands.append(Vector4(shape.p.x,shape.p.y,shape.radius.x,shape.radius.y))
	for data:Dictionary in world._bridges:
		var r:Rect2=data.rect
		bridges.append(Vector4(r.get_center().x,r.get_center().y,r.size.x/2,r.size.y/2))
	_path_material.set_shader_parameter("water_count",waters.size())
	_path_material.set_shader_parameter("land_count",lands.size())
	_path_material.set_shader_parameter("bridge_count",bridges.size())
	_path_material.set_shader_parameter("polygon_count",polygon.size())
	while waters.size()<4:waters.append(Vector4.ZERO);kinds.append(0)
	while lands.size()<6:lands.append(Vector4.ZERO)
	while bridges.size()<8:bridges.append(Vector4.ZERO)
	while polygon.size()<16:polygon.append(Vector2.ZERO)
	_path_material.set_shader_parameter("water_shapes",waters)
	_path_material.set_shader_parameter("water_kinds",kinds)
	_path_material.set_shader_parameter("land_shapes",lands)
	_path_material.set_shader_parameter("bridge_shapes",bridges)
	_path_material.set_shader_parameter("water_polygon",polygon)

func _build_path(points:PackedVector2Array,width:float,index:int) -> void:
	var world:Node2D=_world_ref.get_ref()
	var smooth:=_curved(points)
	var runs:Array=[]
	var run:=PackedVector2Array()
	for i in range(smooth.size()-1):
		var length:=smooth[i].distance_to(smooth[i+1])
		var steps:=maxi(1,int(ceil(length/24.0)))
		for j in range(steps):
			var p:=smooth[i].lerp(smooth[i+1],float(j)/steps)
			if world.is_walkable(p,4):run.append(p)
			else:
				if run.size()>1:runs.append(run)
				run=PackedVector2Array()
	if world.is_walkable(smooth[smooth.size()-1],4):run.append(smooth[smooth.size()-1])
	if run.size()>1:runs.append(run)
	for path:PackedVector2Array in runs:
		var edge:=Line2D.new()
		edge.points=path;edge.width=width*1.15
		edge.texture=_white;edge.texture_mode=Line2D.LINE_TEXTURE_STRETCH
		edge.material=_path_material
		edge.default_color=Color(1,1,1,0.25)
		edge.antialiased=true;edge.joint_mode=Line2D.LINE_JOINT_ROUND
		edge.begin_cap_mode=Line2D.LINE_CAP_ROUND;edge.end_cap_mode=Line2D.LINE_CAP_ROUND
		edge.round_precision=12;edge.z_index=-1
		add_child(edge)
		var road:=Line2D.new()
		road.points=path;road.width=width*0.94
		road.texture=_white;road.texture_mode=Line2D.LINE_TEXTURE_STRETCH
		road.material=_path_material;road.antialiased=true
		road.joint_mode=Line2D.LINE_JOINT_ROUND
		road.begin_cap_mode=Line2D.LINE_CAP_ROUND;road.end_cap_mode=Line2D.LINE_CAP_ROUND
		road.round_precision=12;road.z_index=0
		var profile:=Curve.new()
		for n in range(7):profile.add_point(Vector2(n/6.0,0.92+sin(n*2.2+index)*0.08))
		road.width_curve=profile
		add_child(road)

func _add_shadow(p:Vector2,size:Vector2,offset:Vector2) -> void:
	var rect:=Rect2(p+offset-size*0.5,size)
	_polygon(PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]),rect,_shadow_material,5)

func _build_bridge(bridge:Dictionary) -> void:
	var r:Rect2=bridge.rect
	_add_shadow(r.get_center(),r.size+Vector2(28,40),Vector2(11,13))
	var mat:=_material(DECK)
	mat.set_shader_parameter("wooden",bridge.style=="wood")
	mat.set_shader_parameter("horizontal",r.size.x>r.size.y)
	mat.set_shader_parameter("deck_size",r.size)
	_polygon(_rounded_rect(r,5),r,mat,10)

func _draw_details(canvas:Object,tufts:Array,flowers:Array,reeds:Array,lilies:Array) -> void:
	var green:=Color(_theme.shade).lightened(0.07)
	for tuft:Array in tufts:
		var p:Vector2=tuft[0]
		var h:float=tuft[1]*1.2
		var light:=Color(_theme.sun).lightened(0.04)
		for n in range(3):
			var bend:float=(n-1)*3.1
			var points:=PackedVector2Array([p+Vector2(n*2.1,1),p+Vector2(n*2.1+bend*0.35,-h*0.6),p+Vector2(n*2.1+bend,-h)])
			canvas.draw_polyline(points,green.lerp(light,float(n)*0.24),1.15,true)
	for data:Array in flowers:
		var p:Vector2=data[0]
		var size_value:float=data[1]
		for n in range(int(data[2])):
			var q:=p+Vector2(cos(n*2.399)*n*4.3,sin(n*2.399)*n*2.2)*size_value
			canvas.draw_line(q+Vector2(0,4),q+Vector2(1,-5)*size_value,green,1.0,true)
			var petal:=Color("#f5e9bd") if n%3!=0 else Color("#e7ce9c")
			if _chapter==3:petal=Color("#e3b4cc") if n%2 else Color("#f0e3d2")
			for j in range(5):canvas.draw_circle(q+Vector2.from_angle(j*TAU/5)*2.8*size_value,2.2*size_value,petal,true,-1,true)
			canvas.draw_circle(q,1.1*size_value,Color("#c39847"),true,-1,true)
	for p:Vector2 in reeds:
		for n in range(4):
			var q:=p+Vector2(n*3.5,0)
			canvas.draw_polyline(PackedVector2Array([q,q+Vector2(-2,-15-n*2),q+Vector2(1+n,-21-n*2)]),green.lightened(n*0.04),1.4,true)
	for p:Vector2 in lilies:
		_ellipse(canvas,p,Vector2(13,6),Color("#729f71"))
		canvas.draw_line(p,p+Vector2(10,-4),Color(_theme.water),1,true)
		if _chapter==3:
			for n in range(5):canvas.draw_circle(p+Vector2.from_angle(n*TAU/5)*2,2.4,Color("#efcad8"),true,-1,true)

func _commit_batch(batch:DetailBatch,parent:Node2D,label:String)->void:
	if batch.indices.is_empty():return
	var node:=MeshInstance2D.new();node.name=label;node.mesh=batch.mesh();parent.add_child(node)
	detail_mesh_count+=1;detail_triangle_count+=batch.indices.size()/3

func _build_batched_details()->void:
	var chunks:Dictionary={}
	var groups:Array=[[],_flowers,_reeds,_lilies]
	for i in range(0,_tufts.size(),2):groups[0].append(_tufts[i])
	for kind in range(4):
		for entry in groups[kind]:
			var p:Vector2=entry[0] if kind<2 else entry
			var cell:=Vector2i(floori(p.x/512),floori(p.y/512))
			if not chunks.has(cell):chunks[cell]=[[],[],[],[]]
			chunks[cell][kind].append(entry)
	for cell:Vector2i in chunks:
		var data:Array=chunks[cell];var batch:=DetailBatch.new()
		_draw_details(batch,data[0],data[1],data[2],data[3])
		_commit_batch(batch,_details,"Wildflowers_%d_%d"%[cell.x,cell.y])
	var landmarks:=DetailBatch.new()
	for points:PackedVector2Array in _cliffs:_draw_cliff(landmarks,points)
	if _chapter==2:
		for p in [Vector2(790,1660),Vector2(1120,970),Vector2(2820,950),Vector2(2030,2300),Vector2(2900,1770)]:_draw_wheat(landmarks,p)
	if _chapter==0:_draw_garden(landmarks)
	if _chapter==6:
		for n in range(12):
			var angle:=n*TAU/12
			var p:=Vector2(1800,1320)+Vector2(cos(angle)*890,sin(angle)*630)
			landmarks.draw_arc(p,20,0,TAU,48,Color(0.93,0.89,0.65,0.5),1.6,true)

	_commit_batch(landmarks,_details,"LandmarkGroundDetails")

func _ellipse(canvas:Object,p:Vector2,r:Vector2,c:Color) -> void:
	canvas.draw_set_transform(p,0,r)
	canvas.draw_circle(Vector2.ZERO,1,c,true,-1,true)
	canvas.draw_set_transform(Vector2.ZERO)

func _draw_cliff(canvas:Object,points:PackedVector2Array) -> void:
	var center:=Vector2.ZERO
	for p:Vector2 in points:center+=p
	center/=points.size()
	var color:=Color("#99987a")
	for layer in range(4,-1,-1):
		var contour:=PackedVector2Array()
		for p:Vector2 in points:contour.append(p.lerp(center,0.04*(4-layer))+Vector2(0,layer*7))
		canvas.draw_colored_polygon(contour,color.darkened(layer*0.065))
	for i in range(points.size()):
		var a:Vector2=points[i].lerp(center,0.17)
		var b:Vector2=points[(i+1)%points.size()].lerp(center,0.17)
		canvas.draw_line(a,b,color.lightened(0.12),2,true)
	for i in range(55):
		var p:=center+Vector2(sin(i*2.37)*194,cos(i*1.65)*225)
		if Geometry2D.is_point_in_polygon(p,points):
			canvas.draw_arc(p,7+i%4,PI*0.7,PI*1.8,12,color.darkened(0.10),1,true)

func _draw_wheat(canvas:Object,p:Vector2) -> void:
	for row in range(8):
		for col in range(17):
			var jitter:=sin(row*17.1+col*3.7)*3
			var q:=p+Vector2((col-8)*15+jitter,(row-3.5)*17)
			var h:=21.0+sin(col*1.7+row)*5
			canvas.draw_line(q,q+Vector2(3,-h),Color("#a3974e"),1.3,true)
			for n in range(3):
				var tip:=q+Vector2(3,-h+n*4)
				canvas.draw_line(tip,tip+Vector2(-3,-4),Color("#e3cc7a"),2.1,true)
				canvas.draw_line(tip,tip+Vector2(4,-3),Color("#eee09b"),1.8,true)

func _draw_garden(canvas:Object) -> void:
	for i in range(4):
		var p:=Vector2(470+i*90,1220+i%2*75)
		_ellipse(canvas,p,Vector2(36,45),Color("#75613f"))
		for j in range(4):
			var q:=p+Vector2(0,j*20-30)
			for n in range(4):
				var tip:=q+Vector2.from_angle(-PI*0.95+n*0.95)*14
				canvas.draw_line(q,tip,Color("#92ac5c"),5,true)
			canvas.draw_circle(q+Vector2(0,-3),4.0,Color("#bc8d4e"),true,-1,true)

func _draw_bridge_details(canvas:Object) -> void:
	for bridge:Dictionary in _bridges:
		var r:Rect2=bridge.rect
		var horizontal:=r.size.x>r.size.y
		var wood:bool=bridge.style=="wood"
		var dark:=Color("#65492c") if wood else Color("#758678")
		var lit:=Color("#b59458") if wood else Color("#c5cfb2")
		var lines:Array=[]
		if horizontal:lines=[[r.position+Vector2(0,3),r.position+Vector2(r.size.x,3)],[r.position+Vector2(0,r.size.y-4),r.end-Vector2(0,4)]]
		else:lines=[[r.position+Vector2(4,0),r.position+Vector2(4,r.size.y)],[r.position+Vector2(r.size.x-4,0),r.end-Vector2(4,0)]]
		for ends:Array in lines:
			canvas.draw_line(ends[0]+Vector2(0,3),ends[1]+Vector2(0,3),dark,11,true)
			canvas.draw_line(ends[0],ends[1],lit,7.5,true)
			canvas.draw_line(ends[0]+Vector2(-1,-2),ends[1]+Vector2(-1,-2),lit.lightened(0.16),1.5,true)
			var length:float=ends[0].distance_to(ends[1])
			var count:=maxi(1,int(length/90))
			for i in range(count+1):
				var p:Vector2=ends[0].lerp(ends[1],float(i)/count)
				canvas.draw_line(p+Vector2(1,4),p+Vector2(1,-13),dark,10,true)
				canvas.draw_line(p,p+Vector2(0,-14),lit,7,true)
				_ellipse(canvas,p+Vector2(0,-14),Vector2(5,2.8),lit.lightened(0.19))
