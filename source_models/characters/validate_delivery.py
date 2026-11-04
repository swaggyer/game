"""Read-only validation of GLB structure, embedded textures and sprite alpha."""
from pathlib import Path
import struct,json,math
from PIL import Image
HERE=Path(__file__).resolve().parent

def read_glb(p):
 data=p.read_bytes();magic,version,size=struct.unpack_from('<III',data,0)
 assert magic==0x46546c67 and version==2 and size==len(data)
 length,kind=struct.unpack_from('<II',data,12);assert kind==0x4e4f534a
 doc=json.loads(data[20:20+length]);offset=20+length
 blen,btype=struct.unpack_from('<II',data,offset);assert btype==0x004e4942
 blob=data[offset+8:offset+8+blen]
 return doc,blob

report={}
for key in ['wangzai','xiaomantou']:
 detail={}
 for suffix in ['', '-lod1']:
  p=HERE/key/(key+suffix+'.glb');doc,blob=read_glb(p)
  mesh_nodes=[n for n in doc['nodes'] if 'mesh' in n]
  animations=[a.get('name','') for a in doc.get('animations',[])]
  joints=[len(s['joints']) for s in doc.get('skins',[])]
  embedded=all('bufferView' in i for i in doc.get('images',[]))
  assert mesh_nodes and joints and min(joints)>=18
  assert len(animations)>=5,animations
  assert embedded,'External texture would break portability'
  tris=0;finite=True
  for m in doc.get('meshes',[]):
   for pr in m['primitives']:
    ac=doc['accessors'][pr['attributes']['POSITION']];bv=doc['bufferViews'][ac['bufferView']]
    start=bv.get('byteOffset',0)+ac.get('byteOffset',0);stride=bv.get('byteStride',12)
    for i in range(ac['count']):finite &= all(math.isfinite(v) for v in struct.unpack_from('<3f',blob,start+i*stride))
    if 'indices' in pr:tris+=doc['accessors'][pr['indices']]['count']//3
  assert finite
  detail['model'+suffix]={'path':str(p),'bytes':p.stat().st_size,'mesh_nodes':len(mesh_nodes),'skin_joint_counts':joints,'animations':animations,'triangles':tris,'embedded_textures':embedded,'finite_positions':finite}
 sprites=[]
 for p in sorted((HERE/'renders').glob(key+'_*.png')):
  with Image.open(p) as im:
   assert im.mode=='RGBA',(p.name,im.mode)
   alpha=im.getchannel('A');lo,hi=alpha.getextrema();bbox=alpha.getbbox()
   assert lo==0 and hi>0 and bbox,(p.name,lo,hi,bbox)
   sprites.append({'path':str(p),'size':list(im.size),'alpha_min':lo,'alpha_max':hi,'alpha_bbox':list(bbox)})
 detail['sprite_count']=len(sprites);detail['sprites']=sprites
 report[key]=detail
(HERE/'reports'/'delivery-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:{'models':{n:{'triangles':m['triangles'],'mesh_nodes':m['mesh_nodes'],'bones':m['skin_joint_counts'],'animations':m['animations']} for n,m in v.items() if n.startswith('model')},'rgba_sprites':v['sprite_count']} for k,v in report.items()},ensure_ascii=False,indent=2))
