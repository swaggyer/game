import bpy, math, os, json
from mathutils import Vector, Matrix

BASE = r'E:\game\StarLanternIsland\source_models\creatures'
os.makedirs(BASE, exist_ok=True)
for p in ['models', 'renders', 'reports']:
    os.makedirs(os.path.join(BASE,p), exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE'
scene.render.threads_mode='FIXED'; scene.render.threads=2
scene.render.resolution_x=768;scene.render.resolution_y=768;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.render.film_transparent=True
scene.render.fps=24;scene.frame_start=1;scene.frame_end=48
scene.world.color=(.22,.25,.34)
scene.view_settings.view_transform='AgX'

def mat(name,c,metal=0,rough=.43,em=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*c,1);m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*c,1)
    bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
    if 'Coat Weight' in bs.inputs: bs.inputs['Coat Weight'].default_value=.18
    if em:
        bs.inputs['Emission Color'].default_value=(*c,1);bs.inputs['Emission Strength'].default_value=em
    return m

M={
'jade':mat('Jade dragon scales',(.10,.54,.49),.12),
'jade_dark':mat('Deep jade accents',(.027,.28,.29),.12),
'mint':mat('Mint wing membrane',(.32,.79,.65),.04,.52),
'cream':mat('Warm ivory belly',(.96,.81,.51),.03,.48),
'gold':mat('Brushed lantern brass',(.88,.53,.13),.68,.28),
'star':mat('Living amber starlight',(1,.65,.13),.18,.25,2.3),
'cyan':mat('Cyan crystal glow',(.12,.78,1),.2,.26,1.8),
'white':mat('Pearl eye whites',(.93,.98,.92),.05,.23),
'ink':mat('Soft midnight ink',(.014,.025,.055),.05,.31),
'iris':mat('Warm amber iris',(.86,.34,.04),.2,.24),
'pink':mat('Warm coral accents',(.92,.34,.29),0,.5),
'purple':mat('Velvet shadow violet',(.15,.07,.28),.12,.48),
'purple_light':mat('Lilac shadow edges',(.40,.22,.57),.12,.41),
'blue':mat('Moon blue',(.14,.37,.66),.17,.34),
'bubble':mat('Pearlescent water body',(.24,.70,.78),.3,.19),
'wood':mat('Carved warm bark',(.29,.16,.075),.05,.62),
'wood_light':mat('Bark raised ridges',(.48,.29,.12),.03,.57),
'leaf':mat('Forest leaves',(.24,.44,.17),.02,.54),
'stone':mat('Weathered moon stone',(.39,.45,.51),.18,.57),
'stone_light':mat('Raised ivory stone',(.66,.69,.65),.12,.48),
'rust':mat('Oxidized windmill red',(.54,.23,.13),.15,.52),
'cloth':mat('Wind sail linen',(.86,.75,.48),0,.65),
}
ROOT=None

def finish(o,name,m):
    o.name=name
    if m: o.data.materials.append(M[m] if isinstance(m,str) else m)
    if o.type=='MESH':
        for p in o.data.polygons:p.use_smooth=True
    if ROOT:o.parent=ROOT
    return o
def sphere(name,loc,scale,m,seg=24,rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,location=loc)
    o=bpy.context.object;o.scale=scale;return finish(o,name,m)
def ico(name,loc,scale,m,sub=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc)
    o=bpy.context.object;o.scale=scale;return finish(o,name,m)
def capsule(name,a,b,r,m,vertices=16):
    a,b=Vector(a),Vector(b);v=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r*.85,depth=v.length,location=(a+b)/2)
    o=bpy.context.object;o.rotation_euler=v.to_track_quat('Z','Y').to_euler();finish(o,name,m)
    sphere(name+' end A',a,(r,r,r),m,16,12);sphere(name+' end B',b,(r*.85,)*3,m,16,12)
    return o
def cone(name,a,b,r,m,r2=0,vertices=16):
    a,b=Vector(a),Vector(b);v=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r2,depth=v.length,location=(a+b)/2)
    o=bpy.context.object;o.rotation_euler=v.to_track_quat('Z','Y').to_euler();return finish(o,name,m)
