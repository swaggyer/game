"""Restore armature modifiers on converted costume pieces and verify pose motion."""
from pathlib import Path
import bpy,json,sys
from mathutils import Vector
HERE=Path(__file__).resolve().parent
scope={'__file__':str(HERE/'build_starlight_characters.py'),'__name__':'starlight_helpers'}
exec(compile((HERE/'build_starlight_characters.py').read_text(encoding='utf-8'),str(HERE/'build_starlight_characters.py'),'exec'),scope)
for key in ['wangzai','xiaomantou']:
 bpy.ops.wm.open_mainfile(filepath=str(HERE/key/(key+'.blend')))
 scene=bpy.context.scene;root=bpy.data.objects[key];scope['rest'](root)
 objects=[o for o in scene.objects if o.type=='MESH' and o.parent==root]
 repaired=[]
 for o in objects:
  assert o.vertex_groups,'Mesh lacks skin groups: '+o.name
  if not any(m.type=='ARMATURE' for m in o.modifiers):
   m=o.modifiers.new('Restored_costume_skin','ARMATURE');m.object=root;repaired.append(o.name)
  for m in o.modifiers:
   if m.type=='ARMATURE':m.object=root
 root['skin_qa']='Every costume/head mesh has live skin modifier. Curve conversion selection isolated in builder; converted static parts restored.'
 # Evaluate a representative boot cuff in rest vs animated stride.
 def center(o):
  dg=bpy.context.evaluated_depsgraph_get();e=o.evaluated_get(dg);me=e.to_mesh();v=sum((e.matrix_world@p.co for p in me.vertices),Vector())/len(me.vertices);e.to_mesh_clear();return v
 cuff=bpy.data.objects['Cream_boot_cuff.L'];a=center(cuff)
 root.animation_data.action=bpy.data.actions['run'];root.animation_data.action_slot=root.animation_data.action.slots[0];scene.frame_set(1);bpy.context.view_layer.update();b=center(cuff)
 assert (a-b).length>.04,('Cuff failed animation test',list(a),list(b))
 skinqa={'repaired_meshes':repaired,'all_meshes_have_armature':all(any(m.type=='ARMATURE' for m in o.modifiers) for o in objects),'boot_cuff_rest_center':list(a),'boot_cuff_run_center':list(b),'boot_cuff_displacement':(a-b).length}
 scope['rest'](root)
 bpy.ops.wm.save_as_mainfile(filepath=str(HERE/key/(key+'.blend')))
 # Merged runtime model and LOD; preserve all five original bone actions.
 bpy.ops.object.select_all(action='DESELECT');copies=[]
 for o in objects:
  cp=o.copy();cp.data=o.data.copy();scene.collection.objects.link(cp);cp.select_set(True);copies.append(cp)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();runtime=bpy.context.object;runtime.name=key+'_SkinnedMesh';root.select_set(True);bpy.context.view_layer.objects.active=root
 options=dict(export_format='GLB',use_selection=True,export_cameras=False,export_lights=False,export_extras=True,export_animations=True,export_animation_mode='ACTIONS',export_nla_strips=True,export_frame_range=False,export_force_sampling=True,export_skins=True,export_def_bones=True,export_morph=False,export_apply=True,export_armature_object_remove=False,export_leaf_bone=False,export_influence_nb=4)
 bpy.ops.export_scene.gltf(filepath=str(HERE/key/(key+'.glb')),**options)
 root.select_set(False);runtime.data=runtime.data.copy();bpy.context.view_layer.objects.active=runtime
 d=runtime.modifiers.new('Mobile_LOD1','DECIMATE');d.ratio=min(.52,45000/sum(len(p.vertices)-2 for p in runtime.data.polygons));bpy.ops.object.modifier_apply(modifier=d.name)
 lodtris=sum(len(p.vertices)-2 for p in runtime.data.polygons);root.select_set(True);bpy.context.view_layer.objects.active=root
 bpy.ops.export_scene.gltf(filepath=str(HERE/key/(key+'-lod1.glb')),**options);bpy.data.objects.remove(runtime,do_unlink=True)
 report_path=HERE/'reports'/(key+'.json');report=json.loads(report_path.read_text(encoding='utf-8'));report['skin_qa']=skinqa;report['lod1']['triangles']=lodtris;report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 # Re-render the bone cycle after repair. Static rest renders remain identical.
 cam=scene.camera;s=root.scale.x;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=4;scene.cycles.use_denoising=True;scene.render.use_persistent_data=True
 scene.render.resolution_x=256;scene.render.resolution_y=320;scene.render.resolution_percentage=100;scene.render.film_transparent=True;scene.render.image_settings.color_mode='RGBA'
 root.animation_data.action=bpy.data.actions['run'];root.animation_data.action_slot=root.animation_data.action.slots[0]
 for t in root.animation_data.nla_tracks:t.mute=True
 for name,pos in {'front':(0,-5,3.2),'back':(0,5,3.2),'left':(-5,0,3.2),'right':(5,0,3.2)}.items():
  cam.location=tuple(v*s for v in pos);scope['look_at'](cam,(0,0,.93*s));cam.data.ortho_scale=2.22*s
  for i,frame in enumerate([1,7,13,19]):
   scene.frame_set(frame);scene.render.filepath=str(HERE/'renders'/(key+'_walk_'+name+'_'+str(i).zfill(2)+'.png'));bpy.ops.render.render(write_still=True);print('SKIN_QA_FRAME',key,name,i,flush=True)
 print('SKIN_QA_COMPLETE',key,len(repaired),flush=True)
