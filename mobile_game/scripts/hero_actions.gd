extends RefCounted
## Stateful combat timing, bone-rendered attack poses and real echo projectiles.
## update() scales input only; the world remains responsible for player motion.

const MELEE_TIMES = [[0.15, 0.10, 0.10, 0.10], [0.18, 0.12, 0.11, 0.11], [0.28, 0.15, 0.16, 0.16]]
const BELL_TIMES = [[0.25, 0.08, 0.12, 0.17], [0.28, 0.08, 0.14, 0.20], [0.32, 0.10, 0.18, 0.22]]
const PHASE_NAMES = ["windup", "contact", "followthrough", "recovery"]
const MELEE_REACH = [160.0, 185.0, 210.0]
const MELEE_MULT = [1.0, 1.15, 1.7]
const BELL_MULT = [0.90, 1.05, 1.35]

var game: Node2D
var busy: bool = false
var state: String = "idle"
var combo: int = 0
var time_left: float = 0.0
var projectiles: Array = []
var _phase: int = 0
var _character: int = 0
var _facing: Vector2 = Vector2.RIGHT
var _buffer: float = 0.0
var _chain_idle: float = 99.0
var _next_combo: int = 0
var _clock: float = 0.0
var _phase_duration: float = 0.0
var _skill: String = ""
var _skill_left: float = 0.0
var _textures: Dictionary = {}
var _base_scale: Vector2 = Vector2.ONE
var _support: Dictionary = {}

func setup(value: Node2D) -> void:
	game = value
	if is_instance_valid(game.player):
		_base_scale = game.player.scale
	# A tap changes the pose immediately; resource decoding belongs to loading.
	for actor: String in ["wangzai","xiaomantou"]:
		for direction: String in ["front","back","left","right"]:
			_texture("res://assets/actors/%s_%s.png"%[actor,direction])
			for attack_index: int in range(3):
				for phase_index: int in range(4):
					_texture("res://assets/actions/%s_attack_%d_%s_%d.png"%[actor,attack_index,direction,phase_index])
	reset()

func reset() -> void:
	busy = false
	state = "idle"
	combo = 0
	time_left = 0.0
	_buffer = 0.0
	_chain_idle = 99.0
	_next_combo = 0
	_skill = ""
	_skill_left = 0.0
	projectiles.clear()
	_support.clear()
	_restore_player()

func attacking() -> bool:
	return busy and _skill.is_empty()

func supporting() -> bool:
	return not _support.is_empty() and _support.get("actor", "partner") == "partner"

func supporting_player() -> bool:
	return not _support.is_empty() and _support.get("actor", "partner") == "player" and not busy

func start_attack() -> bool:
	if game == null or not is_instance_valid(game.player):
		return false
	if busy:
		if not _skill.is_empty() or _character != int(game.campaign.active_character):
			return false
		_buffer = 0.30
		return true
	if _chain_idle > 0.85:
		_next_combo = 0
	_begin_attack(_next_combo)
	return true

func _begin_attack(index: int) -> void:
	busy = true
	combo = clampi(index, 0, 2)
	_character = int(game.campaign.active_character)
	_skill = ""
	_facing = game.facing.normalized()
	if _facing.length_squared() < 0.5:
		_facing = Vector2.RIGHT
	var auto_range = 540.0 if _character == 1 else MELEE_REACH[combo] + 65.0
	var target = _nearest(game.player.position, auto_range, _facing)
	if not target.is_empty() and is_instance_valid(target.get("sprite")):
		_facing = game.player.position.direction_to(target.sprite.position)
	game.facing = _facing
	_buffer = 0.0
	_set_phase(0)

func _set_phase(index: int) -> void:
	_phase = index
	state = PHASE_NAMES[index]
	var timings = MELEE_TIMES[combo] if _character == 0 else BELL_TIMES[combo]
	_phase_duration = float(timings[index])
	time_left = _phase_duration
	_set_pose(index)
	if index == 1:
		_contact()

