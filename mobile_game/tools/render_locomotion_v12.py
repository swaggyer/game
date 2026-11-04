"""Grounded eight-direction locomotion from original immutable 3D assets.

Run with Blender --background --python this_file.py [-- --only wangzai --dirs right]
Children: two-bone foot-target IK, heel/toe articulation and restrained arm swing.
Dragon: articulated upper/lower leg and paw transforms, diagonal stepping pairs,
folded wings, stabilized head and counterbalancing tail. No whole-sprite bobbing.
"""
from pathlib import Path
import sys, math, json, hashlib, subprocess

PROJECT=Path(__file__).resolve().parents[1]
BASE=PROJECT.parent/'source_models'
OUT=PROJECT/'assets'/'locomotion_v12';OUT.mkdir(parents=True,exist_ok=True)
RAW=OUT/'source';RAW.mkdir(exist_ok=True);(RAW/'.gdignore').write_text('',encoding='utf-8')
NAMES=['right','front_right','front','front_left','left','back_left','back','back_right']
CAMERA_XY=[(-5,0),(-3.5355,-3.5355),(0,-5),(3.5355,-3.5355),(5,0),(3.5355,3.5355),(0,5),(-3.5355,3.5355)]
SOURCES={k:BASE/'characters'/k/(k+'.blend') for k in ['wangzai','xiaomantou']}
SOURCES['little_dragon']=BASE/'creatures'/'creature_library.blend'

