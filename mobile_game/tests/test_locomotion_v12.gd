extends SceneTree
## Real displacement, collision stop, independent actors, eight screen facings,
## pause invariance and retained source/frame integrity.
const Locomotion=preload("res://scripts/locomotion.gd")
var checks=0
var failures:Array=[]

func _initialize():call_deferred("run")

func check(value:bool,message:String):
	checks+=1
	if not value:failures.append(message);printerr("FAIL: "+message)

func run():
	var game=Node2D.new();root.add_child(game)
	var sprite=Sprite2D.new();game.add_child(sprite);sprite.scale=Vector2(.65,.65);sprite.modulate=Color(.8,.9,1,.7)
	var partner=Sprite2D.new();game.add_child(partner)
	var locomotion=Locomotion.new();locomotion.setup(game)
	locomotion.animate(sprite,"wangzai",Vector2.RIGHT,0,.016)
	check(not locomotion.debug_state(sprite).moving,"zero achieved movement shows grounded idle")
	var start_distance=locomotion.debug_state(sprite).distance
	var stride=float(locomotion.actor_info("wangzai").get("step_length_world",128))
	locomotion.animate(sprite,"wangzai",Vector2.RIGHT,stride/8,.016)
	check(locomotion.debug_state(sprite).frame==1,"one eighth actual stride advances one pose")
	check(locomotion.debug_state(sprite).direction=="right","rightward displacement uses actual right facing")
	var distance=locomotion.debug_state(sprite).distance
	locomotion.animate(sprite,"wangzai",Vector2.RIGHT,0,5)
	check(locomotion.debug_state(sprite).distance==distance and not locomotion.debug_state(sprite).moving,"five seconds against collision do not animate or slide")
	check(sprite.scale==Vector2(.65,.65) and sprite.modulate==Color(.8,.9,1,.7),"locomotion preserves caller scale and damage tint")
	for i in range(8):
		var direction=Vector2.from_angle(i*PI/4)
		locomotion.animate(sprite,"wangzai",direction,1,.016)
		check(locomotion.debug_state(sprite).direction==Locomotion.DIRECTION_NAMES[i],"eight-direction screen facing %d"%i)
	locomotion.animate(partner,"xiaomantou",Vector2.LEFT,10,.016)
	check(locomotion.debug_state(partner).distance==10 and locomotion.debug_state(sprite).distance!=10,"two sprites retain independent displacement phases")
	var before=locomotion.debug_state(sprite)
	paused=true
	locomotion.animate(sprite,"wangzai",Vector2.LEFT,20,1)
	check(locomotion.debug_state(sprite)==before,"paused tree cannot advance pose, facing or distance")
	paused=false
	locomotion.animate(sprite,"wangzai",Vector2.RIGHT,2000,.016)
	check(locomotion.debug_state(sprite).distance==before.distance,"teleport is not counted as walking")
	locomotion.animate(sprite,"xiaomantou",Vector2.DOWN,0,.016)
	check(locomotion.debug_state(sprite).actor=="xiaomantou" and locomotion.debug_state(sprite).distance==0,"character switch starts an independent idle phase")
	locomotion.reset(sprite)
	check(locomotion.debug_state(sprite).actor.is_empty(),"single sprite phase resets cleanly")
	var document=JSON.parse_string(FileAccess.get_file_as_string("res://assets/locomotion_v12/manifest.json"))
	for actor in ["wangzai","xiaomantou","little_dragon"]:
		var info:Dictionary=document.get("actors",{}).get(actor,{})
		check(info.get("source_unchanged",false),actor+" original 3D source hash unchanged")
		check(info.get("directions",{}).size()==8,actor+" has all eight directions")
		check(int(info.get("frames_per_direction",0))==8,actor+" has eight true 3D gait poses per direction")
		for direction in Locomotion.DIRECTION_NAMES:
			var files:Array=info.get("directions",{}).get(direction,[])
			check(files.size()==8,actor+" "+direction+" has complete cycle")
			var hashes:Dictionary={}
			for file in files:
				var path="res://assets/locomotion_v12/"+str(file)
				check(FileAccess.file_exists(path),str(file)+" exists")
				var bytes=FileAccess.get_file_as_bytes(path)
				var ctx=HashingContext.new();ctx.start(HashingContext.HASH_SHA256);ctx.update(bytes)
				var hash=ctx.finish().hex_encode();hashes[hash]=true
				check(hash==info.get("frame_sha256",{}).get(file,""),str(file)+" matches authored frame")
				var bounds:Array=info.get("alpha_bounds",{}).get(file,[])
				var canvas:Array=info.get("canvas",[0,0])
				check(bounds.size()==4 and bounds[0]>0 and bounds[1]>0 and bounds[2]<canvas[0] and bounds[3]<canvas[1],str(file)+" retains complete feet, antlers and a transparent border")
			check(hashes.size()==8,actor+" "+direction+" has eight distinct posed images")
			var idle=str(info.get("idle",{}).get(direction,""))
			check(not idle.is_empty() and FileAccess.file_exists("res://assets/locomotion_v12/"+idle),actor+" "+direction+" grounded idle exists")
		check(info.get("baseline",[]).size()==2 and int(info.baseline[1])==227,actor+" has stable shared floor anchor")
	locomotion=null;game.queue_free();await process_frame
	if failures.is_empty():print("LOCOMOTION V1.2 TESTS PASSED: %d checks"%checks)
	else:printerr("LOCOMOTION V1.2 TESTS FAILED: %d / %d"%[failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
