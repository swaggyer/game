"""Retarget the existing photo-UV child meshes into editable starlight adventurers.

Non-destructive: original models/photos are read-only. No synthetic replacement
face is used. Built with Blender 5.4; final GLBs preserve source armature/actions.
"""
from pathlib import Path
import bpy, math, json, hashlib, sys
from mathutils import Vector

HERE=Path(__file__).resolve().parent
RENDERS=HERE/'renders'; RENDERS.mkdir(parents=True,exist_ok=True)
REPORTS=HERE/'reports'; REPORTS.mkdir(exist_ok=True)
SOURCES={
 'wangzai':Path('E:/game/BlenderModels/v2/wangzai/wangzai.blend'),
 'xiaomantou':Path('E:/game/BlenderModels/v1/characters/xiaomantou.blend')}
ROOT=None

def mat(name,color,metal=0,rough=.6,glow=0):
 m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color[:3],1)
 s=m.node_tree.nodes.get('Principled BSDF');s.inputs['Base Color'].default_value=(*color[:3],1)
 s.inputs['Metallic'].default_value=metal;s.inputs['Roughness'].default_value=rough
 if glow:s.inputs['Emission Color'].default_value=(*color[:3],1);s.inputs['Emission Strength'].default_value=glow
 return m

def bind(ob,bone):
 ob.parent=ROOT
 g=ob.vertex_groups.new(name=bone);g.add(list(range(len(ob.data.vertices))),1,'REPLACE')
 a=ob.modifiers.new('Starlight_skin','ARMATURE');a.object=ROOT
 return ob

def mesh(name,vs,fs,material,bone=None,smooth=True):
 me=bpy.data.meshes.new(name+'_mesh');me.from_pydata(vs,[],fs);me.update()
 ob=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(ob)
 ob.data.materials.append(material)
 for p in me.polygons:p.use_smooth=smooth
 if bone:bind(ob,bone)
 return ob

def ball(name,loc,scale,material,bone,seg=32,rings=16):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,location=loc)
 ob=bpy.context.object;ob.name=name;ob.scale=scale
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 ob.data.materials.append(material)
 for p in ob.data.polygons:p.use_smooth=True
 return bind(ob,bone)

def tube(name,a,b,r,material,bone,r2=None):
 a,b=Vector(a),Vector(b)
 bpy.ops.mesh.primitive_cone_add(vertices=24,radius1=r,radius2=r if r2 is None else r2,depth=(a-b).length,location=(a+b)/2)
 o=bpy.context.object;o.name=name;o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 o.data.materials.append(material)
 bevel=o.modifiers.new('Rounded_fabric_edges','BEVEL');bevel.width=.012;bevel.segments=3
 for p in o.data.polygons:p.use_smooth=True
 return bind(o,bone)

def line(name,pts,r,material,bone):
 bpy.ops.object.select_all(action='DESELECT')
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.bevel_depth=r;cu.bevel_resolution=3
 cu.use_fill_caps=True
 sp=cu.splines.new('POLY');sp.points.add(len(pts)-1)
 for p,co in zip(sp.points,pts):p.co=(*co,1)
 ob=bpy.data.objects.new(name,cu);bpy.context.scene.collection.objects.link(ob)
 bpy.context.view_layer.objects.active=ob;ob.select_set(True)
 bpy.ops.object.convert(target='MESH');ob=bpy.context.object;ob.data.materials.append(material)
 ob.select_set(False);return bind(ob,bone)

def slab(name,outline,y,depth,material,bone,bevel=.01):
 n=len(outline);vs=[(x,y,z) for x,z in outline]+[(x,y+depth,z) for x,z in outline]
 fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 ob=mesh(name,vs,fs,material,bone,False)
 mod=ob.modifiers.new('Handcrafted_rounded_edges','BEVEL');mod.width=bevel;mod.segments=3
 mod=ob.modifiers.new('Soft_normals','WEIGHTED_NORMAL');mod.keep_sharp=True
 return ob

