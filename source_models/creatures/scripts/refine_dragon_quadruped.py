"""Refine the three dragon stages to match the new four-legged design reference."""
import bpy, os, json, math
from mathutils import Vector
BASE=r'E:\game\StarLanternIsland\source_models\creatures'
source=open(os.path.join(BASE,'scripts','build_creatures.py'),encoding='utf-8').read()
exec(source.split('BUILDERS=[')[0])
# Load the real creature library after defining reusable mesh helpers.
bpy.ops.wm.open_mainfile(filepath=os.path.join(BASE,'creature_library.blend'))
scene=bpy.context.scene
names={'jade':'Jade dragon scales','jade_dark':'Deep jade accents','mint':'Mint wing membrane','cream':'Warm ivory belly','gold':'Brushed lantern brass','star':'Living amber starlight','cyan':'Cyan crystal glow','white':'Pearl eye whites','ink':'Soft midnight ink','iris':'Warm amber iris','pink':'Warm coral accents','purple':'Velvet shadow violet','purple_light':'Lilac shadow edges','blue':'Moon blue','bubble':'Pearlescent water body','wood':'Carved warm bark','wood_light':'Bark raised ridges','leaf':'Forest leaves','stone':'Weathered moon stone','stone_light':'Raised ivory stone','rust':'Oxidized windmill red','cloth':'Wind sail linen'}
M={k:bpy.data.materials[n] for k,n in names.items()}
ROOT=None

def tuft(name,pts,r,m='cream'):
    o=curve(name,pts,r,m)
    for i,p in enumerate(o.data.splines[0].bezier_points):p.radius=[.55,1,.08][min(i,2)]
    return o

def scale_plate(name,co,normal,size=(.075,.11,.02),color='jade'):
    normal=Vector(normal).normalized();co=Vector(co)
    rim=sphere(name+' brass edge',co,tuple(v*1.07 for v in size),'gold',16,10)
    rim.rotation_euler=normal.to_track_quat('Z','Y').to_euler()
    top=sphere(name+' enamel',co+normal*.012,size,color,16,10)
    top.rotation_euler=rim.rotation_euler

