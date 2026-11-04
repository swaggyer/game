"""Make a reproducible complete delivery without local saves or render caches."""
from pathlib import Path
import hashlib,json,zipfile

project=Path(__file__).resolve().parents[1]
base=project.parent
destination=base/'星灯岛-实战闯关版-v1.2.1.zip'

def include(path,root):
    parts=path.relative_to(root).parts
    if any(p in {'.godot','.git','__pycache__','userdata'} for p in parts):return False
    if path.suffix in {'.tmp','.pyc','.blend1','.blend2'}:return False
    if root==project and parts[0]=='tests' and len(parts)>2 and parts[1]!='history':return False
    if root==project and parts[:3]==('assets','locomotion_v12','source'):return False
    return True

roots=[project,base/'source_models',base/'design_web'/'content']
files=[]
for root in roots:
    if root.exists():
        for path in sorted(root.rglob('*')):
            if path.is_file() and include(path,root):files.append(path)
with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
    for path in files:archive.write(path,path.relative_to(base).as_posix())
with zipfile.ZipFile(destination) as archive:
    bad=archive.testzip()
    assert bad is None,bad
    names=set(archive.namelist())
    for required in ['mobile_game/project.godot','mobile_game/builds/试玩星灯岛.cmd','mobile_game/builds/StarLanternIsland.pck','mobile_game/builds/StarLanternIsland.exe','mobile_game/assets/portraits_v12/wangzai.png','mobile_game/assets/portraits_v12/xiaomantou.png','mobile_game/assets/locomotion_v12/manifest.json','source_models/characters/wangzai/wangzai.blend']:
        assert required in names,required
    assert not any('/userdata/' in name or '/.godot/' in name for name in names)
print(json.dumps({'archive':str(destination),'files':len(files),'bytes':destination.stat().st_size,'sha256':hashlib.file_digest(destination.open('rb'),'sha256').hexdigest(),'integrity':'passed'},ensure_ascii=False))
