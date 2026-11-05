extends SceneTree
const World=preload("res://scripts/open_world.gd")
const Landscape=preload("res://scripts/landscape_renderer.gd")
const AreaMap=preload("res://scripts/area_map.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)
func run()->void:
	var world=World.new();root.add_child(world)
	for chapter in range(7):
		world.configure(chapter,0)
		var landscape=world._landscape
		var reference=Landscape.DetailBatch.new()
		var tufts:Array=[]
		for i in range(0,world._tufts.size(),2):tufts.append(world._tufts[i])
		landscape._draw_details(reference,tufts,world._flowers,world._reeds,world._lilies)
		var vertices:=0;var indices:=0;var chunks:=0
		for node in landscape._details.get_children():
			check(node is MeshInstance2D,"retained scenery uses bounded meshes")
			if not str(node.name).begins_with("Wildflowers_"):continue
			chunks+=1
			var arrays=node.mesh.surface_get_arrays(0)
			vertices+=arrays[Mesh.ARRAY_VERTEX].size();indices+=arrays[Mesh.ARRAY_INDEX].size()
			var aabb:AABB=node.mesh.get_aabb()
			check(aabb.size.x<650 and aabb.size.y<650,"floral chunk permits camera culling")
		check(chunks>4 and chunks<50,"bounded scenery chunks instead of individual canvas primitives")
		check(vertices==reference.vertices.size(),"all original grass/flower/reed/lily vertices are preserved")
		check(indices==reference.indices.size(),"all original detail triangles are preserved")
		check(landscape._details.z_index==6 and landscape._rails.z_index==13,"water/path/detail/bridge depth order retained")
		for mat in landscape._materials:
			if mat.shader in [Landscape.MEADOW,Landscape.WATER,Landscape.SOIL,Landscape.DECK]:
				check(mat.get_shader_parameter("noise_lattice")==landscape._noise_lattice,"one shared noise texture, no duplicate material images")
		for mat in landscape._animated_materials:check(mat.shader in [Landscape.MEADOW,Landscape.WATER,Landscape.SOIL,Landscape.FOAM,Landscape.FOLIAGE],"only animated materials receive simulation-clock updates")
		var glints:=0;var stars:=0
		for i in range(80):
			if world._water_blocked(Vector2(190+fmod(i*631.0,3220),210+fmod(i*337.0,2220)),0):glints+=1
		if chapter==6:
			for i in range(70):
				if not world.is_walkable(Vector2(140+fmod(i*817.0,3320),150+fmod(i*313.0,2310)),0):stars+=1
		check(glints==world._water_glints.size() and stars==world._island_stars.size(),"precomputed ambient samples match original geometry tests")
		await process_frame
	var map=AreaMap.new();root.add_child(map);map.size=Vector2(220,175)
	var first=map._map_rect()
	check(first==map._map_rect(),"minimap fitting cache is stable")
	map.size=Vector2(790,400);map.expanded=true
	check(map._map_rect()!=first,"minimap fitting invalidates when expanded/resized")
	check(map._point(map.bounds.position).is_equal_approx(map._map_rect().position),"cached map coordinates stay aligned")
	for shader in [Landscape.MEADOW,Landscape.WATER,Landscape.SOIL,Landscape.DECK]:
		check(not shader.code.contains("sin(dot("),"per-fragment trigonometric noise hashes removed")
		check(shader.code.contains("texture(noise_lattice"),"noise uses shared baked lattice")
	world.queue_free();map.queue_free();await process_frame
	if not failures.is_empty():
		for failure in failures:printerr("FAIL: "+failure)
		quit(1)
	else:print("RENDER OPTIMIZATION TESTS PASSED: %d checks"%checks);quit(0)
