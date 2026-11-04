extends Node
## Offline audio. A single voice player prevents overlapping story narration.
## This node and its players keep processing while the story pauses gameplay.

signal narration_started(id:String)
signal narration_finished(id:String)
signal narration_state_changed(state:String)
signal audio_warning(message:String)
signal settings_changed(values:Dictionary)

const MUSIC_BUS:StringName=&"StarLanternMusic"
const VOICE_BUS:StringName=&"StarLanternVoice"
const SFX_BUS:StringName=&"StarLanternSfx"
const DEFAULT_MUSIC:float=0.55
const DEFAULT_VOICE:float=1.0
const DUCK_LEVEL:float=0.24

var manifest_path:String="res://data/audio_v13.json"
var settings_path:String="user://audio_settings.json"
var manifest:Dictionary={}
var music_enabled:bool=true
var voice_enabled:bool=true
var music_volume:float=DEFAULT_MUSIC
var voice_volume:float=DEFAULT_VOICE
var sfx_volume:float=1.0
var music_player:AudioStreamPlayer
var music_outgoing:AudioStreamPlayer
var voice_player:AudioStreamPlayer
var region:int=-1
var music_context:String="explore"
var crossfade_seconds:float=1.2
var last_error:String=""
var narration_state:String="idle"

var _story_id:String=""
var _story_text:String=""
var _last_story_id:String=""
var _last_story_text:String=""
var _music_path:String=""
var _music_gain:float=1.0
var _outgoing_gain:float=1.0
var _music_weight:float=0.0
var _outgoing_weight:float=0.0
var _outgoing_start:float=0.0
var _fade_elapsed:float=0.0
var _fading:bool=false
var _duck:float=1.0
var _voice_gain:float=1.0

func setup(game:Node)->void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	if get_parent()==null and is_instance_valid(game):game.add_child(self)
	if is_instance_valid(music_player):return
	_ensure_bus(MUSIC_BUS);_ensure_bus(VOICE_BUS);_ensure_bus(SFX_BUS)
	if is_instance_valid(game):
		for property:Dictionary in game.get_property_list():
			if property.name in [&"attack_sound",&"chime_sound"]:
				register_sfx(game.get(property.name) as AudioStreamPlayer)
	music_player=_player("RegionMusic",MUSIC_BUS)
	music_outgoing=_player("OutgoingMusic",MUSIC_BUS)
	voice_player=_player("StoryNarration",VOICE_BUS)
	voice_player.finished.connect(_on_voice_finished)
	load_manifest();load_settings();set_region(0)
	_apply_volumes()

func _player(player_name:String,bus_name:StringName)->AudioStreamPlayer:
	var player:AudioStreamPlayer=AudioStreamPlayer.new()
	player.name=player_name;player.bus=bus_name
	player.max_polyphony=1;player.process_mode=Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player

func _ensure_bus(bus_name:StringName)->void:
	if AudioServer.get_bus_index(bus_name)>=0:return
	AudioServer.add_bus()
	var index:int=AudioServer.bus_count-1
	AudioServer.set_bus_name(index,bus_name)
	AudioServer.set_bus_send(index,&"Master")

func register_sfx(player:AudioStreamPlayer)->void:
	if is_instance_valid(player):player.bus=SFX_BUS

func load_manifest()->bool:
	manifest.clear()
	if not FileAccess.file_exists(manifest_path):return false
	var parser:JSON=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(manifest_path))!=OK or not parser.data is Dictionary:
		_warn("音频清单无法读取，故事仍可阅读。")
		return false
	manifest=parser.data
	return true

func set_region(chapter:int)->void:
	var next_region:int=clampi(chapter,0,6)
	if region>=0 and region!=next_region:stop_narration()
	region=next_region
	music_context="explore"
	_refresh_music()
	_apply_volumes()