def quadruped_dragon(name,royal=False,elder=False):
    r,lay=root(name);jade='jade_dark' if elder else 'jade'
    # Long, four-legged silhouette with an upright young eastern-dragon neck.
    sphere('long jade torso',(0,.27,.54),(.36,.66,.35),jade,32,20)
    sphere('raised tapering dragon neck',(0,-.36,.90),(.265,.285,.57),jade,32,20)
    sphere('cream chest',(0,-.595,.83),(.215,.067,.43),'cream',28,18)
    for z in [.53,.68,.83,.98,1.13]:
        curve('cream chest segmented seam',[(-.155,-.60,z),(0,-.655,z-.035),(.155,-.60,z)],.009,'gold')
    # Front and rear legs are separately modeled; toes are integral small meshes.
    for s in [-1,1]:
        for y,label in [(-.30,'front'),(.61,'rear')]:
            sphere(label+' muscular haunch',(s*.28,y,.36),(.16,.19,.25),jade)
            capsule(label+' foreleg',(s*.28,y,.31),(s*.30,y-.045,.15),.10,jade)
            sphere(label+' broad paw',(s*.30,y-.10,.10),(.155,.225,.095),jade)
            for dx in [-.085,0,.085]:
                sphere(label+' ivory toe',(s*.30+dx,y-.294,.09),(.036,.054,.042),'cream',16,10)
    # Head: longer muzzle, cheek ruffs and expressive amber eyes.
    sphere('young dragon head',(0,-.56,1.35),(.39,.32,.31),jade,32,24)
    sphere('broad jade nose bridge',(0,-.79,1.28),(.255,.27,.145),jade,28,20)
    sphere('extended cream muzzle',(0,-.87,1.19),(.295,.25,.125),'cream',32,20)
    sphere('soft lower dragon jaw',(0,-.78,1.105),(.24,.19,.065),'cream',24,16)
    for s in [-1,1]:
        eye('amber dragon eye',s*.202,-.820,1.405,.115)
        curve('jade upper eyelid',[(s*.09,-.812,1.47),(s*.205,-.837,1.53),(s*.31,-.76,1.48)],.033,jade)
        curve('ivory expressive brow',[(s*.09,-.794,1.50),(s*.20,-.809,1.56),(s*.31,-.736,1.53)],.022,'cream')
        sphere('small nostril',(s*.11,-1.079,1.262),(.026,.012,.018),'jade_dark',16,10)
        for k in range(3):
            tuft('layered cream cheek mane',[(s*.26,-.77,1.18+k*.052),(s*.40,-.60,1.18+k*.07),(s*.46,-.45,1.24+k*.07)],.052)
        # Fanlike ears, kept broad enough to read at mobile sprite scale.
        ear=sphere('jade ear fin',(s*.386,-.46,1.48),(.16,.065,.17),jade)
        ear.rotation_euler.y=s*.55
        inside=sphere('cream ear fin',(s*.411,-.502,1.49),(.105,.019,.12),'cream');inside.rotation_euler.y=s*.55
        curve('branching brass antler',[(s*.245,-.45,1.57),(s*.30,-.41,1.80),(s*.40,-.37,1.94)],.055,'gold')
        curve('inner antler fork',[(s*.29,-.41,1.75),(s*.22,-.36,1.91),(s*.24,-.34,2.01)],.036,'gold')
        if royal or elder:
            curve('royal third antler fork',[(s*.34,-.39,1.85),(s*.49,-.28,2.01),(s*.55,-.28,2.06)],.033,'gold')
        curve('fine gold dragon whisker',[(s*.24,-1.00,1.20),(s*.45,-1.05,1.15),(s*.57,-.95,1.29)],.009,'gold')
    curve('subtle smiling mouth',[(-.23,-1.032,1.155),(0,-1.10,1.12),(.23,-1.032,1.155)],.010,'jade_dark')
    star('forehead star prism',(0,-.864,1.58),.088,'star',.035)
    # Ivory forelock and nape mane, with separately tapered strands.
    for dx,dz in [(-.11,0),(0,.08),(.11,0)]:
        tuft('ivory forehead forelock',[(dx,-.55,1.59),(dx*.6,-.49,1.78+dz),(dx*.5,-.37,1.84+dz)],.052)
    for z in [.74,.91,1.08,1.25,1.42,1.57]:
        tuft('flowing ivory nape mane',[(0,-.10,z),(0,.03,z+.07),(0,.23,z-.035)],.070)
    # Overlapping enamel scales with fine brass edges, sculpted as real geometry.
    for row,y in enumerate([-.02,.18,.38,.58,.76]):
        for col,phi in enumerate([-1.26,-.84,-.42,0,.42,.84,1.26]):
            phi+=.07 if row%2 else 0
            n=(math.sin(phi),0,math.cos(phi))
            co=(.355*math.sin(phi),y,.54+.335*math.cos(phi))
            scale_plate('body overlapping scale',co,n,(.079,.115,.019),jade)
    for row,z in enumerate([.64,.80,.96,1.12,1.27]):
        for phi in [-1.45,-.95,-.47,0,.47,.95,1.45]:
            n=(math.sin(phi),math.cos(phi),0)
            co=(.258*math.sin(phi),-.35+.266*math.cos(phi),z)
            scale_plate('neck overlapping scale',co,n,(.073,.085,.017),jade)
    # Sweeping tail behind the body, with a cream ridge and faceted star finial.
    curve('long rising dragon tail',[(0,.76,.53),(.22,1.10,.36),(.56,1.34,.40),(.78,1.39,.65),(.78,1.34,.81)],.095,jade)
    tuft('cream tail mane',[(.19,1.08,.44),(.45,1.24,.53),(.71,1.35,.70)],.045)
    for x,y,z in [(.20,1.10,.45),(.38,1.26,.46),(.58,1.36,.51)]:
        cone('tail gold dorsal scale',(x,y,z),(x+.015,y+.012,z+.11),.052,'gold')
    star('tail celestial star',(.78,1.34,.88),.16,'star',.04)
    for side in [-1,1]:
        w=wing(side,royal);w.location=(side*.27,.14,.90);w.scale=(.72,.72,.72)
    if royal or elder:
        curve('royal shoulder gorget',[(-.27,-.43,.95),(0,-.63,.90),(.27,-.43,.95)],.034,'gold')
        star('royal chest medallion',(0,-.66,.91),.10,'star')
        for side in [-1,1]:
            cloak=sphere('ivory shoulder mantle',(side*.315,.08,.84),(.075,.39,.17),'cream',24,16)
            for yy in [-.17,.00,.17,.30]:
                curve('mantle gold filigree',[(side*.37,yy,.82),(side*.38,yy+.05,.92),(side*.35,yy+.11,.92)],.008,'gold')
    if elder:
        for side in [-1,0,1]:
            tuft('long wise king beard',[(side*.10,-.91,1.10),(side*.15,-.80,.82),(side*.13,-.65,.64)],.055)
        for side in [-1,1]:
            tuft('long royal mane',[(side*.29,-.29,1.40),(side*.46,.05,1.22),(side*.48,.43,.91)],.10)
    animate_bob(r,.025,.017)
    return r,lay,2.7

