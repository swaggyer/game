extends SceneTree
const AudioDirector=preload("res://scripts/audio_director.gd")
var checks:int=0
var failures:Array[String]=[]
var director
var owner:AudioOwner
var started:Array[String]=[]
var finished:Array[String]=[]
var states:Array[String]=[]
var fixture_root:String="user://audio_v13_fixture"
var fixture_manifest:String="user://audio_v13_fixture/manifest.json"
var fixture_settings:String="user://audio_v13_fixture/settings.json"

class AudioOwner:
	extends Node
	var attack_sound:AudioStreamPlayer=AudioStreamPlayer.new()
	var chime_sound:AudioStreamPlayer=AudioStreamPlayer.new()
	func _ready()->void:
		add_child(attack_sound);add_child(chime_sound)
		attack_sound.volume_db=-15.0;chime_sound.volume_db=-14.0

func _initialize()->void:call_deferred("_run")

func _run()->void:
	_make_fixtures()
	owner=AudioOwner.new();root.add_child(owner)
	director=AudioDirector.new();director.manifest_path=fixture_manifest;director.settings_path=fixture_settings
	director.setup(owner);director.set_process(false)
	director.narration_started.connect(func(id:String):started.append(id))
	director.narration_finished.connect(func(id:String):finished.append(id))
	director.narration_state_changed.connect(func(state:String):states.append(state))
	_test_setup_and_regions()
	await _test_narration()
	_test_mixing_and_settings()
	await _test_real_pause_and_finish()
	_test_invalid_settings_and_manifest()
	if not "--fixtures-only" in OS.get_cmdline_user_args():_test_production_manifest_if_present()
	paused=false;director.stop_narration();director.stop_music()
	owner.queue_free();await process_frame;await process_frame
	director=null;owner=null
	await create_timer(0.08,true).timeout
	if failures.is_empty():
		print("V1.3 AUDIO TESTS PASSED: %d checks; actual offline playback, looping, crossfade, narration interruption/finish/pause, ducking and independent settings"%checks)
		call_deferred("quit",0)
	else:
		for failure:String in failures:printerr("FAIL: "+failure)
		printerr("V1.3 AUDIO TESTS FAILED: %d / %d"%[failures.size(),checks])
		call_deferred("quit",1)

func _make_fixtures()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture_root))
	for suffix:String in ["",".bak",".tmp"]:
		var path:String=ProjectSettings.globalize_path(fixture_settings+suffix)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	var regions:Array=[]
	for chapter:int in range(7):
		var path:String=fixture_root+"/region_%d.wav"%chapter
		_wave(path,0.30,170+chapter*35)
		regions.append({"id":"chapter_%d"%chapter,"path":path,"gain":0.5+chapter*0.03})
	_wave(fixture_root+"/voice.wav",1.5,260)
	_wave(fixture_root+"/short.wav",0.09,240)
	_wave(fixture_root+"/battle.wav",0.35,190)
	_wave(fixture_root+"/boss.wav",0.35,140)
	_wave(fixture_root+"/title.wav",0.35,300)
	var data:Dictionary={"version":1,"music":{"regions":regions,"contexts":{
		"title":{"path":fixture_root+"/title.wav","gain":0.6},
		"battle":{"path":fixture_root+"/battle.wav","gain":0.7},
		"boss":{"path":fixture_root+"/boss.wav","gain":0.8}}},
		"stories":{"intro_0":{"path":fixture_root+"/voice.wav","text":"星灯照亮了小岛。"},
		"clear_0":{"path":fixture_root+"/voice.wav","gain":0.8},
		"short":{"path":fixture_root+"/short.wav"},"missing":{"path":"res://assets/audio_v13/voice/not_present.mp3"},
		"remote":{"path":"https://example.invalid/voice.mp3"}}}
	_write(fixture_manifest,JSON.stringify(data))

func _wave(path:String,duration:float,frequency:float)->void:
	var stream:AudioStreamWAV=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=8000
	var data:PackedByteArray=PackedByteArray()
	data.resize(int(duration*8000)*2)
	for index:int in range(data.size()/2):data.encode_s16(index*2,int(sin(index*TAU*frequency/8000)*250))
	stream.data=data
	_check(stream.save_to_wav(ProjectSettings.globalize_path(path))==OK,"fixture WAV encoded locally")

