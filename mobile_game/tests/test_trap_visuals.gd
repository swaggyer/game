extends SceneTree
## Exercise all physical-material drawing paths, including extreme animation
## phases, without changing or advancing the actual hazard simulation.
const Visuals=preload("res://scripts/trap_visuals.gd")
var painter=Visuals.new()
var canvas:Node2D
var pass_index:int=0
var draw_count:int=0

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	canvas=Node2D.new();root.add_child(canvas);canvas.draw.connect(_paint)
	for i in range(12):
		pass_index=i;canvas.queue_redraw();await process_frame;await process_frame
	canvas.queue_free();await process_frame
	assert(draw_count>=12,"all trap material animation phases must draw")
	print("TRAP MATERIAL RENDER SMOKE PASSED: %d draw passes, 6 trap types, 4 states"%draw_count)
	call_deferred("quit",0)

func _paint() -> void:
	draw_count+=1
	for i in range(6):
		var p:Vector2=Vector2(220+(i%3)*440,180+int(i/3)*460)
		var state:String=["rest","warning","active","recover"][pass_index%4]
		var descriptor:Dictionary={"kind":["spikes","firejet","pendulum","shooter","whirlpool","collapse"][i],"p":p,"phase":0.0,"rotation":0.0,"state":state,"disabled":pass_index==11,"timer":0.6,"lever":p+Vector2(-130,85),"previous_weight":p+Vector2(85,150)}
		painter.draw_trap(canvas,descriptor,1.05+pass_index*0.071,1.0)
		painter.draw_arrow(canvas,{"p":p+Vector2(70,30),"v":Vector2(430,35)})
