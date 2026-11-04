extends Node2D
## Seven fixed, explorable regions. Geometry, navigation and art share one map definition.

const WORLD_RECT := Rect2(100, 100, 3400, 2400)
const GRID_SIZE := 50.0
const LandscapeRenderer=preload("res://scripts/landscape_renderer.gd")
const PALETTES := [
	["#36594d","#52725b","#223f3c","#a5a07d","#c0c0a0","#204d5a","#61846a","#ebd29a"],
	["#284e47","#3f6755","#183b36","#899373","#adb69a","#1d4b5c","#4d7c63","#b2dccc"],
	["#667a52","#819165","#415b48","#b5ad82","#d1c69e","#326174","#91a16c","#f0d690"],
	["#3d6867","#60877b","#284c59","#a5b8a3","#c6d4ba","#235970","#6b9b83","#edc2d2"],
	["#52615b","#6c7a66","#33494b","#a0a58d","#c0c7ad","#2a5360","#73917a","#c1dcd0"],
	["#424659","#596274","#2b324a","#93908e","#b8b4a8","#49385e","#697586","#d9bbdf"],
	["#426579","#5b8792","#2b415d","#afc2ba","#e0ddbd","#20344f","#7aa6a0","#ffe3a7"]
]

var definition: Dictionary = {}
var chapter := 0
var stage := 0
var palette: Array = []
var _solids: Array = []
var _water: Array = []
var _land: Array = []
var _bridges: Array = []
var _paths: Array = []
var _path_widths: Array = []
var _objective_sets: Array = []
var _structures: Array = []
var _art_props: Array = []
var _patches: Array = []
var _tufts: Array = []
var _flowers: Array = []
var _stones: Array = []
var _motes: Array = []
var _reeds: Array = []
var _shrubs: Array = []
var _lilies: Array = []
var _texture_cache: Dictionary = {}
var _bounds_cache: Dictionary = {}
var _nav := AStarGrid2D.new()
var _rng := RandomNumberGenerator.new()
var _props: Node2D
var _ambient: Node2D
var _landscape: Node2D
var _environment_manifest:Dictionary={}
var _time := 0.0
var _redraw_time := 0.0

class Structure:
	extends Node2D
	var kind := "house"
	var footprint := Vector2(210,100)
	var color := Color("#65878a")
	var glow := Color("#edce88")
	func _draw() -> void:
		var w := footprint.x
		var h := footprint.y
		if kind == "house":
			_oval(Vector2(0,3),Vector2(w*0.58,h*0.4),Color(0.02,0.08,0.1,0.25))
			draw_style_box(_box(Color("#65756b"),14),Rect2(-w/2,-h,w,h))
			draw_style_box(_box(Color("#aab096"),12),Rect2(-w/2+8,-h-78,w-16,h+63))
			var roof := PackedVector2Array([Vector2(-w*0.59,-h-53),Vector2(0,-h-139),Vector2(w*0.59,-h-53),Vector2(w*0.49,-h-32),Vector2(0,-h-96),Vector2(-w*0.49,-h-32)])
			draw_colored_polygon(roof,color)
			draw_polyline(PackedVector2Array([roof[0],roof[1],roof[2]]),color.lightened(0.2),5,true)
			for i in range(4):
				var y := -h-116.0+i*18
				var width := (y+h+139.0)*w/230.0
				draw_line(Vector2(-width,y),Vector2(width,y),color.darkened(0.13),2,true)
			draw_style_box(_box(Color("#3c5553"),13),Rect2(-24,-66,48,67))
			draw_circle(Vector2(13,-31),3,Color("#dbbd79"))
			for x in [-w*0.29,w*0.29]:
				draw_style_box(_box(Color("#4e655a"),6),Rect2(x-20,-h-38,40,38))
				draw_style_box(_box(glow,5),Rect2(x-15,-h-33,30,28))
				draw_line(Vector2(x,-h-33),Vector2(x,-h-5),Color("#798364"),3)
				draw_line(Vector2(x-15,-h-19),Vector2(x+15,-h-19),Color("#798364"),3)
			draw_line(Vector2(-w/2+4,-4),Vector2(w/2-4,-4),Color("#c0bfa2"),5,true)
		elif kind == "wall":
			var limestone:=Color("#a4ad92")
			draw_style_box(_box(limestone.darkened(0.35),6),Rect2(-w/2,-h+3,w,h+6))
			var rows:=maxi(1,int(ceil(h/29.0)))
			for row in range(rows):
				var top:float=-h-15+row*h/rows
				var pieces:=maxi(1,int(ceil(w/62.0)))
				for col in range(pieces):
					var left:float=-w/2+col*w/pieces
					var stone:=Rect2(left+1.3,top+1.2,w/pieces-2.6,h/rows-2.4)
					var tint:float=sin(row*8.1+col*5.2)*0.045
					draw_style_box(_box(limestone.lightened(tint),4),stone)
					draw_line(stone.position+Vector2(4,2),stone.position+Vector2(stone.size.x-4,2),limestone.lightened(0.21),1.3,true)
			draw_style_box(_box(limestone.lightened(0.15),4),Rect2(-w/2-2,-h-24,w+4,14))
			draw_line(Vector2(-w/2+1,-h-23),Vector2(w/2-1,-h-23),Color("#dae0ba"),2,true)
			for x in range(int(-w/2+20),int(w/2),43):
				draw_line(Vector2(x,-7),Vector2(x+11,-10),Color("#718758"),3.5,true)
		elif kind == "rock":
			_oval(Vector2(0,5),Vector2(w*0.61,h*0.43),Color(0.02,0.08,0.1,0.25))
			var points := PackedVector2Array([Vector2(-w*0.48,-h*0.22),Vector2(-w*0.4,-h*0.83),Vector2(-w*0.11,-h*1.12),Vector2(w*0.31,-h*0.93),Vector2(w*0.51,-h*0.38),Vector2(w*0.28,0),Vector2(-w*0.24,0)])
			draw_colored_polygon(points,color)
			draw_colored_polygon(PackedVector2Array([points[0],points[1],points[2],Vector2(-w*0.09,-h*0.35)]),color.lightened(0.14))
			draw_colored_polygon(PackedVector2Array([points[2],points[3],points[4],Vector2(w*0.09,-h*0.4)]),color.darkened(0.11))
			draw_polyline(PackedVector2Array([points[1],points[2],points[3]]),color.lightened(0.22),2,true)
	func _oval(p:Vector2,r:Vector2,c:Color) -> void:
		draw_set_transform(p,0,r)
		draw_circle(Vector2.ZERO,1,c)
		draw_set_transform(Vector2.ZERO)
	func _box(c:Color,r:int) -> StyleBoxFlat:
		var box := StyleBoxFlat.new()
		box.bg_color=c
		box.set_corner_radius_all(r)
		return box

func configure(chapter_index:int,stage_index:int) -> void:
	chapter=clampi(chapter_index,0,6)
	stage=clampi(stage_index,0,2)
	palette=PALETTES[chapter]
	z_index=-100
	_clear_art()
	_solids.clear();_water.clear();_land.clear();_bridges.clear()
	_paths.clear();_path_widths.clear();_structures.clear();_art_props.clear()
	_rng.seed=910733+chapter*1927
	match chapter:
		0:_village()
		1:_forest()
		2:_windmill()
		3:_water_town()
		4:_ruins()
		5:_rift()
		6:_island()
	definition["bounds"]=WORLD_RECT
	definition["chapter"]=chapter
	definition["stage"]=stage
	definition["safe"]=chapter==6 or (chapter==0 and stage==0)
	_filter_hazards()
	_build_navigation()
	_decorate()
	_landscape=LandscapeRenderer.new()
	_landscape.name="SunlitPainterlyLandscape"
	add_child(_landscape)
	_landscape.configure(self)
	_build_art()
	queue_redraw()
	_ambient.queue_redraw()