func update(delta: float, motion: Vector2) -> Vector2:
	if game == null:
		return motion
	_clock += delta
	_chain_idle += delta
	_buffer = maxf(0.0, _buffer - delta)
	_update_projectiles(delta)
	_update_support(delta)
	if not busy:
		return motion
	if _character != int(game.campaign.active_character):
		_end_attack()
		return motion
	game.facing = _facing
	if not _skill.is_empty():
		_skill_left -= delta
		time_left = maxf(0.0, _skill_left)
		state = "skill_windup" if _skill_left > 0.35 else "skill_release"
		_set_pose(0 if _skill_left > 0.35 else (1 if _skill_left > 0.12 else 3))
		if _skill_left <= 0:
			_end_attack()
		return motion * 0.50
	var remaining = delta
	while busy and remaining >= time_left:
		remaining -= time_left
		if _phase < 3:
			_set_phase(_phase + 1)
		else:
			var queued = _buffer > 0.0
			_next_combo = (combo + 1) % 3
			_chain_idle = 0.0
			_end_attack()
			if queued:
				_begin_attack(_next_combo)
			else:
				break
	if busy:
		time_left = maxf(0.001, time_left - remaining)
		_set_pose(_phase)
		return motion * (0.35 if _phase == 0 else (0.22 if _phase == 1 else 0.65))
	return motion

func _end_attack() -> void:
	busy = false
	state = "idle"
	time_left = 0.0
	_skill = ""
	_skill_left = 0.0
	_restore_player()

func _contact() -> void:
	if is_instance_valid(game.attack_sound) and game.attack_sound.stream != null:
		game.attack_sound.pitch_scale = [1.05, 1.16, 0.82][combo] if _character == 0 else [1.35, 1.52, 1.14][combo]
		game.attack_sound.play()
	if _character == 0:
		_melee_contact()
	else:
		_bell_contact()

func _melee_contact() -> void:
	var origin = game.player.position
	if game.has_method("_hit_challenge_targets"):
		game._hit_challenge_targets(origin,_facing,MELEE_REACH[combo],game.campaign.attack()*MELEE_MULT[combo],"melee",0.95)
	var cone = [0.60, 0.28, 0.40][combo]
	var targets = _enemies().duplicate()
	for enemy in targets:
		if not _valid_enemy(enemy):
			continue
		var offset: Vector2 = enemy.sprite.position - origin
		if offset.length() > MELEE_REACH[combo] + (22.0 if enemy.get("boss", false) else 0.0):
			continue
		if offset.length() > 34 and _facing.dot(offset.normalized()) < cone:
			continue
		if not _line_of_sight(origin, enemy.sprite.position):
			continue
		var shield_bonus=float(game.campaign.upgrades.get("shield",0))*3 if combo==2 else 0.0
		if _damage(enemy, game.campaign.attack() * MELEE_MULT[combo]+shield_bonus, "shield" if combo == 2 else "melee"):
			_effect(enemy.sprite.position + Vector2(0,-35), Color("f8df9c"), "burst", 0.28, 38)
			if combo == 2:
				_interrupt(enemy, 1.0 if not enemy.get("boss", false) else 0.45)
				if _valid_enemy(enemy) and not enemy.get("boss", false):
					var pushed = _facing * 65.0
					if game.world.has_method("move_actor"):
						enemy.sprite.position = game.world.move_actor(enemy.sprite.position, pushed, 20.0)
					elif _line_of_sight(enemy.sprite.position, enemy.sprite.position + pushed):
						enemy.sprite.position += pushed
	if combo == 2:
		_effect(origin + _facing*65, Color("f0d393"), "ring", 0.5, 105)

func _bell_contact() -> void:
	var origin: Vector2 = game.player.position
	var target = _nearest(origin, 540.0, _facing)
	var direction = _facing
	if not target.is_empty() and is_instance_valid(target.get("sprite")):
		direction = origin.direction_to(target.sprite.position)
	var projectile = {"p":origin + direction*30.0,"dir":direction,"travel":0.0,"range":500.0,"speed":440.0,"damage":game.campaign.attack()*BELL_MULT[combo]+float(game.campaign.upgrades.get("bell",0))*2,"combo":combo,"trail":[],"age":0.0}
	projectiles.append(projectile)
	if projectiles.size() > 12:
		projectiles.pop_front()
	_effect(origin, Color("ffd695"), "ring", 0.35, 48)
	if combo == 2:
		_effect(origin, Color("ffdc9b"), "ring", 0.85, 190)
		for enemy in _enemies():
			if _valid_enemy(enemy) and origin.distance_to(enemy.sprite.position) <= 185 and _line_of_sight(origin, enemy.sprite.position):
				_interrupt(enemy, 0.9 if not enemy.get("boss",false) else 0.4)
				var director = game.get("enemy_director")
				if director != null and director.has_method("expose"):
					director.expose(enemy, 2.0)

