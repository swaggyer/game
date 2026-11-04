import bpy, math, random, json, os, traceback
from mathutils import Vector
from pathlib import Path

ROOT=Path(r'E:\game\StarLanternIsland\source_models\world')
random.seed(20261103)
REPORT={'style':'Rounded handcrafted starlight fantasy; warm ivory, midnight blue, brass, cyan/amber glow','props':[],'scenes':[],'warnings':[]}

def material(name, rgb, metallic=0, rough=.55, emission=0, alpha=1):
    # Palette values are artist-facing sRGB; convert to linear Blender shader inputs.
    rgb=tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb)
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color=(*rgb,alpha);m.use_nodes=True
    n=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if n is None:
        n=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
        out=next((n for n in m.node_tree.nodes if n.type=='OUTPUT_MATERIAL'),None) or m.node_tree.nodes.new('ShaderNodeOutputMaterial')
        m.node_tree.links.new(n.outputs['BSDF'],out.inputs['Surface'])
    n.inputs['Base Color'].default_value=(*rgb,alpha)
    n.inputs['Metallic'].default_value=metallic;n.inputs['Roughness'].default_value=rough
    n.inputs['Alpha'].default_value=alpha
    if emission:
        n.inputs['Emission Color'].default_value=(*rgb,1);n.inputs['Emission Strength'].default_value=emission
    return m

M={
'ivory':material('Warm ivory stone',(.82,.79,.65)),
'stone':material('Pearl stone',(.64,.72,.69)),
'stone_dark':material('Blue grey stone',(.27,.38,.44)),
'navy':material('Midnight blue enamel',(.035,.13,.23),.12,.36),
'roof':material('Deep peacock roof',(.055,.26,.34),.08,.4),
'gold':material('Brushed warm brass',(.72,.43,.12),.68,.32),
'wood':material('Honey wood',(.42,.22,.09)),
'wood_light':material('Warm cut wood',(.63,.39,.17)),
'wood_dark':material('Dark wood',(.19,.095,.055)),
'grass':material('Meadow jade',(.23,.48,.29)),
'grass_light':material('Fresh leaf',(.40,.63,.29)),
'leaf':material('Forest teal',(.10,.37,.28)),
'leaf_blue':material('Night forest blue leaf',(.085,.29,.34)),
'leaf_light':material('Canopy sage',(.30,.53,.36)),
'earth':material('Clay earth',(.37,.26,.17)),
'path':material('Soft golden sand',(.70,.58,.36)),
'water':material('Moon water',(.11,.43,.55),.15,.24),
'foam':material('Water glimmer',(.43,.84,.83),.05,.3,.35),
'cyan':material('Cyan starlight',(.12,.74,.89),.22,.25,2.3),
'amber':material('Amber starlight',(1,.49,.12),.15,.25,2.4),
'purple':material('Violet starlight',(.54,.28,.82),.2,.28,1.7),
'mint':material('Wind crystal',(.30,.89,.68),.2,.28,1.1),
'red':material('Apple red',(.75,.13,.075),.05,.37),
'flower':material('Ivory flower',(.98,.89,.59)),
'lavender':material('Lavender flower',(.58,.43,.79)),
'cloud':material('Cloud porcelain',(.77,.84,.9)),
'dark':material('Unlit lantern',(.06,.12,.16)),
'roof_edge':material('Roof edge',(.085,.20,.26)),
}

def finish(obj,name,mat,smooth=True):
    obj.name=name
    if mat:obj.data.materials.append(M[mat] if isinstance(mat,str) else mat)
    if obj.type=='MESH' and smooth:
        for p in obj.data.polygons:p.use_smooth=True
    return obj

def cube(name,loc,scale,mat,bevel=.07):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object
    o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Soft crafted edges','BEVEL');mod.width=bevel;mod.segments=3
        o.modifiers.new('Weighted soft normals','WEIGHTED_NORMAL')
    return finish(o,name,mat)

def uv(name,loc,scale,mat,segments=20,rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,radius=1,location=loc)
    o=bpy.context.object;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,mat)

def ico(name,loc,scale,mat,sub=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc)
    o=bpy.context.object;o.scale=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,mat)

def cyl(name,loc,radius,depth,mat,vertices=24,bevel=.045):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc)
    o=bpy.context.object
    if bevel:
        b=o.modifiers.new('Rounded rims','BEVEL');b.width=bevel;b.segments=3
        o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return finish(o,name,mat)

def cone(name,loc,r1,r2,depth,mat,vertices=24,bevel=.04):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r1,radius2=r2,depth=depth,location=loc)
    o=bpy.context.object
    if bevel:
        b=o.modifiers.new('Soft cone edges','BEVEL');b.width=bevel;b.segments=3
    return finish(o,name,mat)

def rod(name,a,b,radius,mat,vertices=16):
    a,b=Vector(a),Vector(b);o=cyl(name,(a+b)/2,radius,(b-a).length,mat,vertices, min(.025,radius*.3))
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def curve(name,pts,radius,mat):
    d=bpy.data.curves.new(name,'CURVE');d.dimensions='3D';d.resolution_u=12
    d.bevel_depth=radius;d.bevel_resolution=3
    sp=d.splines.new('BEZIER');sp.bezier_points.add(len(pts)-1)
    for p,co in zip(sp.bezier_points,pts):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.data.materials.append(M[mat]);return o

def torus(name,loc,major,minor,mat,rot=(0,0,0),segments=36):
    bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=segments,minor_segments=10,location=loc,rotation=rot)
    return finish(bpy.context.object,name,mat)

def star(name,loc,radius,mat,rotation=0,depth=.045):
    verts=[]
    for z in [-depth/2,depth/2]:
        for i in range(10):
            a=rotation+math.pi/2+i*math.pi/5;r=radius if i%2==0 else radius*.45
            verts.append((r*math.cos(a),r*math.sin(a),z))
    faces=[tuple(range(9,-1,-1)),tuple(range(10,20))]
    faces += [(i,(i+1)%10,(i+1)%10+10,i+10) for i in range(10)]
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.location=loc;finish(o,name,mat,False)
    return o