func _clear_art() -> void:
	if is_instance_valid(_landscape):
		remove_child(_landscape)
		_landscape.queue_free()
	if is_instance_valid(_props):
		remove_child(_props)
		_props.queue_free()
	if is_instance_valid(_ambient):
		remove_child(_ambient)
		_ambient.queue_free()
	_props=Node2D.new()
	_props.name="RegionLandmarks"
	add_child(_props)
	_ambient=Node2D.new()
	_ambient.name="WaterAndFireflies"
	_ambient.z_index=1
	_ambient.draw.connect(_draw_ambient)
	add_child(_ambient)

func _village() -> void:
	definition={"name":"星溪村 · 广场与果园","spawn":Vector2(650,1680),"lamp":Vector2(2810,670),
		"objectives":_objectives([[Vector2(820,950),Vector2(1770,1110),Vector2(2570,1460)],[Vector2(1150,1830),Vector2(2520,1130),Vector2(1770,1110)],[Vector2(900,740),Vector2(1700,1870),Vector2(2730,1050)]]),
		"zones":[{"name":"苹果果园","p":Vector2(660,830)},{"name":"守灯广场","p":Vector2(1770,1110)},{"name":"溪畔花园","p":Vector2(2730,1850)},{"name":"村口营地","p":Vector2(650,1680)},{"name":"北门灯塔","p":Vector2(2810,670)}],
		"chests":[Vector2(530,470),Vector2(3060,1000),Vector2(1460,2160),Vector2(3100,2180)],
		"camps":[Vector2(650,1680),Vector2(2810,670)],
		"patrols":[] if stage==0 else [_patrol("shadow_blob",1240,1540),_patrol("crystal_thief",2190,1130),_patrol("shadow_blob",2520,1710),_patrol("crystal_thief",1050,970)],
		"hazards":[] if stage==0 else [_hazard("spikes",1430,1450),_hazard("pendulum",2370,910,0.5),_hazard("shooter",2830,1570,PI)]}
	_water.append(_ellipse(Vector2(2770,1960),Vector2(370,265)))
	_path([Vector2(650,1680),Vector2(660,820),Vector2(1440,580),Vector2(2810,670),Vector2(3010,1320),Vector2(2680,1630),Vector2(2310,2160),Vector2(1190,2160),Vector2(650,1680)],190)
	_path([Vector2(660,820),Vector2(1770,1110),Vector2(3010,1320)],240)
	_path([Vector2(1770,1110),Vector2(1770,1870),Vector2(2310,2160)],210)
	_path([Vector2(650,1680),Vector2(1770,1110),Vector2(2810,670)],180)
	_house(Vector2(1230,800),Vector2(260,120),Color("#607e86"))
	_house(Vector2(2100,600),Vector2(220,110),Color("#8d7864"))
	_house(Vector2(1050,1500),Vector2(230,110),Color("#6b8275"))
	_house(Vector2(2310,1520),Vector2(250,115),Color("#5c7b82"))
	for p in [Vector2(390,700),Vector2(660,520),Vector2(350,1150),Vector2(880,430),Vector2(450,1430)]:
		_tree(p,185,true)
	_rock(Vector2(3050,420),Vector2(160,94))
	_rock(Vector2(1970,2190),Vector2(105,65))
	_prop("water_wheel",Vector2(2470,1980),155)
	_prop("signpost",Vector2(1540,1170),95)
	_prop("apple_cluster",Vector2(750,670),58)
	_prop("supply_basket",Vector2(870,1390),61)

func _forest() -> void:
	definition={"name":"萤火森林 · 环湖秘径","spawn":Vector2(590,1690),"lamp":Vector2(2850,600),
		"objectives":_objectives([[Vector2(750,720),Vector2(2840,1180),Vector2(2680,2110)],[Vector2(1100,1140),Vector2(2520,650),Vector2(1570,2070)],[Vector2(850,1020),Vector2(2500,1760),Vector2(2820,900)]]),
		"zones":[{"name":"西林营地","p":Vector2(590,1690)},{"name":"萤光湖","p":Vector2(1830,1280)},{"name":"树根神殿","p":Vector2(2850,600)},{"name":"南岸花田","p":Vector2(1570,2070)},{"name":"北溪木桥","p":Vector2(1860,620)}],
		"chests":[Vector2(420,420),Vector2(1150,2240),Vector2(3140,1620),Vector2(2540,350)],
		"camps":[Vector2(590,1690),Vector2(2850,600)],
		"patrols":[_patrol("shadow_blob",900,650),_patrol("crystal_thief",1200,1900),_patrol("shadow_blob",2640,1200),_patrol("crystal_thief",2520,2040),_patrol("shadow_blob",1440,540)],
		"hazards":[_hazard("spikes",1020,1460,0,0.4),_hazard("shooter",1290,730,0.4,1),_hazard("pendulum",2500,1540,0.3,0.7),_hazard("collapse",1810,1960,0,1.8),_hazard("spikes",2820,1920,0,1.3)]}
	_water.append(_ellipse(Vector2(1830,1280),Vector2(560,405)))
	_water.append(_rect(Rect2(1760,100,185,840)))
	_water.append(_ellipse(Vector2(3050,2090),Vector2(170,150)))
	_bridge(Rect2(1610,530,485,180),"wood")
	_path([Vector2(590,1690),Vector2(730,720),Vector2(1530,610),Vector2(2140,610),Vector2(2850,600),Vector2(2810,1390),Vector2(2540,2020),Vector2(1570,2070),Vector2(780,2110),Vector2(590,1690)],180)
	_path([Vector2(730,720),Vector2(1100,1140),Vector2(1080,1650),Vector2(1570,2070)],145)
	_path([Vector2(2140,610),Vector2(2500,1110),Vector2(2500,1760),Vector2(2540,2020)],160)
	for p in [Vector2(1180,650),Vector2(920,1670),Vector2(2440,500),Vector2(3100,1020),Vector2(1380,2220),Vector2(2220,2070),Vector2(540,1050)]:
		_tree(p,220,true)
	for p in [Vector2(1060,1320),Vector2(2340,1830),Vector2(3020,450)]:
		_rock(p,Vector2(125,83))
	_prop("ruin_arch",Vector2(2860,440),220)
	_prop("mirror_mechanism",Vector2(2310,730),100)

