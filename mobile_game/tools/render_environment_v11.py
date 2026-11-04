"""Editable storybook environment library and coherent transparent game renders.

Run: E:/blender/blender.exe --background --python tools/render_environment_v11.py
Optional: -- --only tree_round,house_blue  (the complete .blend is still built).
Original supplied assets are read-only. Each named collection is a complete,
independently editable model, arranged on a library grid in the saved .blend.
"""
from pathlib import Path
import bpy, bmesh, math, random, json, sys
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

OUT=Path(__file__).resolve().parents[1]/"assets"/"environment_v11"
OUT.mkdir(parents=True,exist_ok=True)
SOURCE_OUT=OUT/'source'
SOURCE_OUT.mkdir(exist_ok=True)
(SOURCE_OUT/'.gdignore').write_text('',encoding='utf-8')
R=random.Random(1104)
CURRENT=None
ROOT=None
M={}
SPHERES={}

def mat(name,color,rough=.7,metal=0,noise=0,bump=.08,glow=0,leaf=False):
    # Palette values are authored as display RGB; Blender shader inputs are linear.
    color=tuple(v**2.2 for v in color)
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
    n=m.node_tree.nodes;l=m.node_tree.links
    s=next(x for x in n if x.type=='BSDF_PRINCIPLED')
    s.inputs['Base Color'].default_value=(*color,1);s.inputs['Roughness'].default_value=rough;s.inputs['Metallic'].default_value=metal
    if glow:s.inputs['Emission Color'].default_value=(*color,1);s.inputs['Emission Strength'].default_value=glow
    if leaf:
        s.inputs['Subsurface Weight'].default_value=.065
        s.inputs['Coat Weight'].default_value=.14
        s.inputs['Coat Roughness'].default_value=.6
    if noise:
        t=n.new('ShaderNodeTexNoise');t.inputs['Scale'].default_value=noise;t.inputs['Detail'].default_value=3
        ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.18;ramp.color_ramp.elements[0].color=tuple(c*.64 for c in color)+(1,)
        ramp.color_ramp.elements[1].position=.82;ramp.color_ramp.elements[1].color=tuple(min(1,c*1.22+.025) for c in color)+(1,)
        l.new(t.outputs['Fac'],ramp.inputs['Fac']);l.new(ramp.outputs['Color'],s.inputs['Base Color'])
        b=n.new('ShaderNodeBump');b.inputs['Strength'].default_value=bump;b.inputs['Distance'].default_value=.10
        l.new(t.outputs['Fac'],b.inputs['Height']);l.new(b.outputs['Normal'],s.inputs['Normal'])
    M[name]=m;return m

def register(o,name,material=None):
    o.name=name
    for c in list(o.users_collection):c.objects.unlink(o)
    CURRENT.objects.link(o)
    if ROOT:o.parent=ROOT
    if material:o.data.materials.append(material)
    return o

def smooth(o):
    if o.type=='MESH':
        for p in o.data.polygons:p.use_smooth=True
    return o

def cube(name,loc,scale,material,bevel=.05,rotation=None):
    vs=[(x*scale[0]*.5,y*scale[1]*.5,z*scale[2]*.5) for x,y,z in [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]]
    fs=[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]
    me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs)
    o=bpy.data.objects.new(name,me);CURRENT.objects.link(o);o.parent=ROOT;o.location=loc;me.materials.append(material)
    if bevel:
        b=o.modifiers.new('Soft hand finished edges','BEVEL');b.width=bevel;b.segments=3
        n=o.modifiers.new('Weighted surface normals','WEIGHTED_NORMAL');n.keep_sharp=True
    if rotation:o.rotation_euler=rotation
    return o

def ball(name,loc,scale,material,sub=2,organic=.0):
    if sub not in SPHERES:
        bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=sub,radius=1)
        me=bpy.data.meshes.new('Reusable smooth sphere topology');bm.to_mesh(me);bm.free();SPHERES[sub]=me
    me=SPHERES[sub].copy();o=bpy.data.objects.new(name,me);CURRENT.objects.link(o);o.parent=ROOT;o.location=loc;me.materials.append(material)
    if organic:
        for v in o.data.vertices:
            v.co*=1+organic*(math.sin(v.co.x*7+v.co.z*5)*math.cos(v.co.y*8-v.co.z*4)+R.uniform(-.25,.25))
    o.scale=scale;smooth(o)
    return o

def cylinder(name,loc,radius,depth,material,vertices=32,r2=None,rotation=None):
    top=radius if r2 is None else r2
    vs=[(math.cos(j*math.tau/vertices)*r,math.sin(j*math.tau/vertices)*r,z) for r,z in [(radius,-depth*.5),(top,depth*.5)] for j in range(vertices)]
    fs=[tuple(range(vertices-1,-1,-1)),tuple(range(vertices,vertices*2))]+[(j,(j+1)%vertices,(j+1)%vertices+vertices,j+vertices) for j in range(vertices)]
    me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);o=bpy.data.objects.new(name,me);CURRENT.objects.link(o);o.parent=ROOT;o.location=loc;me.materials.append(material);smooth(o)
    if rotation:o.rotation_euler=rotation
    return o

