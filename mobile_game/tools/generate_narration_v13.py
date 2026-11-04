"""Generate cached Chinese story narration; the shipped game plays local MP3s.

Install edge-tts and imageio-ffmpeg in a separate build environment.
Only story text in data/audio_v13.json is submitted to the synthesis service.
"""
from pathlib import Path
import asyncio,hashlib,json,subprocess,socket
import aiohttp,edge_tts,imageio_ffmpeg

PROJECT=Path(__file__).resolve().parents[1]
MANIFEST=PROJECT/'data/audio_v13.json'
VOICE='zh-CN-XiaoxiaoNeural'
RATE='-5%'
TEMP=PROJECT.parents[1]/'.build-toolchain/audio/voice-source'
TEMP.mkdir(parents=True,exist_ok=True)
FFMPEG=imageio_ffmpeg.get_ffmpeg_exe()

async def main():
    data=json.loads(MANIFEST.read_text(encoding='utf-8'))
    unique={key:value for key,value in data['stories'].items() if not value.get('alias_of')}
    semaphore=asyncio.Semaphore(1)
    results={}
    async def generate(key,entry):
        async with semaphore:
            output=PROJECT/entry['path'].removeprefix('res://')
            output.parent.mkdir(parents=True,exist_ok=True)
            source=TEMP/(key+'.mp3')
            fingerprint=hashlib.sha256((VOICE+RATE+entry['text']).encode()).hexdigest()
            stamp=TEMP/(key+'.sha256')
            if not source.is_file() or not stamp.is_file() or stamp.read_text()!=fingerprint:
                for attempt in range(6):
                    try:
                        async with aiohttp.TCPConnector(family=socket.AF_INET) as connector:
                            await edge_tts.Communicate(entry['text'],VOICE,rate=RATE,connector=connector,connect_timeout=15,receive_timeout=45).save(str(source))
                        assert source.stat().st_size>1000
                        stamp.write_text(fingerprint)
                        break
                    except Exception:
                        if attempt==5:raise
                        print('NARRATION_RETRY',key,attempt+1,flush=True)
                        await asyncio.sleep(2+attempt*2)
            subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-y','-i',str(source),'-af','loudnorm=I=-17:TP=-2:LRA=8','-ar','44100','-ac','1','-codec:a','libmp3lame','-b:a','96k',str(output)],check=True)
            from mutagen.mp3 import MP3
            results[key]={'path':entry['path'],'text_sha256':hashlib.sha256(entry['text'].encode()).hexdigest(),'sha256':hashlib.file_digest(output.open('rb'),'sha256').hexdigest(),'duration_seconds':round(MP3(output).info.length,3),'bytes':output.stat().st_size}
            print('NARRATION_READY',key,results[key]['duration_seconds'],flush=True)
    await asyncio.gather(*(generate(key,entry) for key,entry in unique.items()))
    report={'provider':'Microsoft Edge read-aloud via edge-tts','voice':VOICE,'rate':RATE,'offline_runtime':True,'clips':results}
    (PROJECT/'assets/audio_v13/voice/production.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('NARRATION COMPLETE',len(results),'clips',sum(x['duration_seconds'] for x in results.values()),'seconds',flush=True)

if __name__=='__main__':asyncio.run(main())
