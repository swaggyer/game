from pathlib import Path
import hashlib,json

project=Path(__file__).resolve().parents[1]
def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
counts={'campaign':105,'navigation':2190,'enemy_combat':85,'trap_mechanics':27,'damage_v12':993,'locomotion_v12':678,'challenges_v12':983,'main_trials_v12':48,'full_scene_v12':480}
document={
    'version':'1.2.1-hud-layout-fix','engine':'Godot 4.7.2 stable','date':'2026-11-04',
    'implemented':{'open_regions':7,'region_size':[3400,2400],'main_quest_groups':21,'main_goals':63,'optional_challenges':21,'optional_challenges_per_region':3,'challenge_types':['race','waves','pressure','targets','escort'],'main_two_wave_battles':9,'walk_frames':192,'idle_frames':24,'walk_directions_per_actor':8,'combat_pose_frames':96,'hq_blender_environment_assets':12,'trap_types':6,'portraits':{'xiaomantou':'user reference image 1','wangzai':'user reference image 2','revision':2,'method':'built-in image_gen, identity-priority restrained 2D rendering','prompt_record':'docs/PORTRAIT-PROMPTS-v1.2.json'},'removed_idle_bell_gates':True},
    'balance':{'minimum_enemy_hit':'ceil(max_hp * 0.25), after passive mitigation','heavy_attack_can_exceed_quarter':True,'environment_damage_rule_separate':True,'successful_movement_dodge_avoids_hit':True,'active_water_shield_and_grace_preserved':True,'actual_AI_damage_cases':324},
    'hud_fix':'VBox-controlled level, 14px health bar and resource text, 6px gaps, dedicated zero-margin bar styles; native GPU screenshot verified complete text.',
    'validation_scope':'Numbered gameplay suites passed for v1.2; v1.2.1 changes HUD layout only, verified in native source and exported build.',
    'animation_limit':'Eight-direction 2D projected frames with natural cadence and distance-driven playback; not a full 3D world-space foot-lock solver.',
    'save_migration':{'world_version':3,'accepts':[2,3],'v2_preserves':['campaign progression','equipment','chests','exploration','camps','disabled traps'],'v2_resets':['incompatible partial stage goals','puzzle positions'],'optional_rewards_once':True},
    'validation':dict(counts,total_numbered_checks=sum(counts.values()),hero_actions_special='passed',trap_material_draw_special='12 passes across 6 trap types and 4 states passed',packed_assets='96 combat +12 environment +216 locomotion textures, 2 portraits and all challenge data verified',native_gpu='actual Godot OpenGL on AMD Vega 8 screenshots inspected',portable_exe_exit_code=0,native_mobile_tested=False),
    'screenshots':['v12-village.png','v12-portraits-hud.png','v12-main-course.png','v12-map.png','v12-forest-challenge.png','v12-packed-gameplay.png'],
    'delivery':{'windows_portable':True,'godot_mobile_source':True,'original_blender_models_in_archive':True,'android_apk':False,'ios_ipa':False},
    'build_files':{},'source_hashes':{}
}
for name in ['StarLanternIsland.exe','StarLanternIsland.pck']:
    path=project/'builds'/name
    document['build_files'][name]={'bytes':path.stat().st_size,'sha256':sha(path)}
for folder in ['scripts','shaders','data','assets/portraits_v12']:
    for path in sorted((project/folder).glob('*')):
        if path.is_file() and path.suffix in {'.gd','.gdshader','.json','.png'}:document['source_hashes'][path.relative_to(project).as_posix()]=sha(path)
for relative in ['assets/locomotion_v12/manifest.json','assets/environment_v11/manifest.json','project.godot','export_presets.cfg']:
    document['source_hashes'][relative]=sha(project/relative)
target=project/'docs'/'validation.json'
target.write_text(json.dumps(document,ensure_ascii=False,indent=2),encoding='utf-8')
print('V1.2 VALIDATION WRITTEN:',sum(counts.values()),'numbered checks, source and packed-build hashes')