def beam(name,a,b,width,material,rect=None):
    a,b=Vector(a),Vector(b);d=b-a
    o=cube(name,(a+b)*.5,(width,width,d.length) if rect is None else (*rect,d.length),material,min(width*.18,.045))
    o.rotation_euler=d.to_track_quat('Z','Y').to_euler()
    return o

def curve(name,points,radius,material,cyclic=False):
    c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.resolution_u=16;c.bevel_depth=radius;c.bevel_resolution=3
    spl=c.splines.new('POLY');spl.points.add(len(points)-1)
    for p,co in zip(spl.points,points):p.co=(*co,1)
    spl.use_cyclic_u=cyclic
    o=bpy.data.objects.new(name,c);CURRENT.objects.link(o)
    if ROOT:o.parent=ROOT
    c.materials.append(material);return o

def leaf(name,p,direction,size,material,width=.42):
    # Real curved leaf surface, with a raised midrib and tapered tip.
    vs=[(0,0,0),(-width*.42,.30,.045),(-width*.50,.62,.025),(0,1,.02),(width*.50,.62,.025),(width*.42,.30,.045),(0,.30,.10),(0,.63,.10)]
    fs=[(0,1,6),(1,2,7,6),(2,3,7),(3,4,7),(4,5,6,7),(5,0,6)]
    me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);o=bpy.data.objects.new(name,me);CURRENT.objects.link(o);o.parent=ROOT
    me.materials.append(material);o.location=p;o.scale=(size,size,size)
    o.rotation_euler=Vector(direction).to_track_quat('Y','Z').to_euler();smooth(o)
    return o

def spray(center,radius,count,materials,size=.34):
    c=Vector(center)
    for i in range(count):
        z=R.uniform(-.65,1);a=R.uniform(0,math.tau);v=Vector((math.sqrt(1-z*z)*math.cos(a),math.sqrt(1-z*z)*math.sin(a),z))
        p=c+v*radius*R.uniform(.63,1)
        direction=(v+Vector((0,0,R.uniform(-.2,.4)))).normalized()
        leaf('Individual curved leaf',p,direction,size*R.uniform(.75,1.35),R.choice(materials))

def make_materials():
    mat('Bark chestnut',(.25,.13,.065),noise=9,bump=.36)
    mat('Bark sunlit ridges',(.40,.23,.10),noise=11,bump=.20)
    mat('Warm aged timber',(.34,.19,.085),noise=8,bump=.3)
    mat('Honey cut wood',(.56,.34,.15),noise=7,bump=.20)
    mat('Dark endgrain',(.16,.10,.055),noise=15,bump=.15)
    mat('Rope flax',(.65,.51,.29),noise=12,bump=.1)
    for i,c in enumerate([(.21,.40,.13),(.30,.48,.17),(.39,.55,.22),(.47,.62,.27),(.25,.43,.19)]):mat('Leaf%d'%i,c,noise=5,bump=.05,leaf=True)
    for i,c in enumerate([(.12,.30,.21),(.18,.37,.23),(.24,.43,.28),(.31,.47,.29)]):mat('Pine%d'%i,c,noise=6,bump=.07,leaf=True)
    for i,c in enumerate([(.41,.44,.38),(.53,.53,.43),(.59,.57,.46),(.40,.44,.44)]):mat('Stone%d'%i,c,noise=6,bump=.24)
    mat('Moss velvet',(.29,.40,.13),noise=14,bump=.15)
    mat('Lichen pale',(.58,.63,.35),noise=16,bump=.1)
    mat('Plaster ivory',(.76,.71,.53),noise=12,bump=.08)
    mat('Plaster ochre',(.72,.54,.32),noise=14,bump=.09)
    for i,c in enumerate([(.17,.30,.34),(.22,.36,.39),(.26,.39,.41),(.20,.32,.38),(.30,.42,.43)]):mat('Blue slate%d'%i,c,noise=16,bump=.09)
    for i,c in enumerate([(.47,.20,.10),(.58,.27,.13),(.63,.32,.18),(.53,.23,.12),(.68,.36,.19)]):mat('Warm tile%d'%i,c,noise=15,bump=.09)
    mat('Window warm glass',(.97,.72,.30),rough=.28,glow=.18)
    mat('Window blue glass',(.29,.50,.50),rough=.22)
    mat('Brass weathered',(.66,.43,.12),rough=.35,metal=.7,noise=10,bump=.07)
    mat('Iron dark',(.10,.14,.13),rough=.5,metal=.6)
    mat('Lamp glass honey',(.97,.66,.21),rough=.26,glow=.5)
    mat('Cream canvas',(.78,.70,.49),noise=12,bump=.08)
    mat('Flower ivory',(.95,.90,.68),rough=.6)
    mat('Flower violet',(.52,.34,.58),rough=.65)
    mat('Flower gold',(.96,.61,.15),rough=.55)