def star(name,center,r,material,bone,ydepth=.008):
 x,y,z=center;pts=[]
 for i in range(16):
  a=math.pi/2+i*math.tau/16;rad=(r if i%4==0 else r*.68) if i%2==0 else r*.27;pts.append((x+math.cos(a)*rad,z+math.sin(a)*rad))
 return slab(name,pts,y,ydepth,material,bone,.003)

def torso_tunic(cream,gold,cloth):
 rings=[(.79,.258,.170),(.85,.246,.171),(.94,.195,.156),(1.08,.230,.173),(1.23,.259,.178),(1.29,.249,.165),(1.34,.163,.125)]
 vs=[];n=64
 for z,rx,ry in rings:
  for j in range(n):
   a=j/n*math.tau;vs.append((rx*math.sin(a),ry*math.cos(a)+.008,z))
 fs=[]
 for i in range(len(rings)-1):
  for j in range(n):fs.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
 fs += [tuple(reversed(range(n))),tuple((len(rings)-1)*n+j for j in range(n))]
 ob=mesh('Ivory_woven_adventure_tunic',vs,fs,cream)
 ob.parent=ROOT
 # Weighted continuously through hips/spine/chest; no opaque full-body card.
 groups={b:ob.vertex_groups.new(name=b) for b in ['Hips','Spine','Chest']}
 for v in ob.data.vertices:
  z=v.co.z
  if z<.96:
   f=max(0,min(1,(z-.84)/.12));groups['Hips'].add([v.index],1-f,'REPLACE');groups['Spine'].add([v.index],f,'REPLACE')
  else:
   f=max(0,min(1,(z-1.04)/.17));groups['Spine'].add([v.index],1-f,'REPLACE');groups['Chest'].add([v.index],f,'REPLACE')
 mod=ob.modifiers.new('Weighted_cloth_skin','ARMATURE');mod.object=ROOT
 sub=ob.modifiers.new('Tailored_soft_surface','SUBSURF');sub.levels=1
 # Embroidered lower hem and a narrow open front-tab.
 line('Gold_tunic_hem',[(.263*math.sin(j/n*math.tau),.176*math.cos(j/n*math.tau)+.008,.802) for j in range(n+1)],.005,gold,'Hips')
 slab('Coloured_front_tab',[(-.070,1.32),(.070,1.32),(.064,.80),(0,.755),(-.064,.80)],-.182,.022,cloth,'Spine',.012)
 for x in [-.064,.064]:line('Tab_gold_piping',[(x,-.209,1.29),(x,-.209,.83),(0,-.209,.775)],.0035,gold,'Spine')

def cape(cloth,gold):
 nx,nz=32,20;vs=[]
 for iz in range(nz):
  t=iz/(nz-1);z=1.346-t*.49;w=.27+.075*math.sin(t*math.pi*.75)
  for ix in range(nx):
   u=-1+2*ix/(nx-1)
   x=w*u;y=.210+.13*t+.028*math.cos(u*math.pi*3)*math.sin(t*math.pi*.8)
   zz=z+.025*t*t*math.cos(u*math.pi*2)
   vs.append((x,y,zz))
 fs=[(j*nx+i,j*nx+i+1,(j+1)*nx+i+1,(j+1)*nx+i) for j in range(nz-1) for i in range(nx-1)]
 ob=mesh('Short_starlight_cape',vs,fs,cloth,'Chest')
 mod=ob.modifiers.new('Cloak_thickness','SOLIDIFY');mod.thickness=.008
 mod=ob.modifiers.new('Soft_cloak_folds','SUBSURF');mod.levels=1
 # Golden stitch travels round the silhouette of an actual folded mesh.
 for edge in [[vs[j*nx] for j in range(nz)],[vs[j*nx+nx-1] for j in range(nz)],[vs[(nz-1)*nx+i] for i in range(nx)]]:
  line('Cape_gold_edge',[(x,y+.008,z) for x,y,z in edge],.004,gold,'Chest')
 # Back emblem is a raised star set into the fabric, facing +Y.
 backstar=star('Cape_star_crest',(0,.356,1.09),.074,gold,'Chest')
 for v in backstar.data.vertices:v.co.y=.356+(.356-v.co.y)
 # Raised embroidered constellations and curling hem line echo the concept.
 for xx,zz,rr in [(-.22,1.02,.021),(.22,1.02,.021),(-.14,.94,.015),(.14,.94,.015),(-.105,1.21,.014),(.105,1.21,.014)]:
  st=star('Cape_small_constellation',(xx,.345,zz),rr,gold,'Chest')
  for v in st.data.vertices:v.co.y=.345+(.345-v.co.y)
 for side in [-1,1]:
  pts=[]
  for i in range(33):
   t=i/32;pts.append((side*(.035+.25*t),.355,.918+.016*math.sin(t*math.pi*3)))
  line('Cape_embroidered_vine',pts,.0026,gold,'Chest')
 # Rolled hood folded onto shoulders, modeled rather than image-projected.
 line('Cape_folded_hood',[(-.19,.12,1.35),(-.16,.22,1.30),(0,.264,1.29),(.16,.22,1.30),(.19,.12,1.35)],.029,cloth,'Chest')
 line('Hood_gold_binding',[(-.19,.135,1.372),(-.16,.24,1.319),(0,.285,1.31),(.16,.24,1.319),(.19,.135,1.372)],.004,gold,'Chest')

