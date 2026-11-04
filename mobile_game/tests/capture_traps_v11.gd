extends SceneTree
## GPU contact sheet of the actual TrapDirector renderer at 1:1 scale.
const Traps=preload("res://scripts/trap_director.gd")
var director=Traps.new()
var game:CaptureOwner
var canvas:Node2D

class CaptureWorld extends Node2D:
	func is_walkable(_p:Vector2,_radius:float=20)->bool:return true
	func nearest_safe(p:Vector2)->Vector2:return p
	func has_line_of_sight(_a:Vector2,_b:Vector2)->bool:return true
	func move_actor(p:Vector2,m:Vector2,_radius:float=20)->Vector2:return p+m
class CaptureCampaign extends RefCounted:
	var difficulty="explorer"
class CaptureUI extends RefCounted:
	func toast(_text:String)->void:pass
class CaptureOwner extends Node2D:
	var world=CaptureWorld.new()
	var campaign=CaptureCampaign.new()
	var ui=CaptureUI.new()
	var player=Sprite2D.new()
	var active=true
	var invulnerable=0.0
	var spawn_position=Vector2(-1000,-1000)
	var camp_positions:Array=[]
	var last_safe_position=Vector2(875,755)
	func _hurt(_damage:float,_source:Vector2,_unblockable:bool=false)->void:invulnerable=100
	func _effect(_p:Vector2,_color:Color,_kind:String,_life:float,_radius:float)->void:pass

func _initialize()->void:call_deferred("run")

func run()->void:
	if DisplayServer.get_name()=="headless":
		printerr("Native GPU display is required for the trap contact sheet");quit(1);return
	root.size=Vector2i(1280,900);root.content_scale_size=Vector2i(1280,900)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	# Retain project antialiasing settings; GLES3 has no 2D MSAA support.
	game=CaptureOwner.new();root.add_child(game);game.add_child(game.world);game.add_child(game.player)
	game.player.position=game.last_safe_position
	var descriptors:Array=[]
	var positions:Array=[Vector2(285,165),Vector2(790,185),Vector2(285,365),Vector2(875,470),Vector2(285,745),Vector2(875,755)]
	var kinds:Array=["spikes","firejet","pendulum","shooter","whirlpool","collapse"]
	for i in range(6):descriptors.append({"kind":kinds[i],"p":positions[i],"rotation":-0.8 if i==2 else 0.0,"phase":0.0})
	director.setup(game,descriptors);director.clock=0;director.update(1.60)
	canvas=Node2D.new();root.add_child(canvas);canvas.draw.connect(paint)
	canvas.queue_redraw()
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var result:Error=image.save_png("res://docs/v11-traps-closeup.png")
	assert(result==OK)
	print("V1.1_TRAPS_GPU_CAPTURE_SAVED 1280x900 actual1:1 TrapDirector")
	canvas.queue_free();game.queue_free();await process_frame;await process_frame;call_deferred("quit",0)

func paint()->void:
	canvas.draw_rect(Rect2(0,0,1280,900),Color("344c42"))
	# Neutral stone test ground: no image substitution and no UI overlays.
	for row in range(18):
		for col in range(26):
			var p:Vector2=Vector2(col*51+(25 if row%2 else 0),row*51)
			var shade:float=sin(row*7.4+col*5.2)*0.016
			canvas.draw_rect(Rect2(p,Vector2(49,49)),Color(0.20+shade,0.30+shade,0.25+shade))
	director.draw(canvas,null)