func set_music_context(context:String="explore")->void:
	var next_context:String=context if context in ["title","explore","battle","boss","pause"] else "explore"
	if music_context==next_context:return
	music_context=next_context
	_refresh_music()
	_apply_volumes()

func _entry(value:Variant)->Dictionary:
	if value is String:return {"path":value,"gain":1.0}
	if value is Dictionary:return value.duplicate()
	return {}

func _region_entry()->Dictionary:
	var music_data:Variant=manifest.get("music",{})
	var regions:Variant=music_data.get("regions",[]) if music_data is Dictionary else []
	var entry:Dictionary={}
	if regions is Array and region<regions.size():entry=_entry(regions[region])
	elif regions is Dictionary:entry=_entry(regions.get(str(region),regions.get("chapter_%d"%region,{})))
	# Retain the existing local theme until the optional new audio manifest exists.
	if entry.is_empty():entry={"path":"res://assets/audio/island.wav","gain":0.55}
	return entry

func _desired_music()->Dictionary:
	var entry:Dictionary=_region_entry()
	var music_data:Variant=manifest.get("music",{})
	var contexts:Variant=music_data.get("contexts",{}) if music_data is Dictionary else {}
	if contexts is Dictionary and music_context in contexts:
		var contextual:Dictionary=_entry(contexts[music_context])
		if not str(contextual.get("path","")).is_empty():entry=contextual
	return entry

func _refresh_music()->void:
	if not is_instance_valid(music_player):return
	if not music_enabled:
		stop_music()
		return
	var entry:Dictionary=_desired_music()
	var path:String=str(entry.get("path",""))
	var gain:float=_number(entry.get("gain",1.0),1.0,0.0,1.5)
	if path==_music_path and music_player.stream!=null:
		_music_gain=gain
		return
	var stream:AudioStream=_load_stream(path,true)
	if stream==null:
		_warn("地区音乐暂不可用，保留当前音乐。")
		return
	music_outgoing.stop();music_outgoing.stream=null
	_outgoing_start=0.0
	if music_player.playing and music_player.stream!=null:
		music_outgoing.stream=music_player.stream
		music_outgoing.play(maxf(0.0,music_player.get_playback_position()))
		_outgoing_gain=_music_gain
		_outgoing_start=_music_weight
	music_player.stop();music_player.stream=stream;music_player.stream_paused=false
	_music_path=path;_music_gain=gain;_music_weight=0.0
	_outgoing_weight=_outgoing_start;_fade_elapsed=0.0;_fading=true
	music_player.volume_linear=0.0;music_player.play()
	_apply_volumes()

func stop_music()->void:
	if is_instance_valid(music_player):music_player.stop();music_player.stream=null
	if is_instance_valid(music_outgoing):music_outgoing.stop();music_outgoing.stream=null
	_music_path="";_music_weight=0.0;_outgoing_weight=0.0;_fading=false

func _process(delta:float)->void:
	var step:float=maxf(0.0,delta)
	if _fading:
		_fade_elapsed+=step
		var t:float=clampf(_fade_elapsed/maxf(crossfade_seconds,0.01),0.0,1.0)
		var blend:float=t*t*(3.0-2.0*t)
		_music_weight=blend;_outgoing_weight=_outgoing_start*(1.0-blend)
		if t>=1.0:
			_fading=false;_outgoing_weight=0.0
			music_outgoing.stop();music_outgoing.stream=null
	var narrating:bool=narration_state=="playing" and voice_enabled and voice_volume>0.0
	var desired:float=DUCK_LEVEL if narrating else 1.0
	_duck=move_toward(_duck,desired,step/(0.12 if narrating else 0.35))
	_apply_volumes()