def belt_and_boots(leather,gold,cream,cloth):
 n=64;vs=[];fs=[]
 for z in [.905,.951]:
  for j in range(n):a=j/n*math.tau;vs.append((.205*math.sin(a),.169*math.cos(a)+.008,z))
 for j in range(n):fs.append((j,(j+1)%n,n+(j+1)%n,n+j))
 ob=mesh('Leather_waist_belt',vs,fs,leather,'Hips');mod=ob.modifiers.new('Belt_thickness','SOLIDIFY');mod.thickness=.014
 slab('Golden_belt_buckle',[(-.041,.956),(.041,.956),(.041,.900),(-.041,.900)],-.190,.016,gold,'Hips',.009)
 slab('Belt_buckle_inset',[(-.026,.946),(.026,.946),(.026,.910),(-.026,.910)],-.201,.009,cloth,'Hips',.005)
 for side,suf in [(-1,'.L'),(1,'.R')]:
  x=side*.145
  # Individually rigged leather boots replace the futuristic foot hardware.
  ball('Leather_round_boot'+suf,(x,-.080,.095),(.100,.164,.088),leather,'Foot'+suf)
  ball('Quiet_rubber_sole'+suf,(x,-.080,.032),(.103,.164,.028),leather,'Foot'+suf)
  tube('Soft_boot_shaft'+suf,(x,.002,.12),(x,-.002,.31),.086,leather,'LowerLeg'+suf,r2=.095)
  tube('Cream_boot_cuff'+suf,(x,-.002,.282),(x,-.002,.326),.101,cream,'LowerLeg'+suf)
  line('Boot_gold_seam'+suf,[(x-.064,-.098,.27),(x,-.109,.25),(x+.064,-.098,.27)],.003,gold,'LowerLeg'+suf)
  slab('Boot_strap'+suf,[(x-.085,.12),(x+.085,.12),(x+.085,.085),(x-.085,.085)],-.177,.016,cloth,'Foot'+suf,.005)
  ball('Boot_buckle'+suf,(x,-.192,.102),(.016,.006,.018),gold,'Foot'+suf,16,8)

