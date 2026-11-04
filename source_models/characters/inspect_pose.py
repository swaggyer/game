import bpy,json
from pathlib import Path
from mathutils import Vector
p=Path('E:/game/StarLanternIsland/source_models/characters')
bpy.ops.wm.open_mainfile(filepath=str(p/'wangzai/wangzai.blend'))
r=bpy.data.objects['wangzai'];r.animation_data.action=bpy.data.actions['run'];r.animation_data.action_slot=r.animation_data.action.slots[0]
for t in r.animation_data.nla_tracks:t.mute=True
bpy.context.scene.frame_set(1);dg=bpy.context.evaluated_depsgraph_get()
for n in ['Cream_boot_cuff.L','Cream_boot_cuff.R','Leather_round_boot.L','Leather_round_boot.R','Final_soft_knee_pad.L','Final_soft_knee_pad.R','Soft_boot_shaft.L','Soft_boot_shaft.R']:
 o=bpy.data.objects[n];e=o.evaluated_get(dg);me=e.to_mesh();c=sum((e.matrix_world@v.co for v in me.vertices),Vector())/len(me.vertices);e.to_mesh_clear();print(n,'CENTER',list(c),'GROUPS',[g.name for g in o.vertex_groups],'MODS',[(m.type,m.object.name if m.type=='ARMATURE' else '') for m in o.modifiers])
for n in ['UpperLeg.L','LowerLeg.L','Foot.L','UpperLeg.R','LowerLeg.R','Foot.R']:
 b=r.pose.bones[n];print('BONE',n,list(r.matrix_world@b.head),list(r.matrix_world@b.tail))