func _windmill() -> void:
	definition={"name":"风车原野 · 麦海与断崖","spawn":Vector2(570,1400),"lamp":Vector2(2790,590),
		"objectives":_objectives([[Vector2(950,1860),Vector2(2030,1840),Vector2(2750,1290)],[Vector2(1050,660),Vector2(1940,640),Vector2(2880,1590)],[Vector2(1140,1200),Vector2(2430,1670),Vector2(2600,850)]]),
		"zones":[{"name":"西风磨坊","p":Vector2(570,1400)},{"name":"中央断崖","p":Vector2(1720,1270)},{"name":"云帆高地","p":Vector2(2790,590)},{"name":"南岸麦田","p":Vector2(1850,2320)},{"name":"送粮旧道","p":Vector2(920,1840)}],
		"chests":[Vector2(430,450),Vector2(3120,1070),Vector2(1830,2320),Vector2(470,2230)],
		"camps":[Vector2(570,1400),Vector2(2790,590)],
		"patrols":[_patrol("wind_gremlin",1160,700),_patrol("crystal_thief",2210,570),_patrol("wind_gremlin",2600,1480),_patrol("shadow_blob",1230,1800),_patrol("wind_gremlin",2890,2300)],
		"hazards":[_hazard("pendulum",1260,1010,0.0,0.4),_hazard("shooter",2260,1140,PI,0.8),_hazard("collapse",2660,2070,0,1.5),_hazard("spikes",1590,1800,0,0.7),_hazard("firejet",2110,810,PI/2,1.2),_hazard("pendulum",950,2180,0.3,1.8)]}
	var cliff := PackedVector2Array([Vector2(1460,1020),Vector2(1580,880),Vector2(1840,920),Vector2(1990,1090),Vector2(1940,1470),Vector2(1750,1610),Vector2(1470,1500),Vector2(1370,1270)])
	_solids.append(_polygon(cliff))
	_water.append(_rect(Rect2(100,2020,3400,150)))
	_bridge(Rect2(750,1920,230,345),"wood")
	_bridge(Rect2(2580,1920,230,345),"stone")
	_path([Vector2(570,1400),Vector2(930,730),Vector2(1940,640),Vector2(2790,590),Vector2(2940,1350),Vector2(2430,1800),Vector2(1250,1840),Vector2(570,1400)],205)
	_path([Vector2(1250,1840),Vector2(860,1840),Vector2(860,2300),Vector2(1830,2320),Vector2(2700,2300),Vector2(2700,1790)],165)
	_path([Vector2(930,730),Vector2(1140,1200),Vector2(1250,1840)],150)
	_path([Vector2(1940,640),Vector2(2260,950),Vector2(2260,1540),Vector2(2430,1800)],160)
	_prop("windmill_mechanism",Vector2(2630,480),310)
	_solids.append(_ellipse(Vector2(2630,410),Vector2(90,80)))
	_prop("windmill_mechanism",Vector2(700,1040),240)
	_solids.append(_ellipse(Vector2(700,990),Vector2(65,55)))
	_house(Vector2(430,1310),Vector2(240,110),Color("#8a8762"))
	for p in [Vector2(1240,1590),Vector2(2300,1540),Vector2(3010,1750)]:
		_rock(p,Vector2(120,76))
	_prop("push_crate",Vector2(680,1730),85)
	_prop("push_crate",Vector2(745,1750),72)

func _water_town() -> void:
	definition={"name":"月光水乡 · 五岛回廊","spawn":Vector2(650,700),"lamp":Vector2(2800,670),
		"objectives":_objectives([[Vector2(1070,810),Vector2(830,2070),Vector2(1850,1390)],[Vector2(2760,1010),Vector2(2760,2050),Vector2(1560,1450)],[Vector2(840,1830),Vector2(2720,1740),Vector2(2740,720)]]),
		"zones":[{"name":"月湾营地","p":Vector2(650,700)},{"name":"莲花祭台","p":Vector2(2800,670)},{"name":"水闸中岛","p":Vector2(1750,1370)},{"name":"西南渡口","p":Vector2(820,2110)},{"name":"东岸水车","p":Vector2(2800,2130)}],
		"chests":[Vector2(510,480),Vector2(3010,490),Vector2(520,2180),Vector2(3030,2180)],
		"camps":[Vector2(650,700),Vector2(2800,670)],
		"patrols":[_patrol("moon_bubble",1130,700),_patrol("crystal_thief",2480,670),_patrol("moon_bubble",1930,1440),_patrol("moon_bubble",820,2050),_patrol("crystal_thief",2850,2130)],
		"hazards":[_hazard("whirlpool",1080,2070,0,0.3),_hazard("shooter",1750,900,PI/2,0.8),_hazard("collapse",1450,700,0,1),_hazard("whirlpool",2100,1400,0,1.6),_hazard("pendulum",2700,1400,0,1.2),_hazard("spikes",1790,2100,0,2)]}
	_water.append(_rect(WORLD_RECT))
	_land=[_ellipse(Vector2(840,700),Vector2(650,440)),_ellipse(Vector2(2690,720),Vector2(650,440)),_ellipse(Vector2(1750,1370),Vector2(650,450)),_ellipse(Vector2(820,2110),Vector2(600,360)),_ellipse(Vector2(2800,2130),Vector2(590,340))]
	_bridge(Rect2(1290,615,1010,180),"stone")
	_bridge(Rect2(1655,650,190,770),"stone")
	_bridge(Rect2(745,950,190,1110),"wood")
	_bridge(Rect2(2620,990,195,1110),"wood")
	_bridge(Rect2(730,1630,1040,180),"stone")
	_bridge(Rect2(1940,1630,900,180),"stone")
	_bridge(Rect2(1200,2050,1200,180),"wood")
	_path([Vector2(650,700),Vector2(1750,700),Vector2(2800,670)],150)
	_path([Vector2(1750,700),Vector2(1750,1390),Vector2(1750,1720)],145)
	_path([Vector2(840,760),Vector2(840,2110),Vector2(1750,2140),Vector2(2720,2140),Vector2(2720,750)],145)
	_path([Vector2(840,1720),Vector2(1750,1720),Vector2(2720,1720)],135)
	_house(Vector2(970,580),Vector2(210,100),Color("#5c7e90"))
	_house(Vector2(2560,570),Vector2(210,100),Color("#5c7e90"))
	_house(Vector2(690,2060),Vector2(200,95),Color("#68758d"))
	_prop("water_wheel",Vector2(2940,2030),210)
	_solids.append(_ellipse(Vector2(2940,1990),Vector2(65,53)))
	_prop("ruin_arch",Vector2(2880,480),190)
	_prop("mirror_mechanism",Vector2(1950,1230),92)

func _ruins() -> void:
	definition={"name":"旧王遗迹 · 九庭星图","spawn":Vector2(670,1290),"lamp":Vector2(2870,610),
		"objectives":_objectives([[Vector2(700,600),Vector2(1740,1980),Vector2(2850,1300)],[Vector2(1740,600),Vector2(2140,1270),Vector2(2860,1980)],[Vector2(730,2030),Vector2(1740,600),Vector2(2840,1170)]]),
		"zones":[{"name":"遗迹营地","p":Vector2(670,1290)},{"name":"西庭花园","p":Vector2(700,600)},{"name":"星图中庭","p":Vector2(1750,1250)},{"name":"王印殿","p":Vector2(2870,610)},{"name":"南庭回廊","p":Vector2(1740,1980)}],
		"chests":[Vector2(560,400),Vector2(3040,440),Vector2(560,2220),Vector2(3080,2210)],
		"camps":[Vector2(670,1290),Vector2(2870,610)],
		"patrols":[_patrol("crystal_thief",870,670),_patrol("shadow_blob",1720,730),_patrol("moon_bubble",2820,1350),_patrol("wind_gremlin",1700,1980),_patrol("shadow_blob",2810,2060),_patrol("crystal_thief",780,1970)],
		"hazards":[_hazard("spikes",1070,1160,0,0.3),_hazard("pendulum",2450,1700,0,0.8),_hazard("shooter",1560,930,PI/2,1),_hazard("firejet",2100,1950,PI,1.4),_hazard("collapse",1740,1760,0,1.8),_hazard("spikes",2840,1510,0,2.2)]}
	for r in [Rect2(1160,340,90,650),Rect2(1160,1370,90,900),Rect2(2300,340,90,1180),Rect2(2300,1880,90,390),Rect2(340,900,540,80),Rect2(1490,900,600,80),Rect2(2690,900,570,80),Rect2(340,1650,540,80),Rect2(1210,1650,780,80),Rect2(2680,1650,580,80)]:
		_wall(r)
	_water.append(_ellipse(Vector2(1750,1250),Vector2(210,160)))
	_path([Vector2(670,1290),Vector2(1060,1160),Vector2(1420,1160),Vector2(1420,760),Vector2(1740,600),Vector2(2140,740),Vector2(2450,740),Vector2(2870,610)],170)
	_path([Vector2(670,1290),Vector2(670,2020),Vector2(1020,2020),Vector2(1020,1820),Vector2(1500,1940),Vector2(2150,1940),Vector2(2450,1700),Vector2(2870,1700),Vector2(2870,1300),Vector2(2450,1300),Vector2(2450,740)],160)
	_path([Vector2(1420,1160),Vector2(1420,1460),Vector2(2140,1460),Vector2(2140,1270),Vector2(2140,740)],155)
	_path([Vector2(2140,1460),Vector2(2140,1940)],145)
	_path([Vector2(670,1290),Vector2(670,1070),Vector2(1010,1070),Vector2(1010,600),Vector2(700,600)],145)
	_prop("ruin_arch",Vector2(1205,1320),210)
	_prop("ruin_arch",Vector2(2345,1830),215)
	_prop("dragon_throne",Vector2(2870,440),220)
	for p in [Vector2(410,1200),Vector2(2060,450),Vector2(3040,1860)]:
		_rock(p,Vector2(110,70))