def gear(key,cloth,gold,leather,gem,cream):
 for side,suf in [(-1,'.L'),(1,'.R')]:
  a=ROOT.data.bones['UpperArm'+suf].head_local;b=ROOT.data.bones['UpperArm'+suf].tail_local
  tube('Ivory_short_sleeve'+suf,a.lerp(b,.10),a.lerp(b,.62),.102,cream,'UpperArm'+suf,r2=.092)
  tube('Sleeve_embroidery'+suf,a.lerp(b,.56),a.lerp(b,.65),.097,gold,'UpperArm'+suf)
  ball('Ivory_round_pauldron'+suf,(side*.288,-.070,1.319),(.106,.055,.069),gold,'UpperArm'+suf)
  ball('Ivory_shoulder_inlay'+suf,(side*.288,-.106,1.319),(.092,.030,.057),cream,'UpperArm'+suf)
  star('Shoulder_star'+suf,(side*.288,-.139,1.32),.028,gold,'UpperArm'+suf)
  a=ROOT.data.bones['Forearm'+suf].head_local;b=ROOT.data.bones['Forearm'+suf].tail_local
  tube('Leather_wrist_bracer'+suf,a.lerp(b,.40),a.lerp(b,.94),.079,leather,'Forearm'+suf,r2=.071)
  tube('Bracer_gold_cuff'+suf,a.lerp(b,.41),a.lerp(b,.47),.081,gold,'Forearm'+suf)
  # Rounded shoulder clasps secure the cape.
  ball('Cape_shoulder_clasp'+suf,(side*.17,-.115,1.334),(.038,.018,.028),gold,'Chest')
  line('Cape_neck_cord'+suf,[(side*.17,-.132,1.337),(side*.085,-.157,1.308),(0,-.165,1.30)],.007,cloth,'Chest')
 star('Chest_star_setting',(0,-.217,1.23),.058,gold,'Chest',.018)
 ball('Starlight_chest_crystal',(0,-.240,1.235),(.022,.012,.032),gem,'Chest')
 if key=='wangzai':
  # A true mesh shield with dimensional rim and raised crest, bound to arm.
  x=-.515;z=1.03
  outline=[(x-.133,z+.17),(x+.133,z+.17),(x+.151,z+.080),(x+.128,z-.10),(x,z-.203),(x-.128,z-.10),(x-.151,z+.080)]
  slab('Starshield_outer_frame',outline,-.186,.040,gold,'Forearm.L',.018)
  inner=[(x+(px-x)*.86,z+(pz-z)*.86) for px,pz in outline]
  slab('Starshield_blue_enamel',inner,-.208,.025,cloth,'Forearm.L',.015)
  tube('Shield_back_leather_grip',(-.375,-.028,1.00),(-.515,-.135,1.00),.028,leather,'Forearm.L')
  star('Starshield_raised_star',(x,-.229,z+.01),.094,gold,'Forearm.L')
  ball('Starshield_heart',(x,-.247,z+.01),(.026,.013,.035),gem,'Forearm.L')
  for i in [-1,1]:ball('Shield_rivet',(x+i*.103,-.223,z+.115),(.010,.007,.010),gold,'Forearm.L',12,8)
 else:
  # Rotational bell mesh, closed lip and freely visible clapper; no flat image.
  cx,cy,cz=.463,-.10,.677;vs=[];fs=[];n=48
  rings=[(.000,.074),(.018,.073),(.031,.057),(.048,.047),(.071,.045),(.088,.061)]
  for height,r in rings:
   for j in range(n):a=j/n*math.tau;vs.append((cx+r*math.cos(a),cy+r*math.sin(a),cz+height))
  for k in range(len(rings)-1):
   for j in range(n):fs.append((k*n+j,k*n+(j+1)%n,(k+1)*n+(j+1)%n,(k+1)*n+j))
  fs.append(tuple(reversed(range(n))))
  bell=mesh('Golden_echo_bell',vs,fs,gold,'Hand.R');mod=bell.modifiers.new('Bell_shell','SOLIDIFY');mod.thickness=.004
  tube('Bell_wood_handle',(cx,cy,cz+.085),(cx,cy,cz+.143),.016,leather,'Hand.R')
  ball('Bell_clapper',(cx,cy,cz-.004),(.018,.018,.024),gold,'Hand.R')
  star('Bell_star_charm',(cx,cy-.076,cz+.046),.024,gem,'Hand.R')
 # Small utility pouch: both heroes carry supplies, not modern machinery.
 x=.211 if key=='wangzai' else -.211
 ball('Leather_supplies_pouch',(x,.021,.858),(.062,.086,.083),leather,'Hips')
 ball('Pouch_round_closure',(x,-.063,.874),(.013,.006,.014),gold,'Hips',16,8)
 # Delicate quilt stitches on the tunic front; static embroidered mesh details.
 for row in range(4):
  z=.99+row*.074
  for x in [-.165,.165]:
   line('Quilt_embroidered_diamond',[(x,-.173,z+.034),(x+.027,-.180,z),(x,-.185,z-.034),(x-.027,-.180,z),(x,-.173,z+.034)],.0018,gold,'Chest' if z>1.08 else 'Spine')
 # Small waist crystal and a chest-to-waist leather strap.
 line('Diagonal_leather_satchel_strap',[(-.17,-.178,1.31),(-.07,-.201,1.16),(.05,-.199,1.03),(.18,-.178,.94)],.015,leather,'Chest')
 star('Strap_star_buckle',(-.084,-.220,1.18),.021,gold,'Chest')