def normalize(key):
    from PIL import Image
    p=OUT/'manifest.json';m=json.loads(p.read_text(encoding='utf-8'));a=m['actors'][key]
    ref=Image.open(RAW/f'{key}_reference.png').convert('RGBA');b=ref.getbbox()
    ratio=180/max(1,b[3]-b[1]);width=320 if key=='little_dragon' else 240
    # Reserve room below the reference foot for an approaching heel/toe and
    # above the tallest diagonal dragon antler; every direction shares this.
    shift=(round(width*.5-ref.width*ratio*.5),round(227-b[3]*ratio))
    files=[v for rows in a['directions'].values() for v in rows]+list(a['idle'].values())
    for file in files:
        image=Image.open(RAW/file).convert('RGBA')
        image=image.resize((round(image.width*ratio),round(image.height*ratio)),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',(width,240));canvas.alpha_composite(image,shift)
        # Remove only invisible Lanczos ringing (<1.2% opacity); retain genuine
        # antialiased silhouettes and guarantee a transparent canvas border.
        canvas.putalpha(canvas.getchannel('A').point(lambda v:0 if v<3 else v))
        canvas.save(OUT/file,optimize=True)
    a.update({'canvas':[width,240],'body_height_px':180,'baseline':[width*.5,227],'normalization':{'source_reference_alpha':list(b),'scale':ratio,'translation':list(shift)}})
    # Pixel bounds and hashes make missing or flattened animation detectable.
    a['frame_sha256']={f:hashlib.sha256((OUT/f).read_bytes()).hexdigest() for f in files}
    a['alpha_bounds']={f:list(Image.open(OUT/f).getbbox()) for f in files}
    p.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
    print('LOCOMOTION_NORMALIZED',key,len(files),flush=True)

if '--normalize' in sys.argv:
    normalize(sys.argv[sys.argv.index('--normalize')+1]);raise SystemExit

import bpy
from mathutils import Vector,Matrix,Quaternion

def aim(camera,target):camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
def empty(name,parent=None,loc=(0,0,0)):
    o=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(o);o.parent=parent;o.location=loc;return o

def pose_bone(root,name,head,tail):
    b=root.pose.bones[name];rest=root.data.bones[name]
    q=(rest.tail_local-rest.head_local).rotation_difference(Vector(tail)-Vector(head))
    b.matrix=Matrix.Translation(head)@q.to_matrix().to_4x4()@rest.matrix_local.to_quaternion().to_matrix().to_4x4()
    bpy.context.view_layer.update()

def knee_solution(hip,ankle,l1,l2,pole):
    v=ankle-hip;d=min(max(v.length,.01),l1+l2-.002);axis=v.normalized()
    along=(l1*l1-l2*l2+d*d)/(2*d);height=math.sqrt(max(.00001,l1*l1-along*along))
    bend=Vector(pole)-axis*Vector(pole).dot(axis)
    if bend.length<.01:bend=Vector((0,-1,0))
    return hip+axis*along+bend.normalized()*height

def step(phase,stride=.42,lift=.105):
    phase%=1.0;stance=.62
    if phase<stance:
        f=phase/stance;y=-stride*.5+stride*f
        # Heel contact settles, then the ankle rises slightly for toe-off.
        z=.012*max(0,(f-.78)/.22)
        roll=math.radians(9*(1-f/.20)) if f<.20 else -math.radians(15)*max(0,(f-.78)/.22)
        return y,z,roll
    f=(phase-stance)/(1-stance);s=f*f*(3-2*f)
    return stride*.5-stride*s,lift*math.sin(math.pi*f),math.radians(-12+20*f)

def human_setup(key):
    bpy.ops.wm.open_mainfile(filepath=str(SOURCES[key]));r=bpy.data.objects[key];r.animation_data_clear()
    for b in r.pose.bones:b.rotation_mode='QUATERNION'
    return r

def human_pose(root,t,idle=False):
    for b in root.pose.bones:b.matrix_basis=Matrix.Identity(4)
    phase=t*math.tau
    # A slight walking pelvis settle gives the knee chain room to plant each
    # ankle without overextending its actual retained bone lengths.
    bob=0 if idle else -.035+.009*(math.cos(2*phase)-1)
    hip=root.pose.bones['Hips'];hip.location.z=bob
    hip.rotation_mode='XYZ';hip.rotation_euler=(0,0,0 if idle else math.radians(3.2)*math.sin(phase))
    spine=root.pose.bones['Spine'];spine.rotation_mode='XYZ';spine.rotation_euler=(math.radians(-1.5),0,0 if idle else -math.radians(1.6)*math.sin(phase))
    chest=root.pose.bones['Chest'];chest.rotation_mode='XYZ';chest.rotation_euler=(0,0,0 if idle else -math.radians(2.0)*math.sin(phase))
    head=root.pose.bones['Head'];head.rotation_mode='XYZ';head.rotation_euler=(math.radians(1.0),0,0 if idle else math.radians(.6)*math.sin(phase))
    for side,sign,offset in [('L',-1,0),('R',1,.5)]:
        swing=0 if idle else math.sin(phase+offset*math.tau)
        arm=root.pose.bones['UpperArm.'+side];arm.rotation_mode='XYZ';arm.rotation_euler=(math.radians(-3+12*swing),0,math.radians(-sign*2.0))
        fore=root.pose.bones['Forearm.'+side];fore.rotation_mode='XYZ';fore.rotation_euler=(math.radians(-10-5*max(0,-swing)),0,0)
        hand=root.pose.bones['Hand.'+side];hand.rotation_mode='XYZ';hand.rotation_euler=(math.radians(2*swing),0,0)
    bpy.context.view_layer.update()
    for side,sign,offset in [('L',-1,0),('R',1,.5)]:
        y,lift,roll=(0,0,0) if idle else step(t+offset)
        upper=root.data.bones['UpperLeg.'+side];lower=root.data.bones['LowerLeg.'+side]
        hip_point=root.pose.bones['UpperLeg.'+side].head.copy()
        ankle=Vector((sign*.145,y+.006,.125+lift))
        knee=knee_solution(hip_point,ankle,(upper.tail_local-upper.head_local).length,(lower.tail_local-lower.head_local).length,(0,-1,0))
        pose_bone(root,'UpperLeg.'+side,hip_point,knee)
        pose_bone(root,'LowerLeg.'+side,knee,ankle)
        # Plant the heel through stance, articulate toe-off and toe clearance.
        rest=root.data.bones['Foot.'+side];foot_vec=rest.tail_local-rest.head_local
        # Foot forward is -Y: negative X rotation raises the toes at heel strike.
        tail=ankle+Quaternion(Vector((1,0,0)),-roll)@foot_vec
        pose_bone(root,'Foot.'+side,ankle,tail)
    bpy.context.view_layer.update()

def dragon_setup():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCES['little_dragon']))
    r=bpy.data.objects['little_dragon'];keep=set([r,r.parent]+list(r.children_recursive))
    for o in list(bpy.context.scene.objects):
        if o not in keep and o.type not in ['LIGHT','CAMERA']:bpy.data.objects.remove(o,do_unlink=True)
    r.parent.location=(0,0,0);r.animation_data_clear();r.location=(0,0,0);r.rotation_euler=(0,0,0)
    for o in r.children_recursive:
        if o.animation_data:o.animation_data_clear()
    bpy.context.view_layer.update()
    parts=list(r.children_recursive);rest={o.name:o.matrix_world.copy() for o in parts}
    legs=[]
    for label,y in [('front',-.30),('rear',.61)]:
        for sign in [-1,1]:
            groups={'upper':[],'lower':[],'foot':[]}
            for o in parts:
                if not o.name.startswith(label+' '):continue
                if o.matrix_world.translation.x*sign<.05:continue
                if 'muscular haunch' in o.name:groups['upper'].append(o)
                elif 'broad paw' in o.name or 'ivory toe' in o.name:groups['foot'].append(o)
                else:groups['lower'].append(o)
            legs.append({'label':label,'sign':sign,'y':y,'groups':groups,'phase':0 if (label=='front' and sign<0) or (label=='rear' and sign>0) else .5})
    leg_names={o.name for leg in legs for group in leg['groups'].values() for o in group}
    tail=[o for o in parts if 'tail' in o.name]
    wings=[o for o in parts if 'wing_joint' in o.name]
    # Original wing articulation is retained but folded close to the shoulders.
    for o in wings:
        sign=-1 if o.name.startswith('L') else 1
        o.rotation_euler[1]=sign*.18;o.rotation_euler[2]=sign*.16
        o.scale=(.55,.55,.55)
    bpy.context.view_layer.update()
    # Wing children include their parent's fold in the preserved rest transform.
    rest={o.name:o.matrix_world.copy() for o in parts}
    return {'root':r,'parts':parts,'rest':rest,'legs':legs,'leg_names':leg_names,'tail':tail,'wings':wings}

