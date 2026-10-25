"""Fetch pinned public sources; source bytes/metadata stay outside Godot.
ArcGIS object-ID batching prevents silently truncated polygon downloads.
"""
import argparse, hashlib, json, time
from pathlib import Path
import requests
ROOT=Path(__file__).resolve().parents[2]
BASE='https://encdirect.noaa.gov/arcgis/rest/services/encdirect/enc_coastal/MapServer'
def get(url,params=None):
    for attempt in range(4):
        r=requests.get(url,params=params,timeout=120);r.raise_for_status()
        d=r.json()
        if 'error' not in d: break
        time.sleep(1)
    if 'error' in d: raise RuntimeError(str(d['error'])+' '+r.url)
    return d

def fetch_enc(config,force=False):
    out=ROOT/'data/sources';out.mkdir(parents=True,exist_ok=True)
    bbox=','.join(map(str,config['bbox_wgs84']))
    for name,layer in [('land',171),('rivers',174),('lakes',170),('coverage',158),('channels',150)]:
        path=out/(name+'.geojson')
        if path.exists() and not force:
            sidecar=path.with_suffix('.metadata.json')
            if not sidecar.exists(): raise RuntimeError(f'Missing metadata for {path}; use --force to refresh')
            previous=json.loads(sidecar.read_text())
            if previous['bbox_wgs84']!=config['bbox_wgs84']: raise RuntimeError('Boundary changed: use --force to refresh source selection')
            if previous['sha256']!=hashlib.sha256(path.read_bytes()).hexdigest(): raise RuntimeError(f'Source checksum mismatch: {path}')
            continue
        meta=get(f'{BASE}/{layer}',{'f':'json'})
        ids=get(f'{BASE}/{layer}/query',{'f':'json','where':'1=1','geometry':bbox,'geometryType':'esriGeometryEnvelope','inSR':4326,'returnIdsOnly':'true'})
        features=[]
        for start in range(0,len(ids.get('objectIds') or []),50):
            batch=sorted(ids['objectIds'])[start:start+50]
            d=get(f'{BASE}/{layer}/query',{'f':'geojson','objectIds':','.join(map(str,batch)),'outFields':'*','outSR':4326,'returnGeometry':'true'})
            if d.get('exceededTransferLimit'): raise RuntimeError('Server truncated response')
            features.extend(d['features'])
        path.write_text(json.dumps({'type':'FeatureCollection','features':features},sort_keys=True),encoding='utf8')
        meta.update(url=f'{BASE}/{layer}',bbox_wgs84=config['bbox_wgs84'],download_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),feature_count=len(features),quality='charted; compilation-scale dependent',vertical_datum='not used for elevation')
        path.with_suffix('.metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf8')
        print(name,len(features),path.stat().st_size,flush=True)

def download(url,path):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists(): return
    temp=path.with_suffix(path.suffix+'.partial')
    with requests.get(url,stream=True,timeout=120) as r:
        r.raise_for_status()
        with temp.open('wb') as f:
            for chunk in r.iter_content(1024*1024): f.write(chunk)
    temp.replace(path)
    path.with_suffix(path.suffix+'.download.json').write_text(json.dumps({'url':url,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()},indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--config',default=str(ROOT/'config/region.json'));p.add_argument('--force',action='store_true');p.add_argument('--url');p.add_argument('--output');a=p.parse_args()
    if a.url: download(a.url,a.output)
    else: fetch_enc(json.loads(Path(a.config).read_text()),a.force)

