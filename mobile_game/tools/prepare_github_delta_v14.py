"""Package changed public sources and a lossless, locally verified APK transport."""
from pathlib import Path
import hashlib,json,zipfile
from apk_delta import make,apply

project=Path(__file__).resolve().parents[1]
workspace=project.parents[1]
staging=workspace/'github_upload_staging'
output=workspace/'.build-toolchain/publication-v14'
output.mkdir(parents=True,exist_ok=True)
paths=json.loads((output/'changed-paths.json').read_text(encoding='utf-8'))
base=project/'builds/android/StarLanternIsland-v1.3.0-arm64.apk'
target=project/'builds/android/StarLanternIsland-v1.4.0-arm64.apk'
patch=output/'android.delta.zip'
stats=make(base,target,patch)
rebuilt=output/'verified-rebuilt.apk'
apply(base,patch,rebuilt)
assert rebuilt.read_bytes()==target.read_bytes()
archive_path=output/'game-source-delivery.zip'
with zipfile.ZipFile(archive_path,'w',zipfile.ZIP_DEFLATED,compresslevel=5) as archive:
    for relative in paths:
        path=(staging/relative).resolve()
        assert path.is_relative_to(staging.resolve()) and path.is_file()
        assert path.suffix not in {'.jks','.keystore','.p12','.pem','.mobileprovision','.apk','.ipa'}
        archive.write(path,relative)
    archive.write(patch,'.release-assets/android.delta.zip')
    archive.write(project/'docs/V1.4性能修复.md','.release-assets/RELEASE-NOTES.md')
parts=[]
with archive_path.open('rb') as stream:
    while data:=stream.read(512*1024):
        name=f'part-{len(parts):04d}.bin';(output/name).write_bytes(data)
        parts.append(dict(name=name,bytes=len(data),sha256=hashlib.sha256(data).hexdigest()))
manifest=dict(version=1,release_tag='v1.4.0',source_files=len(paths),archive_bytes=archive_path.stat().st_size,archive_sha256=hashlib.sha256(archive_path.read_bytes()).hexdigest(),parts=parts)
(output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps(dict(source_files=len(paths),parts=len(parts),archive_bytes=manifest['archive_bytes'],**stats)))