func _update_projectiles(delta: float) -> void:
	for i in range(projectiles.size()-1,-1,-1):
		var projectile: Dictionary = projectiles[i]
		var previous: Vector2 = projectile.p
		var next: Vector2 = previous + projectile.dir * projectile.speed * delta
		projectile.travel += previous.distance_to(next)
		projectile.age += delta
		projectile.trail.append(previous)
		if projectile.trail.size()>6:
			projectile.trail.pop_front()
		var remove = projectile.travel >= projectile.range or not _line_of_sight(previous,next)
		if not remove and game.has_method("_hit_challenge_projectile"):
			remove=game._hit_challenge_projectile(previous,next,projectile.damage,"projectile")
		if not remove:
			for enemy in _enemies().duplicate():
				if not _valid_enemy(enemy):
					continue
				var radius = 50.0 if enemy.get("boss",false) else 25.0
				var closest = Geometry2D.get_closest_point_to_segment(enemy.sprite.position,previous,next)
				if closest.distance_to(enemy.sprite.position) <= radius:
					_damage(enemy,projectile.damage,"echo")
					_effect(enemy.sprite.position+Vector2(0,-45),Color("ffe3a8"),"ring",0.35,55)
					remove=true
					break
		projectile.p = next
		if remove:
			projectiles.remove_at(i)

func cast_skill(id: String) -> bool:
	return start_skill_visual(id)

func start_skill_visual(id: String) -> bool:
	if busy or game == null:
		return false
	_character = int(game.campaign.active_character)
	_facing = game.facing.normalized()
	_skill = id
	_skill_left = 0.60
	time_left = _skill_left
	combo = 2
	busy = true
	state = "skill_windup"
	_buffer = 0.0
	_set_pose(0)
	return true

func play_support(kind: String, target: Vector2) -> void:
	var character = 0 if kind == "shield" else 1
	var actor = "player" if int(game.campaign.active_character) == character else "partner"
	_support = {"kind":kind,"target":target,"life":0.75,"duration":0.75,"character":character,"actor":actor}
	var sprite = game.player if actor == "player" else game.partner
	if game != null and is_instance_valid(sprite):
		_effect(sprite.position, Color("9debd8") if kind == "bell" else Color("f3d98d"), "ring", 0.65, 65)

func _update_support(delta: float) -> void:
	if _support.is_empty():
		return
	_support.life -= delta
	if _support.life <= 0:
		_support.clear()
		return
	if game == null:
		return
	var sprite = game.player if _support.actor == "player" else game.partner
	if not is_instance_valid(sprite) or (sprite == game.player and busy):
		return
	var character = int(_support.character)
	var direction = sprite.position.direction_to(_support.target)
	var phase = clampi(int((1.0-_support.life/_support.duration)*4),0,3)
	var key = "wangzai" if character == 0 else "xiaomantou"
	var path = "res://assets/actions/%s_attack_%d_%s_%d.png" % [key,2 if character == 0 else 0,_direction_name(direction),phase]
	var pose = _texture(path)
	if pose != null:
		if sprite.texture != pose:
			sprite.texture = pose
			sprite.offset = Vector2(0,-pose.get_height()*0.5)
		sprite.z_index = int(sprite.position.y)

func _set_pose(phase: int) -> void:
	if game == null or not is_instance_valid(game.player):
		return
	var key = "wangzai" if _character == 0 else "xiaomantou"
	var path = "res://assets/actions/%s_attack_%d_%s_%d.png" % [key,combo,_direction_name(_facing),phase]
	var pose = _texture(path)
	if pose != null:
		if game.player.texture != pose:
			game.player.texture = pose
			game.player.offset = Vector2(0,-pose.get_height()*0.5)
	game.player.scale = _base_scale
	game.player.z_index = int(game.player.position.y)
	game.player.modulate = Color(1,0.75,0.7,0.65) if game.get("invulnerable") != null and game.invulnerable > 0 and int(_clock*12)%2 == 0 else Color.WHITE

