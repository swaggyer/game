import bpy,json
from pathlib import Path
out=Path('E:/game/StarLanternIsland/source_models/characters')
for key,path in [('wangzai','E:/game/BlenderModels/v2/wangzai/wangzai.blend'),('xiaomantou','E:/game/BlenderModels/v1/characters/xiaomantou.blend')]:
 bpy.ops.wm.open_mainfile(filepath=path)
 scene=bpy.context.scene
 d={'objects':[{ 'name':o.name,'type':o.type,'parent':o.parent.name if o.parent else None,'materials':[m.name if m else '' for m in o.data.materials] if o.type=='MESH' else [],'verts':len(o.data.vertices) if o.type=='MESH' else 0} for o in scene.objects],'materials':[m.name for m in bpy.data.materials],'actions':[a.name for a in bpy.data.actions],'armatures':[{ 'name':o.name,'scale':list(o.scale),'bones':[b.name for b in o.data.bones]} for o in scene.objects if o.type=='ARMATURE']}
 (out/(key+'-inspection.json')).write_text(json.dumps(d,indent=2),encoding='utf-8')
 print(key,len(d['objects']),len(d['actions']))