def fine_hair_tips(key):
 """Add irregular closed hair tufts over preserved source haircut silhouette."""
 import random
 rng=random.Random(741 if key=='wangzai' else 731)
 hair=bpy.data.materials.get('Hair_black')
 # These tiny tapered locks follow the visible front/crown and leave facial UVs.
 for i in range(41):
  u=-1+2*i/40;x=.148*u
  z=1.718+.012*abs(u)+rng.uniform(-.008,.008)
  y=-.157*math.sqrt(max(.05,1-u*u))
  base=(x,y+.007,z+.045);tip=(x+rng.uniform(-.009,.009),y-.005,z-rng.uniform(.005,.020))
  tube('Fine_fringe_'+str(i),base,tip,.0034,hair,'Head',r2=.0004)
 for i in range(22):
  a=rng.uniform(-math.pi,math.pi);r=rng.uniform(.035,.105)
  x=math.sin(a)*r;y=.025+math.cos(a)*r;z=1.865-.20*r
  tube('Crown_flyaway_'+str(i),(x,y,z),(x+rng.uniform(-.009,.009),y+rng.uniform(-.008,.008),z+rng.uniform(.010,.021)),.0023,hair,'Head',r2=.0001)

def setup_studio(root):
 scene=bpy.context.scene
 for o in list(scene.objects):
  if o.parent!=root and o!=root:bpy.data.objects.remove(o,do_unlink=True)
 scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True
 scene.render.resolution_x=720;scene.render.resolution_y=900;scene.render.resolution_percentage=100
 scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.film_transparent=True
 scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
 if not scene.world:scene.world=bpy.data.worlds.new('Starlight_world')
 scene.world.use_nodes=True;bg=scene.world.node_tree.nodes.get('Background');bg.inputs['Color'].default_value=(.30,.36,.42,1);bg.inputs['Strength'].default_value=.4
 for name,loc,energy,size,color in [('Warm_key',(-2.7,-4,4.5),380,4,(1,.86,.70)),('Sky_fill',(3,-2,3),240,4,(.70,.86,1)),('Moon_rim',(.7,3,3.8),500,3,(.70,.90,1))]:
  d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.shape='DISK';d.size=size;d.color=color
  o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;look_at(o,(0,0,.72))
 d=bpy.data.cameras.new('Starlight_asset_camera');cam=bpy.data.objects.new('Starlight_asset_camera',d);scene.collection.objects.link(cam)
 d.type='ORTHO';scene.camera=cam
 return scene,cam