func _rift() -> void:
	definition={"name":"人间裂隙 · 三桥守界","spawn":Vector2(620,1430),"lamp":Vector2(2830,650),
		"objectives":_objectives([[Vector2(1030,720),Vector2(2310,1190),Vector2(2790,1930)],[Vector2(980,1850),Vector2(2280,1910),Vector2(2700,1100)],[Vector2(1210,1070),Vector2(2300,1580),Vector2(2760,960)]]),
		"zones":[{"name":"避难营地","p":Vector2(620,1430)},{"name":"北桥星纹","p":Vector2(1540,670)},{"name":"中央救援桥","p":Vector2(1720,1310)},{"name":"南桥营地","p":Vector2(2290,2070)},{"name":"最后的星灯","p":Vector2(2830,650)}],
		"chests":[Vector2(470,410),Vector2(3080,1050),Vector2(600,2180),Vector2(3090,2190)],
		"camps":[Vector2(620,1430),Vector2(2830,650)],
		"patrols":[_patrol("shadow_blob",1100,780),_patrol("wind_gremlin",1170,1870),_patrol("moon_bubble",2290,1040),_patrol("crystal_thief",2820,1810),_patrol("shadow_blob",2450,2140),_patrol("wind_gremlin",2320,1500)],
		"hazards":[_hazard("firejet",1220,1510,-PI/2,0.2),_hazard("shooter",2090,930,0.8,0.5),_hazard("collapse",1700,1310,0,1.2),_hazard("pendulum",2200,2010,0.4,1.7),_hazard("spikes",2490,1470,0,2),_hazard("firejet",2890,1610,PI,1),_hazard("whirlpool",1070,2140,0,1.4)]}
	var scar := PackedVector2Array([Vector2(1470,100),Vector2(1630,100),Vector2(1540,680),Vector2(1860,1080),Vector2(1770,1500),Vector2(2170,1880),Vector2(2210,2500),Vector2(2020,2500),Vector2(1990,1940),Vector2(1590,1570),Vector2(1670,1130),Vector2(1360,720)])
	_water.append(_polygon(scar))
	_bridge(Rect2(1220,590,590,180),"stone")
	_bridge(Rect2(1470,1220,570,190),"stone")
	_bridge(Rect2(1810,1940,670,190),"wood")
	_path([Vector2(620,1430),Vector2(780,740),Vector2(1220,680),Vector2(1780,680),Vector2(2410,620),Vector2(2830,650),Vector2(2980,1430),Vector2(2790,2130),Vector2(2310,2070),Vector2(1830,2070),Vector2(980,2110),Vector2(620,1430)],185)
	_path([Vector2(620,1430),Vector2(1230,1310),Vector2(2060,1310),Vector2(2980,1430)],180)
	_path([Vector2(1060,870),Vector2(1230,1310),Vector2(980,2110)],160)
	_path([Vector2(2410,620),Vector2(2330,1180),Vector2(2300,1580),Vector2(2310,2070)],175)
	_house(Vector2(650,620),Vector2(260,120),Color("#68718a"))
	_house(Vector2(2620,540),Vector2(220,110),Color("#73768a"))
	_house(Vector2(700,1950),Vector2(230,110),Color("#655c72"))
	for p in [Vector2(940,1160),Vector2(2420,920),Vector2(3000,1870),Vector2(1350,2080)]:
		_rock(p,Vector2(135,85))
	_prop("star_gate",Vector2(2790,470),230)
	_prop("ruin_arch",Vector2(2010,1710),180)

func _island() -> void:
	definition={"name":"星灯岛 · 环星花园","spawn":Vector2(680,1370),"lamp":Vector2(2760,1370),
		"objectives":_objectives([[Vector2(1030,800),Vector2(2300,700),Vector2(2720,1910)],[Vector2(1300,1950),Vector2(2380,1300),Vector2(1800,1320)],[Vector2(1150,1300),Vector2(1750,2090),Vector2(2690,1040)]]),
		"zones":[{"name":"约定星门","p":Vector2(680,1370)},{"name":"星海北庭","p":Vector2(1800,600)},{"name":"龙王灯台","p":Vector2(1800,1320)},{"name":"南庭花环","p":Vector2(1750,2090)},{"name":"相聚之灯","p":Vector2(2760,1370)}],
		"chests":[Vector2(750,1600),Vector2(1320,530),Vector2(2710,1000),Vector2(2500,2080)],
		"camps":[Vector2(680,1370),Vector2(2760,1370)],"patrols":[],"hazards":[]}
	_water.append(_rect(WORLD_RECT))
	_land.append(_ellipse(Vector2(1800,1320),Vector2(1450,1050)))
	# The inner star pool is a real obstacle; its four bridges make a second loop.
	_water.append(_ellipse(Vector2(1800,1320),Vector2(465,335)))
	_bridge(Rect2(1160,1240,1280,180),"star")
	_bridge(Rect2(1710,830,180,1000),"star")
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(33):
		var a := i*TAU/32
		outer.append(Vector2(1800,1320)+Vector2(cos(a)*1110,sin(a)*760))
		inner.append(Vector2(1800,1320)+Vector2(cos(a)*640,sin(a)*490))
	_paths.append(outer);_path_widths.append(155.0)
	_paths.append(inner);_path_widths.append(130.0)
	_path([Vector2(680,1370),Vector2(1800,1320),Vector2(2760,1370)],155)
	_path([Vector2(1800,600),Vector2(1800,1320),Vector2(1750,2090)],140)
	_prop("star_gate",Vector2(630,1240),220)
	_prop("dragon_throne",Vector2(1800,620),255)
	_solids.append(_ellipse(Vector2(1800,570),Vector2(95,70)))
	_prop("royal_lantern",Vector2(2020,630),140)
	for p in [Vector2(1030,1890),Vector2(2470,750)]:
		_prop("ruin_arch",p,175)

func _patrol(id:String,x:float,y:float) -> Dictionary:
	return {"id":id,"p":Vector2(x,y)}

func _objectives(sets:Array) -> Array:
	_objective_sets=sets
	return sets[stage]

func _hazard(kind:String,x:float,y:float,rotation:float=0,phase:float=0) -> Dictionary:
	return {"kind":kind,"p":Vector2(x,y),"rotation":rotation,"phase":phase,"radius":64.0 if kind!="pendulum" else 95.0}

func _filter_hazards() -> void:
	var safe_points:Array=[definition.spawn,definition.lamp]
	safe_points.append_array(definition.objectives)
	safe_points.append_array(definition.camps)
	var valid:Array=[]
	for hazard in definition.hazards:
		var safe:=true
		for point:Vector2 in safe_points:
			if point.distance_to(hazard.p)<160:
				safe=false
				break
		if safe and is_walkable(hazard.p,26):
			valid.append(hazard)
	definition.hazards=valid

