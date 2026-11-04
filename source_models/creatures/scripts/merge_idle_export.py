import bpy, os, json
BASE=r'E:\game\StarLanternIsland\source_models\creatures'
bpy.ops.wm.open_mainfile(filepath=os.path.join(BASE,'creature_library.blend'))
scene=bpy.context.scene
manifest=json.load(open(os.path.join(BASE,'reports','manifest.json'),encoding='utf-8'))
for asset in manifest:
    root=bpy.data.objects[asset['id']];layout=root.parent;previous=layout.location.copy();layout.location=(0,0,0)
    scene.frame_set(1);bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
    for ob in [root]+list(root.children_recursive):ob.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=asset['model'],export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='SCENE',export_frame_range=True,export_force_sampling=True,export_yup=True)
    layout.location=previous
print('MERGED_IDLE_EXPORT_COMPLETE')
