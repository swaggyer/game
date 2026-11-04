"""Transport verified source and the release APK through the connected Git API.

The import workflow checks every chunk and materializes normal source files.
Signing credentials and local saves are never added to this archive.
"""
from pathlib import Path
import hashlib,json,zipfile

project=Path(__file__).resolve().parents[1]
workspace=project.parents[1]
staging=workspace/'github_upload_staging'
output=workspace/'.build-toolchain'/'publication'
output.mkdir(parents=True,exist_ok=True)
apk=project/'builds/android/StarLanternIsland-v1.2.1-arm64.apk'
assert apk.is_file()
archive_path=output/'game-source-delivery.zip'
source_files=[p for p in sorted(staging.rglob('*')) if p.is_file() and p.name!='repository_preparation_manifest.json']
assert not any(p.suffix in {'.jks','.keystore','.p12','.pem','.mobileprovision'} for p in source_files)
notes='''# 星灯岛 v1.2.1

- Android arm64 独立签名 release APK；签名、16KB 对齐及 AndroidManifest 校验通过。
- iOS Xcode 工程和未签名设备 IPA 将在 macOS 构建成功后附加到本发布。
- 未签名 IPA 需要开发者签名后才能安装到普通 iPhone，当前没有提供正式 Apple 签名。
- 完整源码、原始 Blender 模型、构建脚本与字体许可位于仓库。
- 当前未进行 Android/iPhone 真机试玩。
'''
with zipfile.ZipFile(archive_path,'w',zipfile.ZIP_DEFLATED,compresslevel=5) as archive:
    for path in source_files:archive.write(path,path.relative_to(staging).as_posix())
    archive.write(apk,'.release-assets/'+apk.name)
    archive.writestr('.release-assets/RELEASE-NOTES.md',notes)
with zipfile.ZipFile(archive_path) as archive:assert archive.testzip() is None
parts=[]
with archive_path.open('rb') as source:
    index=0
    while data:=source.read(4*1024*1024):
        name=f'part-{index:04d}.bin'
        (output/name).write_bytes(data)
        parts.append({'name':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
        index+=1
manifest={'version':1,'release_tag':'v1.2.1','source_files':len(source_files),'archive_bytes':archive_path.stat().st_size,'archive_sha256':hashlib.file_digest(archive_path.open('rb'),'sha256').hexdigest(),'apk_sha256':hashlib.file_digest(apk.open('rb'),'sha256').hexdigest(),'parts':parts}
(output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in manifest.items() if k!='parts'},ensure_ascii=False))
print('TRANSPORT PARTS:',len(parts))