def curve(name,pts,r,m):
    d=bpy.data.curves.new(name,'CURVE');d.dimensions='3D';d.resolution_u=16;d.bevel_depth=r;d.bevel_resolution=3;d.use_fill_caps=True
    s=d.splines.new('BEZIER');s.bezier_points.add(len(pts)-1)
    for p,co in zip(s.bezier_points,pts):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
    if any(word in name for word in ['horn','whisker','antler','tendril']):
        s.bezier_points[-1].radius=.12
    o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);return finish(o,name,m)
def cube(name,loc,scale,m,bevel=.08):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        be=o.modifiers.new('Soft carved edges','BEVEL');be.width=bevel;be.segments=3
        n=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return finish(o,name,m)
def crystal(name,loc,scale,m='cyan'):
    return ico(name,loc,scale,m,1)
def star(name,loc,r,m='star',depth=.04):
    x,y,z=loc; verts=[]
    for dy in [-depth/2,depth/2]:
        for i in range(10):
            a=math.pi/2+i*math.pi/5;rr=r if i%2==0 else r*.45
            verts.append((x+math.cos(a)*rr,y+dy,z+math.sin(a)*rr))
    faces=[tuple(range(9,-1,-1)),tuple(range(10,20))]
    for i in range(10):j=(i+1)%10;faces.append((i,j,j+10,i+10))
    d=bpy.data.meshes.new(name);d.from_pydata(verts,[],faces);d.update();o=bpy.data.objects.new(name,d);scene.collection.objects.link(o)
    finish(o,name,m);b=o.modifiers.new('Polished star edges','BEVEL');b.width=.018;b.segments=3;return o
def eye(name,x,y,z,s=.12,iris='iris'):
    sphere(name+' white',(x,y,z),(s,s*.35,s*1.08),'white')
    sphere(name+' iris',(x,y-s*.30,z),(s*.58,s*.17,s*.7),iris)
    sphere(name+' pupil',(x,y-s*.45,z),(s*.26,s*.10,s*.49),'ink')
    sphere(name+' highlight',(x-s*.14,y-s*.55,z+s*.28),(s*.15,s*.07,s*.18),'white',16,10)
def root(name):
    global ROOT
    lay=bpy.data.objects.new(name+'_presentation',None);scene.collection.objects.link(lay)
    ROOT=bpy.data.objects.new(name,None);scene.collection.objects.link(ROOT);ROOT.parent=lay
    return ROOT,lay
def descendants(ob):
    return [ob]+list(ob.children_recursive)
def visible(ob,state):
    for child in descendants(ob):child.hide_render=not state
def animate_bob(ob,amp=.055,tilt=.025):
    for fr,z,rz in [(1,0,0),(13,amp,tilt),(25,0,0),(37,amp,-tilt),(49,0,0)]:
        ob.location.z=z;ob.rotation_euler.z=rz
        ob.keyframe_insert(data_path='location',frame=fr);ob.keyframe_insert(data_path='rotation_euler',frame=fr)
    if ob.animation_data and ob.animation_data.action:ob.animation_data.action.name=ob.name+'_Idle_ObjectAnimation'
    scene.frame_set(1)