func _test_setup_and_regions()->void:
	_check(director.get_parent()==owner and director.process_mode==Node.PROCESS_MODE_ALWAYS,"director belongs to game and keeps processing during story pause")
	_check(director.get_child_count()==3,"exactly two music players and one voice player")
	director.setup(owner)
	_check(director.get_child_count()==3,"setup is idempotent and cannot stack players")
	_check(director.music_player.max_polyphony==1 and director.voice_player.max_polyphony==1,"single narration and single incoming music voice")
	_check(owner.attack_sound.bus==AudioDirector.SFX_BUS and owner.chime_sound.bus==AudioDirector.SFX_BUS,"existing action sounds routed to independent SFX bus")
	_check(owner.attack_sound.volume_db==-15 and owner.chime_sound.volume_db==-14,"SFX routing preserves original effect loudness")
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index(AudioDirector.MUSIC_BUS))==&"Master","dedicated music bus routes to Master")
	var fixed_player:AudioStreamPlayer=director.music_player
	director._process(2.0)
	for chapter:int in range(7):
		director.set_region(chapter)
		_check(director.region==chapter and director.music_context=="explore","region%d selected"%chapter)
		_check(director.music_player==fixed_player,"region%d retains game.music compatibility reference"%chapter)
		_check(director.music_player.playing and director.music_player.stream is AudioStreamWAV,"region%d starts actual offline stream"%chapter)
		_check(director.music_player.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,"region%d native music looping enabled"%chapter)
		director._process(2.0)
		_check(not director.music_outgoing.playing and director.music_outgoing.stream==null,"region%d outgoing stream released after fade"%chapter)
	director.set_region(0);director._process(2.0)
	var full:float=director.music_player.volume_linear
	director.set_region(1)
	_check(director.music_outgoing.playing and is_zero_approx(director.music_player.volume_linear),"changing region retains old playback while incoming starts silent")
	director._process(director.crossfade_seconds*0.5)
	_check(director.music_outgoing.volume_linear>0 and director.music_player.volume_linear>0,"mid-crossfade has two audible streams")
	_check(director.music_outgoing.volume_linear<full,"old theme fades down rather than stacking at full volume")
	director.set_region(2)
	_check(director.get_child_count()==3,"rapid region changes keep bounded player count")
	director._process(2.0)
	for context:String in ["title","battle","boss"]:
		director.set_music_context(context);director._process(2.0)
		_check(director._music_path.ends_with(context+".wav"),context+" selects the manifest track")
	director.set_region(2)
	_check(director.music_context=="explore" and director._music_path.ends_with("region_2.wav"),"same-chapter next stage restores regional exploration music")
	director.set_region(500);_check(director.region==6,"region upper bound clamped")
	director.set_region(-2);_check(director.region==0,"region lower bound clamped")
	director._process(2.0)

func _test_narration()->void:
	_check(director.story_available("intro_0") and not director.story_available("missing"),"availability uses local prerecorded assets")
	_check(not director.story_available("remote"),"runtime rejects network audio paths")
	_check(director.play_story("intro_0","星灯照亮了小岛。"),"narration starts a local prerecorded clip")
	_check(director.voice_player.playing and director.narration_state=="playing","actual voice player and state agree")
	_check(director.voice_player.stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,"narration never inherits music looping")
	_check(started==["intro_0"],"start signal identifies story")
	var old_stream:AudioStream=director.voice_player.stream
	_check(director.play_story("clear_0","队伍找到了新的星灯。"),"opening another story replaces narration")
	_check(director.voice_player.stream!=old_stream and director.get_child_count()==3,"replacement does not add voices or nodes")
	_check(finished.is_empty(),"replacement does not emit natural completion or advance story")
	_check(director.narration_status().id=="clear_0" and director.narration_status().text=="队伍找到了新的星灯。","status matches current subtitles")
	director.pause_narration()
	_check(director.voice_player.stream_paused and director.narration_state=="paused","explicit narration pause preserves stream")
	director.resume_narration()
	_check(not director.voice_player.stream_paused and director.narration_state=="playing","explicit narration resume continues same clip")
	director.stop_narration()
	_check(not director.voice_player.playing and director.voice_player.stream==null,"skip stops playback immediately and releases voice resource")
	_check(finished.is_empty(),"skip never emits natural completion")
	_check(director.replay_narration() and director.narration_status().id=="clear_0","replay remembers the most recent story after skip")
	_check(not director.play_story("missing","即使缺配音仍可阅读。"),"missing narration fails gracefully")
	_check(not director.voice_player.playing and director.narration_state=="unavailable","missing next clip cancels old voice instead of leaving it playing")
	director.stop_narration()
	await process_frame

