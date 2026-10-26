"""Cached authoritative NHD polygon acquisition for tributary corridors."""
import json,hashlib
from concurrent.futures import ThreadPoolExecutor
from tools.gis.pilot_acquire import session,query,NHD
from tools.gis.build import ROOT,write_json
CORRIDORS={'alafia':[-82.43,27.80,-82.15,27.96],'hillsborough':[-82.49,27.92,-82.30,28.18],'little_manatee':[-82.56,27.60,-82.15,27.79],'manatee':[-82.66,27.35,-82.15,27.60],'old_tampa':[-82.76,27.94,-82.48,28.18]}
def acquire(pair):
 name,bb=pair;s=session();out=ROOT/'data/sources/phase3/hydro';out.mkdir(parents=True,exist_ok=True)
 for layer,kind in [(8,'areas'),(3,'flowlines'),(7,'barriers')]:
  final=out/f'{name}-{kind}.geojson'
  if final.exists():continue
  url=NHD+'/'+str(layer)+'/query';where='ftype IN (343,369)' if kind=='barriers' else '1=1'
  ids=query(s,url,dict(f='json',where=where,geometry=','.join(map(str,bb)),geometryType='esriGeometryEnvelope',inSR=4326,returnIdsOnly='true')).get('objectIds') or []
  features=[]
  for i in range(0,len(ids),100):
   batch=sorted(ids)[i:i+100];cache=out/(kind+'-'+hashlib.sha256(str(batch).encode()).hexdigest()[:16]+'.json')
   if cache.exists():d=json.loads(cache.read_text())
   else:d=query(s,url,dict(f='geojson',objectIds=','.join(map(str,batch)),outFields='*',outSR=4326,returnGeometry='true'));write_json(cache,d)
   assert len(d['features'])==len(batch);features+=d['features'];print(name,kind,i+len(batch),'/',len(ids),flush=True)
  write_json(final,dict(type='FeatureCollection',features=features));print(name,kind,len(features),flush=True)
if __name__=='__main__':
 with ThreadPoolExecutor(3) as pool:list(pool.map(acquire,CORRIDORS.items()))