def tree_round():
    # Tapered bent trunk with visible ridges and spreading supported boughs.
    points=[(0,0,0),(.04,.02,.8),(-.12,.03,1.8),(-.04,.06,2.8),(.15,.09,3.6)]
    for i in range(len(points)-1):
        a,b=Vector(points[i]),Vector(points[i+1]);d=b-a
        o=cylinder('Tapered textured trunk',(a+b)*.5,.28-i*.035,d.length,M['Bark chestnut'],32,.24-i*.035)
        o.rotation_euler=d.to_track_quat('Z','Y').to_euler()
    for i in range(12):
        a=i/12*math.tau
        curve('Fine raised bark ridge',[(math.cos(a)*(.25-z*.025)+.04*math.sin(z*2),math.sin(a)*(.25-z*.025),z) for z in [j*.15 for j in range(22)]],.012,M['Bark sunlit ridges'])
    for i in range(7):
        a=i*math.tau/7;beam('Spreading root',(.0,.0,.18),(.65*math.cos(a),.65*math.sin(a),.025),.14,M['Bark chestnut'])
    crowns=[(-1.1,.1,4.1,1.28),(.92,.22,4.30,1.4),(-.10,.65,5.05,1.28),(.0,-.65,4.0,1.35),(-.85,-.58,4.86,1.0),(.75,-.50,5.1,.95),(.0,.05,5.6,.95)]
    colors=[M['Leaf%d'%i] for i in range(5)]
    for i,(x,y,z,r) in enumerate(crowns):
        beam('Organic branching bough',(.0,.0,2.6),(x,y,z),.13,M['Bark chestnut'])
        ball('Soft organic leaf mass',(x,y,z),(r,r*.88,r*.77),colors[i%5],3,.10)
        spray((x,y,z),r,75,colors,.36)

def tree_fir():
    cylinder('Fir taper trunk',(0,0,2.8),.22,5.6,M['Bark chestnut'],24,.07)
    colors=[M['Pine%d'%i] for i in range(4)]
    for layer in range(6):
        z=1.2+layer*.77;r=1.75-layer*.23
        for j in range(8):
            a=j*math.tau/8+layer*.45;end=Vector((math.cos(a)*r,math.sin(a)*r,z-.30))
            beam('Fir branch',(0,0,z+.2),end,.075,M['Bark chestnut'])
            center=end*.64+Vector((0,0,z))*.36
            ball('Soft needle bough',center,(r*.66,.42,.34),colors[(j+layer)%4],2,.12).rotation_euler[2]=a
            for k in range(14):
                f=R.uniform(.35,1);p=Vector((math.cos(a)*r*f,math.sin(a)*r*f,z+.15-.4*f))
                side=Vector((-math.sin(a),math.cos(a),.2))*R.choice([-1,1])
                leaf('Pointed fir spray',p,side,.30,colors[R.randrange(4)],.75)
    ball('Fir crown',(0,0,5.7),(.5,.5,.95),colors[2],3,.07)

def rock():
    for loc,scale in [((0,0,1.0),(1.55,1.15,1.10)),((1.1,.25,.48),(.75,.62,.60)),((-.95,-.5,.30),(.55,.46,.35))]:
        ball('Weathered rounded rock',loc,scale,R.choice([M['Stone%d'%i] for i in range(4)]),3,.17)
    for i in range(13):
        a=R.uniform(0,math.tau);p=(math.cos(a)*R.uniform(.1,1.3),math.sin(a)*R.uniform(.1,.9),R.uniform(.45,1.7))
        ball('Moss lichen pocket',p,(R.uniform(.15,.34),R.uniform(.13,.25),.065),M['Moss velvet'] if i%3 else M['Lichen pale'],2,.08)
    for i in range(9):leaf('Crevice fern',(-1.0,-.25,.2),(R.uniform(-1,1),R.uniform(-1,1),R.uniform(.5,1)),.65,M['Leaf2'],.30)