func _test_mixing_and_settings()->void:
	director.set_region(0);director._process(2.0)
	var normal:float=director.music_player.volume_linear
	director.play_story("intro_0","配音压低音乐。")
	director._process(0.2)
	_check(is_equal_approx(director.music_player.volume_linear,normal*AudioDirector.DUCK_LEVEL),"voice smoothly ducks current music to24percent")
	director.pause_narration();director._process(0.5)
	_check(is_equal_approx(director.music_player.volume_linear,normal),"paused narration restores music volume")
	director.resume_narration();director._process(0.2)
	_check(director.music_player.volume_linear<normal,"resumed narration ducks music again")
	director.stop_narration();director._process(0.5)
	_check(is_equal_approx(director.music_player.volume_linear,normal),"skipped narration restores music smoothly")
	director.set_music_context("pause");director._process(2.0)
	_check(is_equal_approx(director.music_player.volume_linear,normal*0.55),"optional pause context gently reduces regional music")
	director.set_region(0);director._process(2.0)
	director.set_volume("music",0.32);director.set_volume("voice",0.73);director.set_volume("sfx",0.44)
	_check(is_equal_approx(director.settings().music_volume,0.32) and is_equal_approx(director.settings().voice_volume,0.73),"independent music and voice linear settings")
	_check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index(AudioDirector.SFX_BUS)),0.44),"SFX volume reaches the existing action-sound bus")
	_check(is_equal_approx(director.music_player.volume_linear,0.32*0.5),"music setting combines with manifest gain")
	director.set_volume("music",-9);director.set_volume("voice",9)
	_check(director.music_volume==0.0 and director.voice_volume==1.0,"sliders clamp to supported bounds")
	director.set_volume("voice",NAN)
	_check(director.voice_volume==1.0,"non-finite input rejected")
	director.set_volume("unknown",0.5)
	_check(not director.settings().has("unknown"),"unknown setting cannot modify saved schema")
	director.set_enabled("music",false)
	_check(not director.music_player.playing and not director.music_outgoing.playing,"music disable stops both sides of crossfade")
	director.set_enabled("music",true);director._process(2.0)
	_check(director.music_player.playing,"music enable resumes selected regional theme")
	director.play_story("intro_0","关闭配音立即停止。")
	director.set_enabled("voice",false)
	_check(not director.voice_player.playing and not director.play_story("intro_0","文字仍显示。"),"disabled narration remains silent")
	director.set_enabled("voice",true)
	_check(director.replay_narration(),"re-enabling narration permits replay")
	director.stop_narration()
	director.set_volume("music",0.32);director.set_volume("voice",0.73);director.set_enabled("voice",false)
	var second=AudioDirector.new();second.settings_path=fixture_settings;second.manifest_path=fixture_manifest;second.setup(owner);second.set_process(false)
	_check(is_equal_approx(second.music_volume,0.32) and is_equal_approx(second.voice_volume,0.73) and is_equal_approx(second.sfx_volume,0.44),"fresh director reloads all three saved volumes")
	_check(not second.voice_enabled and second.music_enabled,"fresh director reloads enabled flags")
	second.stop_music();second.queue_free()
	_check(not FileAccess.file_exists("user://campaign.json"),"audio preferences never create or reset the campaign save")
	_check(FileAccess.file_exists(fixture_settings) and FileAccess.file_exists(fixture_settings+".bak"),"independent settings use atomic primary and backup")
	director.set_enabled("voice",true)

func _test_real_pause_and_finish()->void:
	# Discard the large first frame spent creating/importing fixtures: audio uses
	# its own mixing clock, while a SceneTreeTimer can expire on that first delta.
	await process_frame;await process_frame
	director.set_region(0);director.set_volume("music",0.5);director.set_volume("voice",1.0)
	director.play_story("intro_0","暂停游戏时仍可听剧情。")
	director.set_process(true);paused=true
	await create_timer(0.18,true).timeout
	_check(director.voice_player.playing and director.voice_player.get_playback_position()>0.03,"voice actually advances while SceneTree is paused (playing=%s position=%.3f paused=%s)"%[director.voice_player.playing,director.voice_player.get_playback_position(),director.voice_player.stream_paused])
	_check(director.music_player.volume_linear<0.1,"ALWAYS processing still applies voice ducking while gameplay is paused")
	director.pause_narration()
	var before:float=director.voice_player.get_playback_position()
	await create_timer(0.12,true).timeout
	_check(absf(director.voice_player.get_playback_position()-before)<0.035,"explicit voice pause holds actual playback position")
	director.resume_narration()
	await create_timer(0.12,true).timeout
	_check(director.voice_player.get_playback_position()>before+0.03,"explicit resume advances actual playback under gameplay pause")
	director.stop_narration()
	var count_before:int=finished.size()
	director.play_story("short","短旁白自然播完。")
	await create_timer(0.35,true).timeout
	_check(finished.size()==count_before+1 and finished.back()=="short","natural finish emits exactly one correct story completion")
	_check(director.narration_state=="idle","natural finish restores idle state")
	_check(director.music_player.playing,"short regional theme loops natively past its own duration")
	paused=false;director.set_process(false)
	director._on_voice_finished()
	_check(finished.size()==count_before+1,"stale finish cannot emit duplicate story completion")