def wing(side,king=False):
    global ROOT
    pivot=bpy.data.objects.new(('R' if side>0 else 'L')+'_wing_joint',None);scene.collection.objects.link(pivot);pivot.parent=ROOT;pivot.location=(side*.36,.14,1.23)
    pts=[(0,0,0),(side*.34,.05,.48),(side*.77,.12,.60),(side*.67,-.01,.15),(side*.50,-.08,.02),(side*.24,-.10,.08)]
    d=bpy.data.meshes.new('scalloped_wing_membrane');d.from_pydata(pts,[],[tuple(range(6))]);d.update()
    o=bpy.data.objects.new('silky_mint_wing',d);scene.collection.objects.link(o);o.parent=pivot;o.data.materials.append(M['mint'])
    so=o.modifiers.new('Wing thickness','SOLIDIFY');so.thickness=.025
    be=o.modifiers.new('Wing soft edge','BEVEL');be.width=.025;be.segments=3
    for a,b in [(0,1),(1,2),(1,3),(1,4),(1,5)]:
        old=ROOT;ROOT=pivot;curve('golden wing rib',[pts[a],pts[b]],.025,'gold');ROOT=old
    for fr,ang in [(1,-.15*side),(13,.28*side),(25,-.15*side),(37,.28*side),(49,-.15*side)]:
        pivot.rotation_euler.y=ang;pivot.keyframe_insert(data_path='rotation_euler',frame=fr)
    if pivot.animation_data:pivot.animation_data.action.name=ROOT.name+'_WingFlap_'+str(side)
    return pivot

def dragon(name,king=False,elder=False):
    r,l=root(name)
    jade='jade_dark' if elder else 'jade'
    sphere('pear shaped dragon torso',(0,.08,.78),(.43,.34,.58),jade)
    sphere('ivory belly',(0,-.224,.74),(.30,.09,.42),'cream')
    for z in [.48,.65,.82,.99]:curve('belly segmented groove',[(-.22,-.302,z),(0,-.327,z-.025),(.22,-.302,z)],.009,'gold')
    for s in [-1,1]:
        sphere('planted haunch',(s*.29,.03,.30),(.22,.25,.27),jade)
        sphere('rounded dragon paw',(s*.29,-.20,.16),(.20,.31,.14),jade)
        for dx in [-.09,0,.09]:sphere('ivory rounded toe',(s*.29+dx,-.442,.16),(.039,.055,.038),'cream',16,10)
        capsule('little arm',(s*.35,-.01,1.00),(s*.47,-.27,.79),.105,jade)
        sphere('little hand',(s*.47,-.31,.76),(.13,.105,.12),jade)
    sphere('friendly oversized head',(0,-.035,1.47),(.48,.40,.43),jade,32,20)
    sphere('broad rounded muzzle',(0,-.37,1.34),(.345,.24,.205),'cream',32,20)
    for s in [-1,1]:
        eye('expressive amber eye',s*.235,-.397,1.53,.143)
        sphere('nostril',(s*.115,-.585,1.385),(.033,.012,.022),'jade_dark',16,10)
        sphere('coral cheek',(s*.342,-.410,1.34),(.065,.018,.041),'pink',16,10)
        ear=sphere('jade ear',(s*.43,.00,1.63),(.13,.09,.23),jade);ear.rotation_euler.y=s*.65
        inner=sphere('inner ear',(s*.465,-.065,1.66),(.061,.022,.13),'mint');inner.rotation_euler.y=s*.65
        curve('curved golden horn',[(s*.27,.04,1.77),(s*.31,.07,1.99),(s*.41,.02,2.10 if king or elder else 2.02)],.060,'gold')
        if king or elder:
            curve('antler crown branch',[(s*.31,.07,1.98),(s*.43,.15,2.13),(s*.51,.13,2.16)],.038,'gold')
            curve('gentle whisker',[(s*.29,-.48,1.33),(s*.45,-.55,1.29),(s*.62,-.48,1.36)],.014,'cream')
            curve('crown eyebrow',[(s*.11,-.42,1.72),(s*.24,-.43,1.77),(s*.35,-.37,1.73)],.025,'gold')
    curve('soft dragon smile',[(-.16,-.585,1.285),(0,-.609,1.25),(.16,-.585,1.285)],.012,'jade_dark')
    star('forehead star',(0,-.425,1.77),.108,'star')
    curve('sweeping tail',[(0,.30,.60),(.15,.64,.43),(.55,.78,.30),(.83,.55,.45)],.115,jade)
    for x,y,z in [(.08,.37,.94),(.23,.60,.65),(.46,.75,.49),(.68,.69,.43)]:
        fin=ico('dorsal golden scale',(x,y,z),(.08,.095,.13),'gold',1)
    star('tail star fin',(.88,.52,.51),.22,'star',.055)
    wing(-1,king);wing(1,king)
    if king or elder:
        curve('royal brass gorget',[(-.32,-.14,1.12),(0,-.30,1.05),(.32,-.14,1.12)],.043,'gold')
        crystal('royal chest prism',(0,-.337,1.04),(.09,.06,.15),'cyan')
        for s in [-1,1]:
            for x,z in [(s*.34,.58),(s*.36,.76),(s*.36,.92)]:star('royal flank star',(x,-.17,z),.044,'star',.02)
    if elder:
        for s in [-1,0,1]:curve('old king soft beard',[(s*.11,-.54,1.22),(s*.12,-.46,1.04),(s*.075,-.35,.91)],.045,'cream')
        star('old king crown',(0,.02,2.15),.15,'star')
    animate_bob(r,.065,.026)
    return r,l,2.45 if elder else 2.3

