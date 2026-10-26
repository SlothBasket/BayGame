from tools.gis.phase3_acquire import CORRIDORS
from tools.gis.pilot_acquire import session,query,NHD
from tools.gis.build import ROOT,write_json
s=session()
for name,bb in CORRIDORS.items():
 p=ROOT/'data/sources/phase3/hydro'/f'{name}-barriers.geojson'
 if p.exists():continue
 d=query(s,NHD+'/7/query',{'f':'geojson','where':'ftype IN (343,369)','geometry':','.join(map(str,bb)),'geometryType':'esriGeometryEnvelope','inSR':4326,'outSR':4326,'outFields':'*','returnGeometry':'true'})
 assert not d.get('exceededTransferLimit');write_json(p,d);print(name,len(d['features']),flush=True)
# Patch barrier inventories independently of an expensive shoreline rebuild.
import json,hashlib
from shapely.geometry import shape,box
from shapely.ops import transform
from tools.gis.coordinates import Coordinates
out=ROOT/'godot/assets/generated';path=out/'water-network.json'
if path.exists():
 geo=Coordinates(json.loads((ROOT/'config/region.json').read_text()));barriers={}
 for name in CORRIDORS:
  for f in json.loads((ROOT/'data/sources/phase3/hydro'/f'{name}-barriers.geojson').read_text())['features']:
   barriers[f['properties']['permanent_identifier']]=transform(geo.to_world,shape(f['geometry']))
 graph=json.loads(path.read_text())
 for n in graph['nodes']:
  n['barrier']=any(shape(n['geometry']).intersects(g) for g in barriers.values())
  if n['barrier']:n['boat_passage']='blocked';n['fish_passage']='unknown at mapped barrier'
 graph['incomplete_acquisitions']=[n for n in graph['incomplete_acquisitions'] if not n.endswith('-barriers')];write_json(path,graph)
 m=json.loads((out/'manifest.json').read_text());count=0
 def segments(g,x,y):
  if g.geom_type in ['LineString','LinearRing']:return [[[a-x,b-y] for a,b in g.coords]]
  return [v for child in getattr(g,'geoms',[]) for v in segments(child,x,y)]
 for key,node in m['nodes'].items():
  if node['level']!=0:continue
  x,y,size=node['x'],node['y'],node['size'];tile=box(x,y,x+size,y+size);near=[g for g in barriers.values() if g.intersects(tile)]
  if not near:continue
  p=out/'chunks'/f'{key}.json';d=json.loads(p.read_text());d['barriers']=[v for g in near for v in segments(g.intersection(tile),x,y)];payload=json.dumps(d,separators=(',',':'),sort_keys=True).encode();p.write_bytes(payload);raw=p.with_suffix('.f32').read_bytes();digest=hashlib.sha256(payload+raw+b'3').hexdigest();p.with_suffix('.sha256').write_text(digest);p.with_suffix('.input.sha256').write_text('phase3-barriers-'+digest);node.update(bytes=len(payload)+len(raw),sha256=digest);count+=1
 m['hydrography_phase3']['barriers']=len(barriers);write_json(out/'manifest.json',m);print('Patched barriers',len(barriers),'in',count,'tiles')
