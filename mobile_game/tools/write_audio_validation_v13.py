from pathlib import Path
import hashlib,json

project=Path(__file__).resolve().parents[1]
def file_info(path):
    with path.open('rb') as stream:checksum=hashlib.file_digest(stream,'sha256').hexdigest()
    return {'bytes':path.stat().st_size,'sha256':checksum}
music=project/'assets/audio_v13/music/source/score_manifest.json'
voice=project/'assets/audio_v13/voice/production.json'
document={
    'version':'1.3.0-music-story','engine':'Godot 4.7.2 stable',
    'audio':{'region_music':7,'context_music':['title','battle','boss'],'music_files':10,'voice_files':28,'story_ids':29,'music_seconds':824.225,'voice_seconds':378.357,'offline_runtime':True,'replay_pause_skip':True,'duck_on_narration':True,'saved_volumes':['music','sfx','voice']},
    'validation':{'audio_runtime_and_assets':222,'story_ui':49,'actual_scene':269,'native_scene_with_capture':271,'packed_headless':355,'packed_native_gpu':358,'existing_full_story_regression':480,'tests_overlap_not_additive':True,'actual_phone_tested':False,'native_gpu':'AMD Vega 8 / OpenGL compatibility','packed_mix_sample':'docs/v13-packed-mix.wav'},
    'android':{'file':'StarLanternIsland-v1.3.0-arm64.apk','signed':True,'signature_v2':True,'signature_v3':True,'same_certificate_as_v121':True,'version_code':14,'min_sdk':24,'target_sdk':36,'architecture':'arm64-v8a','verified_audio_mappings':38},
    'ios':{'signed':False,'directly_installable':False,'architecture':'arm64','minimum_ios':'15.0','workflow':'https://github.com/swaggyer/game/actions/runs/41847735433'},
    'build_files':{},'audio_provenance':{},'source_hashes':{}
}
for relative in ['builds/android/StarLanternIsland-v1.3.0-arm64.apk','builds/StarLanternIsland.pck']:
    document['build_files'][relative]=file_info(project/relative)
for path in [music,voice]:document['audio_provenance'][path.relative_to(project).as_posix()]=file_info(path)
for relative in ['scripts/audio_director.gd','scripts/game_main.gd','scripts/mobile_ui.gd','data/audio_v13.json','project.godot','export_presets.cfg']:
    document['source_hashes'][relative]=file_info(project/relative)['sha256']
(project/'docs/AUDIO验证.json').write_text(json.dumps(document,ensure_ascii=False,indent=2),encoding='utf-8')
print('AUDIO VERIFICATION WRITTEN: ten music tracks,28 narration files,source+APK/PCK hashes')