def shadow_blob():
    r,l=root('shadow_blob')
    sphere('shadow pear',(0,0,.58),(.50,.40,.49),'purple')
    for s in [-1,1]:
        curve('soft shadow ear',[(s*.31,.02,.84),(s*.48,.02,1.02),(s*.38,-.03,1.12)],.075,'purple_light')
        sphere('shadow toe',(s*.28,-.15,.16),(.22,.27,.12),'purple')
        sphere('luminous eye',(s*.17,-.375,.66),(.072,.035,.106),'star')
        sphere('eye tiny pupil',(s*.17,-.411,.65),(.025,.009,.057),'ink')
    curve('puzzled mouth',[(-.10,-.393,.43),(0,-.416,.41),(.10,-.393,.43)],.015,'purple_light')
    for x,y,z in [(-.15,.0,1.01),(.18,.06,1.08)]:ico('floating shadow wisp',(x,y,z),(.07,.07,.09),'purple_light',2)
    animate_bob(r,.12,.05);return r,l,1.6

def crystal_imp():
    r,l=root('crystal_thief')
    sphere('imp robe',(0,.05,.57),(.34,.28,.44),'purple_light')
    sphere('imp face',(0,-.075,1.02),(.35,.30,.30),'purple')
    for s in [-1,1]:
        ear=sphere('pointed soft ear',(s*.36,-.02,1.05),(.22,.10,.11),'purple_light');ear.rotation_euler.y=s*.2
        eye('imp keen eye',s*.135,-.33,1.05,.085,'cyan')
        capsule('imp arm',(s*.29,-.01,.72),(s*.29,-.28,.54),.077,'purple_light')
        sphere('imp boot',(s*.16,-.10,.13),(.145,.23,.12),'ink')
    cube('crystal satchel',(.18,.25,.49),(.31,.14,.35),'wood',.08)
    curve('satchel strap',[(-.24,-.20,.82),(0,-.25,.65),(.26,-.12,.43)],.031,'gold')
    crystal('stolen crystal',(0,-.36,.55),(.14,.12,.24))
    for s in [-1,1]:sphere('little grasping hand',(s*.12,-.38,.52),(.075,.06,.085),'purple_light')
    star('imp belt clasp',(0,-.245,.49),.051,'gold')
    animate_bob(r,.055,.04);return r,l,1.6

def wind_gremlin():
    r,l=root('wind_gremlin')
    sphere('wind imp body',(0,.02,.71),(.34,.27,.46),'rust')
    sphere('round wind imp head',(0,-.04,1.14),(.35,.30,.32),'cream')
    for s in [-1,1]:
        eye('wind imp eye',s*.145,-.306,1.18,.09)
        capsule('wind imp shin',(s*.16,.04,.31),(s*.17,-.06,.17),.07,'rust')
        sphere('wind imp shoe',(s*.17,-.13,.11),(.14,.22,.105),'wood')
        capsule('wooden imp arm',(s*.27,0,.87),(s*.47,-.05,.64),.065,'wood')
        sphere('wind mitten',(s*.48,-.07,.63),(.10,.08,.11),'cream')
    sphere('wind helmet',(0,.02,1.40),(.37,.29,.10),'rust')
    capsule('pinwheel mast',(0,0,1.46),(0,0,1.71),.027,'gold')
    for angle in [0,math.pi/2,math.pi,3*math.pi/2]:
        dx,dz=math.sin(angle)*.18,math.cos(angle)*.18
        ob=cube('pinwheel petal',(dx,-.02,1.73+dz),(.12,.025,.25),'cloth',.025);ob.rotation_euler.y=-angle+.25
    sphere('pinwheel hub',(0,-.06,1.73),(.06,.04,.06),'gold')
    curve('red scarf',[(-.21,-.16,.98),(0,-.28,.94),(.22,-.15,.98),(.41,.05,.86)],.048,'rust')
    animate_bob(r,.06,.07);return r,l,2.3

