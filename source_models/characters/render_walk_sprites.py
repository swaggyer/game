"""Render true-alpha four-direction run cycles from retained bone actions."""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).resolve().parent
OUT=HERE/'renders';OUT.mkdir(exist_ok=True)
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['wangzai','xiaomantou']
for key in args:
 bpy.ops.wm.open_mainfile(filepath=str(HERE/key/(key+'.blend')))
 scene=bpy.context.scene;root=bpy.data.objects[key];cam=scene.camera;s=root.scale.x
 scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=4;scene.cycles.use_denoising=True
 scene.render.use_persistent_data=True
 scene.render.resolution_x=256;scene.render.resolution_y=320;scene.render.resolution_percentage=100
 scene.render.film_transparent=True;scene.render.image_settings.color_mode='RGBA';scene.render.image_settings.file_format='PNG'
 for t in root.animation_data.nla_tracks:t.mute=True
 root.animation_data.action=bpy.data.actions['run']
 if hasattr(root.animation_data.action,'slots') and root.animation_data.action.slots:
  root.animation_data.action_slot=root.animation_data.action.slots[0]
 dirs={'front':(0,-5,3.2),'back':(0,5,3.2),'left':(-5,0,3.2),'right':(5,0,3.2)}
 files=[]
 for name,pos in dirs.items():
  cam.location=tuple(v*s for v in pos);aim(cam,(0,0,.93*s));cam.data.ortho_scale=2.22*s
  for i,frame in enumerate([1,7,13,19]):
   scene.frame_set(frame);scene.render.filepath=str(OUT/(key+'_walk_'+name+'_'+str(i).zfill(2)+'.png'))
   bpy.ops.render.render(write_still=True);files.append(scene.render.filepath);print('WALK_FRAME_OK',key,name,i,flush=True)
 (HERE/'reports'/(key+'-walk-sprites.json')).write_text(json.dumps({'asset_id':key,'source_action':'run','source_frames':[1,7,13,19],'playback_fps':8,'directions':list(dirs),'frame_size':[256,320],'alpha':True,'files':files},indent=2),encoding='utf-8')
 print('WALK_COMPLETE',key,flush=True)