func _rect(rect:Rect2) -> Dictionary:
	return {"shape":"rect","rect":rect}

func _ellipse(p:Vector2,radius:Vector2) -> Dictionary:
	return {"shape":"ellipse","p":p,"radius":radius}

func _polygon(points:PackedVector2Array) -> Dictionary:
	return {"shape":"polygon","points":points}

func _bridge(rect:Rect2,style:String) -> void:
	_bridges.append({"rect":rect,"style":style})

func _path(points:Array,width:float=180) -> void:
	_paths.append(PackedVector2Array(points))
	_path_widths.append(width)

func _house(p:Vector2,size:Vector2,color:Color) -> void:
	_solids.append(_rect(Rect2(p-Vector2(size.x/2,size.y),size)))
	_structures.append({"kind":"house","p":p,"size":size,"color":color})

func _wall(rect:Rect2) -> void:
	_solids.append(_rect(rect))
	# Split long walls into short Y-sorted pieces so actors can pass behind them.
	var pieces:=maxi(1,int(ceil(rect.size.y/120.0)))
	for i in range(pieces):
		var h:=rect.size.y/pieces
		_structures.append({"kind":"wall","p":Vector2(rect.get_center().x,rect.position.y+(i+1)*h),"size":Vector2(rect.size.x,h),"color":Color(palette[4]).darkened(0.15)})

func _rock(p:Vector2,size:Vector2) -> void:
	_solids.append(_ellipse(p-Vector2(0,size.y*0.32),size*Vector2(0.45,0.36)))
	_structures.append({"kind":"rock","p":p,"size":size,"color":Color(palette[4]).darkened(0.24)})

func _tree(p:Vector2,height:float,solid:bool=false) -> void:
	_prop("tree_fir" if chapter==1 else "tree_round",p,height)
	if solid:
		_solids.append(_ellipse(p-Vector2(0,10),Vector2(25,22)))

func _prop(id:String,p:Vector2,height:float) -> void:
	_art_props.append({"id":id,"p":p,"height":height})

func _shape_hit(shape:Dictionary,p:Vector2,radius:float=0) -> bool:
	match shape.shape:
		"rect":
			return (shape.rect as Rect2).grow(radius).has_point(p)
		"ellipse":
			var r:Vector2=shape.radius+Vector2.ONE*radius
			return ((p-shape.p)/r).length_squared()<=1.0
		"polygon":
			var points:PackedVector2Array=shape.points
			if Geometry2D.is_point_in_polygon(p,points):return true
			if radius>0:
				for i in range(points.size()):
					if Geometry2D.get_closest_point_to_segment(p,points[i],points[(i+1)%points.size()]).distance_to(p)<radius:return true
	return false

func _in_land_cutout(p:Vector2,radius:float) -> bool:
	for shape:Dictionary in _land:
		if _shape_hit(shape,p,-radius):return true
	return false

func _water_blocked(p:Vector2,radius:float) -> bool:
	for bridge:Dictionary in _bridges:
		if (bridge.rect as Rect2).grow(-radius).has_point(p):return false
	for i in range(_water.size()):
		if _shape_hit(_water[i],p,radius):
			# First shape can be an ocean surrounding explicit islets.
			if i==0 and not _land.is_empty() and _in_land_cutout(p,radius):continue
			return true
	return false

func is_walkable(p:Vector2,radius:float=20) -> bool:
	if not WORLD_RECT.grow(-radius).has_point(p):return false
	if _water_blocked(p,radius):return false
	for shape:Dictionary in _solids:
		if _shape_hit(shape,p,radius):return false
	return true

func is_water(p:Vector2) -> bool:
	return _water_blocked(p,0)

func is_obstacle(p:Vector2,radius:float=20) -> bool:
	if not WORLD_RECT.grow(-radius).has_point(p):return true
	for shape:Dictionary in _solids:
		if _shape_hit(shape,p,radius):return true
	return false

func has_line_of_sight(a:Vector2,b:Vector2) -> bool:
	var count:=maxi(1,int(ceil(a.distance_to(b)/18.0)))
	for i in range(count+1):
		if not is_walkable(a.lerp(b,float(i)/count),3):return false
	return true

func move_actor(from:Vector2,motion:Vector2,radius:float=20) -> Vector2:
	var current:=from
	# Substeps avoid tunnelling through a narrow wall after a long frame.
	var steps:=maxi(1,int(ceil(motion.length()/16.0)))
	var step:=motion/steps
	for i in range(steps):
		var proposed:=current+step
		if is_walkable(proposed,radius):
			current=proposed
		else:
			proposed=current+Vector2(step.x,0)
			if is_walkable(proposed,radius):current=proposed
			proposed=current+Vector2(0,step.y)
			if is_walkable(proposed,radius):current=proposed
	return current

func _build_navigation() -> void:
	_nav.region=Rect2i(0,0,int(WORLD_RECT.size.x/GRID_SIZE),int(WORLD_RECT.size.y/GRID_SIZE))
	_nav.cell_size=Vector2.ONE*GRID_SIZE
	_nav.offset=WORLD_RECT.position+Vector2.ONE*GRID_SIZE*0.5
	_nav.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	_nav.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	_nav.update()
	for y in range(_nav.region.size.y):
		for x in range(_nav.region.size.x):
			var cell:=Vector2i(x,y)
			_nav.set_point_solid(cell,not is_walkable(_nav.get_point_position(cell),27))

func _cell_for(p:Vector2) -> Vector2i:
	var relative:Vector2=(p-WORLD_RECT.position)/GRID_SIZE
	return Vector2i(clampi(int(relative.x),0,_nav.region.size.x-1),clampi(int(relative.y),0,_nav.region.size.y-1))

func _nearest_cell(p:Vector2) -> Vector2i:
	var center:=_cell_for(p)
	if not _nav.is_point_solid(center):return center
	var best:=Vector2i(-1,-1)
	var best_distance:=INF
	for ring in range(1,maxi(_nav.region.size.x,_nav.region.size.y)):
		for dy in range(-ring,ring+1):
			for dx in range(-ring,ring+1):
				if abs(dx)!=ring and abs(dy)!=ring:continue
				var cell:=center+Vector2i(dx,dy)
				if not _nav.region.has_point(cell) or _nav.is_point_solid(cell):continue
				var distance:=_nav.get_point_position(cell).distance_squared_to(p)
				if distance<best_distance:
					best=cell;best_distance=distance
		if best.x>=0:return best
	return Vector2i(-1,-1)

func nearest_safe(p:Vector2) -> Vector2:
	if is_walkable(p,27):return p
	var cell:=_nearest_cell(p)
	return _nav.get_point_position(cell) if cell.x>=0 else definition.get("spawn",Vector2(300,300))

func find_path(a:Vector2,b:Vector2) -> PackedVector2Array:
	var first:=_nearest_cell(a)
	var last:=_nearest_cell(b)
	if first.x<0 or last.x<0:return PackedVector2Array()
	var raw:=_nav.get_point_path(first,last)
	if raw.is_empty():return raw
	var result:=PackedVector2Array()
	if is_walkable(a) and has_line_of_sight(a,raw[0]):result.append(a)
	result.append_array(raw)
	if is_walkable(b) and has_line_of_sight(raw[raw.size()-1],b):result.append(b)
	return result

func _shape_bounds(shape:Dictionary) -> Rect2:
	if shape.shape=="rect":return shape.rect
	if shape.shape=="ellipse":return Rect2(shape.p-shape.radius,shape.radius*2)
	var points:PackedVector2Array=shape.points
	var rect:=Rect2(points[0],Vector2.ZERO)
	for p:Vector2 in points:rect=rect.expand(p)
	return rect