def moon_bubble():
    r,l=root('moon_bubble')
    sphere('pearl water body',(0,0,.62),(.49,.43,.48),'bubble',32,20)
    sphere('water skirt',(0,.01,.26),(.55,.43,.14),'blue')
    for s in [-1,1]:
        eye('water expressive eye',s*.18,-.405,.72,.104,'blue')
        fin=sphere('water side fin',(s*.46,.0,.58),(.18,.06,.13),'bubble');fin.rotation_euler.y=s*.4
    curve('water smile',[(-.12,-.43,.49),(0,-.45,.46),(.12,-.43,.49)],.016,'blue')
    for p,ss in [((-.19,.04,1.10),.13),((.10,.04,1.23),.10),((.27,.10,1.06),.075)]:
        sphere('floating bubble',p,(ss,)*3,'bubble');sphere('bubble catchlight',(p[0]-.03,p[1]-.08,p[2]+.03),(.025,)*3,'white',12,8)
    star('water forehead star',(0,-.36,.98),.064,'cyan')
    animate_bob(r,.10,.035);return r,l,1.7

def thorn_treant():
    r,l=root('thorn_treant')
    sphere('massive carved trunk',(0,.03,1.03),(.59,.40,.86),'wood')
    sphere('old bark face',(0,-.19,1.44),(.55,.30,.44),'wood_light')
    for s in [-1,1]:
        sphere('tree hollow eye',(s*.21,-.458,1.48),(.13,.035,.105),'ink')
        sphere('tree glowing pupil',(s*.21,-.495,1.48),(.065,.014,.067),'star')
        curve('bark eyebrow',[(s*.08,-.47,1.65),(s*.22,-.46,1.71),(s*.35,-.40,1.68)],.047,'wood')
        capsule('branch arm',(s*.44,.01,1.36),(s*.78,-.06,.97),.14,'wood')
        capsule('twig forearm',(s*.78,-.06,.97),(s*.91,-.26,.85),.12,'wood_light')
        for off in [-.12,0,.12]:curve('branch fingers',[(s*.88,-.25,.86),(s*(1.03+off),-.30,.73),(s*(1.07+off),-.22,.69)],.038,'wood')
        sphere('root foot',(s*.36,-.09,.18),(.35,.40,.16),'wood')
        for dx in [-.11,.12]:curve('root tendril',[(s*.35+dx,-.10,.19),(s*.50+dx,-.34,.10),(s*.62+dx,-.41,.08)],.061,'wood_light')
        curve('antler branch',[(s*.30,.05,1.75),(s*.45,.05,2.09),(s*.70,.03,2.20)],.10,'wood')
        curve('antler twig',[(s*.45,.05,2.07),(s*.42,.13,2.33)],.055,'wood_light')
    for x,y,z,ss in [(-.51,.08,2.16,.28),(.53,.12,2.15,.30),(0,.15,1.99,.30),(-.13,.21,2.26,.24)]:
        sphere('soft foliage crown',(x,y,z),(ss,ss*.75,ss*.72),'leaf')
    for x in [-.34,-.13,.13,.34]:curve('vertical bark groove',[(x,-.34,.46),(x*.9,-.39,.91),(x,-.36,1.17)],.018,'wood_light')
    curve('tree determined mouth',[(-.17,-.43,1.22),(0,-.48,1.18),(.17,-.43,1.22)],.025,'wood')
    crystal('corrupted tree heart',(0,-.40,.87),(.15,.11,.23),'cyan')
    for p in [(-.40,.0,1.87),(.44,-.03,1.97)]:sphere('tiny glowing woodland fruit',p,(.065,)*3,'star')
    animate_bob(r,.025,.015);return r,l,3.15

