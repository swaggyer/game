"""Lossless ZIP-entry transport for an APK signed locally; no signing material travels."""
from pathlib import Path
import argparse, hashlib, json, struct, zipfile

def sha(data):
    return hashlib.sha256(data).hexdigest()

def segments(path):
    raw = path.read_bytes()
    with zipfile.ZipFile(path) as archive:
        offsets = []
        for info in archive.infolist():
            header=info.header_offset
            name_length,extra_length=struct.unpack_from('<HH',raw,header+26)
            payload=header+30+name_length+extra_length
            offsets.extend([header,payload,payload+info.compress_size])
        central = archive.start_dir
    positions = sorted(set([0, *offsets, central, len(raw)]))
    return raw, [(a,b) for a,b in zip(positions,positions[1:])]

def make(base, target, patch):
    old, spans = segments(base)
    new, target_spans = segments(target)
    matches = {sha(old[a:b]): (a,b-a) for a,b in spans}
    document = dict(base_sha256=sha(old), target_sha256=sha(new), target_bytes=len(new), operations=[])
    copied = 0
    with zipfile.ZipFile(patch, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for a,b in target_spans:
            data = new[a:b]
            match = matches.get(sha(data))
            if match:
                document['operations'].append(dict(copy=list(match)))
                copied += len(data)
            else:
                name = f"data/{len(document['operations']):05d}.bin"
                archive.writestr(name, data)
                document['operations'].append(dict(data=name))
        archive.writestr('manifest.json', json.dumps(document))
    return dict(patch_bytes=patch.stat().st_size, reused_bytes=copied, target_sha256=document['target_sha256'])

def apply(base, patch, output):
    raw = base.read_bytes()
    with zipfile.ZipFile(patch) as archive:
        document=json.loads(archive.read('manifest.json'))
        assert sha(raw)==document['base_sha256'], 'Base APK checksum mismatch'
        with output.open('wb') as stream:
            for operation in document['operations']:
                if 'copy' in operation:
                    offset,length=operation['copy']
                    assert offset>=0 and length>=0 and offset+length<=len(raw)
                    stream.write(raw[offset:offset+length])
                else:stream.write(archive.read(operation['data']))
        assert output.stat().st_size==document['target_bytes']
        assert sha(output.read_bytes())==document['target_sha256'], 'Rebuilt signed APK checksum mismatch'

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['make','apply'])
    parser.add_argument('base',type=Path)
    parser.add_argument('input',type=Path)
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    if args.mode=='make':print(json.dumps(make(args.base,args.input,args.output)))
    else:apply(args.base,args.input,args.output)