def shrub():
    colors=[M['Leaf%d'%i] for i in range(5)]
    for x,y,z,r in [(-.62,0,.5,.75),(.45,.15,.70,.9),(0,-.45,.5,.68)]:
        ball('Leafy shrub heart',(x,y,z),(r,r*.85,r*.65),colors[1],3,.08)
        spray((x,y,z),r,80,colors,.30)
    for i in range(11):
        x=R.uniform(-.9,.9);y=R.uniform(-.6,.5);z=R.uniform(.8,1.15)
        beam('Flower stalk',(x,y,.2),(x,y,z),.018,M['Leaf0'])
        for j in range(5):
            a=j*math.tau/5;ball('Tiny meadow petal',(x+.07*math.cos(a),y+.07*math.sin(a),z),(.075,.05,.025),M['Flower ivory'] if i%3 else M['Flower violet'],2)
        ball('Pollen center',(x,y,z+.02),(.035,.035,.025),M['Flower gold'],2)

def window(x,y,z,width=.65,height=.85,front=True):
    frame=M['Honey cut wood'];glass=M['Window warm glass']
    cube('Recessed window shadow',(x,y+.02,z),(width+.15,.14,height+.15),M['Dark endgrain'],.035)
    cube('Luminous window panes',(x,y-.065,z),(width,.05,height),glass,.025)
    for dx in [-width*.5,width*.5,0]:cube('Wooden window mullion',(x+dx,y-.11,z),(.055,.075,height+.07),frame,.015)
    for dz in [-height*.5,height*.5,0]:cube('Wooden window crossbar',(x,y-.11,z+dz),(width+.12,.075,.055),frame,.015)
    cube('Stone window sill',(x,y-.13,z-height*.5-.09),(width+.23,.35,.10),M['Stone2'],.035)

def mini_lantern(x,y,z,scale=.5):
    brass=M['Brass weathered'];glass=M['Lamp glass honey']
    cube('Amber lantern glass',(x,y,z),(.52*scale,.52*scale,.70*scale),glass,.05*scale)
    for dx in [-.28,.28]:
        for dy in [-.28,.28]:beam('Lantern brass mullion',(x+dx*scale,y+dy*scale,z-.38*scale),(x+dx*scale,y+dy*scale,z+.38*scale),.045*scale,brass)
    for dz in [-.4,.4]:cube('Lantern frame ledge',(x,y,z+dz*scale),(.66*scale,.66*scale,.09*scale),brass,.025)
    cylinder('Lantern tier roof',(x,y,z+.51*scale),.51*scale,.20*scale,brass,4,.17*scale,rotation=(0,0,math.pi/4))
    curve('Lantern ring',[(x+math.cos(a)*.13*scale,y,z+.77*scale+math.sin(a)*.14*scale) for a in [j*math.tau/32 for j in range(32)]],.024*scale,brass,True)