def grouped(fn,*args,loc=(0,0,0),scale=1,rotation=0,**kwargs):
    before=set(bpy.context.scene.objects);fn(*args,**kwargs);objs=[o for o in bpy.context.scene.objects if o not in before]
    e=bpy.data.objects.new(fn.__name__+'_instance',None);bpy.context.collection.objects.link(e)
    for o in objs:o.parent=e
    e.location=loc;e.scale=(scale,)*3;e.rotation_euler.z=rotation
    return e,objs

def lantern(lit=True,royal=False):
    n='royal' if royal else 'star_lantern';h=1.9 if royal else 1.35
    cube(n+'_foot',(0,0,.11),(.68,.68,.22),'stone_dark',.10)
    cube(n+'_base',(0,0,.27),(.50,.50,.18),'ivory',.055)
    cyl(n+'_pillar',(0,0,.57),.145,.58,'stone',16)
    torus(n+'_collar',(0,0,.81),.16,.035,'gold')
    cube(n+'_lower',(0,0,.92),(.46,.46,.12),'gold',.035)
    uv(n+'_glowing_core',(0,0,1.16),(.17,.17,.24),'amber' if lit else 'dark')
    for x in [-.21,.21]:
        for y in [-.21,.21]:rod(n+'_cage',(x,y,.98),(x*.85,y*.85,1.41),.025,'gold')
    cone(n+'_hat',(0,0,1.44),.36,.08,.22,'navy',8)
    uv(n+'_finial',(0,0,1.6),(.065,.065,.065),'gold')
    if royal:
        # A second crown halo makes the king lamp a distinct identifiable object.
        torus('royal_halo',(0,0,1.55),.40,.035,'gold',(math.pi/2,0,0))
        for a in [0,math.pi/2,math.pi,math.pi*1.5]:
            uv('royal_orbit_star',(.44*math.cos(a),0,1.55+.44*math.sin(a)),(.06,.04,.06),'cyan')
        for o in list(bpy.context.selected_objects):pass

def chest(opened=False):
    cube('chest_body',(0,0,.31),(1.05,.66,.54),'wood',.085)
    for x in [-.39,.39]:cube('chest_brass_band',(x,0,.35),(.09,.70,.63),'gold',.025)
    for i in range(4):cube('chest_plank_seam',(0,-.337,.15+i*.13),(.92,.015,.012),'wood_dark',.005)
    cube('chest_inside',(0,0,.61),(.86,.48,.025),'wood_dark',.02)
    before=set(bpy.context.scene.objects)
    # Lid has rounded overlapping wooden slats with three gold straps.
    lid=cube('rounded_chest_lid',(0,0,.72),(1.09,.71,.28),'wood_light',.13)
    for x in [-.40,.40]:cube('lid_band',(x,0,.75),(.10,.74,.26),'gold',.045)
    cube('chest_lock',(0,-.385,.60),(.18,.07,.23),'gold',.03)
    uv('lock_keyhole',(0,-.43,.61),(.026,.012,.036),'dark')
    if opened:
        e=bpy.data.objects.new('lid_hinge',None);bpy.context.collection.objects.link(e);e.location=(0,.31,.59)
        bpy.context.view_layer.update()
        for o in [o for o in bpy.context.scene.objects if o not in before and o != e]:
            world=o.matrix_world.copy();o.parent=e;o.matrix_world=world
        e.rotation_euler.x=math.radians(-70)
        uv('treasure_glow',(0,0,.72),(.29,.18,.10),'amber')
        for i in range(5):cyl('coins',(-.29+i*.14,0,.79),.095,.045,'gold',16)

def key():
    torus('key_bow',(0,0,.16),.26,.075,'gold')
    cube('key_shaft',(.52,0,.16),(.72,.13,.13),'gold',.025)
    for x in [.65,.83]:cube('key_tooth',(x,-.14,.16),(.13,.27,.14),'gold',.025)
    star('key_star',(0,0,.17),.13,'cyan')

def crystal(kind='common'):
    mat={'common':'cyan','fire':'amber','wind':'mint','water':'cyan','space':'purple'}[kind]
    verts=[]
    for z,r in [(0,.12),(.19,.31),(.65,.25),(1.08,0)]:
        for i in range(6):verts.append((r*math.cos(i*math.pi/3),r*math.sin(i*math.pi/3),z))
    faces=[]
    for j in range(3):
        for i in range(6):faces.append((j*6+i,j*6+(i+1)%6,(j+1)*6+(i+1)%6,(j+1)*6+i))
    faces.append(tuple(range(5,-1,-1)))
    me=bpy.data.meshes.new(kind+'_gem');me.from_pydata(verts,[],faces);me.update()
    o=bpy.data.objects.new(kind+'_source_crystal',me);bpy.context.collection.objects.link(o);finish(o,o.name,mat,False)
    torus('crystal_brass_socket',(0,0,.15),.25,.035,'gold')
    if kind != 'common':
        cyl('source_crystal_pedestal',(0,0,.06),.37,.12,'ivory',8)
        for i in range(3):
            a=i*math.tau/3;ico('small_crystal_satellite',(.5*math.cos(a),.5*math.sin(a),.2),(.09,.09,.17),mat,1)

def stone_bridge():
    for i in range(11):
        x=-1.5+i*.3;z=.32+.30*(1-(x/1.65)**2)
        cube('bridge_step',(x,0,z),(.29,1.10,.19),'ivory',.035)
        for y in [-.61,.61]:cube('bridge_rail_block',(x,y,z+.24),(.27,.15,.38),'stone',.025)
    for x in [-1.52,1.52]:
        for y in [-.61,.61]:cube('bridge_endpost',(x,y,.66),(.29,.29,.83),'stone_dark',.045)