def delta_matrix(a,b,target_a,target_b):
    q=(Vector(b)-Vector(a)).rotation_difference(Vector(target_b)-Vector(target_a))
    return Matrix.Translation(target_a)@q.to_matrix().to_4x4()@Matrix.Translation(-Vector(a))

def dragon_pose(data,t,idle=False):
    rest=data['rest'];phase=t*math.tau
    # Body rests on the feet; the head does not inherit the original idle bob.
    for o in data['parts']:o.matrix_world=rest[o.name].copy()
    if not idle:
        body_roll=Matrix.Translation((0,.2,.55))@Matrix.Rotation(math.radians(.8)*math.sin(phase),4,'Y')@Matrix.Translation((0,-.2,-.55))
        for o in data['parts']:
            if o.name in data['leg_names'] or 'wing' in o.name.lower() or 'rib' in o.name.lower():continue
            # Keep face/neck almost still, gently counter-rotate the tail.
            if o in data['tail']:
                tail_matrix=Matrix.Translation((0,.76,.53))@Matrix.Rotation(math.radians(5)*math.sin(phase),4,'Z')@Matrix.Translation((0,-.76,-.53))
                o.matrix_world=tail_matrix@rest[o.name]
            elif 'torso' in o.name or o.name.startswith('body overlapping'):
                o.matrix_world=body_roll@rest[o.name]
    for leg in data['legs']:
        sign,y=leg['sign'],leg['y'];a=Vector((sign*.28,y,.56));b=Vector((sign*.28,y,.31));c=Vector((sign*.30,y-.045,.15))
        shift,lift,roll=(0,0,0) if idle else step(t+leg['phase'],.27,.075)
        target_c=c+Vector((0,shift,lift));target_b=knee_solution(a,target_c,(b-a).length,(c-b).length,(0,1 if leg['label']=='front' else -1,0))
        upper=delta_matrix(a,b,a,target_b);lower=delta_matrix(b,c,target_b,target_c)
        foot=Matrix.Translation(target_c)@Matrix.Rotation(roll*.65,4,'X')@Matrix.Translation(-c)
        for kind,matrix in [('upper',upper),('lower',lower),('foot',foot)]:
            for o in leg['groups'][kind]:o.matrix_world=matrix@rest[o.name]
    bpy.context.view_layer.update()