def house(warm=False):
    plaster=M['Plaster ochre' if warm else 'Plaster ivory'];timber=M['Warm aged timber'];trim=M['Honey cut wood']
    cube('Plaster and timber cottage',(0,1.55,1.95),(3.8,3.1,3.1),plaster,.12)
    for row in range(2):
        for j in range(7):
            cube('Individual foundation stone',(-1.65+j*.54,-.045,.15+row*.25),(.50,.35,.23),M['Stone%d'%R.randrange(4)],.045)
    for side in [-1,1]:
        for j in range(6):cube('Side foundation stones',(side*1.88,.22+j*.52,.28),(.30,.49,.48),M['Stone%d'%R.randrange(4)],.055)
        beam('Corner timber post',(side*1.82,-.04,.35),(side*1.82,-.04,3.45),.18,timber)
        beam('Side timber post',(side*1.82,3.07,.35),(side*1.82,3.07,3.45),.18,timber)
        beam('Front diagonal brace',(side*.65,-.08,3.35),(side*1.80,-.08,2.45),.12,timber)
    for z in [.55,3.38]:beam('Continuous front beam',(-1.93,-.06,z),(1.93,-.06,z),.19,timber)
    # Gable wall, solid thickness and exposed timber pattern.
    vs=[(-1.9,-.02,3.42),(1.9,-.02,3.42),(0,-.02,4.85),(-1.9,3.1,3.42),(1.9,3.1,3.42),(0,3.1,4.85)]
    me=bpy.data.meshes.new('Gable plaster');me.from_pydata(vs,[],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)])
    o=bpy.data.objects.new('Solid plaster gable',me);CURRENT.objects.link(o);o.parent=ROOT;me.materials.append(plaster)
    beam('Gable ridge beam',(0,-.13,3.35),(0,-.13,4.9),.15,timber)
    for side in [-1,1]:beam('Gable diagonal trim',(side*2.18,-.18,3.4),(0,-.18,5.08),.18,timber)
    prefix='Warm tile' if warm else 'Blue slate'
    slope=.72;angle=math.atan(slope)
    for side in [-1,1]:
        for row in range(5):
            x=side*(.19+row*.44);z=5.03-abs(x)*slope
            for j in range(8):
                y=-.23+j*.49+(0.04 if row%2 else 0)
                cube('Individually bevelled roof tile',(x,y,z+R.uniform(-.014,.014)),(.58,.51,.08),M[prefix+str(R.randrange(5))],.026,(0,side*angle,0))
        beam('Overhanging eave',(side*2.20,-.45,3.45),(side*2.20,3.54,3.45),.17,timber)
        for j in range(9):beam('Exposed roof rafter',(side*2.21,-.35+j*.47,3.42),(side*1.78,-.35+j*.47,3.76),.10,trim)
    for j in range(10):cylinder('Ridge cap tile',(0,-.32+j*.43,5.10),.13,.44,M[prefix+str(j%5)],16,rotation=(math.pi/2,0,0))
    # Deep door frame and six visible vertical planks.
    cube('Door recess',(0,-.10,1.36),(1.08,.18,1.95),M['Dark endgrain'],.075)
    for j in range(6):cube('Door individual oak plank',(-.38+j*.152,-.22,1.30),(.142,.09,1.78),trim,.018)
    for z in [.76,1.74]:cube('Iron door hinge strap',(-.17,-.286,z),(.63,.035,.07),M['Iron dark'],.012)
    ball('Round brass doorknob',(.28,-.30,1.22),(.065,.04,.065),M['Brass weathered'],2)
    for dx in [-.60,.60]:beam('Deep carved door jamb',(dx,-.19,.38),(dx,-.19,2.4),.15,timber)
    beam('Door lintel',(-.67,-.18,2.36),(.67,-.18,2.36),.18,timber)
    for j in range(3):cube('Worn front step',(0,-.38-j*.25,.30-j*.07),(1.35+j*.17,.33,.18),M['Stone2'],.065)
    window(-1.18,-.12,2.0,.63,.82);window(1.18,-.12,2.0,.63,.82)
    # Attic diamond window and planter boxes.
    cube('Attic diamond pane',(.0,-.12,4.03),(.50,.08,.50),M['Window blue glass'],.03,(0,math.pi/4,0))
    for x in [-1.18,1.18]:
        cube('Window flower box',(x,-.29,1.35),(.88,.38,.24),timber,.035)
        for j in range(7):
            p=(x+R.uniform(-.35,.35),-.36+R.uniform(-.07,.07),1.52)
            leaf('Windowbox leaves',p,(R.uniform(-.7,.7),-.5,1),.40,M['Leaf3'])
            ball('Windowbox blossom',(p[0],p[1]-.03,1.85),(.075,.075,.055),M['Flower gold' if j%2 else 'Flower ivory'],2)
    # Weathered chimney and stone cap with a dark interior.
    for j in range(5):cube('Chimney stone course',(.93,2.38,4.52+j*.27),(.60,.60,.25),M['Stone%d'%(j%3)],.05)
    cube('Chimney opening',(.93,2.38,5.80),(.43,.43,.04),M['Dark endgrain'],.01)
    for dx,dy,sx,sy in [(-.29,0,.12,.75),(.29,0,.12,.75),(0,-.29,.75,.12),(0,.29,.75,.12)]:cube('Chimney coping rim',(.93+dx,2.38+dy,5.84),(sx,sy,.13),M['Stone2'],.03)
    mini_lantern(-.78,-.55,2.28,.55)
    curve('Wall lantern bracket',[(-.77,-.12,2.8),(-.77,-.58,2.8),(-.77,-.60,2.65)],.025,M['Iron dark'])
    for side in [-1,1]:
        curve('Climbing cottage vine',[(side*1.8+.08*math.sin(j),-.20,.50+j*.24) for j in range(13)],.02,M['Leaf0'])
        for j in range(16):leaf('Cottage ivy',(side*1.8+.08*math.sin(j),-.24,.55+j*.18),(side*R.uniform(-.5,.8),-.25,R.uniform(.2,.8)),.24,M['Leaf%d'%(1+j%3)],.75)

def wood_bridge():
    timber=M['Warm aged timber'];trim=M['Honey cut wood']
    for side in [-1,1]:
        pts=[]
        for j in range(33):
            x=-3.5+j*7/32;z=.45+.65*math.sin(j/32*math.pi)
            pts.append((x,side*1.08,z-.12))
        curve('Curved loadbearing bridge beam',pts,.13,timber)
    for j in range(27):
        t=j/26;x=-3.45+6.9*t;z=.49+.65*math.sin(t*math.pi)
        cube('Separate weathered deck plank',(x,0,z),(.245,2.2,.14),trim if j%5 else timber,.035,(0,-.20*math.cos(t*math.pi),R.uniform(-.012,.012)))
        for side in [-1,1]:ball('Iron plank nail',(x,side*.91,z+.085),(.026,.026,.012),M['Iron dark'],1)
    for side in [-1,1]:
        rail=[]
        for j in range(7):
            t=j/6;x=-3.4+6.8*t;z=.48+.65*math.sin(t*math.pi)
            beam('Bridge baluster',(x,side*1.12,z),(x,side*1.12,z+1.05),.12,timber)
            ball('Rounded railing post cap',(x,side*1.12,z+1.08),(.10,.10,.07),trim,2)
            rail.append((x,side*1.12,z+1.02))
        curve('Smooth arched timber handrail',rail,.09,trim)
        curve('Flax safety rope',[(x,y,z-.42) for x,y,z in rail],.025,M['Rope flax'])

