"""Validate GLB mesh/animation structure and PNG alpha without external packages."""
import os, json, struct, zlib, csv
BASE=r'E:\game\StarLanternIsland\source_models\creatures'

def glb(path):
    raw=open(path,'rb').read();magic,version,size=struct.unpack_from('<4sII',raw)
    assert magic==b'glTF' and version==2 and size==len(raw)
    length,typ=struct.unpack_from('<II',raw,12);assert typ==0x4E4F534A
    d=json.loads(raw[20:20+length]);a=d.get('accessors',[])
    tris=0;verts=0
    for mesh in d.get('meshes',[]):
        for primitive in mesh['primitives']:
            verts+=a[primitive['attributes']['POSITION']]['count']
            if primitive.get('mode',4)==4:
                tris+=a[primitive['indices']]['count']//3 if 'indices' in primitive else a[primitive['attributes']['POSITION']]['count']//3
    return {'bytes':len(raw),'nodes':len(d.get('nodes',[])),'meshes':len(d.get('meshes',[])),'vertices':verts,'triangles':tris,'skins':len(d.get('skins',[])),'animation_clips':len(d.get('animations',[])),'animation_channels':sum(len(x['channels']) for x in d.get('animations',[]))}

def png(path):
    raw=open(path,'rb').read();assert raw[:8]==b'\x89PNG\r\n\x1a\n'
    pos=8;idat=[]
    while pos<len(raw):
        n,tag=struct.unpack_from('>I4s',raw,pos);chunk=raw[pos+8:pos+8+n]
        if tag==b'IHDR':w,h,depth,ct,comp,filt,interlace=struct.unpack('>IIBBBBB',chunk)
        if tag==b'IDAT':idat.append(chunk)
        pos+=n+12
    assert depth==8 and ct==6 and interlace==0,(depth,ct,interlace)
    stream=zlib.decompress(b''.join(idat));stride=w*4;prev=bytearray(stride);pos=0;amin=255;amax=0;opaque=0;xmin=w;xmax=-1;ymin=h;ymax=-1
    for y in range(h):
        ft=stream[pos];pos+=1;row=bytearray(stream[pos:pos+stride]);pos+=stride
        for i in range(stride):
            left=row[i-4] if i>=4 else 0;up=prev[i];ul=prev[i-4] if i>=4 else 0
            if ft==1:row[i]=(row[i]+left)&255
            elif ft==2:row[i]=(row[i]+up)&255
            elif ft==3:row[i]=(row[i]+((left+up)//2))&255
            elif ft==4:
                p=left+up-ul;pa=abs(p-left);pb=abs(p-up);pc=abs(p-ul)
                pred=left if pa<=pb and pa<=pc else up if pb<=pc else ul
                row[i]=(row[i]+pred)&255
        alphas=row[3::4];amin=min(amin,min(alphas));amax=max(amax,max(alphas))
        for x,a in enumerate(alphas):
            if a>5:xmin=min(xmin,x);xmax=max(xmax,x);ymin=min(ymin,y);ymax=max(ymax,y);opaque+=1
        prev=row
    return {'width':w,'height':h,'alpha_min':amin,'alpha_max':amax,'visible_pixels':opaque,'visible_bounds':[xmin,ymin,xmax,ymax],'clear_outer_margin':xmin>0 and ymin>0 and xmax<w-1 and ymax<h-1}

manifest=json.load(open(os.path.join(BASE,'reports','manifest.json'),encoding='utf-8'))
results=[]
for asset in manifest:
    info=glb(asset['model']);assert info['meshes']>0 and info['skins']==0 and info['animation_channels']>0
    rendered={}
    for path in [asset['preview']]+list(asset['sprites'].values()):
        p=png(path);assert p['alpha_min']==0 and p['alpha_max']==255;assert p['clear_outer_margin'],path
        rendered[os.path.basename(path)]=p
    asset['exported_triangles']=info['triangles'];asset['exported_vertices']=info['vertices'];asset['exported_animation_clips']=info['animation_clips']
    results.append({'id':asset['id'],'model':info,'pngs':rendered,'passed':True})
with open(os.path.join(BASE,'reports','validation.json'),'w',encoding='utf-8') as f:json.dump({'passed':True,'asset_count':len(results),'results':results},f,ensure_ascii=False,indent=2)
with open(os.path.join(BASE,'reports','manifest.json'),'w',encoding='utf-8') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)
with open(os.path.join(BASE,'reports','asset_list.csv'),'w',encoding='utf-8-sig',newline='') as f:
    w=csv.writer(f);w.writerow(['id','name_zh','triangles','vertices','animation_clips','skeletal_rig','model','preview'])
    for a in manifest:w.writerow([a['id'],a['name_zh'],a['exported_triangles'],a['exported_vertices'],a['exported_animation_clips'],False,a['model'],a['preview']])
print(json.dumps({'passed':True,'assets':len(results),'triangle_counts':{a['id']:a['exported_triangles'] for a in manifest}},ensure_ascii=False))
