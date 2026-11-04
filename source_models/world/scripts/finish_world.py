import bpy, sys
from pathlib import Path
ROOT=Path(r'E:\game\StarLanternIsland\source_models\world')
sys.path.insert(0,str(ROOT/'scripts'))
import build_world as lib

def fix():
    for o in bpy.context.scene.objects:
        if o.name.startswith('gate_crown_star'):o.location.y-=.21
        if o.name.startswith('throne_crown_star'):o.location.y-=.17
    bpy.context.view_layer.update()

# Refine the two crown stars so they sit in front of their supporting stonework.
for ident in ['star_gate','dragon_throne']:
    lib.clear_scene();bpy.ops.import_scene.gltf(filepath=str(ROOT/'props'/(ident+'.glb')))
    fix();objects=list(bpy.context.scene.objects)
    # Imported glTF becomes Z-up in Blender; objects retain their original transforms.
    lib.export_glb(ROOT/'props'/(ident+'.glb'),objects)
    lo,hi=lib.bounds(objects);from mathutils import Vector
    c=Vector([(lo[i]+hi[i])/2 for i in range(3)]);extent=max(hi[i]-lo[i] for i in range(3))
    s=lib.setup_render(True,(512,512),ortho=max(1.3,extent*1.6))
    s.camera.location=c+Vector((5,-8,6));s.camera.rotation_euler=(c-s.camera.location).to_track_quat('-Z','Y').to_euler()
    lib.render(ROOT/'renders'/(ident+'.png'))

for path in [ROOT/'world_library.blend', ROOT/'scenes'/'06_star_lantern_island.blend']:
    bpy.ops.wm.open_mainfile(filepath=str(path));fix();bpy.ops.wm.save_as_mainfile(filepath=str(path))
    if path.name=='world_library.blend':lib.render(ROOT/'renders'/'world_library.png')
    else:
        objects=[o for o in bpy.context.scene.objects if o.type in {'MESH','CURVE','EMPTY'} and not o.name.startswith('presentation_backdrop')]
        lib.export_glb(ROOT/'scenes'/'06_star_lantern_island.glb',objects)
        lib.render(ROOT/'renders'/'06_star_lantern_island.png')
print('FINISH_WORLD_DONE',flush=True)
