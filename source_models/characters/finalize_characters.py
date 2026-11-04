"""Final mesh QA polish, export, and consistent static/walk sprite renders."""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,sys
from mathutils import Vector
HERE=Path(__file__).resolve().parent
scope={'__file__':str(HERE/'build_starlight_characters.py'),'__name__':'starlight_functions'}
exec(compile((HERE/'build_starlight_characters.py').read_text(encoding='utf-8'),str(HERE/'build_starlight_characters.py'),'exec'),scope)

def front_y(x,z):
 rings=[(.79,.258,.170),(.85,.246,.171),(.94,.195,.156),(1.08,.230,.173),(1.23,.259,.178),(1.29,.249,.165),(1.34,.163,.125)]
 z=max(.79,min(1.34,z))
 for (a,rx,ry),(b,rxx,ryy) in zip(rings,rings[1:]):
  if a<=z<=b:
   f=(z-a)/(b-a);rx=rx+(rxx-rx)*f;ry=ry+(ryy-ry)*f
   return .008-ry*math.sqrt(max(.04,1-(x/rx)**2))-.004
 return -.17

def close_ends(o):
 bm=bmesh.new();bm.from_mesh(o.data);edges=[e for e in bm.edges if e.is_boundary]
 if edges:bmesh.ops.holes_fill(bm,edges=edges,sides=0)
 bm.to_mesh(o.data);bm.free();o.data.update()