def windmill_guard():
    r,l=root('windmill_guardian')
    cube('round wooden torso',(0,.02,.93),(.75,.50,.93),'wood',.19)
    sphere('guard head',(0,-.02,1.57),(.38,.31,.31),'stone_light')
    for s in [-1,1]:
        sphere('guard amber eye',(s*.15,-.317,1.59),(.072,.02,.10),'star')
        capsule('guard leg',(s*.23,.03,.47),(s*.25,-.04,.21),.115,'wood')
        cube('guard boot',(s*.25,-.11,.15),(.31,.44,.22),'stone',.08)
        sphere('guard shoulder',(s*.48,.02,1.20),(.18,.20,.20),'gold')
        capsule('guard arm',(s*.51,.02,1.14),(s*.65,-.13,.68),.105,'wood')
        sphere('guard hand',(s*.65,-.15,.64),(.15,.14,.17),'stone_light')
    cube('front brass panel',(0,-.255,1.0),(.46,.055,.46),'gold',.08)
    star('guard heart lantern',(0,-.294,1.02),.15,'cyan')
    curve('guard brow',[(-.28,-.23,1.77),(0,-.35,1.83),(.28,-.23,1.77)],.05,'gold')
    for i,a in enumerate([math.pi/4,3*math.pi/4,5*math.pi/4,7*math.pi/4]):
        dx,dz=math.cos(a)*.52,math.sin(a)*.52
        ob=cube('large guardian wind sail',(dx,.30,1.54+dz),(.30,.075,.72),'cloth',.04);ob.rotation_euler.y=-a+math.pi/2
        curve('sail spar',[(0,.31,1.54),(math.cos(a)*.92,.31,1.54+math.sin(a)*.92)],.032,'wood')
    sphere('wind sail central bearing',(0,.17,1.54),(.15,.11,.15),'gold')
    animate_bob(r,.025,.025);return r,l,3.05

def stone_guard():
    r,l=root('stone_shell_guardian')
    sphere('guardian crouching body',(0,.01,.65),(.61,.49,.50),'stone')
    shell=sphere('carved stone shell',(0,.15,.94),(.66,.48,.37),'stone_light')
    for s in [-1,1]:
        sphere('guardian knee',(s*.52,.11,.30),(.23,.24,.22),'stone')
        cube('guardian planted foot',(s*.49,-.13,.15),(.34,.41,.23),'stone_light',.09)
        sphere('guardian front claw',(s*.39,-.40,.27),(.20,.27,.15),'stone')
        for dx in [-.07,.07]:sphere('guardian toe cap',(s*.39+dx,-.61,.26),(.055,.06,.05),'gold',16,10)
    cube('guardian rounded head',(0,-.39,.74),(.62,.35,.40),'stone_light',.15)
    for s in [-1,1]:sphere('guardian cyan eyes',(s*.17,-.583,.77),(.092,.022,.043),'cyan')
    for x in [-.36,0,.36]:
        curve('shell geometric inlay',[(x,-.13,1.10),(x*.9,.14,1.31),(x,.42,1.09)],.022,'gold')
    for y in [.01,.30]:curve('shell transverse band',[(-.52,y,.99),(0,y,1.31),(.52,y,.99)],.017,'gold')
    crystal('guardian shell crystal',(0,.19,1.38),(.13,.13,.25),'cyan')
    animate_bob(r,.025,.025);return r,l,2.2