def wood_bridge():
    for i in range(12):
        x=-1.38+i*.25;z=.18+.07*math.sin(i*math.pi/11)
        cube('wood_bridge_plank',(x,0,z),(.23,1.05,.12),'wood_light',.025)
    for y in [-.58,.58]:
        for x in [-1.45,0,1.45]:cyl('wood_post',(x,y,.56),.065,.95,'wood',12)
        curve('rope_rail',[(-1.45,y,.98),(-.72,y,.84),(0,y,.98),(.72,y,.84),(1.45,y,.98)],.025,'gold')

def mirror():
    cyl('mirror_pedestal',(0,0,.10),.48,.20,'stone_dark',16)
    cyl('mirror_column',(0,0,.49),.12,.62,'gold',16)
    o=cyl('mirror_disc',(0,0,1.16),.43,.07,'foam',32);o.rotation_euler.x=math.pi/2
    torus('mirror_frame',(0,-.045,1.16),.44,.055,'gold',(math.pi/2,0,0))
    for a in range(8):
        r=.53;t=a*math.tau/8
        uv('mirror_star_decoration',(r*math.cos(t),-.045,1.16+r*math.sin(t)),(.045,.03,.045),'gold')

def crate():
    cube('push_crate',(0,0,.5),(.98,.98,.98),'wood',.065)
    for side in [-1,1]:
        for i in range(4):
            cube('crate_front_plank',(-.36+i*.24,side*.501,.5),(.21,.025,.86),'wood_light',.01)
            cube('crate_side_plank',(side*.501,-.36+i*.24,.5),(.025,.21,.86),'wood_light',.01)
        for z in [.13,.87]:cube('crate_front_brace',(0,side*.535,z),(1.04,.07,.13),'wood',.02)
    for x in [-.4,.4]:
        for y in [-.4,.4]:uv('crate_brass_rivet',(x,y,1.01),(.035,.035,.02),'gold')

def windmill():
    cone('windmill_tower',(0,0,1.1),.67,.44,2.2,'ivory',24)
    for z in [.16,.85,1.6]:torus('tower_band',(0,0,z),.65-z*.09,.035,'stone')
    cone('windmill_roof',(0,0,2.38),.70,.06,.62,'navy',24)
    cube('windmill_door',(0,-.61,.43),(.30,.05,.75),'wood_dark',.14)
    for x in [-.27,.27]:
        uv('windmill_window',(x,-.48,1.4),(.09,.03,.12),'amber')
    hub=(0,-.67,1.95)
    for angle in [math.pi/4+i*math.pi/2 for i in range(4)]:
        end=(math.cos(angle)*1.65,-.67,1.95+math.sin(angle)*1.65)
        rod('wind_sail_arm',hub,end,.055,'wood')
        for d in [.48,.75,1.02,1.29,1.55]:
            x,z=d*math.cos(angle),1.95+d*math.sin(angle)
            q=cube('wind_sail_panel',(x,-.68,z),(.47,.055,.22),'wood_light',.025);q.rotation_euler.y=-angle+math.pi/2
    uv('windmill_hub',hub,(.18,.13,.18),'gold')

def star_gate():
    cyl('gate_platform',(0,0,.10),1.22,.20,'stone_dark',40)
    cyl('gate_inlay',(0,0,.22),1.08,.08,'ivory',40)
    for x in [-.88,.88]:
        cube('gate_pillar',(x,0,1.20),(.32,.45,2.0),'ivory',.11)
        cube('gate_pillar_foot',(x,0,.36),(.52,.62,.22),'gold',.06)
        for z in [.7,1.3,1.9]:cube('gate_runic_inlay',(x,-.235,z),(.07,.025,.20),'cyan',.025)
    # Eight curved arch segments preserve an open, genuinely passable doorway.
    pts=[]
    for i in range(9):
        a=i*math.pi/8;pts.append((.89*math.cos(a),0,2.03+.89*math.sin(a)))
    for a,b in zip(pts[:-1],pts[1:]):rod('gate_arch_segment',a,b,.18,'ivory',16)
    curve('star_gate_glowing_inner_rim',[(.73,0,1.2),(.73,0,2.04),(.52,0,2.60),(0,0,2.78),(-.52,0,2.6),(-.73,0,2.04),(-.73,0,1.2)],.035,'cyan')
    st=star('gate_crown_star',(0,-.23,2.97),.21,'gold');st.rotation_euler.x=math.pi/2
    for i in range(6):
        a=i*math.tau/6;uv('portal_orbit_spark',(.56*math.cos(a),0,1.5+.60*math.sin(a)),(.04,.025,.04),'cyan')

def basket():
    cone('supply_basket',(0,0,.27),.29,.42,.48,'wood_light',20)
    for z in [.11,.24,.38,.49]:torus('basket_weave',(0,0,z),.30+.24*z,.02,'wood')
    curve('basket_handle',[(-.37,0,.46),(-.34,0,.92),(0,0,1.05),(.34,0,.92),(.37,0,.46)],.04,'wood')
    for x,y in [(-.17,-.05),(.16,-.03),(0,.18)]:apple(x,y,.56)

def apple(x=0,y=0,z=.25):
    uv('apple',(x,y,z),(.20,.19,.20),'red')
    rod('apple_stem',(x,y,z+.15),(x+.035,y,z+.28),.018,'wood')
    o=uv('apple_leaf',(x+.08,y,z+.22),(.10,.035,.028),'grass_light');o.rotation_euler.y=-.35

def apples():
    for x,y,z in [(-.15,0,.19),(.19,.08,.19),(.04,-.15,.43)]:apple(x,y,z)

