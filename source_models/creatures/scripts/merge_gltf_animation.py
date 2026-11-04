"""Unify disjoint root/wing tracks as one simultaneously playable Idle clip."""
import os, json, struct
BASE=r'E:\game\StarLanternIsland\source_models\creatures'
for filename in os.listdir(os.path.join(BASE,'models')):
    if not filename.endswith('.glb'):continue
    path=os.path.join(BASE,'models',filename);raw=open(path,'rb').read()
    length,chunk_type=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+length]);old=doc.get('animations',[])
    if not old:continue
    merged={'name':'Idle','channels':[],'samplers':[],'extras':{'source_tracks':[a.get('name','') for a in old],'animation_kind':'object transforms, not skeletal'}}
    for animation in old:
        offset=len(merged['samplers']);merged['samplers'].extend(animation['samplers'])
        for channel in animation['channels']:
            channel=dict(channel);channel['sampler']+=offset;merged['channels'].append(channel)
    doc['animations']=[merged]
    encoded=json.dumps(doc,ensure_ascii=False,separators=(',',':')).encode('utf-8');encoded+=b' '*((-len(encoded))%4)
    tail=raw[20+length:];new=struct.pack('<4sII',b'glTF',2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),chunk_type)+encoded+tail
    with open(path,'wb') as f:f.write(new)
    print(filename,'Idle channels',len(merged['channels']))