func get_overview() -> Dictionary:
	var obstacles:Array=[]
	var water:Array=[]
	for shape:Dictionary in _solids:obstacles.append(_shape_bounds(shape))
	for shape:Dictionary in _water:water.append(_shape_bounds(shape))
	return {"bounds":WORLD_RECT,"zones":definition.get("zones",[]),"obstacles":obstacles,"water":water,"paths":_paths,"bridges":_bridges,"geometry":_solids,"water_geometry":_water,"land_cutouts":_land}

func _near_paths(p:Vector2,margin:float=0) -> bool:
	for i in range(_paths.size()):
		var points:PackedVector2Array=_paths[i]
		for j in range(points.size()-1):
			if Geometry2D.get_closest_point_to_segment(p,points[j],points[j+1]).distance_to(p)<_path_widths[i]*0.5+margin:return true
	return false

func _near_interest(p:Vector2,margin:float=110) -> bool:
	var points:Array=[definition.spawn,definition.lamp]
	for objective_set:Array in _objective_sets:points.append_array(objective_set)
	points.append_array(definition.chests);points.append_array(definition.camps)
	for q:Vector2 in points:
		if q.distance_to(p)<margin:return true
	return false

func _decorate() -> void:
	_patches.clear();_tufts.clear();_flowers.clear();_stones.clear();_motes.clear();_reeds.clear();_shrubs.clear();_lilies.clear()
	for i in range(430):
		var p:=Vector2(_rng.randf_range(160,3440),_rng.randf_range(160,2440))
		if is_walkable(p,5):_patches.append([p,Vector2(_rng.randf_range(20,90),_rng.randf_range(9,34)),_rng.randf()])
	for i in range(1800):
		var p:=Vector2(_rng.randf_range(160,3440),_rng.randf_range(160,2440))
		if is_walkable(p,5) and not _near_paths(p,8):_tufts.append([p,_rng.randf_range(4,10),_rng.randf()])
	for i in range(270):
		var p:=Vector2(_rng.randf_range(170,3430),_rng.randf_range(170,2430))
		if is_walkable(p,15) and not _near_paths(p,15):_flowers.append([p,_rng.randf_range(0.65,1.2),_rng.randi_range(3,6)])
	for i in range(160):
		var p:=Vector2(_rng.randf_range(160,3440),_rng.randf_range(160,2440))
		if is_walkable(p,5):_motes.append([p,_rng.randf_range(0,TAU),_rng.randf_range(0.3,1)])
	for i in range(170):
		var p:=Vector2(_rng.randf_range(170,3430),_rng.randf_range(170,2430))
		if is_walkable(p,5) and _water_blocked(p,90) and not _near_paths(p,10):_reeds.append(p)
	for i in range(160):
		var p:=Vector2(_rng.randf_range(190,3410),_rng.randf_range(190,2410))
		if is_walkable(p,40) and not _near_paths(p,24) and not _near_interest(p,100):_shrubs.append([p,_rng.randf_range(0.65,1.1)])
	if chapter!=5 and chapter!=6:
		for i in range(140):
			var p:=Vector2(_rng.randf_range(200,3400),_rng.randf_range(200,2400))
			if not _water_blocked(p,0):continue
			if is_walkable(p+Vector2(90,0),0) or is_walkable(p-Vector2(90,0),0) or is_walkable(p+Vector2(0,90),0) or is_walkable(p-Vector2(0,90),0):_lilies.append(p)
	# Fixed-seed flora are scenery only. They never add unpredictable collision.
	for i in range(95):
		var p:=Vector2(_rng.randf_range(210,3390),_rng.randf_range(210,2390))
		if is_walkable(p,50) and not _near_paths(p,95) and not _near_interest(p,150):
			_prop("tree_fir" if chapter==1 and i%3!=0 else "tree_round",p,_rng.randf_range(140,220))
	for i in range(31):
		for y in [170.0,2460.0]:
			var p:=Vector2(150+i*110+_rng.randf_range(-10,10),y)
			if is_walkable(p,10) and not _near_interest(p,150):_prop("tree_round",p,_rng.randf_range(160,215))
	for i in range(19):
		for x in [160.0,3450.0]:
			var p:=Vector2(x,270+i*115+_rng.randf_range(-12,12))
			if is_walkable(p,10) and not _near_interest(p,150):_prop("tree_fir",p,_rng.randf_range(165,220))
	# A few wayfinding lights at junctions, well clear of gameplay markers.
	for path:PackedVector2Array in _paths:
		for i in range(1,path.size()-1,3):
			var p:=path[i]+Vector2(-90,65)
			if is_walkable(p,15) and not _near_interest(p,125):_prop("star_lantern_lit",p,104)
	for i in range(_paths.size()):
		var path:PackedVector2Array=_paths[i]
		var width:float=_path_widths[i]
		for j in range(path.size()-1):
			var count:=maxi(1,int(path[j].distance_to(path[j+1])/49))
			for step in range(count+1):
				var base:=path[j].lerp(path[j+1],float(step)/count)
				var normal:Vector2=(path[j+1]-path[j]).normalized().orthogonal()
				for row in range(-1,2):
					var p:=base+normal*(row*minf(42,width*0.23)+_rng.randf_range(-5,5))
					if is_walkable(p,2):_stones.append([p,Vector2(_rng.randf_range(17,25),_rng.randf_range(11,17)),_rng.randf()])

func _build_art() -> void:
	_environment_manifest.clear()
	var manifest_path:="res://assets/environment_v11/manifest.json"
	if FileAccess.file_exists(manifest_path):
		var document=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if document is Dictionary:_environment_manifest=document.get("assets",{})
	for data:Dictionary in _structures:
		if data.kind=="house":
			var house_name:="house_blue" if (data.color as Color).b>(data.color as Color).r else "house_warm"
			if _new_environment_sprite(house_name,data.p,maxf(225,float(data.size.x)*0.96)):continue
		elif data.kind=="rock":
			if _new_environment_sprite("rock",data.p,maxf(75,float(data.size.x)*0.72)):continue
		var node:=Structure.new()
		node.kind=data.kind;node.footprint=data.size;node.color=data.color
		node.position=data.p
		node.z_as_relative=false;node.z_index=clampi(int(node.position.y),0,3500)
		_props.add_child(node)
	var replacements:={"tree_round":"tree_round","tree_fir":"tree_fir","windmill_mechanism":"windmill","water_wheel":"water_wheel","ruin_arch":"ruin_arch","star_lantern_lit":"lantern","star_lantern_unlit":"lantern"}
	for data:Dictionary in _art_props:
		if replacements.has(data.id) and _new_environment_sprite(replacements[data.id],data.p,float(data.height)):continue
		var path:String="res://assets/props/"+data.id+".png"
		if not ResourceLoader.exists(path):continue
		if not _texture_cache.has(path):
			var texture:Texture2D=load(path)
			_texture_cache[path]=texture
			_bounds_cache[path]=texture.get_image().get_used_rect()
		var bounds:Rect2i=_bounds_cache[path]
		if bounds.size.y<1:continue
		var sprite:=Sprite2D.new()
		sprite.texture=_texture_cache[path]
		sprite.centered=false
		sprite.offset=Vector2(-bounds.position.x-bounds.size.x*0.5,-bounds.end.y)
		sprite.scale=Vector2.ONE*float(data.height)/bounds.size.y
		sprite.position=data.p
		sprite.z_as_relative=false;sprite.z_index=clampi(int(sprite.position.y),0,3500)
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		if chapter==5:sprite.modulate=Color(0.83,0.86,1)
		_props.add_child(sprite)
	for shrub:Array in _shrubs:
		_new_environment_sprite("shrub",shrub[0],51.0*float(shrub[1]))