def signpost():
    cyl('signpost_post',(0,0,.65),.07,1.3,'wood',12)
    cube('signboard',(0,0,1.08),(.92,.14,.36),'wood_light',.07)
    for x in [-.35,.35]:uv('sign_rivet',(x,-.085,1.08),(.035,.015,.035),'gold')
    # Clear geometric arrow, no invented unreadable text.
    cube('sign_arrow_shaft',(-.03,-.084,1.08),(.35,.025,.055),'ivory',.01)
    o=cube('sign_arrow_tip',(.14,-.086,1.08),(.15,.025,.15),'ivory',.01);o.rotation_euler.y=math.pi/4

def tree(kind='round'):
    rod('tree_trunk',(0,0,0),(.08,.04,1.45),.16,'wood')
    rod('tree_branch',(.03,0,.8),(-.43,0,1.55),.075,'wood')
    rod('tree_branch',(.06,0,1.1),(.48,.10,1.75),.065,'wood')
    if kind=='fir':
        for z,r in [(1.0,.82),(1.5,.71),(2.0,.53),(2.40,.34)]:
            ico('fir_soft_canopy',(0,0,z),(r,r,.58),'leaf_blue',2)
    else:
        for x,y,z,s in [(-.45,0,1.75,.68),(.40,.13,1.95,.70),(0,-.35,2.05,.74),(0,.12,2.42,.71)]:
            ico('round_canopy',(x,y,z),(s,s,s*.78),['leaf','leaf_light','grass'][int((z*10)%3)],2)
        for i in range(6):
            a=i*math.tau/6;uv('canopy_leaf_detail',(.60*math.cos(a),.4*math.sin(a),2.15),(.15,.10,.07),'grass_light',12,8)

def waterwheel():
    axis=rod('waterwheel_axis',(0,-.42,1.0),(0,.42,1.0),.12,'wood_dark')
    for y in [-.31,.31]:
        torus('waterwheel_rim',(0,y,1.0),.84,.085,'wood',(math.pi/2,0,0))
        for a in range(8):
            t=a*math.tau/8;rod('waterwheel_spoke',(0,y,1.0),(.80*math.cos(t),y,1+.80*math.sin(t)),.045,'wood_light')
    for a in range(12):
        t=a*math.tau/12;o=cube('waterwheel_paddle',(.89*math.cos(t),0,1+.89*math.sin(t)),(.28,.80,.10),'wood_light',.025);o.rotation_euler.y=-t

def arch():
    for x in [-.82,.82]:
        cube('ruin_pillar_foot',(x,0,.13),(.64,.67,.26),'stone_dark',.07)
        for i in range(5):cube('ruin_pillar_block',(x,0,.43+i*.33),(.44,.50,.31),'ivory',.035)
        cube('ruin_capital',(x,0,1.98),(.65,.62,.22),'ivory',.04)
    for i in range(7):
        a=math.pi*(i+.5)/7;o=cube('ruin_arch_block',(.84*math.cos(a),0,1.97+.84*math.sin(a)),(.37,.56,.40),'ivory',.035);o.rotation_euler.y=-a+math.pi/2
    for x in [-.82,.82]:
        uv('ruin_crystal_inlay',(x,-.26,1.1),(.06,.035,.18),'cyan')

def throne():
    for z,sz in [(.10,1.4),(.27,1.18)]:cube('throne_platform',(0,0,z),(sz,1.1,.18),'ivory',.10)
    cube('throne_seat',(0,0,.70),(.94,.80,.30),'navy',.13)
    cube('throne_back',(0,.33,1.25),(.95,.22,1.35),'ivory',.16)
    cube('throne_back_cushion',(0,.19,1.33),(.67,.07,.90),'navy',.12)
    for x in [-.55,.55]:
        cube('throne_arm',(x,0,1.0),(.18,.9,.18),'gold',.07)
        curve('throne_dragon_horn',[(x,.34,1.4),(x*1.3,.35,1.88),(x*1.1,.35,2.2)],.08,'gold')
    uv('throne_star_jewel',(0,.15,1.54),(.15,.045,.22),'cyan')
    st=star('throne_crown_star',(0,.12,2.03),.23,'gold');st.rotation_euler.x=math.pi/2

PROPS=[
('star_lantern_lit',lambda:lantern(True)),('star_lantern_unlit',lambda:lantern(False)),
('royal_lantern',lambda:lantern(True,True)),('chest_closed',lambda:chest(False)),('chest_open',lambda:chest(True)),
('star_key',key),('crystal_common',lambda:crystal('common')),('crystal_fire',lambda:crystal('fire')),
('crystal_wind',lambda:crystal('wind')),('crystal_water',lambda:crystal('water')),('crystal_space',lambda:crystal('space')),
('stone_bridge',stone_bridge),('wood_bridge',wood_bridge),('mirror_mechanism',mirror),('push_crate',crate),
('windmill_mechanism',windmill),('star_gate',star_gate),('supply_basket',basket),('apple_cluster',apples),
('signpost',signpost),('tree_round',lambda:tree('round')),('tree_fir',lambda:tree('fir')),
('water_wheel',waterwheel),('ruin_arch',arch),('dragon_throne',throne)]

def clear_scene():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)

