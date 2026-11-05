extends SceneTree
## Run this external script against --main-pack from an empty working directory.
## STARLAN_QA_PNG optionally captures the actual packed story UI; STARLAN_QA_WAV
## records ten seconds of the real Master bus (music, narration, duck/recovery).
var checks:int=0
var failures:Array[String]=[]
var game:Node2D
var audio
var music_count:int=0
var voice_count:int=0
var callbacks:int=0
var completions:Array[String]=[]

func _initialize()->void:call_deferred("_run")

func _run()->void:
	root.size=Vector2i(1280,720)
	_check(str(ProjectSettings.get_setting("application/config/version","")).begins_with("1.5.0"),"packed project is the current update-enabled release with audio")
	var manifest:Dictionary=_json("res://data/audio_v13.json")
	_check(not manifest.is_empty(),"runtime audio JSON is packed")
	_check(FileAccess.get_file_as_string("res://assets/audio_v13/licenses/GeneralUser-LICENSE.txt").contains("GeneralUser"),"music instrument license is packed")
	_check(FileAccess.get_file_as_string("res://assets/font-license/OFL.txt").contains("SIL Open Font License"),"Chinese font license is packed")
	for name:String in ["chapters","systems","objectives","challenges_v12"]:
		_check(FileAccess.file_exists("res://data/"+name+".json"),"runtime data JSON packed: "+name)
	var scene:PackedScene=load("res://scenes/main.tscn") as PackedScene
	_check(scene!=null,"main scene loads from pack")
	if scene==null:
		_finish()
		return
	game=scene.instantiate() as Node2D
	game.campaign.save_path="user://packed-audio-qa/campaign.json"
	game.audio_director.settings_path="user://packed-audio-qa/audio_settings.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://packed-audio-qa"))
	root.add_child(game);game.set_process(false);audio=game.audio_director
	await _frames(3)
	_check(game.music==audio.music_player and game.ui.audio_controller==audio,"packed main scene owns the audio controller and compatibility player")
	_check(audio.music_context=="title" and audio.music_player.playing,"packed title music actually plays")
	audio.narration_finished.connect(func(id:String):completions.append(id))
	_decode_all(manifest)
	await _frames(2)
	game._start(false)
	await _frames(3)
	_check(game.ui.dialog_screen.visible and paused,"packed chapter introduction pauses gameplay")
	_check(audio.narration_state=="playing" and audio.narration_status().id=="intro_0","packed introduction starts the correct offline narration")
	_check(audio.voice_player.stream is AudioStreamMP3 and audio.voice_player.playing,"packed voice uses the real MP3 player")
	_check(game.ui.story_audio_state=="playing","packed story UI reflects the actual narration state")
	await create_timer(0.18,true).timeout
	_check(audio.voice_player.get_playback_position()>0.02,"packed narration advances while gameplay is paused")
	_check(audio._duck<0.4,"packed story narration ducks regional background music")
	await _capture()
	var initial_skip:Button=game.ui.dialog_screen.find_child("SkipStory",true,false) as Button
	_check(initial_skip!=null,"packed story exposes a real Skip button")
	if initial_skip!=null:initial_skip.pressed.emit()
	_check(not game.ui.dialog_screen.visible and not paused,"actual packed Skip button closes story and restores gameplay")
	_check(not audio.voice_player.playing and completions.is_empty(),"packed Skip immediately stops narration without a false completion")
	var entry:Dictionary=manifest.get("stories",{}).get("clear_0",{})
	game.ui.show_dialog("旅途中的星灯",str(entry.get("text","")),"继续旅程",_count_callback,"clear_0",str(entry.get("text","")))
	var skip:Button=game.ui.dialog_screen.find_child("SkipStory",true,false) as Button
	var advance:Button=game.ui.dialog_screen.find_child("ContinueDialog",true,false) as Button
	_check(skip!=null and advance!=null and audio.narration_status().id=="clear_0","packed completion dialog starts the corresponding clip and actions")
	if skip!=null:skip.pressed.emit()
	_check(callbacks==1 and not audio.voice_player.playing,"actual story Skip invokes the supplied game callback once and stops speech")
	if advance!=null:advance.pressed.emit()
	_check(callbacks==1,"stale Continue button cannot duplicate the skipped-story callback")
	_check(completions.is_empty(),"skipping two packed stories never masquerades as natural narration completion")
	if not OS.get_environment("STARLAN_QA_WAV").is_empty():await _record_mix(manifest)
	paused=false;audio.stop_narration();audio.stop_music()
	game.hero_actions.game=null;game.locomotion.game=null
	game.queue_free();await _frames(3)
	_check(not is_instance_valid(game) and not is_instance_valid(audio),"packed scene and audio players are freed cleanly")
	game=null;audio=null
	await create_timer(0.1,true).timeout
	_finish()

