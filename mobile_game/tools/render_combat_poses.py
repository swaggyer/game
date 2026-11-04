"""Render genuine bone-posed combat frames without modifying the source .blend.

E:/blender/blender.exe --background --python tools/render_combat_poses.py
Optional Blender args after --: --hero wangzai --limit 1 --cycles
The script also invokes the local Pillow runtime to normalize every frame to a
shared 240x240 canvas with a stable foot baseline and the existing idle height.
"""
from pathlib import Path
import sys, json, math, hashlib, subprocess

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT.parent / "source_models" / "characters"
OUT = PROJECT / "assets" / "actions"
RAW = OUT / "raw"
DIRECTIONS = {"front": (0,-5,3.2), "back": (0,5,3.2), "left": (-5,0,3.2), "right": (5,0,3.2)}
PHASES = ["windup", "contact", "followthrough", "recovery"]

def normalize():
    from PIL import Image
    manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    for hero, entry in manifest["heroes"].items():
        ref = Image.open(RAW / f"{hero}_reference.png").convert("RGBA")
        bounds = ref.getbbox()
        ratio = 180 / max(1, bounds[3] - bounds[1])
        # Keep all directions and all poses in one coordinate system. No per-pose
        # bounding-box trimming: raised arms and lunging feet remain animated.
        foot_y = bounds[3]
        raw_width, raw_height = ref.size
        for name in entry["frames"]:
            image = Image.open(RAW / name).convert("RGBA")
            scaled = image.resize((round(raw_width * ratio), round(raw_height * ratio)), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", (240, 240))
            x = round(120 - raw_width * ratio / 2)
            y = round(240 - foot_y * ratio)
            canvas.alpha_composite(scaled, (x, y))
            canvas.save(OUT / name, optimize=True)
        entry["normalization"] = {"idle_body_height":180,"canvas":[240,240],"foot_baseline":240,"scale":ratio,"reference_alpha_bounds":bounds}
    manifest["normalized"] = True
    (OUT / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    print("NORMALIZED_COMBAT_POSES", flush=True)

if "--normalize" in sys.argv:
    normalize()
    raise SystemExit(0)

import bpy
from mathutils import Vector

def aim(camera, target):
    camera.rotation_euler = (Vector(target)-camera.location).to_track_quat("-Z","Y").to_euler()

def material(name, color, metallic=0.0, glow=0.0):
    m=bpy.data.materials.new(name);m.use_nodes=True
    shader=next(n for n in m.node_tree.nodes if n.type=="BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value=(*color,1)
    shader.inputs["Metallic"].default_value=metallic
    shader.inputs["Roughness"].default_value=.35
    shader.inputs["Emission Color"].default_value=(*color,1)
    shader.inputs["Emission Strength"].default_value=glow
    return m

def rigid_mesh(name, vertices, faces, mat, root, bone="Hand.R"):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.materials.append(mat)
    o=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(o)
    o.parent=root
    group=o.vertex_groups.new(name=bone);group.add(list(range(len(vertices))),1,"REPLACE")
    modifier=o.modifiers.new("Combat_prop_bone_skin","ARMATURE");modifier.object=root
    bevel=o.modifiers.new("Soft_sword_edges","BEVEL");bevel.width=.006;bevel.segments=2
    return o

def add_sword(root):
    gold=material("Combat_sword_stargold",(.84,.57,.17),.7)
    blade=material("Combat_sword_ivory_glow",(.67,.93,1),.35,.7)
    leather=material("Combat_sword_wrapped_grip",(.16,.07,.025))
    x,y,z=.42,-.025,.745
    def prism(name,coords,thickness,mat):
        vs=[(x+px,y+side*thickness,z+pz) for side in [-1,1] for px,pz in coords]
        n=len(coords);fs=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
        fs += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        rigid_mesh(name,vs,fs,mat,root)
    prism("Combat_short_sword_blade",[(-.032,-.06),(.032,-.06),(.040,-.45),(0,-.56),(-.040,-.45)],.010,blade)
    prism("Combat_short_sword_guard",[(-.10,-.045),(.10,-.045),(.10,-.077),(-.10,-.077)],.025,gold)
    prism("Combat_short_sword_grip",[(-.018,.060),(.018,.060),(.018,-.035),(-.018,-.035)],.018,leather)

# Euler degrees are applied to actual retained armature bones. Poses have clear
# anticipation, contact, followthrough and recovery silhouettes for each combo.
WANGZAI = [
 [
  {"Hips":(0,0,-10),"Chest":(-5,0,-20),"UpperArm.R":(-90,-10,-55),"Forearm.R":(-72,0,0),"Hand.R":(0,0,-20),"UpperArm.L":(-35,0,15),"Forearm.L":(-35,0,0),"UpperLeg.L":(-8,0,-7),"UpperLeg.R":(12,0,8)},
  {"Hips":(0,0,7),"Chest":(-9,0,27),"UpperArm.R":(-76,5,37),"Forearm.R":(-12,0,0),"Hand.R":(0,0,20),"UpperArm.L":(-52,0,8),"Forearm.L":(-25,0,0),"UpperLeg.L":(-18,0,-8),"LowerLeg.R":(-12,0,0)},
  {"Chest":(-7,0,38),"UpperArm.R":(-38,0,65),"Forearm.R":(-25,0,0),"UpperArm.L":(-35,0,15),"Forearm.L":(-30,0,0)},
  {"Chest":(-2,0,8),"UpperArm.R":(-24,0,20),"Forearm.R":(-42,0,0),"UpperArm.L":(-20,0,5),"Forearm.L":(-20,0,0)},
 ],
 [
  {"Hips":(0,0,9),"Chest":(0,0,25),"UpperArm.R":(-30,0,65),"Forearm.R":(-75,0,-15),"UpperArm.L":(-35,0,10),"Forearm.L":(-30,0,0),"UpperLeg.R":(-13,0,8)},
  {"Hips":(0,0,-12),"Chest":(-10,0,-33),"UpperArm.R":(-92,0,-65),"Forearm.R":(-18,0,0),"Hand.R":(0,0,-25),"UpperArm.L":(-65,0,-18),"Forearm.L":(-20,0,0),"UpperLeg.L":(8,0,-10),"UpperLeg.R":(-22,0,10)},
  {"Chest":(-7,0,-42),"UpperArm.R":(-68,0,-78),"Forearm.R":(-15,0,0),"UpperArm.L":(-45,0,-12),"Forearm.L":(-30,0,0)},
  {"Chest":(0,0,-8),"UpperArm.R":(-30,0,-15),"Forearm.R":(-40,0,0),"UpperArm.L":(-20,0,0),"Forearm.L":(-25,0,0)},
 ],
 [
  {"Hips":(8,0,-8),"Chest":(12,0,-15),"UpperArm.L":(-92,0,25),"Forearm.L":(-68,0,12),"UpperArm.R":(-48,0,-55),"Forearm.R":(-65,0,0),"UpperLeg.L":(-25,0,-8),"LowerLeg.L":(-22,0,0),"UpperLeg.R":(-20,0,8),"LowerLeg.R":(-22,0,0)},
  {"Hips":(-10,0,0),"Chest":(-18,0,10),"UpperArm.L":(-100,0,-8),"Forearm.L":(-5,0,0),"UpperArm.R":(-70,0,-35),"Forearm.R":(-20,0,0),"UpperLeg.L":(-30,0,-8),"LowerLeg.L":(-10,0,0),"UpperLeg.R":(15,0,8)},
  {"Chest":(-14,0,16),"UpperArm.L":(-96,0,-18),"Forearm.L":(-12,0,0),"UpperArm.R":(-45,0,-20),"Forearm.R":(-30,0,0)},
  {"Chest":(-4,0,0),"UpperArm.L":(-45,0,10),"Forearm.L":(-40,0,0),"UpperArm.R":(-25,0,-10),"Forearm.R":(-35,0,0)},
 ],
]
XIAOMANTOU = [
 [
  {"Chest":(0,0,-12),"UpperArm.R":(-95,0,-35),"Forearm.R":(-65,0,-12),"Hand.R":(0,0,-30),"UpperArm.L":(-28,0,15),"Forearm.L":(-45,0,0)},
  {"Chest":(-7,0,18),"UpperArm.R":(-95,0,18),"Forearm.R":(-10,0,0),"Hand.R":(-25,0,35),"UpperArm.L":(-55,0,40),"Forearm.L":(-25,0,0),"UpperLeg.L":(-12,0,-5)},
  {"Chest":(-3,0,25),"UpperArm.R":(-65,0,42),"Forearm.R":(-24,0,0),"Hand.R":(25,0,-30),"UpperArm.L":(-35,0,30)},
  {"Chest":(0,0,5),"UpperArm.R":(-35,0,10),"Forearm.R":(-38,0,0),"UpperArm.L":(-20,0,15)},
 ],
 [
  {"Chest":(0,0,18),"UpperArm.R":(-75,0,45),"Forearm.R":(-70,0,0),"Hand.R":(15,0,28),"UpperArm.L":(-45,0,32)},
  {"Chest":(-9,0,-25),"UpperArm.R":(-105,0,-35),"Forearm.R":(-12,0,0),"Hand.R":(-20,0,-35),"UpperArm.L":(-70,0,48),"Forearm.L":(-20,0,0),"UpperLeg.R":(-12,0,6)},
  {"Chest":(-4,0,-32),"UpperArm.R":(-85,0,-52),"Forearm.R":(-28,0,0),"Hand.R":(20,0,25),"UpperArm.L":(-48,0,35)},
  {"Chest":(0,0,-8),"UpperArm.R":(-35,0,-10),"Forearm.R":(-40,0,0),"UpperArm.L":(-25,0,20)},
 ],
 [
  {"Chest":(5,0,-10),"UpperArm.R":(-148,0,-20),"Forearm.R":(-30,0,-5),"Hand.R":(-25,0,0),"UpperArm.L":(-110,0,40),"Forearm.L":(-45,0,0),"UpperLeg.L":(-15,0,-8),"LowerLeg.L":(-15,0,0),"UpperLeg.R":(-15,0,8),"LowerLeg.R":(-15,0,0)},
  {"Chest":(-8,0,0),"UpperArm.R":(-130,0,-48),"Forearm.R":(-5,0,0),"Hand.R":(25,0,30),"UpperArm.L":(-108,0,55),"Forearm.L":(-10,0,0)},
  {"Chest":(-5,0,12),"UpperArm.R":(-95,0,-65),"Forearm.R":(-20,0,0),"Hand.R":(-30,0,-25),"UpperArm.L":(-80,0,65),"Forearm.L":(-20,0,0)},
  {"Chest":(0,0,0),"UpperArm.R":(-42,0,-10),"Forearm.R":(-42,0,0),"UpperArm.L":(-35,0,20),"Forearm.L":(-30,0,0)},
 ],
]

def apply_pose(root, pose):
    for bone in root.pose.bones:
        bone.rotation_mode="XYZ";bone.location=(0,0,0);bone.rotation_euler=(0,0,0);bone.scale=(1,1,1)
    for name, angles in pose.items():
        root.pose.bones[name].rotation_euler=tuple(math.radians(v) for v in angles)
    bpy.context.view_layer.update()

def main():
    args=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    heroes=[args[args.index("--hero")+1]] if "--hero" in args else ["wangzai","xiaomantou"]
    limit=int(args[args.index("--limit")+1]) if "--limit" in args else 9999
    OUT.mkdir(parents=True,exist_ok=True);RAW.mkdir(exist_ok=True)
    manifest=json.loads((OUT/"manifest.json").read_text(encoding="utf-8")) if (OUT/"manifest.json").exists() else {"format":1,"engine":"Blender bone poses","phases":PHASES,"directions":list(DIRECTIONS),"heroes":{},"normalized":False}
    count=0
    for hero in heroes:
        src=SOURCE/hero/(hero+".blend");checksum=hashlib.sha256(src.read_bytes()).hexdigest()
        bpy.ops.wm.open_mainfile(filepath=str(src))
        scene=bpy.context.scene;root=bpy.data.objects[hero];root.animation_data_clear()
        scene.frame_set(1)
        scene.render.engine="CYCLES" if "--cycles" in args else "CYCLES" if bpy.app.background and "--cpu" in args else "BLENDER_EEVEE"
        if scene.render.engine=="CYCLES":
            scene.cycles.device="CPU";scene.cycles.samples=4;scene.cycles.use_denoising=True
        elif hasattr(scene,"eevee") and hasattr(scene.eevee,"taa_render_samples"):
            scene.eevee.taa_render_samples=16
        scene.render.resolution_x=240;scene.render.resolution_y=288;scene.render.resolution_percentage=100
        scene.render.film_transparent=True;scene.render.image_settings.color_mode="RGBA";scene.render.image_settings.file_format="PNG"
        scene.render.use_persistent_data=True
        if hero=="wangzai":add_sword(root)
        poses=WANGZAI if hero=="wangzai" else XIAOMANTOU
        cam=scene.camera;s=root.scale.x
        cam.location=Vector(DIRECTIONS["front"])*s;aim(cam,(0,0,.93*s));cam.data.ortho_scale=2.62*s
        apply_pose(root,{})
        scene.render.filepath=str(RAW/f"{hero}_reference.png");bpy.ops.render.render(write_still=True)
        entry={"source_blend":str(src),"source_sha256":checksum,"bone_poses":poses,"frames":[]}
        manifest["heroes"][hero]=entry
        for direction,position in DIRECTIONS.items():
            cam.location=Vector(position)*s;aim(cam,(0,0,.93*s))
            for combo,sequence in enumerate(poses):
                for phase,pose in enumerate(sequence):
                    if count>=limit:break
                    name=f"{hero}_attack_{combo}_{direction}_{phase}.png"
                    entry["frames"].append(name)
                    if not (RAW/name).exists():
                        apply_pose(root,pose)
                        scene.render.filepath=str(RAW/name);bpy.ops.render.render(write_still=True)
                    count+=1;print("COMBAT_POSE_OK",hero,direction,combo,PHASES[phase],flush=True)
                if count>=limit:break
            if count>=limit:break
        assert checksum==hashlib.sha256(src.read_bytes()).hexdigest(),"Source .blend changed"
        print("COMBAT_HERO_COMPLETE",hero,len(entry["frames"]),flush=True)
        (OUT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    subprocess.run(["E:/python/python.exe",str(Path(__file__).resolve()),"--normalize"],check=True)

if __name__=="__main__":main()
