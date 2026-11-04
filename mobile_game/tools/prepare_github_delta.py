"""Prepare a verified incremental source+APK delivery against a GitHub tree."""
from pathlib import Path
import hashlib,json,zipfile

project=Path(__file__).resolve().parents[1]
workspace=project.parents[1]
staging=workspace/'github_upload_staging'
output=workspace/'.build-toolchain/publication-v13'
output.mkdir(parents=True,exist_ok=True)
remote=json.loads((output/'remote-tree.json').read_text(encoding='utf-8'))
known={x['path']:x['sha'] for x in remote['tree'] if x['type']=='blob'}
changed=[]
for path in sorted(staging.rglob('*')):
    if not path.is_file() or path.name=='repository_preparation_manifest.json':continue
    data=path.read_bytes()
    sha=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
    relative=path.relative_to(staging).as_posix()
    if known.get(relative)!=sha:changed.append((path,relative))
apk=project/'builds/android/StarLanternIsland-v1.3.0-arm64.apk'
archive_path=output/'game-source-delivery.zip'
with zipfile.ZipFile(archive_path,'w',zipfile.ZIP_DEFLATED,compresslevel=4) as archive:
    for path,relative in changed:archive.write(path,relative)
    archive.write(apk,'.release-assets/'+apk.name)
    archive.writestr('.release-assets/RELEASE-NOTES.md','''# 星灯岛 v1.3.0 · 音乐与剧情朗读

七个地区与标题、战斗、首领共十首独立配乐；28段离线中文旁白。
剧情支持暂停、重听、跳过；朗读压低音乐，三类音量可保存。
Android APK独立签名；iOS未签名IPA及Xcode工程由macOS原生编译后附加。
未签名IPA需要后续签名才能安装到普通iPhone，尚未进行手机真机试玩。
''')
with zipfile.ZipFile(archive_path) as archive:assert archive.testzip() is None
parts=[]
with archive_path.open('rb') as stream:
    while data:=stream.read(4*1024*1024):
        name=f'part-{len(parts):04d}.bin';(output/name).write_bytes(data)
        parts.append({'name':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'git_sha':hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()})
manifest={'version':1,'release_tag':'v1.3.0','source_files':len(changed),'archive_bytes':archive_path.stat().st_size,'archive_sha256':hashlib.file_digest(archive_path.open('rb'),'sha256').hexdigest(),'parts':parts}
(output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps({'changed_source_files':len(changed),'parts':len(parts),'archive_bytes':manifest['archive_bytes'],'sha256':manifest['archive_sha256']}))