def stone_bridge():
    for j in range(23):
        t=j/22;x=-3.4+6.8*t;z=.50+.80*math.sin(t*math.pi)
        for side in [-1,1]:
            cube('Arch voussoir stone',(x,side*1.05,z-.22),(.38,.38,.60),M['Stone%d'%R.randrange(3)],.065,(0,-.30*math.cos(t*math.pi),0))
        for k in range(5):cube('Stone bridge worn paving',(x,-.9+k*.45,z),(.33,.42,.13),M['Stone%d'%R.randrange(4)],.045)
        if j%2==0:
            for side in [-1,1]:
                cube('Rounded stone parapet',(x,side*1.18,z+.36),(.60,.33,.58),M['Stone1'],.07)
                cube('Parapet coping cap',(x,side*1.18,z+.70),(.65,.43,.12),M['Stone2'],.055)
        if j%4==0:
            for side in [-1,1]:ball('Bridge moss pocket',(x,side*1.30,z+.38),(.20,.08,.14),M['Moss velvet'],2,.1)

def ruin_arch():
    for side in [-1,1]:
        cube('Arch foundation',(side*1.50,0,.13),(1.02,1.15,.26),M['Stone1'],.08)
        for j in range(6):
            cube('Weathered column block',(side*1.50,0,.46+j*.46),(.78+R.uniform(-.04,.04),.80,.43),M['Stone%d'%R.randrange(4)],.07,(0,R.uniform(-.02,.02),R.uniform(-.03,.03)))
        cube('Column capital',(side*1.50,0,3.05),(1.0,1.0,.23),M['Stone2'],.06)
    for j in range(13):
        a=j/12*math.pi;x=math.cos(a)*1.50;z=3.16+math.sin(a)*1.50
        cube('Carved arch keystone segment',(x,0,z),(.49,.88,.65),M['Stone%d'%R.randrange(4)],.065,(0,math.pi/2-a,0))
    for j in range(9):
        a=j/8*math.pi
        ball('Soft arch moss',(math.cos(a)*1.48,-.38,3.30+math.sin(a)*1.54),(.27,.13,.10),M['Moss velvet'],2,.1)
    for i in range(27):
        z=R.uniform(.5,4.5);x=-1.48 if z<3 else -1.48+(.9*(z-3))
        leaf('Arch creeping ivy',(x,-.52,z),(R.uniform(-.6,.6),-.25,.4),R.uniform(.20,.35),M['Leaf%d'%R.randrange(1,4)],.8)
    for j in range(3):cube('Fallen worn masonry',(2.2+j*.35,.2-j*.3,.20),(.72,.62,.40),M['Stone1'],.09,(0,.10,j*.4))
    for side in [-1,1]:
        for z in [1.2,1.7,2.2]:curve('Ancient incised star line',[(side*1.50-.12,-.419,z),(side*1.50,-.435,z+.15),(side*1.50+.12,-.419,z)],.012,M['Brass weathered'])

def windmill():
    cylinder('Circular stone plinth',(0,0,.20),1.65,.40,M['Stone1'],48)
    cylinder('Tapered plaster windmill',(0,0,2.7),1.43,5.1,M['Plaster ivory'],64,.95)
    for z,r in [(.5,1.42),(2.8,1.20),(5.0,1.0)]:
        curve('Windmill timber belt',[(math.cos(j*math.tau/64)*r,math.sin(j*math.tau/64)*r,z) for j in range(64)],.075,M['Warm aged timber'],True)
    cylinder('Shingled conical mill roof',(0,0,5.75),1.38,1.2,M['Blue slate1'],48,.08)
    for row in range(4):
        r=1.35-row*.29;z=5.20+row*.30
        curve('Roof shingle course',[(math.cos(j*math.tau/64)*r,math.sin(j*math.tau/64)*r,z) for j in range(64)],.028,M['Blue slate3'],True)
    window(0,-1.3,2.20,.55,.75)
    cube('Mill oak entry',(0,-1.43,1.04),(.82,.16,1.65),M['Honey cut wood'],.09)
    # Full framed cloth sails in front of the tower, with battens and bolts.
    hub=Vector((0,-1.56,4.25))
    cylinder('Iron mill axle',hub,.23,.60,M['Iron dark'],32,rotation=(math.pi/2,0,0))
    for j in range(4):
        a=math.pi/4+j*math.pi/2;v=Vector((math.sin(a),0,math.cos(a)));side=Vector((math.cos(a),0,-math.sin(a)))
        beam('Long oak sail spar',hub-v*.25,hub+v*3.05,.15,M['Warm aged timber'])
        for k in range(8):
            c=hub+v*(.8+k*.29)
            beam('Sail cross batten',c-side*.11,c+side*.73,.065,M['Honey cut wood'])
        for off in [.0,.70]:beam('Sail canvas edge',hub+v*.72+side*off,hub+v*2.98+side*off,.07,M['Warm aged timber'])
        me=bpy.data.meshes.new('Woven cream sail');vs=[hub+v*.78+side*.06,hub+v*2.94+side*.06,hub+v*2.94+side*.65,hub+v*.78+side*.65]
        me.from_pydata([tuple(p+Vector((0,.035,0))) for p in vs],[],[(0,1,2,3)])
        o=bpy.data.objects.new('Cream linen wind sail',me);CURRENT.objects.link(o);o.parent=ROOT;me.materials.append(M['Cream canvas'])
    ball('Mill polished wooden hub',(0,-1.92,4.25),(.30,.15,.30),M['Honey cut wood'],3)