def lantern_devourer():
    r,l=root('lantern_devourer')
    sphere('great shadow pear',(0,.08,1.0),(.72,.55,.89),'purple')
    sphere('great shadow face',(0,-.15,1.56),(.65,.48,.49),'ink')
    for s in [-1,1]:
        curve('sweeping moon horn',[(s*.43,.04,1.86),(s*.67,.10,2.09),(s*.80,.03,2.20),(s*.76,-.03,2.38)],.102,'purple_light')
        curve('horn gold rim',[(s*.73,-.04,2.13),(s*.79,-.06,2.24),(s*.76,-.05,2.38)],.027,'gold')
        sphere('devourer hood eyebrow',(s*.23,-.518,1.73),(.24,.065,.11),'purple_light')
        eye('devourer brilliant eyes',s*.245,-.57,1.60,.123,'star')
        capsule('shadow strong arm',(s*.60,.03,1.26),(s*.86,-.26,.88),.17,'purple')
        sphere('large rounded shadow hand',(s*.88,-.29,.80),(.19,.16,.23),'purple_light')
        for dx in [-.10,0,.10]:sphere('rounded shadow finger',(s*.88+dx,-.38,.70),(.055,.08,.14),'purple_light',16,12)
        sphere('shadow foot',(s*.41,-.10,.20),(.29,.37,.16),'ink')
        curve('shoulder star crack',[(s*.44,-.28,1.31),(s*.34,-.43,1.20),(s*.47,-.40,1.10)],.022,'star')
    curve('devourer expressive smile',[(-.28,-.59,1.32),(0,-.647,1.24),(.28,-.59,1.32)],.027,'purple_light')
    sphere('lantern brass chest socket',(0,-.46,.95),(.29,.10,.34),'gold')
    sphere('lantern midnight glass',(0,-.555,.95),(.23,.04,.28),'ink')
    star('captive starlight',(0,-.60,.97),.19,'star',.04)
    for x in [-.11,0,.11]:curve('lantern cage grille',[(x,-.61,.70),(x,-.65,.97),(x,-.60,1.20)],.018,'gold')
    for s in [-1,1]:
        curve('floating shadow ribbon',[(s*.42,.30,.88),(s*.79,.54,.65),(s*.94,.35,.86),(s*.92,.14,1.03)],.079,'purple_light')
    star('dark king stolen crest',(0,-.20,2.02),.15,'gold')
    animate_bob(r,.085,.025);return r,l,3.15

def camera(name,loc,target,ortho):
    d=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=ortho;scene.camera=o;return o
def area(name,loc,energy,size,color):
    d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.shape='DISK';d.size=size;d.color=color
    o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler();return o
area('Warm storybook key',(-3,-4,6),600,5,(1,.86,.67))
area('Cool moon fill',(4,-1,4),450,4,(.65,.84,1))
area('Soft rim',(1,4,5),700,4,(.69,1,.91))
cam=camera('Creature portrait camera',(3,-6,3.0),(0,0,1),3.0)

BUILDERS=[
 ('little_dragon',lambda:dragon('little_dragon')),
 ('new_dragon_king',lambda:dragon('new_dragon_king',king=True)),
 ('elder_dragon_king',lambda:dragon('elder_dragon_king',elder=True)),
 ('shadow_blob',shadow_blob),('crystal_thief',crystal_imp),('wind_gremlin',wind_gremlin),('moon_bubble',moon_bubble),
 ('thorn_treant',thorn_treant),('windmill_guardian',windmill_guard),('stone_shell_guardian',stone_guard),('lantern_devourer',lantern_devourer)]