def setup_render(transparent=False,res=(960,800),night=False,ortho=14):
    s=bpy.context.scene;s.render.engine='BLENDER_EEVEE';s.render.resolution_x=res[0];s.render.resolution_y=res[1];s.render.resolution_percentage=100
    s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA';s.render.film_transparent=transparent
    s.render.threads_mode='FIXED';s.render.threads=2
    s.world.color=(.14,.18,.24) if night else (.52,.56,.59)
    s.world.use_nodes=True
    bg=next((n for n in s.world.node_tree.nodes if n.type=='BACKGROUND'),None) or s.world.node_tree.nodes.new('ShaderNodeBackground')
    wo=next((n for n in s.world.node_tree.nodes if n.type=='OUTPUT_WORLD'),None) or s.world.node_tree.nodes.new('ShaderNodeOutputWorld')
    s.world.node_tree.links.new(bg.outputs[0],wo.inputs['Surface'])
    bg.inputs['Color'].default_value=(.10,.16,.25,1) if night else (.63,.70,.73,1)
    bg.inputs['Strength'].default_value=.40 if night else .65
    try:s.eevee.taa_render_samples=32
    except:pass
    s.view_settings.view_transform='AgX'
    for name,loc,power,size,col in [('Softbox',(0,-6,12),1500,9,(1,.87,.69)),('Sky rim',(4,6,9),2000,8,(.44,.71,1)),('Gentle fill',(-7,-1,5),700,8,(.80,.90,1))]:
        d=bpy.data.lights.new(name,'AREA');d.energy=power*(.75 if night else 1);d.shape='DISK';d.size=size;d.color=col
        o=bpy.data.objects.new(name,d);s.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
    d=bpy.data.cameras.new('Presentation camera');o=bpy.data.objects.new('Presentation camera',d);s.collection.objects.link(o)
    o.location=(12,-18,15);o.rotation_euler=(Vector((0,0,.7))-o.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=ortho;s.camera=o
    # Modest glow; compositing keeps actual alpha in sprite outputs.
    # New Blender versions may use node-group compositing; the PBR render is complete without it.
    try:
        s.use_nodes=True;nodes=s.node_tree.nodes;nodes.clear();rl=nodes.new('CompositorNodeRLayers');gl=nodes.new('CompositorNodeGlare');gl.glare_type='FOG_GLOW';gl.quality='HIGH';gl.threshold=1.5
        out=nodes.new('CompositorNodeComposite');s.node_tree.links.new(rl.outputs['Image'],gl.inputs['Image']);s.node_tree.links.new(gl.outputs['Image'],out.inputs['Image'])
    except Exception:
        s.use_nodes=False
    return s

def render(path):
    bpy.context.scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)

def meshes_objects(objs):return [o for o in objs if o.type in {'MESH','CURVE','EMPTY'}]

def export_glb(path,objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes_objects(objs):o.select_set(True)
    if objs:bpy.context.view_layer.objects.active=objs[0]
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True)

def bounds(objs):
    pts=[o.matrix_world@Vector(c) for o in objs if o.type in {'MESH','CURVE'} for c in o.bound_box]
    lo=[min(p[i] for p in pts) for i in range(3)];hi=[max(p[i] for p in pts) for i in range(3)]
    return lo,hi

def mesh_stats(objs):
    dg=bpy.context.evaluated_depsgraph_get();tri=0;num=0
    for o in objs:
        if o.type in {'MESH','CURVE'}:
            eo=o.evaluated_get(dg);me=eo.to_mesh();tri+=sum(max(0,len(p.vertices)-2) for p in me.polygons);num+=1;eo.to_mesh_clear()
    return {'mesh_objects':num,'evaluated_triangles':tri}