def configure(scene,key,root):
    scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=320 if key=='little_dragon' else 240;scene.render.resolution_y=288
    scene.render.resolution_percentage=100;scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.use_persistent_data=True
    if hasattr(scene,'eevee') and hasattr(scene.eevee,'taa_render_samples'):scene.eevee.taa_render_samples=8
    # Remove library-only lights and keep the original character/creature palette.
    for o in list(scene.objects):
        if o.type=='LIGHT' and o.name.startswith('Library broad'):o.hide_render=True
    camera=scene.camera
    if key=='little_dragon':camera=bpy.data.objects['Creature portrait camera'];scene.camera=camera
    camera.data.type='ORTHO';camera.data.ortho_scale=(3.0 if key=='little_dragon' else 2.45*root.scale.x)
    return camera

def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    keys=args[args.index('--only')+1].split(',') if '--only' in args else list(SOURCES)
    dirs=args[args.index('--dirs')+1].split(',') if '--dirs' in args else NAMES
    force='--force' in args
    path=OUT/'manifest.json';manifest=json.loads(path.read_text(encoding='utf-8')) if path.exists() else {'version':'1.2','actors':{},'direction_convention':'actual screen-facing: right=+X, front=+Y/down; corrected Blender camera-side labels','phase_driver':'distance actually travelled; paused/stopped sprites do not cycle'}
    for key in keys:
        checksum=hashlib.sha256(SOURCES[key].read_bytes()).hexdigest()
        data=dragon_setup() if key=='little_dragon' else None
        root=data['root'] if data else human_setup(key);scene=bpy.context.scene;camera=configure(scene,key,root)
        pose=(lambda t,idle=False:dragon_pose(data,t,idle)) if data else (lambda t,idle=False:human_pose(root,t,idle))
        scale=1 if data else root.scale.x;target=(0,.15,.95) if data else (0,0,.93*scale)
        def cam(direction):
            x,y=CAMERA_XY[NAMES.index(direction)];camera.location=(x*scale,y*scale,(3.5 if data else 3.2)*scale);aim(camera,target);bpy.context.view_layer.update()
        cam('front');pose(0,True);scene.render.filepath=str(RAW/f'{key}_reference.png')
        if force or not Path(scene.render.filepath).exists():bpy.ops.render.render(write_still=True)
        actor=manifest['actors'].get(key,{});actor.update({'frames_per_direction':8,'directions':actor.get('directions',{}),'idle':actor.get('idle',{}),'step_length_world':{'wangzai':128,'xiaomantou':120,'little_dragon':98}[key],'stride_note':'Authored cadence distance for 2D screen movement; 3D-camera projection makes exact footplant stride shorter and direction-dependent. Distance-driven phase prevents stationary/collision skating, but this is not a full world-space foot-lock solver.','source_blend':str(SOURCES[key]),'source_sha256':checksum,'gait':'grounded two-bone IK heel contact / toeoff' if not data else 'four articulated legs, diagonally phased stance/swing, stable head and folded wings'})
        for direction in dirs:
            cam(direction);idle_name=f'{key}_idle_{direction}.png';actor['idle'][direction]=idle_name
            pose(0,True);scene.render.filepath=str(RAW/idle_name)
            if force or not Path(scene.render.filepath).exists():bpy.ops.render.render(write_still=True)
            files=[]
            for frame in range(8):
                name=f'{key}_walk_{direction}_{frame:02d}.png';files.append(name)
                if force or not (RAW/name).exists():
                    pose(frame/8);scene.render.filepath=str(RAW/name);bpy.ops.render.render(write_still=True)
                print('WALK_V12_FRAME',key,direction,frame,flush=True)
            actor['directions'][direction]=files
        assert checksum==hashlib.sha256(SOURCES[key].read_bytes()).hexdigest(),'Original asset changed'
        actor['source_unchanged']=True;manifest['actors'][key]=actor;path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
        subprocess.run(['E:/python/python.exe',str(Path(__file__).resolve()),'--normalize',key],check=True)
        manifest=json.loads(path.read_text(encoding='utf-8'))
        print('WALK_V12_COMPLETE',key,flush=True)

if __name__=='__main__':main()
