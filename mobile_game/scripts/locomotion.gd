extends RefCounted
## Locomotion is driven by displacement achieved after world collision.
## Time, requested input, stationary companions and paused worlds cannot step.

const DATA_PATH = "res://assets/locomotion_v12/manifest.json"
const DIRECTION_NAMES = ["right", "front_right", "front", "front_left", "left", "back_left", "back", "back_right"]

var game: Node2D
var actors: Dictionary = {}
var _states: Dictionary = {}
var _textures: Dictionary = {}

func setup(value: Node2D) -> void:
	game = value
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else {}
	actors = parsed.get("actors", {}) if parsed is Dictionary else {}
	# Decode/upload every finite animation frame during scene setup. Walking must
	# never perform its first disk read or texture upload in response to input.
	for actor: String in actors:
		var info: Dictionary = actors[actor]
		for frames: Array in info.get("directions", {}).values():
			for filename: String in frames:_texture("res://assets/locomotion_v12/"+filename)
		for filename: String in info.get("idle", {}).values():_texture("res://assets/locomotion_v12/"+filename)
		for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:_fallback(actor,direction)
	reset()

func reset(sprite: Sprite2D = null) -> void:
	if sprite == null:
		_states.clear()
	else:
		_states.erase(sprite.get_instance_id())

func actor_info(actor: String) -> Dictionary:
	return actors.get(actor, {}).duplicate(true)

func debug_state(sprite: Sprite2D) -> Dictionary:
	var state: Dictionary = _states.get(sprite.get_instance_id(), {})
	return {"actor":state.get("actor",""),"distance":state.get("distance",0.0),"frame":state.get("frame",0),"direction":state.get("direction","front"),"moving":state.get("moving",false)}

func animate(sprite: Sprite2D, actor: String, direction: Vector2, travelled: float, delta: float) -> void:
	if not is_instance_valid(sprite):
		return
	if sprite.is_inside_tree() and sprite.get_tree().paused:
		return
	var id = sprite.get_instance_id()
	if not _states.has(id) or _states[id].actor != actor:
		_states[id] = {"actor":actor,"distance":0.0,"frame":0,"direction":"front","moving":false,"ref":weakref(sprite)}
	var state: Dictionary = _states[id]
	if direction.length_squared() > 0.0025:
		state.direction = _direction_name(direction)
	var info: Dictionary = actors.get(actor,{})
	var count = maxi(1,int(info.get("frames_per_direction",8)))
	var stride = maxf(1.0,float(info.get("step_length_world",98 if actor=="little_dragon" else 128)))
	# Ignore invalid distance and teleports. Large relocation is not a footstep.
	var moved = maxf(0.0,travelled) if is_finite(travelled) else 0.0
	if moved > maxf(60.0,delta*480.0):
		moved = 0.0
	state.moving = moved > 0.001
	if state.moving:
		state.distance += moved
		state.frame = int(floor(fposmod(state.distance/stride,1.0)*count)) % count
	var filename = ""
	if state.moving:
		var frames: Array = info.get("directions",{}).get(state.direction,[])
		if not frames.is_empty():
			filename = str(frames[mini(state.frame,frames.size()-1)])
	else:
		filename = str(info.get("idle",{}).get(state.direction,""))
	var texture: Texture2D = null
	if not filename.is_empty():
		texture = _texture("res://assets/locomotion_v12/"+filename)
	var used_fallback = texture == null
	if used_fallback:
		texture = _fallback(actor,direction)
	if texture != null:
		if sprite.texture != texture:
			sprite.texture = texture
			var baseline: Array = info.get("baseline",[texture.get_width()*.5,texture.get_height()])
			# When falling back to the old sprite, its alpha bottom is the old anchor.
			if used_fallback:
				baseline=[texture.get_width()*.5,texture.get_height()]
			sprite.offset = Vector2(texture.get_width()*.5,texture.get_height()*.5)-Vector2(float(baseline[0]),float(baseline[1]))
	sprite.rotation = 0.0
	sprite.flip_h = false
	sprite.z_index = int(sprite.position.y)
	if _states.size()>16:
		for key in _states.keys():
			if _states[key].ref.get_ref()==null:
				_states.erase(key)

func _direction_name(direction: Vector2) -> String:
	var angle = fposmod(direction.angle(),TAU)
	return DIRECTION_NAMES[int(floor((angle+PI/8.0)/(PI/4.0)))%8]

func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
		# This also allows the validation suite to run before editor import.
		if texture == null and FileAccess.file_exists(path):
			var image = Image.load_from_file(ProjectSettings.globalize_path(path))
			if image != null and not image.is_empty():
				texture = ImageTexture.create_from_image(image)
		_textures[path] = texture
	return _textures[path]

func _fallback(actor: String, direction: Vector2) -> Texture2D:
	var facing = "front"
	if absf(direction.x)>absf(direction.y):
		facing="left" if direction.x>0 else "right"
	elif direction.y<0:
		facing="back"
	var path="res://assets/enemies/little_dragon_%s.png"%facing if actor=="little_dragon" else "res://assets/actors/%s_%s.png"%[actor,facing]
	return _texture(path)
