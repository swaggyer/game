extends SceneTree
## Isolated, fixed-camera visual comparison and CPU draw submission benchmark.
const World=preload("res://scripts/open_world.gd")
const Visuals=preload("res://scripts/trap_visuals.gd")
var world:Node2D
var canvas:Node2D
var painter=Visuals.new()
var draw_us:Array=[]
var frames:Array=[]
var capture_label="after"
var region=0
var bench_traps=false
var descriptors:Array=[]
func _initialize()->void:call_deferred("run")
func paint()->void:
	var start=Time.get_ticks_usec()
	for iteration in range(25):
		for d in descriptors:painter.draw_trap(canvas,d,1.5,1.0)
	draw_us.append(float(Time.get_ticks_usec()-start)/25.0)
func run()->void:
	for method in ClassDB.class_get_method_list("CanvasItem"):
		if method.name=="draw_ellipse":print("ELLIPSE_API ",method)
	var args=OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--label="):capture_label=arg.trim_prefix("--label=")
		if arg.begins_with("--region="):region=int(arg.trim_prefix("--region="))
	bench_traps="--traps" in args
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	world=World.new();root.add_child(world);world.configure(region,1)
	var camera=Camera2D.new();root.add_child(camera);camera.position=Vector2(1750,1350);camera.zoom=Vector2.ONE*0.65
	canvas=Node2D.new();root.add_child(canvas);canvas.z_index=4000
	if bench_traps:
		canvas.draw.connect(paint)
		for i in range(6):
			var p=Vector2(1080+(i%3)*550,1040+int(i/3)*530)
			descriptors.append({"kind":["spikes","firejet","pendulum","shooter","whirlpool","collapse"][i],"p":p,"phase":0.0,"rotation":0.0,"state":"active","disabled":false,"timer":0.6,"lever":p+Vector2(-130,85),"previous_weight":p+Vector2(85,150)})
	for i in range(25):await process_frame
	world.set_process(false);world._landscape.set_process(false)
	var previous=Time.get_ticks_usec()
	for i in range(90):
		if bench_traps:canvas.queue_redraw()
		await process_frame
		var now=Time.get_ticks_usec();frames.append(float(now-previous));previous=now
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	if DisplayServer.get_name()!="headless":root.get_texture().get_image().save_png("res://docs/performance-v131-"+capture_label+"-region%d.png"%region)
	frames.sort();draw_us.sort()
	print("RENDER_BENCH ",JSON.stringify({"label":capture_label,"region":region,"backend":DisplayServer.get_name(),"median_frame_us":frames[frames.size()/2],"p95_frame_us":frames[int(frames.size()*0.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"trap_six_types_median_us":draw_us[draw_us.size()/2] if not draw_us.is_empty() else 0,"materials":world._landscape._materials.size()}))
	world.queue_free();canvas.queue_free();camera.queue_free();await process_frame;quit()