func _restore_player() -> void:
	if game == null or not is_instance_valid(game.player):
		return
	var key = "wangzai" if int(game.campaign.active_character) == 0 else "xiaomantou"
	var idle = _texture("res://assets/actors/%s_%s.png" % [key,_direction_name(game.facing)])
	if idle != null:
		game.player.texture = idle
		game.player.offset = Vector2(0,-idle.get_height()*0.5)
	game.player.scale = _base_scale
	game.player.rotation = 0

func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]

func _direction_name(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		# Blender's camera-side filenames describe the camera, not screen facing.
		return "left" if direction.x > 0 else "right"
	return "front" if direction.y >= 0 else "back"

func _nearest(p: Vector2, reach: float, forward: Vector2) -> Dictionary:
	var director = game.get("enemy_director")
	if director != null and director.has_method("nearest_target"):
		return director.nearest_target(p,reach,forward)
	var found: Dictionary = {}
	var best = reach
	for enemy in _enemies():
		if not _valid_enemy(enemy):
			continue
		var offset: Vector2 = enemy.sprite.position-p
		if offset.length()<best and forward.dot(offset.normalized()) > -0.05 and _line_of_sight(p,enemy.sprite.position):
			best=offset.length();found=enemy
	return found

func _enemies() -> Array:
	var director = game.get("enemy_director")
	return director.enemies if director != null else game.enemies

func _valid_enemy(enemy: Dictionary) -> bool:
	return float(enemy.get("hp",0))>0 and is_instance_valid(enemy.get("sprite"))

func _line_of_sight(a: Vector2, b: Vector2) -> bool:
	return game.world.has_line_of_sight(a,b) if game.world != null and game.world.has_method("has_line_of_sight") else true

func _damage(enemy: Dictionary, amount: float, kind: String) -> bool:
	var director = game.get("enemy_director")
	if director != null and director.has_method("damage"):
		return director.damage(enemy,amount,kind)
	game._damage_enemy(enemy,amount)
	return true

func _interrupt(enemy: Dictionary, duration: float) -> void:
	var director = game.get("enemy_director")
	if director != null and director.has_method("interrupt"):
		director.interrupt(enemy,duration)
	else:
		enemy["warning"] = 0.0
		enemy["timer"] = duration

func _effect(p: Vector2, color: Color, kind: String, life: float, radius: float) -> void:
	if game != null and game.has_method("_effect"):
		game._effect(p,color,kind,life,radius)

func draw(canvas: Node2D, font: Font) -> void:
	if game == null or not is_instance_valid(game.player):
		return
	for projectile in projectiles:
		var color = Color("ffe3a8")
		var trail: Array = projectile.trail
		for j in range(1,trail.size()):
			canvas.draw_line(trail[j-1]+Vector2(0,-48),trail[j]+Vector2(0,-48),Color(1.0,0.75,0.34,float(j)/trail.size()*0.55),2.0+j*0.55,true)
		var p: Vector2 = projectile.p+Vector2(0,-48)
		canvas.draw_circle(p,14,Color(1.0,0.74,0.25,0.15))
		canvas.draw_arc(p,8,-0.7,4.7,22,color,2,true)
		canvas.draw_line(p+Vector2(3,-7),p+Vector2(3,-21),color,2,true)
		canvas.draw_line(p+Vector2(3,-21),p+Vector2(13,-16),color,2,true)
		_star(canvas,p+projectile.dir*16,4.5,color,_clock*4)
	if busy and _skill.is_empty():
		var center: Vector2 = game.player.position+Vector2(0,-45)
		var progress = 1.0-time_left/maxf(0.001,_phase_duration)
		var angle = _facing.angle()
		if _character == 0:
			var reach = MELEE_REACH[combo]*0.66
			if _phase == 0:
				canvas.draw_arc(center,reach*0.6,angle-0.9,angle+0.9,20,Color(1.0,0.85,0.5,0.15+progress*0.2),1.5,true)
			elif _phase in [1,2]:
				var swing = progress if _phase == 1 else 1.0
				var start = angle-1.10 if combo != 1 else angle+1.10-2.2*swing
				var finish = angle-1.10+2.2*swing if combo != 1 else angle+1.10
				var opacity = 0.85 if _phase == 1 else 0.65*(1-progress)
				canvas.draw_arc(center,reach,start,finish,32,Color(1.0,0.86,0.51,opacity),9.0 if combo == 2 else 6.0,true)
				canvas.draw_arc(center,reach-8,start,finish,32,Color(1.0,1.0,0.85,opacity*0.65),2.5,true)
				for j in 4:
					var a = lerpf(start,finish,float(j)/3)
					_star(canvas,center+Vector2.from_angle(a)*reach,3+combo,Color(1.0,0.9,0.6,opacity),a)
			if combo == 2 and _phase in [0,1]:
				var shield = center+_facing*45
				var outline = PackedVector2Array([shield+Vector2(-20,-24),shield+Vector2(20,-24),shield+Vector2(24,6),shield+Vector2(0,32),shield+Vector2(-24,6),shield+Vector2(-20,-24)])
				canvas.draw_polyline(outline,Color(1.0,0.87,0.5,0.8),2.0,true)
		else:
			var radius = 36+progress*50
			canvas.draw_arc(center,radius,0,TAU,40,Color(1.0,0.81,0.48,0.40*(1-progress)),2.5,true)
			if _phase == 0:
				_star(canvas,center+_facing*35+Vector2(0,-30),5+progress*8,Color("ffe4a4"),_clock*3)
	if busy and not _skill.is_empty():
		_draw_skill(canvas)
	if not _support.is_empty():
		var sprite = game.player if _support.actor == "player" else game.partner
		if not is_instance_valid(sprite):
			return
		var source: Vector2 = sprite.position+Vector2(0,-55)
		var target: Vector2 = _support.target+Vector2(0,-45)
		var fade = _support.life/_support.duration
		canvas.draw_line(source,target,Color(0.8,1.0,0.86,fade*0.65),2.5,true)
		for i in 3:
			_star(canvas,source.lerp(target,fmod(_clock*1.5+float(i)/3,1.0)),5,Color(1.0,0.9,0.6,fade),_clock*2)

func _draw_skill(canvas: Node2D) -> void:
	var p: Vector2 = game.player.position+Vector2(0,-43)
	var t = 1.0-_skill_left/0.60
	var color = Color("ffd18b")
	if _skill in ["water","wind"]:
		color=Color("8ce9e3")
	elif _skill == "space":
		color=Color("c7a9ff")
	var fade = sin(t*PI)
	color.a=fade*0.85
	for i in 3:
		var r = 30.0+i*18.0+t*28.0
		var angle = _clock*(2.0+i)+i*2.1
		canvas.draw_arc(p,r,angle,angle+PI*1.3,35,color,2.5,true)
		_star(canvas,p+Vector2.from_angle(angle)*r,5+i,color,angle)
	if _skill == "space":
		var oval = PackedVector2Array()
		for i in 49:
			var a=float(i)/48*TAU
			oval.append(p+_facing*60+Vector2(cos(a)*27,sin(a)*61))
		canvas.draw_polyline(oval,color,4.0,true)
	elif _skill == "water":
		canvas.draw_circle(p,65,Color(0.5,0.9,1.0,fade*0.08))
	elif _skill in ["spark","fire"] and is_instance_valid(game.dragon):
		var mouth: Vector2 = game.dragon.position+Vector2(0,-42)
		for i in 5:
			var q=mouth+_facing*(20+i*12.0)+Vector2(0,sin(_clock*15+i)*7)
			_star(canvas,q,6+i*1.5,Color(1.0,0.72,0.25,fade),_clock*3+i)

func _star(canvas: Node2D, p: Vector2, radius: float, color: Color, rotation: float) -> void:
	var vertices=PackedVector2Array()
	for i in 8:
		vertices.append(p+Vector2.from_angle(rotation+i*TAU/8)*(radius if i%2==0 else radius*0.28))
	canvas.draw_colored_polygon(vertices,color)