def build_prop_library():
    clear_scene();s=setup_render(True,(512,512),ortho=4)
    entries=[]
    for idx,(name,fn) in enumerate(PROPS):
        before=set(s.objects);fn();objs=[o for o in s.objects if o not in before];bpy.context.view_layer.update()
        lo,hi=bounds(objs);center=Vector([(lo[i]+hi[i])/2 for i in range(3)]);extent=max(hi[i]-lo[i] for i in range(3))
        s.camera.location=center+Vector((5,-8,6));s.camera.rotation_euler=(center-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.ortho_scale=max(1.3,extent*1.6)
        export_glb(ROOT/'props'/(name+'.glb'),objs)
        render(ROOT/'renders'/(name+'.png'))
        stats=mesh_stats(objs);entry={'id':name,'glb':str(ROOT/'props'/(name+'.glb')),'sprite':str(ROOT/'renders'/(name+'.png')),'bounds':[lo,hi],**stats};REPORT['props'].append(entry)
        # Keep previously made props out of the icon camera until the library arrangement.
        for o in objs:o.hide_render=True
        entries.append((name,objs))
        print('PROP_DONE',name,flush=True)
    for idx,(name,objs) in enumerate(entries):
        offset=Vector(((idx%5-2)*4.5,(idx//5-2)*4.6,0))
        for o in objs:
            if o.parent not in objs:o.location+=offset
            o.hide_render=False
        # Save individual named collections for easy editing and reusable asset browsing.
        col=bpy.data.collections.new(name);s.collection.children.link(col)
        for o in objs:
            for c in list(o.users_collection):c.objects.unlink(o)
            col.objects.link(o)
    s.camera.location=(19,-29,29);s.camera.rotation_euler=(Vector((0,0,.5))-s.camera.location).to_track_quat('-Z','Y').to_euler();s.camera.data.ortho_scale=34
    s.render.resolution_x=1500;s.render.resolution_y=1400;s.render.film_transparent=False
    cube('library_backdrop',(0,0,-.25),(28,28,.2),'stone',.2)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'world_library.blend'))
    render(ROOT/'renders'/'world_library.png')
    (ROOT/'reports'/'manifest-in-progress.json').write_text(json.dumps(REPORT,ensure_ascii=False,indent=2),encoding='utf-8')

def base(kind='grass',round=False):
    if round:
        cyl('island_earth',(0,0,-.48),4.5,.95,'earth',64,.18)
        cyl('island_surface',(0,0,.02),4.6,.20,kind,64,.15)
    else:
        cube('diorama_earth',(0,0,-.40),(9.6,8.6,.85),'earth',.4)
        cube('diorama_surface',(0,0,.02),(9.7,8.7,.20),kind,.4)
    for i in range(16):
        x=-4.5+i*.6
        if random.random()<.7:ico('diorama_edge_pebble',(x,-4.18,-.14),(.20,.14,.17),'stone_dark',1)

def path(points,width=.75):
    for a,b in zip(points[:-1],points[1:]):
        mid=(Vector(a)+Vector(b))/2;v=Vector(b)-Vector(a)
        o=cube('sandy_path',(mid.x,mid.y,.14),(width,v.length+.25,.035),'path',.20);o.rotation_euler.z=-math.atan2(v.x,v.y)

def flower(x,y,z=.19):
    mat=random.choice(['flower','lavender'])
    for a in [i*math.tau/5 for i in range(5)]:uv('flower_petal',(x+.06*math.cos(a),y+.06*math.sin(a),z),(.055,.045,.025),mat,8,6)
    uv('flower_heart',(x,y,z+.02),(.03,.03,.025),'amber',8,6)

def scatter_flowers(n,region=(-4.3,4.3,-3.9,3.8)):
    for i in range(n):flower(random.uniform(*region[:2]),random.uniform(*region[2:]))

def stepping_stones(points):
    for i,(x,y) in enumerate(points):
        o=cyl('stepping_stone',(x,y,.19),random.uniform(.18,.30),.10,'stone',7);o.scale.y=.70;o.rotation_euler.z=i*.7

def house(size=1):
    cube('cottage_foundation',(0,0,.19),(2.25,1.95,.31),'stone_dark',.10)
    cube('cottage_plaster',(0,0,1.08),(2.10,1.8,1.64),'ivory',.10)
    for x in [-1.0,1.0]:cube('cottage_corner_beam',(x,-.925,1.05),(.12,.08,1.7),'wood',.02)
    cube('cottage_door',(0,-.945,.76),(.62,.07,1.15),'wood',.27)
    cube('door_window',(0,-.987,1.08),(.35,.025,.34),'amber',.11)
    uv('door_handle',(.22,-1.0,.65),(.045,.025,.045),'gold')
    for x in [-.69,.69]:
        o=cyl('cottage_round_window',(x,-.93,1.12),.22,.055,'cyan',32);o.rotation_euler.x=math.pi/2
        torus('cottage_window_frame',(x,-.97,1.12),.23,.035,'wood',(math.pi/2,0,0))
        cube('window_mullion',(x,-1.01,1.12),(.025,.025,.40),'wood',.005)
        cube('flower_windowbox',(x,-1.02,.79),(.56,.26,.16),'wood',.035)
        for dx in [-.15,0,.15]:uv('windowbox_leaf',(x+dx,-1.02,.92),(.10,.08,.11),'grass_light')
    # Two gabled roof slopes, tiled in repeated overlapping rows.
    pitch=.57
    for side in [-1,1]:
        for row in range(5):
            x=side*(.16+row*.25);z=2.63-row*.155
            for col in range(7):
                o=cube('handmade_roof_tile',(x,-1.12+col*.37,z),(.36,.39,.085),'roof',.05);o.rotation_euler.y=side*pitch
        rod('roof_gable_trim',(side*1.34,-1.31,1.85),(0,-1.31,2.73),.06,'gold')
    rod('roof_ridge',(0,-1.29,2.73),(0,1.30,2.73),.08,'roof_edge')
    cube('cottage_chimney',(.72,.56,2.30),(.38,.40,.94),'stone',.05)
    cube('chimney_cap',(.72,.56,2.82),(.53,.53,.12),'ivory',.05)
    cube('front_step',(0,-1.21,.20),(.88,.43,.18),'ivory',.07)

def fence(a,b):
    a,b=Vector(a),Vector(b);v=b-a;num=max(2,int(v.length/.65)+1)
    for i in range(num):
        p=a+v*i/(num-1);cube('fence_picket',(p.x,p.y,.54),(.13,.12,.82),'wood_light',.05)
    rod('fence_rail',(a.x,a.y,.65),(b.x,b.y,.65),.055,'wood')

def river():
    xs=[];verts=[]
    for i in range(25):
        y=-4.2+i*.35;x=2.4+.35*math.sin(y)
        verts.extend([(x-.52,y,.16),(x+.52,y,.16)])
    faces=[(2*i,2*i+1,2*i+3,2*i+2) for i in range(24)]
    me=bpy.data.meshes.new('meandering_stream');me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new('meandering_stream',me);bpy.context.collection.objects.link(o);finish(o,o.name,'water')
    for y in [-3.0,-1.7,.2,1.7,3.2]:cube('water_sparkle',(2.4+.35*math.sin(y),y,.17),(.35,.035,.015),'foam',.015)

def village():
    base();river();path([(-1,-4),(0,-2.2),(-.8,.1),(-1.5,1.0)],.80)
    grouped(house,loc=(-1.5,1.75,.12),scale=1.10)
    grouped(house,loc=(3.55,2.5,.12),scale=.58)
    grouped(wood_bridge,loc=(2.15,-1.2,.10),scale=.80)
    grouped(lantern,loc=(.38,-.1,.14),scale=1.1)
    grouped(signpost,loc=(-1.3,-2.7,.14),scale=.8,rotation=-.15)
    grouped(basket,loc=(-.8,.2,.14),scale=.75)
    grouped(chest,loc=(-2.65,-.85,.14),scale=.63)
    for x,y,s in [(-3.5,2.6,1.0),(-3.4,-2.2,1.1),(.5,3.1,.85),(3.9,-3.0,.8)]:grouped(tree,loc=(x,y,.14),scale=s)
    fence((-4.2,-.2,0),(-3.2,-.2,0));fence((-.2,3.8,0),(1.25,3.8,0))
    stepping_stones([(-.2,-2.7),(-.45,-2.0),(-.55,-1.2),(-.80,-.45)])
    scatter_flowers(35)

def forest():
    base();path([(0,-4),(-.45,-2.5),(.2,-.5),(0,1.8)],.7)
    for x,y,s in [(-3.7,2.6,1.32),(-2.1,3.0,1.13),(.2,3.3,1.03),(2.7,2.7,1.28),(3.5,.9,1.14),(-3.5,-.2,1.19),(-3.2,-2.7,.92),(3.7,-2.9,.96)]:grouped(tree,'fir',loc=(x,y,.14),scale=s)
    grouped(arch,loc=(.0,1.6,.14),scale=.85)
    grouped(crystal,'fire',loc=(0,1.5,.16),scale=.7)
    for x,y in [(-1.2,-2.4),(1.2,.1),(-1.25,1.1)]:grouped(lantern,loc=(x,y,.14),scale=.65)
    grouped(chest,True,loc=(2.1,-.45,.14),scale=.65)
    for i in range(18):
        x,y=random.uniform(-3.7,3.7),random.uniform(-3.2,2.8)
        cyl('mushroom_stem',(x,y,.25),.055,.22,'ivory',12)
        uv('glowing_mushroom_cap',(x,y,.40),(.18,.18,.11),'cyan' if i%3 else 'purple',16,8)
    for i in range(27):
        uv('forest_firefly',(random.uniform(-3,3),random.uniform(-2.6,2.8),random.uniform(.7,2.8)),(.022,.022,.022),'amber',8,6)
    for i in range(10):
        x=random.uniform(-3,3);y=random.uniform(-2,3);ico('mossy_rock',(x,y,.28),(.34,.28,.23),'leaf_blue',1)
    scatter_flowers(18)

def wind_field():
    base();path([(-1,-4),(-.5,-1.7),(1,0),(1.2,2)],.85)
    grouped(windmill,loc=(1.1,1.7,.14),scale=1.20)
    grouped(house,loc=(-2.6,2.1,.14),scale=.70)
    grouped(lantern,loc=(-.5,.25,.14),scale=.80)
    grouped(crate,loc=(-1.7,-.8,.14),scale=.7);grouped(crate,loc=(-2.3,-.55,.14),scale=.58)
    grouped(crystal,'wind',loc=(2.7,-2.25,.14),scale=.75)
    grouped(signpost,loc=(.5,-2.65,.14),scale=.80)
    for x0,y0 in [(-3.0,-2.3),(2.7,.3)]:
        cube('wheat_plot',(x0,y0,.15),(1.8,1.25,.10),'earth',.15)
        for i in range(6):
            for j in range(4):
                x=x0-.72+i*.28;y=y0-.46+j*.30;h=random.uniform(.43,.66)
                rod('wheat_stalk',(x,y,.19),(x+.06,y,.19+h),.018,'wood_light',8)
                uv('wheat_head',(x+.06,y,.21+h),(.055,.045,.13),'flower',10,6)
    fence((-4.1,.0,0),(-2.5,0,0));fence((2.2,-3.8,0),(4.0,-3.8,0))
    for x,y,s in [(-3.9,3.0,.9),(3.8,3.2,.9),(-3.8,-.9,.65)]:grouped(tree,loc=(x,y,.14),scale=s)
    scatter_flowers(34)

def willow(x,y,scale=1):
    e,objs=grouped(tree,loc=(x,y,.12),scale=scale)
    for i in range(7):
        a=i*math.tau/7;xx=x+.6*scale*math.cos(a);yy=y+.6*scale*math.sin(a)
        curve('willow_hanging_leaf',[(xx,yy,1.9*scale),(xx+.08,yy,1.4*scale),(xx,yy,.9*scale)],.075*scale,'leaf')

def water_town():
    base('stone_dark');cube('water_lake',(0,0,.16),(9.3,8.3,.12),'water',.35)
    for x,y,r in [(-2.8,1.5,2.0),(2.3,2.4,1.8),(1.6,-2.4,1.9),(-3.2,-2.9,1.05)]:
        cyl('shore_stone',(x,y,.27),r,.26,'stone',48,.13);cyl('shore_grass',(x,y,.42),r-.10,.12,'grass',48,.1)
    grouped(house,loc=(-2.75,1.55,.48),scale=.85)
    grouped(stone_bridge,loc=(.0,1.0,.17),scale=.80)
    grouped(wood_bridge,loc=(1.5,-.3,.15),scale=.75,rotation=math.pi/2)
    grouped(waterwheel,loc=(-1.6,.7,.28),scale=.75,rotation=.2)
    grouped(lantern,loc=(1.0,-2.4,.48),scale=.95)
    grouped(crystal,'water',loc=(2.45,2.4,.48),scale=.85)
    willow(3.0,-2.4,.85);willow(3.1,2.8,.72)
    for i in range(18):
        x,y=random.uniform(-4.2,4.2),random.uniform(-3.7,3.7)
        if abs(x)<.8 or abs(y)<.6:
            cyl('lily_pad',(x,y,.25),.16,.025,'grass_light',16,.01)
            if i%3==0:flower(x,y,.29)
    for x,y in [(-.6,-2.5),(.3,3.1),(3.7,0),(-3.8,-.6)]:
        for j in range(3):cube('moon_water_ripple',(x,y+j*.15,.24),(.45-j*.08,.025,.015),'foam',.01)

def ruins():
    base('stone_dark');cube('ruin_moss_platform',(0,0,.19),(8.4,7.4,.25),'grass',.25)
    for i in range(7):
        for j in range(6):
            if random.random()>.14:
                cube('ancient_floor_tile',(-3.5+i*1.14,-2.9+j*1.14,.36),(1.06,1.06,.13),'ivory' if (i+j)%4 else 'stone',.045)
    grouped(arch,loc=(0,2.2,.43),scale=1.25)
    for x in [-2.8,2.8]:
        for y in [-1.7,1.5]:
            for k in range(3 if y<0 else 5):cube('broken_colonnade',(x,y,.62+k*.33),(.52,.53,.31),'stone',.04)
            cube('column_capital',(x,y,1.58 if y<0 else 2.24),(.72,.72,.18),'ivory',.04)
    cyl('star_puzzle_platform',(0,-.55,.46),1.15,.13,'navy',10)
    star('ancient_star_floor',(0,-.55,.54),.90,'gold',depth=.025)
    grouped(mirror,loc=(-1.8,-.6,.43),scale=.82,rotation=-.45)
    grouped(mirror,loc=(1.9,.7,.43),scale=.82,rotation=.50)
    grouped(crystal,'space',loc=(0,2.1,.43),scale=.8)
    grouped(chest,True,loc=(2.65,2.8,.43),scale=.62)
    for x,y in [(-1.35,1.65),(1.35,1.65)]:grouped(lantern,loc=(x,y,.43),scale=.80)
    for i in range(12):
        x,y=random.uniform(-3.7,3.7),random.uniform(-3.0,3.1)
        ico('soft_moss_patch',(x,y,.43),(.20,.17,.07),'leaf_light',1)

def star_island():
    # Layered floating rock, with all crystal roots and clouds modelled geometry.
    cone('floating_island_lower',(0,0,-1.45),1.2,4.2,2.7,'stone_dark',14,.18)
    cyl('floating_island_upper',(0,0,-.15),4.4,.45,'stone',64,.18)
    cyl('floating_island_garden',(0,0,.13),4.28,.15,'grass',64,.12)
    for i in range(12):
        a=i*math.tau/12;r=random.uniform(2.2,3.8)
        ico('island_crystal_root',(r*math.cos(a),r*math.sin(a),-.80),(.20,.20,.68),'cyan' if i%2 else 'purple',1)
    for i in range(10):
        a=i*math.tau/10;r=4.2
        uv('cloud_cluster',(r*math.cos(a),r*math.sin(a),-1.2+random.uniform(-.2,.2)),(1.15,.9,.43),'cloud')
    path([(0,-3.8),(0,-2),(0,-.1),(0,2.1)],.94)
    for i in range(4):cube('royal_steps',(0,-.10+i*.42,.25+i*.13),(2.3,.52,.18),'ivory',.06)
    cyl('royal_lamp_dais',(0,1.0,.70),1.25,.24,'stone_dark',40)
    star('dais_star',(0,1.0,.83),1.04,'gold',depth=.025)
    grouped(lantern,True,True,loc=(0,1.0,.84),scale=1.10)
    grouped(star_gate,loc=(-2.4,1.65,.2),scale=.80,rotation=.13)
    grouped(throne,loc=(2.35,1.75,.2),scale=.85,rotation=-.30)
    for x,y in [(-1.5,-2.0),(1.5,-2.0),(-2.7,-.5),(2.7,-.5)]:grouped(lantern,loc=(x,y,.22),scale=.75)
    for x,y in [(-3.0,-1.8),(3.0,-1.8)]:grouped(tree,'fir',loc=(x,y,.20),scale=.70)
    for i in range(16):
        a=i*math.tau/16;r=random.uniform(4.5,5.4);z=random.uniform(1,4)
        uv('star_sea_spark',(r*math.cos(a),r*math.sin(a),z),(.025,.025,.025),'amber' if i%2 else 'cyan',8,6)

SCENES=[('01_home_village',village,False),('02_firefly_forest',forest,True),('03_windmill_meadow',wind_field,False),('04_moon_water_town',water_town,True),('05_old_king_ruins',ruins,False),('06_star_lantern_island',star_island,True)]

def build_scenes():
    for name,fn,night in SCENES:
        clear_scene();fn();bpy.context.view_layer.update();geo=list(bpy.context.scene.objects)
        export_glb(ROOT/'scenes'/(name+'.glb'),geo)
        stats=mesh_stats(geo);lo,hi=bounds(geo)
        setup_render(False,(1200,1000),night,15.0 if name.startswith('06') else 14.2)
        # A matte backdrop exists only in the presentation scene, never in exported GLB.
        backdrop=material('Backdrop '+name,(.035,.075,.13) if night else (.66,.72,.69))
        cube('presentation_backdrop',(0,0,-3.0 if name.startswith('06') else -.95),(200,200,.1),backdrop,.0)
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'scenes'/(name+'.blend')))
        render(ROOT/'renders'/(name+'.png'))
        entry={'id':name,'blend':str(ROOT/'scenes'/(name+'.blend')),'glb':str(ROOT/'scenes'/(name+'.glb')),'preview':str(ROOT/'renders'/(name+'.png')),'bounds':[lo,hi],**stats}
        REPORT['scenes'].append(entry);(ROOT/'reports'/'manifest-in-progress.json').write_text(json.dumps(REPORT,ensure_ascii=False,indent=2),encoding='utf-8')
        print('SCENE_DONE',name,flush=True)

if __name__=='__main__':
    try:
        build_prop_library();build_scenes()
        REPORT['coordinate_system']='Blender Z-up source; GLB exported glTF Y-up. Units are metres. Individual props rest at Z=0 in Blender.'
        REPORT['animation']='Static editable environment/prop meshes. No skeletal animation claimed.'
        REPORT['source_library']=str(ROOT/'world_library.blend')
        REPORT['notes']=['Every prop has a separately rendered RGBA transparent PNG.','All .glb assets contain real mesh geometry and PBR materials, not concept-sheet planes.','Dioramas are visual scene kits; collision, navigation and gameplay must be authored in Godot.']
        (ROOT/'reports'/'manifest.json').write_text(json.dumps(REPORT,ensure_ascii=False,indent=2),encoding='utf-8')
        print('WORLD_COMPLETE',len(REPORT['props']),len(REPORT['scenes']),flush=True)
    except Exception as ex:
        REPORT['warnings'].append(traceback.format_exc());(ROOT/'reports'/'failed-build.json').write_text(json.dumps(REPORT,ensure_ascii=False,indent=2),encoding='utf-8');raise