func _new_environment_sprite(id:String,p:Vector2,height:float) -> bool:
	var path:="res://assets/environment_v11/"+id+".png"
	if not ResourceLoader.exists(path):return false
	if not _texture_cache.has(path):
		var texture:Texture2D=load(path)
		_texture_cache[path]=texture
		_bounds_cache[path]=texture.get_image().get_used_rect()
	var texture:Texture2D=_texture_cache[path]
	var bounds:Rect2i=_bounds_cache[path]
	if bounds.size.y<1:return false
	var foot:=Vector2(bounds.position.x+bounds.size.x*0.5,bounds.end.y)
	var entry:Dictionary=_environment_manifest.get(id,{})
	var declared_foot=entry.get("foot",[])
	if declared_foot is Array and declared_foot.size()>=2:foot=Vector2(float(declared_foot[0]),float(declared_foot[1]))
	var sprite:=Sprite2D.new()
	sprite.name="HQ_"+id
	sprite.texture=texture;sprite.centered=false;sprite.offset=-foot
	sprite.scale=Vector2.ONE*height/bounds.size.y
	sprite.position=p;sprite.z_as_relative=false;sprite.z_index=clampi(int(p.y),0,3500)
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if id.begins_with("tree") or id=="shrub":sprite.material=_landscape.foliage_material()
	if chapter==5:sprite.modulate=Color(0.86,0.90,0.96)
	_props.add_child(sprite)
	return true

func _process(delta:float) -> void:
	_time+=delta
	_redraw_time+=delta
	if _redraw_time>0.075 and is_instance_valid(_ambient):
		_redraw_time=0
		_ambient.queue_redraw()

func _draw() -> void:
	if is_instance_valid(_landscape):return
	if palette.is_empty():return
	var ground:=Color(palette[0])
	var deep:=Color(palette[2])
	draw_rect(Rect2(-3600,-2600,10800,7800),deep.darkened(0.53))
	for ring in range(5,-1,-1):
		var rect:=WORLD_RECT.grow(ring*11)
		draw_style_box(_round_box(deep.lerp(ground,1-ring/6.0),100),rect)
	if not _land.is_empty():
		for water:Dictionary in _water:_paint_shape(water,Color(palette[5]))
		for land:Dictionary in _land:
			_paint_shape_grown(land,20,Color(palette[3]).darkened(0.34))
			_paint_shape(land,ground)
	else:
		for water:Dictionary in _water:
			_paint_shape_grown(water,20,Color(palette[3]).darkened(0.28))
			_paint_shape(water,Color(palette[5]))
	# Water after the first ocean is an interior pool, also on otherwise solid islets.
	if not _land.is_empty():
		for i in range(1,_water.size()):
			_paint_shape_grown(_water[i],16,Color(palette[3]).darkened(0.27))
			_paint_shape(_water[i],Color(palette[5]))
	for patch in _patches:_oval(self,patch[0],patch[1],ground.lerp(Color(palette[1]),0.16+patch[2]*0.3))
	for i in range(_paths.size()):
		var path:PackedVector2Array=_paths[i]
		var width:float=_path_widths[i]
		# Draw only short walkable spans: roads never paint over a solid lake or cliff.
		for j in range(path.size()-1):
			var steps:=maxi(1,int(path[j].distance_to(path[j+1])/30))
			for k in range(steps):
				var p:=path[j].lerp(path[j+1],(k+0.5)/steps)
				if is_walkable(p,4):
					_oval(self,p,Vector2(width*0.52,width*0.35),Color(palette[3]).darkened(0.2))
	for stone in _stones:
		_flagstone(stone[0]+Vector2(0,2),stone[1],Color(palette[3]).darkened(0.39))
		_flagstone(stone[0],stone[1],Color(palette[4]).darkened(0.06+stone[2]*0.13))
	for bridge:Dictionary in _bridges:_draw_bridge(bridge)
	for tuft in _tufts:
		var p:Vector2=tuft[0]
		var h:float=tuft[1]
		var color:=Color(palette[1]).lightened(tuft[2]*0.12)
		draw_line(p,p+Vector2(-3,-h),color,1.3,true)
		draw_line(p+Vector2(3,0),p+Vector2(6,-h*0.7),color,1.2,true)
	for data in _flowers:_flower_cluster(data[0],data[1],data[2])
	for shrub in _shrubs:
		var p:Vector2=shrub[0]
		var scale_value:float=shrub[1]
		_oval(self,p+Vector2(1,7),Vector2(38,13)*scale_value,Color(0.02,0.1,0.1,0.18))
		for i in range(5):
			var q:=p+Vector2((i-2)*13,-sin(i*1.6)*5)*scale_value
			_oval(self,q,Vector2(18,14)*scale_value,Color(palette[6]).darkened(i%2*0.09))
			_oval(self,q+Vector2(-4,-4)*scale_value,Vector2(8,4)*scale_value,Color(palette[6]).lightened(0.07))
	for p:Vector2 in _lilies:
		_oval(self,p,Vector2(12,6),Color("#5c8b79"))
		draw_line(p,p+Vector2(9,-4),Color(palette[5]),1.5,true)
		if chapter==3:
			draw_circle(p+Vector2(1,-3),3.2,Color("#e5b6c7"))
	for p:Vector2 in _reeds:
		for j in range(4):
			var q:=p+Vector2(j*4,0)
			draw_line(q,q+Vector2(-3+j,-15-j*3),Color(palette[6]),1.5,true)
	for data:Dictionary in _art_props:
		var h:float=data.height
		_oval(self,data.p+Vector2(0,-3),Vector2(h*0.17,h*0.05),Color(0.02,0.08,0.1,0.2))
	for solid:Dictionary in _solids:
		if solid.shape=="polygon":
			_paint_shape_grown(solid,7,Color(palette[2]).darkened(0.2))
			_draw_cliff_surface(solid.points)
			var points:PackedVector2Array=solid.points
			var outline:=points.duplicate()
			outline.append(points[0])
			draw_polyline(outline,Color(palette[4]).darkened(0.09),5,true)
	if chapter==0:_draw_orchard_beds()
	if chapter==2:
		for p in [Vector2(790,1660),Vector2(1120,970),Vector2(2820,950),Vector2(2030,2300),Vector2(2900,1770)]:_wheat(p)
	if chapter==4:_draw_ruin_tiles()
	if chapter==6:_draw_star_garden()

func _draw_cliff_surface(points:PackedVector2Array) -> void:
	var center:=Vector2.ZERO
	for p:Vector2 in points:center+=p
	center/=points.size()
	var base:=Color(palette[4]).darkened(0.32)
	for i in range(points.size()):
		var triangle:=PackedVector2Array([center,points[i],points[(i+1)%points.size()]])
		draw_colored_polygon(triangle,base.lightened((i%4)*0.035))
	for ring in range(2):
		var contour:=PackedVector2Array()
		for p:Vector2 in points:contour.append(p.lerp(center,0.18+ring*0.27))
		contour.append(contour[0])
		draw_polyline(contour,base.lightened(0.08+ring*0.025),3,true)
	for i in range(22):
		var p:=center+Vector2(sin(i*2.3)*180,cos(i*1.7)*210)
		if Geometry2D.is_point_in_polygon(p,points):
			_flagstone(p,Vector2(13+i%3*4,7+i%2*3),base.lightened(0.08+(i%4)*0.02))

func _round_box(color:Color,radius:int) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=color;box.set_corner_radius_all(radius);box.corner_detail=16
	return box

func _paint_shape(shape:Dictionary,color:Color) -> void:
	match shape.shape:
		"rect":draw_style_box(_round_box(color,16),shape.rect)
		"ellipse":_oval(self,shape.p,shape.radius,color)
		"polygon":draw_colored_polygon(shape.points,color)