func _decode_all(manifest:Dictionary)->void:
	var tracks:Dictionary={}
	var music_data:Dictionary=manifest.get("music",{})
	var regions:Array=music_data.get("regions",[])
	_check(regions.size()==7,"pack contains seven regional music entries")
	for entry:Dictionary in regions:tracks[str(entry.get("path",""))]=true
	for context:String in ["title","battle","boss"]:
		var entry:Dictionary=music_data.get("contexts",{}).get(context,{})
		_check(not entry.is_empty(),"pack contains context theme: "+context)
		tracks[str(entry.get("path",""))]=true
	var stories:Dictionary=manifest.get("stories",{})
	for chapter:int in range(7):_check(stories.has("intro_%d"%chapter),"packed chapter voice ID: %d"%chapter)
	for stage:int in range(21):_check(stories.has("clear_%d"%stage),"packed stage-clear voice ID: %d"%stage)
	_check(stories.has("ending") and stories.get("clear_20",{}).get("path","")==stories.get("ending",{}).get("path","different"),"final stage reuses the exact ending narration")
	for entry:Dictionary in stories.values():
		var path:String=str(entry.get("path",""))
		_check(not tracks.has(path) or tracks[path]==false,"a narration file never doubles as background music")
		tracks[path]=false
	_check(tracks.size()==38,"PCK manifest resolves to exactly38 unique audio streams")
	for path:String in tracks:
		var looping:bool=tracks[path]
		_check(path.begins_with("res://assets/audio_v13/") and path.ends_with(".mp3"),"packed audio is local MP3: "+path.get_file())
		_check(ResourceLoader.exists(path),"imported stream resource is present in PCK: "+path.get_file())
		var stream:AudioStream=audio._load_stream(path,looping)
		_check(stream is AudioStreamMP3 and stream.get_length()>1.0,"MP3 header and duration decode: "+path.get_file())
		if not stream is AudioStreamMP3:continue
		_check(stream.loop==looping,"runtime loop mode matches music/voice: "+path.get_file())
		var playback:AudioStreamPlayback=stream.instantiate_playback()
		_check(playback!=null,"native MP3 playback decoder instantiates: "+path.get_file())
		if playback==null:continue
		var peak:float=0.0
		var finite:bool=true
		for position:float in [0.5,2.0,stream.get_length()*0.5]:
			playback.start(minf(position,stream.get_length()*0.5))
			var frames:PackedVector2Array=playback.mix_audio(1.0,16384)
			for frame:Vector2 in frames:
				finite=finite and is_finite(frame.x) and is_finite(frame.y)
				peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)))
			playback.stop()
			if peak>0.000001:break
		_check(finite and peak>0.000001,"actual MP3 samples decode to finite non-silent PCM: "+path.get_file())
		playback.start(maxf(0.0,stream.get_length()-0.025))
		playback.mix_audio(1.0,16384)
		if looping:
			_check(playback.is_playing() and playback.get_playback_position()<stream.get_length()*0.5,"music actually wraps across its end: "+path.get_file())
			music_count+=1
		else:
			_check(not playback.is_playing(),"voice actually ends instead of looping: "+path.get_file())
			voice_count+=1
		playback.stop()
	_check(music_count==10 and voice_count==28,"ten looping music streams and28 non-looping narration streams verified")

func _capture()->void:
	var path:String=OS.get_environment("STARLAN_QA_PNG")
	if path.is_empty() or DisplayServer.get_name()=="headless":return
	await _frames(10)
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(path)==OK,"actual packed story screenshot saved")

func _record_mix(manifest:Dictionary)->void:
	var effect:AudioEffectRecord=AudioEffectRecord.new()
	effect.format=AudioStreamWAV.FORMAT_16_BITS
	var effect_index:int=AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0,effect)
	audio.set_region(0);audio.set_volume("music",0.65);audio.set_volume("voice",1.0)
	effect.set_recording_active(true)
	await create_timer(2.0,true).timeout
	var entry:Dictionary=manifest.stories.intro_0
	game.ui.show_dialog("星灯岛 · 伙伴的旅程",str(entry.text),"继续旅程",func():pass,"intro_0",str(entry.text))
	await create_timer(6.0,true).timeout
	game.ui._close_dialog()
	await create_timer(2.0,true).timeout
	effect.set_recording_active(false)
	var recording:AudioStreamWAV=effect.get_recording()
	_check(recording!=null and recording.get_length()>8.5,"real Master bus captured ten-second music/voice/duck mix")
	if recording!=null:
		_check(recording.save_to_wav(OS.get_environment("STARLAN_QA_WAV"))==OK,"native game mix WAV saved")
	AudioServer.remove_bus_effect(0,effect_index)

func _count_callback()->void:callbacks+=1

func _json(path:String)->Dictionary:
	if not FileAccess.file_exists(path):return {}
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func _frames(count:int)->void:
	for index:int in range(count):await process_frame

func _check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);printerr("PACKED AUDIO FAILURE: "+message)

func _finish()->void:
	if failures.is_empty():
		print("PACKED V1.3 AUDIO VERIFIED: %d checks; %d looping music + %d non-looping voices decode real PCM, licenses/JSON packed, actual story Skip callback once"%[checks,music_count,voice_count])
	else:printerr("PACKED V1.3 AUDIO FAILED: %d / %d checks"%[failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
