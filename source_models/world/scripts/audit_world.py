from pathlib import Path
import json, struct, html
from PIL import Image

ROOT=Path(r'E:\game\StarLanternIsland\source_models\world')
manifest=json.loads((ROOT/'reports'/'manifest.json').read_text(encoding='utf-8'))
checks=[]
for entry in manifest['props']+manifest['scenes']:
    p=Path(entry['glb']);raw=p.read_bytes()
    magic,version,length=struct.unpack('<4sII',raw[:12])
    chunklen,chunkkind=struct.unpack('<II',raw[12:20]);gltf=json.loads(raw[20:20+chunklen])
    glb_ok=magic==b'glTF' and version==2 and length==len(raw) and len(gltf.get('meshes',[]))>0
    imagepath=Path(entry.get('sprite',entry.get('preview','')))
    with Image.open(imagepath) as im:
        im.load();alpha=im.getchannel('A').getextrema() if im.mode=='RGBA' else None
        transparent_required='sprite' in entry
        alpha_ok=not transparent_required or alpha==(0,255)
        checks.append({'id':entry['id'],'glb_valid':glb_ok,'glb_bytes':len(raw),'gltf_meshes':len(gltf.get('meshes',[])),
                       'image_size':list(im.size),'image_mode':im.mode,'alpha_extrema':alpha,'alpha_valid':alpha_ok,
                       'passed':glb_ok and alpha_ok})
result={'passed':all(c['passed'] for c in checks),'asset_count':len(checks),'prop_count':len(manifest['props']),
        'scene_count':len(manifest['scenes']),'checks':checks}
(ROOT/'reports'/'validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')

names={
'01_home_village':'家庭院落与村庄','02_firefly_forest':'萤火森林','03_windmill_meadow':'风车原野',
'04_moon_water_town':'月光水乡','05_old_king_ruins':'旧王遗迹','06_star_lantern_island':'星灯岛',
'star_lantern_lit':'点亮的星灯','star_lantern_unlit':'熄灭的星灯','royal_lantern':'龙王灯',
'chest_closed':'宝箱·关闭','chest_open':'宝箱·打开','star_key':'星纹钥匙','crystal_common':'普通晶石',
'crystal_fire':'星火源晶','crystal_wind':'御风源晶','crystal_water':'月水源晶','crystal_space':'空间源晶',
'stone_bridge':'拱形石桥','wood_bridge':'木桥','mirror_mechanism':'镜面机关','push_crate':'可推木箱',
'windmill_mechanism':'风车机关','star_gate':'龙族星门','supply_basket':'补给篮','apple_cluster':'苹果',
'signpost':'路牌','tree_round':'圆冠树','tree_fir':'星蓝杉树','water_wheel':'水车','ruin_arch':'古代石拱门','dragon_throne':'小龙王座'}

cards=[]
for e in manifest['scenes']:
    identifier=e['id'];name=names[identifier]
    cards.append(f'<article class="scene"><a href="renders/{identifier}.png"><img src="renders/{identifier}.png" alt="{name}"></a><div><h3>{name}</h3><p>{e["mesh_objects"]} 个网格 · {e["evaluated_triangles"]:,} 个三角面</p><a class="button" href="scenes/{identifier}.blend">Blender 源文件</a><a class="button" href="scenes/{identifier}.glb">Godot 模型</a></div></article>')
props=[]
for e in manifest['props']:
    identifier=e['id'];name=names[identifier]
    props.append(f'<article class="prop"><div class="checker"><a href="renders/{identifier}.png"><img src="renders/{identifier}.png" alt="{name}"></a></div><h3>{name}</h3><p>{e["evaluated_triangles"]:,} 三角面</p><a href="props/{identifier}.glb">GLB</a><a href="renders/{identifier}.png">透明 PNG</a></article>')
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>星灯岛 · 场景与道具资产</title><style>
*{box-sizing:border-box}body{margin:0;background:#eef2ec;color:#233c43;font:16px/1.6 "Microsoft YaHei",system-ui,sans-serif}header{padding:54px max(5vw,24px) 38px;background:#183b48;color:#fcf1ce}header small{color:#98cbd0;letter-spacing:.2em}h1{font-size:clamp(28px,4vw,48px);margin:.2em 0}header p{max-width:760px;color:#d1ded6}main{max-width:1500px;margin:auto;padding:30px 5vw 70px}h2{font-size:27px;margin-top:32px}.scenes{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}.scene,.prop{background:#fffefa;border:1px solid #d4ded3;border-radius:18px;overflow:hidden;box-shadow:0 8px 28px #17373808}.scene img{width:100%;display:block}.scene>div{padding:18px 22px}h3{margin:0 0 6px;font-size:20px}p{margin:8px 0;color:#698087}.button{display:inline-block;border:1px solid #c7d5cd;border-radius:9px;padding:7px 12px;margin:5px 6px 3px 0;color:#285866;text-decoration:none;background:#f2f6ef}.props{display:grid;grid-template-columns:repeat(auto-fit,minmax(175px,1fr));gap:16px}.prop{padding:12px;text-align:center}.prop h3{font-size:16px;margin-top:10px}.prop p{font-size:12px}.prop a{color:#39717d;margin:0 7px}.prop img{width:100%;display:block}.checker{border-radius:10px;background-color:#e7efea;background-image:linear-gradient(45deg,#d7e1db 25%,transparent 25%),linear-gradient(-45deg,#d7e1db 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#d7e1db 75%),linear-gradient(-45deg,transparent 75%,#d7e1db 75%);background-size:22px 22px;background-position:0 0,0 11px,11px -11px,-11px 0}aside{background:#e1ebe3;border-left:4px solid #8aa895;padding:14px 20px;border-radius:6px;font-size:14px}footer{padding:25px 0;font-size:13px;color:#6c8284}@media(max-width:700px){.scenes{grid-template-columns:1fr}.props{grid-template-columns:repeat(2,minmax(0,1fr))}}
</style><header><small>STAR LANTERN ISLAND · ART LIBRARY</small><h1>星灯岛 · 场景与道具</h1><p>6 个可编辑立体小景、25 件道具，以及透明背景的 2D 静态素材。以温润石材、深蓝屋瓦、黄铜和青蓝／琥珀星光，建立统一的奇幻冒险世界。</p><a class="button" href="world_library.blend">打开道具总库</a><a class="button" href="README.zh-CN.md">使用说明</a><a class="button" href="reports/manifest.json">完整清单</a></header><main><aside>本页展示的图片全部来自对应 Blender 模型的实际渲染。模型可以编辑和导入 Godot；关卡碰撞、导航、交互与动画需要继续制作。透明 PNG 为静态道具精灵，场景预览不是平铺地图图块。</aside><h2>六处冒险场景</h2><section class="scenes">SCENE_CARDS</section><h2>道具与机关</h2><section class="props">PROP_CARDS</section><footer>所有源资产单独保存在 StarLanternIsland/source_models/world；原有游戏项目及角色源文件未被覆盖。</footer></main></html>'''
(ROOT/'世界与道具预览.html').write_text(page.replace('SCENE_CARDS',''.join(cards)).replace('PROP_CARDS',''.join(props)),encoding='utf-8')
print(json.dumps({'passed':result['passed'],'props':result['prop_count'],'scenes':result['scene_count'],'gallery':str(ROOT/'世界与道具预览.html')},ensure_ascii=False))