manifest=json.load(open(os.path.join(BASE,'reports','manifest.json'),encoding='utf-8'))
for asset in manifest:
    if asset['id'] not in ['little_dragon','new_dragon_king','elder_dragon_king']:continue
    old=bpy.data.objects[asset['id']];layout=old.parent;layout_location=layout.location.copy()
    deleting=[old]+list(old.children_recursive)+[layout]
    for ob in deleting:bpy.data.objects.remove(ob,do_unlink=True)
    r,lay,h=quadruped_dragon(asset['id'],royal=asset['id']=='new_dragon_king',elder=asset['id']=='elder_dragon_king')
    for item in manifest:
        ob=bpy.data.objects.get(item['id'])
        if ob:visible(ob.parent,ob==r)
    scene.frame_set(1);bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT');selected=descendants(r)
    for ob in selected:ob.select_set(True)
    bpy.context.view_layer.objects.active=r
    bpy.ops.export_scene.gltf(filepath=asset['model'],export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='SCENE',export_frame_range=True,export_force_sampling=True,export_yup=True)
    cam=bpy.data.objects['Creature portrait camera'];scene.camera=cam
    target=Vector((0,.15,.95));cam.location=(3.4,-5.3,2.9);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=3.0
    scene.render.resolution_x=768;scene.render.resolution_y=768;scene.render.filepath=asset['preview'];bpy.ops.render.render(write_still=True)
    for dn,xy in [('front',(0,-1)),('back',(0,1)),('left',(-1,0)),('right',(1,0))]:
        if dn not in asset['sprites']:continue
        cam.location=(xy[0]*5,xy[1]*5,3.5);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=3.0
        scene.render.filepath=asset['sprites'][dn];bpy.ops.render.render(write_still=True)
    asset['mesh_objects']=sum(o.type=='MESH' for o in selected)
    asset['source_polygon_count']=sum(len(o.data.polygons) for o in selected if o.type=='MESH')
    asset['design_revision']='quadruped_elongated_muzzle_ivory_mane_layered_brass_scales'
    asset['reference']='concepts/dragon-board.png; simplified production mesh, not exact sculpt reproduction'
    asset['height_reference']=h
    lay.location=layout_location
    print('REFINED',asset['id'],flush=True)
for asset in manifest:visible(bpy.data.objects[asset['id']].parent,True)
scene.frame_set(1);bpy.context.view_layer.update();scene.camera=bpy.data.objects['Creature library overview']
scene.render.resolution_x=1600;scene.render.resolution_y=1200;scene.render.filepath=os.path.join(BASE,'renders','creature_library_overview.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BASE,'creature_library.blend'))
with open(os.path.join(BASE,'reports','manifest.json'),'w',encoding='utf-8') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
print('QUADRUPED_REFINEMENT_COMPLETE',flush=True)