func _apply_volumes()->void:
	var context_gain:float=0.55 if music_context=="pause" else 1.0
	var master:float=music_volume*_duck*context_gain if music_enabled else 0.0
	if is_instance_valid(music_player):music_player.volume_linear=master*_music_gain*_music_weight
	if is_instance_valid(music_outgoing):music_outgoing.volume_linear=master*_outgoing_gain*_outgoing_weight
	if is_instance_valid(voice_player):voice_player.volume_linear=voice_volume*_voice_gain if voice_enabled else 0.0
	var sfx_bus:int=AudioServer.get_bus_index(SFX_BUS)
	if sfx_bus>=0:AudioServer.set_bus_volume_linear(sfx_bus,sfx_volume)

func _story_entry(id:String)->Dictionary:
	var stories:Variant=manifest.get("stories",{})
	if stories is Dictionary:return _entry(stories.get(id,{}))
	return {}

func story_available(id:String)->bool:
	return _local_audio_exists(str(_story_entry(id).get("path","")))

func play_story(id:String,text:String)->bool:
	stop_narration()
	_story_id=id;_story_text=text;_last_story_id=id;_last_story_text=text
	if not voice_enabled:
		_set_narration_state("disabled")
		return false
	if not is_instance_valid(voice_player):
		_set_narration_state("unavailable")
		return false
	var entry:Dictionary=_story_entry(id)
	var stream:AudioStream=_load_stream(str(entry.get("path","")),false)
	if stream==null:
		_set_narration_state("unavailable")
		return false
	_voice_gain=_number(entry.get("gain",1.0),1.0,0.0,1.5)
	voice_player.stream=stream;voice_player.stream_paused=false
	_apply_volumes();voice_player.play()
	_set_narration_state("playing")
	narration_started.emit(id)
	return true

func stop_narration()->void:
	if is_instance_valid(voice_player):
		voice_player.stop();voice_player.stream_paused=false;voice_player.stream=null
	_set_narration_state("idle")
	_story_id="";_story_text=""

func pause_narration()->void:
	if narration_state!="playing" or not is_instance_valid(voice_player):return
	voice_player.stream_paused=true
	_set_narration_state("paused")

func resume_narration()->void:
	if narration_state!="paused" or not is_instance_valid(voice_player) or not voice_enabled:return
	voice_player.stream_paused=false
	_set_narration_state("playing")

func replay_narration()->bool:
	if _last_story_id.is_empty():return false
	return play_story(_last_story_id,_last_story_text)

func replay()->bool:return replay_narration()

func narration_status()->Dictionary:
	var valid:bool=is_instance_valid(voice_player)
	var stream:AudioStream=voice_player.stream if valid else null
	return {"id":_story_id,"text":_story_text,"state":narration_state,
		"position":maxf(0.0,voice_player.get_playback_position()) if valid and stream!=null else 0.0,
		"duration":stream.get_length() if stream!=null else 0.0,
		"playing":narration_state=="playing","paused":narration_state=="paused",
		"available":story_available(_story_id if not _story_id.is_empty() else _last_story_id)}

func _on_voice_finished()->void:
	if narration_state!="playing":return
	var finished_id:String=_story_id
	_set_narration_state("idle")
	# stop() deliberately does not emit this; skipping never advances the story.
	narration_finished.emit(finished_id)

func _set_narration_state(value:String)->void:
	if narration_state==value:return
	narration_state=value
	narration_state_changed.emit(value)

func _local_audio_exists(path:String)->bool:
	if not path.begins_with("res://") and not path.begins_with("user://"):return false
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)

func _load_stream(path:String,looping:bool)->AudioStream:
	if not _local_audio_exists(path):return null
	var source:AudioStream
	if ResourceLoader.exists(path):source=load(path) as AudioStream
	elif path.get_extension().to_lower()=="mp3":source=AudioStreamMP3.load_from_file(path)
	elif path.get_extension().to_lower()=="ogg":source=AudioStreamOggVorbis.load_from_file(path)
	elif path.get_extension().to_lower()=="wav":source=AudioStreamWAV.load_from_file(path)
	if source==null:return null
	# Never change the imported shared resource: voice and music may use one file.
	var stream:AudioStream=source.duplicate() as AudioStream
	if stream is AudioStreamMP3:stream.loop=looping;stream.loop_offset=0.0
	elif stream is AudioStreamOggVorbis:stream.loop=looping;stream.loop_offset=0.0
	elif stream is AudioStreamWAV:
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
		if looping and stream.loop_end<=stream.loop_begin:
			stream.loop_begin=0;stream.loop_end=int(stream.get_length()*stream.mix_rate)
	return stream