def water_wheel():
    r=2.15;cz=2.50;wood=M['Warm aged timber'];trim=M['Honey cut wood']
    for side in [-1,1]:
        y=side*.52
        for j in range(40):
            a=j*math.tau/40;p=(r*math.cos(a),y,cz+r*math.sin(a))
            cube('Segmented oak wheel rim',p,(.39,.17,.23),trim,.035,(0,-a,0))
        for j in range(10):
            a=j*math.tau/10
            beam('Tenon wheel spoke',(0,y,cz),(math.cos(a)*r,y,cz+math.sin(a)*r),.13,wood)
    for j in range(20):
        a=j*math.tau/20
        cube('Water paddle board',(math.cos(a)*r,0,cz+math.sin(a)*r),(.39,1.28,.16),trim,.035,(0,-a,0))
    cylinder('Iron waterwheel shaft',(0,0,cz),.18,3.4,M['Iron dark'],32,rotation=(math.pi/2,0,0))
    for y in [-1.3,1.3]:
        for side in [-1,1]:beam('Wheel trestle brace',(side*1.0,y,.15),(0,y,cz),.22,wood)
        cube('Stone wheel pier',(0,y,.25),(1.8,.70,.50),M['Stone1'],.09)
        cylinder('Brass axle collar',(0,y,cz),.33,.20,M['Brass weathered'],32,rotation=(math.pi/2,0,0))
    for j in range(12):
        a=j*math.tau/12;ball('Wheel iron rivet',(math.cos(a)*1.87,-.64,cz+math.sin(a)*1.87),(.04,.025,.04),M['Iron dark'],1)

def lantern():
    cube('Lantern sandstone footing',(0,0,.13),(1.10,1.10,.26),M['Stone1'],.10)
    cube('Lantern upper footing',(0,0,.34),(.78,.78,.22),M['Stone2'],.07)
    cylinder('Tapered brass lantern post',(0,0,1.05),.13,1.32,M['Brass weathered'],32,.09)
    for z in [.50,.65,1.45,1.60]:cylinder('Turned brass collar',(0,0,z),.20,.09,M['Brass weathered'],32)
    mini_lantern(0,0,2.15,1.20)
    for side in [-1,1]:curve('Curled brass bracket',[(0,0,1.55),(side*.45,0,1.82),(side*.43,0,2.05)],.035,M['Brass weathered'])
    # Golden star emblem on the visible glass front.
    pts=[]
    for j in range(10):
        a=j*math.tau/10+math.pi/2;r=.19 if j%2==0 else .085;pts.append((math.cos(a)*r,-.345,2.13+math.sin(a)*r))
    curve('Lantern raised star crest',pts,.018,M['Brass weathered'],True)

BUILDERS={'tree_round':tree_round,'tree_fir':tree_fir,'house_blue':lambda:house(False),'house_warm':lambda:house(True),'rock':rock,'shrub':shrub,'wood_bridge':wood_bridge,'stone_bridge':stone_bridge,'ruin_arch':ruin_arch,'windmill':windmill,'water_wheel':water_wheel,'lantern':lantern}
HEIGHTS={'tree_round':300,'tree_fir':310,'house_blue':255,'house_warm':255,'rock':110,'shrub':85,'wood_bridge':150,'stone_bridge':155,'ruin_arch':245,'windmill':330,'water_wheel':210,'lantern':150}

def bounds(collection):
    pts=[];dg=bpy.context.evaluated_depsgraph_get()
    for o in collection.objects:
        if o.type in ['MESH','CURVE']:
            e=o.evaluated_get(dg);pts.extend(e.matrix_world@Vector(v) for v in e.bound_box)
    return Vector(tuple(min(p[i] for p in pts) for i in range(3))),Vector(tuple(max(p[i] for p in pts) for i in range(3)))