for key in ['wangzai','xiaomantou']:
 bpy.ops.wm.open_mainfile(filepath=str(HERE/key/(key+'.blend')))
 scene=bpy.context.scene;root=bpy.data.objects[key];scope['ROOT']=root
 scope['rest'](root)
 gold=bpy.data.materials[key+'_aged_stargold'];cream=bpy.data.materials[key+'_ivory_linen'];gem=bpy.data.materials[key+'_living_starcrystal'];leather=bpy.data.materials[key+'_cocoa_leather']
 for o in scene.objects:
  if o.type=='MESH' and o.name.startswith('Quilt_embroidered_diamond'):
   for v in o.data.vertices:v.co.y=front_y(v.co.x,v.co.z)
  if o.type=='MESH' and o.name.startswith(('Cape_folded_hood','Hood_gold_binding')):close_ends(o)
 # Enamel kneepads and small embroidery align with the approved outfit.
 for side,suf in [(-1,'.L'),(1,'.R')]:
  scope['ball']('Final_soft_knee_pad'+suf,(side*.143,-.090,.459),(.069,.022,.052),cream,'LowerLeg'+suf)
  scope['star']('Final_knee_star'+suf,(side*.143,-.116,.459),.024,gold,'LowerLeg'+suf)
 if key=='xiaomantou':
  # A bell-lantern: cage above and actual bell below, matching concept silhouette.
  for name in ['Golden_echo_bell','Bell_wood_handle','Bell_clapper','Bell_star_charm']:
   o=bpy.data.objects.get(name)
   if o:
    for v in o.data.vertices:v.co.z-=.135
  cx,cy=.463,-.10
  for z in [.612,.746]:
   pts=[(cx+.066*math.cos(i/8*math.tau),cy+.066*math.sin(i/8*math.tau),z) for i in range(9)]
   scope['line']('Final_lantern_octagon',pts,.005,gold,'Hand.R')
  for i in range(8):
   a=i/8*math.tau;x=cx+.066*math.cos(a);y=cy+.066*math.sin(a)
   scope['line']('Final_lantern_rib',[(x,y,.612),(x,y,.72),(cx,cy,.766)],.004,gold,'Hand.R')
  scope['ball']('Final_lantern_glowing_star',(cx,cy,.676),(.029,.029,.046),gem,'Hand.R',16,8)
  pts=[(cx+.026*math.cos(i/24*math.tau),cy,.786+.026*math.sin(i/24*math.tau)) for i in range(25)]
  scope['line']('Final_lantern_handle_ring',pts,.004,gold,'Hand.R')
 # Apply non-armature finishing modifiers, retain independent editable pieces.
 objs=[o for o in scene.objects if o.type=='MESH' and o.parent==root]
 for o in objs:
  bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
  for m in list(o.modifiers):
   if m.type!='ARMATURE':
    try:bpy.ops.object.modifier_apply(modifier=m.name)
    except RuntimeError:pass
 for im in bpy.data.images:
  if im.source=='FILE':
   try:im.pack()
   except RuntimeError:pass
 bpy.ops.wm.save_as_mainfile(filepath=str(HERE/key/(key+'.blend')))
 bpy.ops.object.select_all(action='DESELECT');dups=[]
 for o in objs:
  cp=o.copy();cp.data=o.data.copy();scene.collection.objects.link(cp);cp.select_set(True);dups.append(cp)
 bpy.context.view_layer.objects.active=dups[0];bpy.ops.object.join();runtime=bpy.context.object;runtime.name=key+'_SkinnedMesh'
 root.select_set(True);bpy.context.view_layer.objects.active=root
 options=dict(export_format='GLB',use_selection=True,export_cameras=False,export_lights=False,export_extras=True,export_animations=True,export_animation_mode='ACTIONS',export_nla_strips=True,export_frame_range=False,export_force_sampling=True,export_skins=True,export_def_bones=True,export_morph=False,export_apply=True,export_armature_object_remove=False,export_leaf_bone=False,export_influence_nb=4)
 bpy.ops.export_scene.gltf(filepath=str(HERE/key/(key+'.glb')),**options)
 runtime.data=runtime.data.copy();root.select_set(False);bpy.context.view_layer.objects.active=runtime
 d=runtime.modifiers.new('Mobile_LOD1','DECIMATE');d.ratio=min(.52,45000/sum(len(p.vertices)-2 for p in runtime.data.polygons));bpy.ops.object.modifier_apply(modifier=d.name)
 lodtris=sum(len(p.vertices)-2 for p in runtime.data.polygons)
 root.select_set(True);bpy.context.view_layer.objects.active=root
 bpy.ops.export_scene.gltf(filepath=str(HERE/key/(key+'-lod1.glb')),**options)
 bpy.data.objects.remove(runtime,do_unlink=True)
 report_path=HERE/'reports'/(key+'.json');report=json.loads(report_path.read_text(encoding='utf-8'))
 report.update(triangles=sum(len(p.vertices)-2 for o in objs for p in o.data.polygons),vertices=sum(len(o.data.vertices) for o in objs))
 report['lod1']['triangles']=lodtris;report['qa_polish']=['front embroidery follows actual cloth surface','closed hood roll end caps','ivory knee pads','bell-lantern cage added for younger character']
 report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 # Consistent final source and PNGs; alpha is rendered, not keyed out.
 cam=scene.camera;s=root.scale.x;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.use_denoising=True;scene.cycles.samples=8;scene.render.use_persistent_data=True
 views=[('preview',(2.5,-5,1.95),(0,0,.96),2.17,640,800),('front',(0,-5,3.2),(0,0,.93),2.22,512,640),('back',(0,5,3.2),(0,0,.93),2.22,512,640),('left',(-5,0,3.2),(0,0,.93),2.22,512,640),('right',(5,0,3.2),(0,0,.93),2.22,512,640)]
 for name,pos,target,ortho,rx,ry in views:
  cam.location=tuple(v*s for v in pos);scope['look_at'](cam,tuple(v*s for v in target));cam.data.ortho_scale=ortho*s
  scene.render.resolution_x=rx;scene.render.resolution_y=ry;scene.render.filepath=str(HERE/'renders'/(key+'_'+name+'.png'))
  bpy.ops.render.render(write_still=True);print('FINAL_STATIC',key,name,flush=True)
 # Render four frames per direction with bone animation, not image warps.
 scene.cycles.samples=4;scene.render.resolution_x=256;scene.render.resolution_y=320
 for t in root.animation_data.nla_tracks:t.mute=True
 root.animation_data.action=bpy.data.actions['run']
 if root.animation_data.action.slots:root.animation_data.action_slot=root.animation_data.action.slots[0]
 files=[]
 for name,pos in {'front':(0,-5,3.2),'back':(0,5,3.2),'left':(-5,0,3.2),'right':(5,0,3.2)}.items():
  cam.location=tuple(v*s for v in pos);scope['look_at'](cam,(0,0,.93*s));cam.data.ortho_scale=2.22*s
  for i,frame in enumerate([1,7,13,19]):
   scene.frame_set(frame);scene.render.filepath=str(HERE/'renders'/(key+'_walk_'+name+'_'+str(i).zfill(2)+'.png'));bpy.ops.render.render(write_still=True);files.append(scene.render.filepath)
   print('FINAL_WALK',key,name,i,flush=True)
 (HERE/'reports'/(key+'-walk-sprites.json')).write_text(json.dumps({'asset_id':key,'source_action':'run','source_frames':[1,7,13,19],'playback_fps':8,'directions':['front','back','left','right'],'frame_size':[256,320],'alpha':True,'files':files},indent=2),encoding='utf-8')
 print('FINAL_CHARACTER_COMPLETE',key,flush=True)