func settings()->Dictionary:
	return {"version":1,"music_volume":music_volume,"voice_volume":voice_volume,"sfx_volume":sfx_volume,
		"music_enabled":music_enabled,"voice_enabled":voice_enabled}

func set_volume(kind:String,linear:float)->void:
	if not is_finite(linear):return
	match kind:
		"music","bgm":music_volume=clampf(linear,0.0,1.0)
		"voice","narration":voice_volume=clampf(linear,0.0,1.0)
		"sfx":sfx_volume=clampf(linear,0.0,1.0)
		_:return
	_apply_volumes();save_settings();settings_changed.emit(settings())

func set_enabled(kind:String,enabled:bool)->void:
	match kind:
		"music","bgm":
			music_enabled=enabled
			if enabled:_refresh_music()
			else:stop_music()
		"voice","narration":
			voice_enabled=enabled
			if not enabled:stop_narration();_set_narration_state("disabled")
			elif narration_state=="disabled":_set_narration_state("idle")
		_:return
	_apply_volumes();save_settings();settings_changed.emit(settings())

func _number(value:Variant,fallback:float,minimum:float=0.0,maximum:float=1.0)->float:
	if (value is int or value is float) and is_finite(float(value)):
		return clampf(float(value),minimum,maximum)
	return fallback

func load_settings()->bool:
	for path:String in [settings_path,settings_path+".bak"]:
		if not FileAccess.file_exists(path):continue
		var parser:JSON=JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary:continue
		var data:Dictionary=parser.data
		if data.get("version",1)!=1:continue
		music_volume=_number(data.get("music_volume",DEFAULT_MUSIC),DEFAULT_MUSIC)
		voice_volume=_number(data.get("voice_volume",DEFAULT_VOICE),DEFAULT_VOICE)
		sfx_volume=_number(data.get("sfx_volume",1.0),1.0)
		music_enabled=data.music_enabled if data.get("music_enabled") is bool else true
		voice_enabled=data.voice_enabled if data.get("voice_enabled") is bool else true
		_apply_volumes()
		return true
	return false

func save_settings()->bool:
	var absolute:String=ProjectSettings.globalize_path(settings_path)
	var temporary:String=absolute+".tmp"
	var backup:String=absolute+".bak"
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())!=OK:
		_warn("音量设置无法保存，请检查设备存储。")
		return false
	var file:FileAccess=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:
		_warn("音量设置无法保存，请检查设备存储。")
		return false
	file.store_string(JSON.stringify(settings()));file.flush()
	var write_error:Error=file.get_error()
	file.close()
	if write_error!=OK:
		_warn("音量设置写入失败，请检查设备存储。")
		return false
	if FileAccess.file_exists(absolute):
		if FileAccess.file_exists(backup):DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(absolute,backup)!=OK:
			_warn("音量设置无法更新，请检查设备存储。")
			return false
	if DirAccess.rename_absolute(temporary,absolute)!=OK:
		if FileAccess.file_exists(backup):DirAccess.rename_absolute(backup,absolute)
		_warn("音量设置无法更新，请检查设备存储。")
		return false
	return true

func _warn(message:String)->void:
	last_error=message
	audio_warning.emit(message)

func _exit_tree()->void:
	if is_instance_valid(voice_player):voice_player.stop()
	if is_instance_valid(music_player):music_player.stop()
	if is_instance_valid(music_outgoing):music_outgoing.stop()