def render_library():
    global CURRENT,ROOT
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    make_materials();scene=bpy.context.scene
    scene.render.engine='BLENDER_EEVEE'
    scene.render.resolution_x=700;scene.render.resolution_y=800;scene.render.resolution_percentage=100
    scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
    scene.render.image_settings.color_depth='8'
    scene.render.use_persistent_data=True
    if hasattr(scene,'eevee') and hasattr(scene.eevee,'taa_render_samples'):scene.eevee.taa_render_samples=64
    scene.world.color=(.25,.32,.40)
    scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
    scene.view_settings.exposure=-.15
    # A broad warm key and cool sky fill produce rounded natural forms and soft shadows.
    for name,loc,power,size,color in [('Warm afternoon sun',(-5,-7,11),1100,5.5,(1,.88,.68)),('Cool open sky',(6,-1,8),500,6,(.67,.82,1)),('Soft canopy rim',(-2,6,8),1000,5,(.91,1,.75))]:
        d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;d.energy=power;d.shape='DISK';d.size=size;d.color=color;o.rotation_euler=(Vector((0,0,2))-o.location).to_track_quat('-Z','Y').to_euler()
    camera_data=bpy.data.cameras.new('Environment orthographic camera');camera=bpy.data.objects.new('Environment orthographic camera',camera_data);scene.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO'
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    only=args[args.index('--only')+1].split(',') if '--only' in args else list(BUILDERS)
    manifest={'version':'1.1','canvas':[700,800],'camera':'orthographic warm sunlight, cool sky fill, high three-quarter','foot_convention':'exact projection of model origin (0,0,0); no opaque floor or baked contact shadow','blend':'res://assets/environment_v11/source/environment_library.blend','assets':{}}
    assets=[]
    for index,(key,builder) in enumerate(BUILDERS.items()):
        CURRENT=bpy.data.collections.new(key);scene.collection.children.link(CURRENT)
        ROOT=bpy.data.objects.new(key+' editable origin',None);CURRENT.objects.link(ROOT)
        builder();assets.append((key,CURRENT,ROOT));print('ENV_BUILT',key,len(CURRENT.objects),flush=True)
    ROOT=None
    for key,collection,origin in assets:
        for _,other,_ in assets:other.hide_render=other!=collection
        scene.view_layers[0].update();lo,hi=bounds(collection);center=(lo+hi)*.5
        camera.location=center+Vector((7,-10,8.2));camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.view_layers[0].update()
        # Fit all projected AABB corners, leaving generous transparent margins.
        inv=camera.matrix_world.inverted();corners=[inv@Vector((x,y,z)) for x in [lo.x,hi.x] for y in [lo.y,hi.y] for z in [lo.z,hi.z]]
        w=max(v.x for v in corners)-min(v.x for v in corners);h=max(v.y for v in corners)-min(v.y for v in corners)
        camera.data.ortho_scale=max(h*1.12,w*800/700*1.12)
        scene.view_layers[0].update();uv=world_to_camera_view(scene,camera,Vector((0,0,0)))
        foot=[round(uv.x*700,3),round((1-uv.y)*800,3)]
        manifest['assets'][key]={'image':'res://assets/environment_v11/'+key+'.png','foot':foot,'world_height':HEIGHTS[key],'blend':'res://assets/environment_v11/source/environment_library.blend','collection':key,'model_dimensions':[round(v,3) for v in hi-lo]}
        if key in only:
            scene.render.filepath=str(OUT/(key+'.png'));bpy.ops.render.render(write_still=True);print('ENV_RENDERED',key,flush=True)
    # Lay the independently editable collections out as a clear source library.
    for index,(key,collection,origin) in enumerate(assets):
        collection.hide_render=False
        origin.location=((index%4)*12,(index//4)*13,0)
    camera.location=(22,-30,40);camera.rotation_euler=(Vector((17,12,2))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=58
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_OUT/'environment_library.blend'))
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    # Alpha bounding boxes use the image pixels, never a guessed UI anchor.
    import subprocess
    script="from pathlib import Path;import json;from PIL import Image;p=Path(r'"+str(OUT)+"');m=json.loads((p/'manifest.json').read_text(encoding='utf-8'));[(a.update({'alpha_bbox':list(Image.open(p/(k+'.png')).getbbox())}) if (p/(k+'.png')).exists() else None) for k,a in m['assets'].items()];(p/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')"
    subprocess.run(['E:/python/python.exe','-c',script],check=True)
    print('ENVIRONMENT_LIBRARY_COMPLETE',flush=True)

if __name__=='__main__':render_library()