func _paint_shape_grown(shape:Dictionary,amount:float,color:Color) -> void:
	match shape.shape:
		"rect":draw_style_box(_round_box(color,25),(shape.rect as Rect2).grow(amount))
		"ellipse":_oval(self,shape.p,shape.radius+Vector2.ONE*amount,color)
		"polygon":
			var polys:=Geometry2D.offset_polygon(shape.points,amount,Geometry2D.JOIN_ROUND)
			for poly:PackedVector2Array in polys:draw_colored_polygon(poly,color)

func _oval(canvas:CanvasItem,p:Vector2,radius:Vector2,color:Color) -> void:
	canvas.draw_set_transform(p,0,radius)
	canvas.draw_circle(Vector2.ZERO,1,color)
	canvas.draw_set_transform(Vector2.ZERO)

func _flagstone(p:Vector2,radius:Vector2,color:Color) -> void:
	var points:=PackedVector2Array()
	for i in range(7):points.append(p+Vector2(cos(i*TAU/7+0.2)*radius.x,sin(i*TAU/7+0.2)*radius.y))
	draw_colored_polygon(points,color)

func _draw_bridge(data:Dictionary) -> void:
	var r:Rect2=data.rect
	var horizontal:=r.size.x>r.size.y
	var wood:bool=data.style=="wood"
	var star:bool=data.style=="star"
	var color:=Color("#a58a63") if wood else Color(palette[4]).darkened(0.08)
	if star:color=Color("#c0d1c5")
	draw_style_box(_round_box(Color(palette[2]).darkened(0.18),11),r.grow(9))
	draw_style_box(_round_box(color.darkened(0.23),8),Rect2(r.position+Vector2(0,8),r.size))
	draw_style_box(_round_box(color,6),r)
	var length:float=r.size.x if horizontal else r.size.y
	var count:=maxi(2,int(length/(24 if wood else 52)))
	for i in range(1,count):
		var t:=float(i)/count
		if horizontal:draw_line(r.position+Vector2(r.size.x*t,4),r.position+Vector2(r.size.x*t,r.size.y-4),color.darkened(0.22),2,true)
		else:draw_line(r.position+Vector2(4,r.size.y*t),r.position+Vector2(r.size.x-4,r.size.y*t),color.darkened(0.22),2,true)
	var rail:=Color("#ccb185") if wood else color.lightened(0.16)
	if horizontal:
		draw_line(r.position+Vector2(0,6),r.position+Vector2(r.size.x,6),rail,7,true)
		draw_line(r.position+Vector2(0,r.size.y-6),r.end-Vector2(0,6),rail,7,true)
	else:
		draw_line(r.position+Vector2(6,0),r.position+Vector2(6,r.size.y),rail,7,true)
		draw_line(r.position+Vector2(r.size.x-6,0),r.end-Vector2(6,0),rail,7,true)
	if star:
		for i in range(1,count,2):
			var p:=r.position+Vector2(r.size.x*0.5,r.size.y*float(i)/count)
			_star(self,p,10,Color("#f6dda0"))

func _flower_cluster(p:Vector2,size:float,count:int) -> void:
	_oval(self,p+Vector2(0,2),Vector2(18,7)*size,Color(palette[2]).lightened(0.05))
	for i in range(count):
		var center:=p+Vector2(cos(i*2.399)*i*3.1,sin(i*2.399)*i*1.7)*size
		var color:=Color(palette[7]).darkened(i*0.025)
		for j in range(5):draw_circle(center+Vector2.from_angle(j*TAU/5)*2.7*size,2.1*size,color)
		draw_circle(center,1.2*size,Color("#e8bf74"))

func _wheat(p:Vector2) -> void:
	_oval(self,p,Vector2(135,70),Color("#6c7853"))
	for row in range(6):
		for col in range(15):
			var q:=p+Vector2((col-7)*15,(row-2.5)*18)
			draw_line(q,q+Vector2(2,-22),Color("#afa66b"),1.5,true)
			for i in range(3):
				var tip:=q+Vector2(2,-16-i*4)
				draw_line(tip,tip+Vector2(-4,-4),Color("#e0c57d"),2,true)
				draw_line(tip,tip+Vector2(4,-4),Color("#e0c57d"),2,true)

func _draw_orchard_beds() -> void:
	for i in range(4):
		var p:=Vector2(470+i*90,1220+i%2*75)
		if not is_walkable(p,20):continue
		draw_style_box(_round_box(Color("#5b5a40"),12),Rect2(p-Vector2(35,35),Vector2(70,90)))
		for j in range(3):
			var q:=p+Vector2(0,j*23-20)
			_oval(self,q,Vector2(26,9),Color("#749566"))
			draw_circle(q+Vector2(-8,-3),4,Color("#d19169"))

func _draw_ruin_tiles() -> void:
	for p in [Vector2(700,600),Vector2(1740,600),Vector2(2850,1300),Vector2(1740,1980)]:
		for i in range(4):
			var a:=PI/4+i*PI/2
			_star(self,p+Vector2(cos(a),sin(a))*88,6,Color("#d3c79a"))
		_oval_outline(p,Vector2(105,65),Color(0.75,0.8,0.65,0.25),2)

func _draw_star_garden() -> void:
	for i in range(12):
		var a:=i*TAU/12
		var p:=Vector2(1800,1320)+Vector2(cos(a)*890,sin(a)*630)
		_star(self,p,15,Color("#c5d6bd"))
		_oval_outline(p,Vector2(28,18),Color("#9ebbaa"),1.7)

func _oval_outline(p:Vector2,radius:Vector2,color:Color,width:float) -> void:
	var points:=PackedVector2Array()
	for i in range(49):points.append(p+Vector2(cos(i*TAU/48)*radius.x,sin(i*TAU/48)*radius.y))
	draw_polyline(points,color,width,true)

func _star(canvas:CanvasItem,p:Vector2,radius:float,color:Color) -> void:
	if radius<3:
		canvas.draw_line(p-Vector2(radius,0),p+Vector2(radius,0),color,0.8,true)
		canvas.draw_line(p-Vector2(0,radius),p+Vector2(0,radius),color,0.8,true)
		return
	var points:=PackedVector2Array()
	for i in range(8):points.append(p+Vector2.from_angle(i*TAU/8)*radius*(1.0 if i%2==0 else 0.3))
	canvas.draw_colored_polygon(points,color)

func _draw_ambient() -> void:
	if not is_instance_valid(_ambient) or definition.is_empty():return
	for mote in _motes:
		var p:Vector2=mote[0]+Vector2(sin(_time*0.5+mote[1])*9,cos(_time*0.6+mote[1])*7)
		var alpha:float=(0.35+sin(_time*1.3+mote[1])*0.22)*mote[2]
		_ambient.draw_circle(p,6,Color(1,0.87,0.52,alpha*0.08))
		_ambient.draw_circle(p,1.4,Color(1,0.92,0.65,alpha))
	for i in range(80):
		var p:=Vector2(190+fmod(i*631.0,3220),210+fmod(i*337.0,2220))
		if _water_blocked(p,0):
			var length:=7+sin(_time+i*1.4)*4
			_ambient.draw_line(p-Vector2(length,0),p+Vector2(length,0),Color(0.58,0.83,0.87,0.2+sin(_time+i)*0.05),1.2,true)
	if chapter==6:
		for i in range(70):
			var p:=Vector2(140+fmod(i*817.0,3320),150+fmod(i*313.0,2310))
			if not is_walkable(p,0):_star(_ambient,p,1.3+sin(_time+i)*0.35,Color(0.79,0.89,1,0.55))