func _test_invalid_settings_and_manifest()->void:
	var backup:Dictionary={"version":1,"music_volume":0.25,"voice_volume":0.6,"sfx_volume":0.8,"music_enabled":false,"voice_enabled":true}
	_write(fixture_settings+".bak",JSON.stringify(backup));_write(fixture_settings,"{invalid JSON")
	_check(director.load_settings() and director.music_volume==0.25 and not director.music_enabled,"malformed primary recovers valid backup settings")
	_write(fixture_settings,JSON.stringify({"version":1,"music_volume":99,"voice_volume":"loud","sfx_volume":-1,"voice_enabled":"yes"}))
	_check(director.load_settings() and director.music_volume==1 and director.voice_volume==AudioDirector.DEFAULT_VOICE and director.sfx_volume==0,"malformed field values bounded or defaulted")
	_check(director.voice_enabled,"invalid boolean does not disable voice")
	_write(fixture_settings,"[]");_write(fixture_settings+".bak","null")
	_check(not director.load_settings(),"non-object primary and backup rejected without crash")
	_write(fixture_settings,JSON.stringify({"version":99}))
	_check(not director.load_settings(),"unsupported settings schema rejected")
	var original_path:String=director.manifest_path
	director.manifest_path=fixture_root+"/bad_manifest.json";_write(director.manifest_path,"[]")
	_check(not director.load_manifest() and director.manifest.is_empty(),"malformed manifest safely rejected")
	_check(not director.play_story("intro_0","配音丢失仍可继续。"),"invalid manifest cannot leave stale narration")
	director.manifest_path=original_path;director.load_manifest()
	# Manifest values are not trusted as network URLs or arbitrary filesystem paths.
	_check(director._load_stream("https://example.invalid/audio.mp3",false)==null,"audio loading stays offline")

func _test_production_manifest_if_present()->void:
	if not FileAccess.file_exists("res://data/audio_v13.json"):return
	var production:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio_v13.json"))
	_check(production is Dictionary,"production manifest is a valid JSON object")
	if not production is Dictionary:return
	_check(production.get("music",{}).get("regions",[]).size()==7,"production manifest covers all seven regional themes")
	var stories:Dictionary=production.get("stories",{})
	for chapter:int in range(7):_check(stories.has("intro_%d"%chapter),"production introduction narration ID exists: chapter%d"%chapter)
	for stage:int in range(21):_check(stories.has("clear_%d"%stage),"production stage-clear narration ID exists: stage%d"%stage)
	_check(stories.has("ending"),"production final ending narration exists")
	for entry:Variant in production.get("music",{}).get("regions",[]):
		if not entry is Dictionary:continue
		var stream:AudioStream=director._load_stream(str(entry.get("path","")),true)
		_check(stream!=null and stream.get_length()>0,"production regional MP3 decodes offline")
		if stream is AudioStreamMP3:_check(stream.loop,"production regional MP3 has native looping enabled")
	for key:String in ["title","battle","boss"]:
		var entry:Variant=production.get("music",{}).get("contexts",{}).get(key,{})
		var stream:AudioStream=director._load_stream(str(entry.get("path","")),true) if entry is Dictionary else null
		_check(stream!=null and stream.get_length()>0,"production context MP3 decodes offline: "+key)
	for key:String in production.get("stories",{}):
		var entry:Variant=production.stories[key]
		if not entry is Dictionary:continue
		var stream:AudioStream=director._load_stream(str(entry.get("path","")),false)
		_check(stream!=null and stream.get_length()>0,"production narration MP3 decodes offline: "+key)
		if stream is AudioStreamMP3:_check(not stream.loop,"production narration never loops: "+key)

func _write(path:String,text:String)->void:
	var file:FileAccess=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text);file.close()

func _check(condition:bool,message:String)->void:
	checks+=1
	if not condition:failures.append(message)