def look_at(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()

def rest(root):
 if root.animation_data:
  root.animation_data.action=None
  for t in root.animation_data.nla_tracks:t.mute=True
 for p in root.pose.bones:p.rotation_euler=(0,0,0);p.location=(0,0,0);p.scale=(1,1,1)
 bpy.context.scene.frame_set(1);bpy.context.view_layer.update()

def main(key):
 global ROOT
 src=SOURCES[key];bpy.ops.wm.open_mainfile(filepath=str(src))
 ROOT=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');ROOT.name=key
 rest(ROOT)
 head=bpy.data.objects['Continuous_sculpted_head']
 head_hash=hashlib.sha256(bytes(str([(tuple(v.co)) for v in head.data.vertices]),'utf-8')).hexdigest()
 keep=('Continuous_flexible_body','Continuous_sculpted_head','Anatomical_ear','Natural_helix','Sculpted_ear','Ear_','Hair_','Short_hair','Sculpted_hair','Eye_','Glove_palm','Finger_','Thumb')
 for o in list(bpy.context.scene.objects):
  if o.type=='MESH' and o.parent==ROOT and not o.name.startswith(keep):bpy.data.objects.remove(o,do_unlink=True)
 # Retained source face/hair geometry and UVs are intentionally unchanged.
 color=(.012,.060,.082) if key=='wangzai' else (.62,.175,.026)
 cloth=mat(key+'_woven_cape',color,rough=.88)
 cream=mat(key+'_ivory_linen',(.78,.694,.52),rough=.84)
 gold=mat(key+'_aged_stargold',(.65,.36,.095),metal=.62,rough=.32)
 leather=mat(key+'_cocoa_leather',(.11,.050,.025),rough=.72)
 pants=mat(key+'_adventure_trousers',(.105,.065,.039) if key=='wangzai' else (.67,.57,.41),rough=.86)
 gem=mat(key+'_living_starcrystal',(.08,.58,.88) if key=='wangzai' else (1,.30,.035),metal=.18,rough=.22,glow=.7)
 for o in list(bpy.context.scene.objects):
  if o.type=='MESH' and o.parent==ROOT:
   if o.name=='Continuous_flexible_body':
    o.data.materials.clear();o.data.materials.append(pants);o.data.materials.append(cream);o.data.materials.append(bpy.data.materials['Warm_skin'])
    for p in o.data.polygons:
     z=sum(o.data.vertices[j].co.z for j in p.vertices)/len(p.vertices)
     x=sum(abs(o.data.vertices[j].co.x) for j in p.vertices)/len(p.vertices)
     p.material_index=2 if z>1.329 else 1 if z>.96 or (x>.265 and z>.83) else 0
   elif o.name.startswith(('Glove_palm','Finger_','Thumb')):
    o.data.materials.clear();o.data.materials.append(leather if key=='wangzai' else bpy.data.materials['Warm_skin'])
 for m in bpy.data.materials:
  if 'Hair_' in m.name and m.use_nodes:
   s=m.node_tree.nodes.get('Principled BSDF');s.inputs['Roughness'].default_value=.66;s.inputs['Specular IOR Level'].default_value=.23
 torso_tunic(cream,gold,cloth);cape(cloth,gold);belt_and_boots(leather,gold,cream,cloth);gear(key,cloth,gold,leather,gem,cream);fine_hair_tips(key)
 ROOT['asset_id']=key;ROOT['story']='Star Lantern Island';ROOT['costume']='ivory woven tunic, gold embroidery, short colored cape, cocoa boots; starlight magical equipment'
 ROOT['face_preserved']='Existing complete sculpted head/approved baked facial UV texture retained unchanged; not a billboard or full-body image.'
 scene,cam=setup_studio(ROOT)
 scene.render.fps=24
 ROOT.animation_data.action=None
 # Apply geometric finishing modifiers to new pieces, keeping live armature.
 objs=[o for o in scene.objects if o.type=='MESH' and o.parent==ROOT]
 for o in objs:
  bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
  for mod in list(o.modifiers):
   if mod.type!='ARMATURE':
    try:bpy.ops.object.modifier_apply(modifier=mod.name)
    except RuntimeError:pass
 for image in bpy.data.images:
  if image.source=='FILE':
   try:image.pack()
   except RuntimeError:pass
 s=ROOT.scale.x;cam.data.ortho_scale=2.17*s;cam.location=(2.5*s,-5*s,1.95*s);look_at(cam,(0,0,.96*s))
 dest=HERE/key;dest.mkdir(exist_ok=True)
 bpy.ops.wm.save_as_mainfile(filepath=str(dest/(key+'.blend')))
 # Export a merged skinned copy: editable source retains named costume pieces,
 # runtime asset avoids hundreds of separate draw nodes.
 bpy.ops.object.select_all(action='DESELECT');copies=[]
 for o in objs:
  cp=o.copy();cp.data=o.data.copy();scene.collection.objects.link(cp);cp.select_set(True);copies.append(cp)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();runtime=bpy.context.object;runtime.name=key+'_SkinnedMesh'
 ROOT.select_set(True);bpy.context.view_layer.objects.active=ROOT
 export_options=dict(export_format='GLB',use_selection=True,export_cameras=False,export_lights=False,export_extras=True,export_animations=True,export_animation_mode='ACTIONS',export_nla_strips=True,export_frame_range=False,export_force_sampling=True,export_skins=True,export_def_bones=True,export_morph=False,export_apply=True,export_armature_object_remove=False,export_leaf_bone=False,export_influence_nb=4)
 bpy.ops.export_scene.gltf(filepath=str(dest/(key+'.glb')),**export_options)
 # Secondary mobile LOD, distinct from unmodified editable source.
 bpy.context.view_layer.objects.active=runtime;ROOT.select_set(False)
 runtime.data=runtime.data.copy()
 dec=runtime.modifiers.new('Mobile_LOD','DECIMATE');dec.ratio=min(.52,45000/max(1,sum(len(p.vertices)-2 for p in runtime.data.polygons)))
 bpy.ops.object.modifier_apply(modifier=dec.name)
 lodtris=sum(len(p.vertices)-2 for p in runtime.data.polygons)
 ROOT.select_set(True);bpy.context.view_layer.objects.active=ROOT
 bpy.ops.export_scene.gltf(filepath=str(dest/(key+'-lod1.glb')),**export_options)
 bpy.data.objects.remove(runtime,do_unlink=True)
 report={'asset_id':key,'source_blend':str(src),'blend':str(dest/(key+'.blend')),'glb':str(dest/(key+'.glb')),'lod1':{'glb':str(dest/(key+'-lod1.glb')),'triangles':lodtris},'bones':len(ROOT.data.bones),'actions':[a.name for a in bpy.data.actions],'vertices':sum(len(o.data.vertices) for o in objs),'triangles':sum(len(p.vertices)-2 for o in objs for p in o.data.polygons),'head_geometry_sha256':head_hash,'head_geometry_unchanged':head_hash==hashlib.sha256(bytes(str([tuple(v.co) for v in head.data.vertices]),'utf-8')).hexdigest(),'face_uv_layers':[u.name for u in head.data.uv_layers],'renders':[],'limitations':['Retained hand-parameterized source head/UV is an approximate likeness, not a 3D scan and not identical to the polished image-generation concept sheet.','Existing 18-bone idle/run/jump/slide/ride actions are retained; no facial rig, combat animation or cloth simulation is claimed.','Cape is a real static folded mesh bound to chest; source costume is re-authored, not a pixel-perfect replica of concept art.']}
 views=[('preview',(2.5,-5,1.95),(0,0,.96),2.17,720,900),('front',(0,-5,3.20),(0,0,.93),2.22,512,640),('back',(0,5,3.20),(0,0,.93),2.22,512,640),('left',(-5,0,3.20),(0,0,.93),2.22,512,640),('right',(5,0,3.20),(0,0,.93),2.22,512,640)]
 for name,pos,target,ortho,rx,ry in views:
  cam.location=tuple(v*s for v in pos);look_at(cam,tuple(v*s for v in target));cam.data.ortho_scale=ortho*s
  scene.render.resolution_x=rx;scene.render.resolution_y=ry
  scene.render.filepath=str(RENDERS/(key+'_'+name+'.png'));bpy.ops.render.render(write_still=True)
  report['renders'].append(str(RENDERS/(key+'_'+name+'.png')));print('RENDER_OK',key,name,flush=True)
 (REPORTS/(key+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 print('CHARACTER_COMPLETE',key,report['triangles'],report['bones'],report['actions'],flush=True)

if __name__=='__main__':
 args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(SOURCES)
 for key in args:main(key)