labels={'little_dragon':'小龙','new_dragon_king':'新龙王','elder_dragon_king':'老龙王','shadow_blob':'影团','crystal_thief':'偷晶小鬼','wind_gremlin':'风车捣蛋怪','moon_bubble':'月水泡妖','thorn_treant':'荆棘木妖','windmill_guardian':'风车守卫','stone_shell_guardian':'石甲守卫','lantern_devourer':'吞灯妖'}
all_assets=[];manifest=[]
for index,(key,build) in enumerate(BUILDERS):
    print('BUILDING',key,flush=True)
    r,lay,h=build();scene.frame_set(1)
    all_assets.append((r,lay,h))
    for rr,ll,hh in all_assets[:-1]:visible(ll,False)
    bpy.context.view_layer.update()
    # A dedicated export scene is not needed: select one actual root with descendants.
    bpy.ops.object.select_all(action='DESELECT')
    selected=descendants(r)
    for ob in selected:ob.select_set(True)
    bpy.context.view_layer.objects.active=r
    glb=os.path.join(BASE,'models',key+'.glb')
    bpy.ops.export_scene.gltf(filepath=glb,export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='SCENE',export_frame_range=True,export_force_sampling=True,export_yup=True)
    polys=sum(len(ob.data.polygons) for ob in selected if ob.type=='MESH')
    target=Vector((0,0,h*.45));cam.location=(h*1.15,-h*1.8,h*1.25)
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=h*1.16
    scene.render.resolution_x=768;scene.render.resolution_y=768
    preview=os.path.join(BASE,'renders',key+'_preview.png');scene.render.filepath=preview;bpy.ops.render.render(write_still=True)
    directions={}
    if key in ['little_dragon','new_dragon_king']:
        for dn,xy in [('front',(0,-1)),('back',(0,1)),('left',(-1,0)),('right',(1,0))]:
            cam.location=(xy[0]*h*2,xy[1]*h*2,h*1.48)
            cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=h*1.16
            path=os.path.join(BASE,'renders',key+'_'+dn+'.png');scene.render.filepath=path;bpy.ops.render.render(write_still=True);directions[dn]=path
    actions=sorted(set(ob.animation_data.action.name for ob in selected if ob.animation_data and ob.animation_data.action))
    manifest.append({'id':key,'name_zh':labels[key],'model':glb,'preview':preview,'sprites':directions,'mesh_objects':sum(ob.type=='MESH' for ob in selected),'source_polygon_count':polys,'animation_type':'object_transform_not_skeletal','animations':actions,'rigged':False,'frames':48,'fps':24,'height_reference':h})
    with open(os.path.join(BASE,'reports','manifest.json'),'w',encoding='utf-8') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
    visible(lay,False)
    print('FINISHED',key,flush=True)

# Editable master library, with each actor under a clearly named presentation root.
ROOT=None
for index,(r,lay,h) in enumerate(all_assets):
    visible(lay,True);lay.location=((index%4)*3.1, (index//4)*3.4, 0)
scene.frame_set(1);bpy.context.view_layer.update()
camera('Creature library overview',(16,-22,22),(4.6,3.5,.9),15.0)
scene.render.resolution_x=1600;scene.render.resolution_y=1200;scene.render.filepath=os.path.join(BASE,'renders','creature_library_overview.png')
# Broad library lighting with sufficient world fill; original portrait lights retained.
area('Library broad key',(3,-3,13),2200,12,(1,.88,.72));area('Library broad fill',(10,6,11),2000,12,(.68,.84,1))
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BASE,'creature_library.blend'))
with open(os.path.join(BASE,'reports','manifest.json'),'w',encoding='utf-8') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
with open(os.path.join(BASE,'README.txt'),'w',encoding='utf-8') as f:
    f.write('星灯岛 小龙与妖怪资产\n\ncreature_library.blend 是可编辑真实网格源文件；models 内为单体 GLB；renders 内为 alpha 透明 PNG。\n共 11 个模型：小龙、成长新龙王、老龙王、4 普通怪、4 首领。\n动画为对象变换与翅膀关节空物体动画，不是骨骼蒙皮；无贴图依赖，材质均为程序设置的实体色材质。\n游戏原设为2D，PNG可直接作精灵，GLB可作进一步动画与多角度渲染源。\n每个GLB的空物体根命名与文件名一致，Y轴朝上（glTF规范）。Blender源Z轴朝上，角色面向-Y。\n小龙与新王各有4方向高俯角透明静止精灵，非完整行走帧序列。\n详见 reports/manifest.json。\n')
print('ALL_CREATURES_COMPLETE',flush=True)
