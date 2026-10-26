"""Connected polygon network and incremental shoreline patch (no invented widths)."""
import json,hashlib
from collections import defaultdict,deque
from shapely.geometry import shape,box,Polygon,mapping,Point
from shapely.ops import transform,unary_union
from shapely import make_valid,STRtree
from tools.gis.pilot_build import context
from tools.gis.build import ROOT,write_json,polygons,rings,mesh
from tools.gis.phase3_acquire import CORRIDORS

def build():
 cfg,geo,out,m,boundary,old=context();src=ROOT/'data/sources/phase3/hydro'
 # The seed is the existing open coastal-water polygon containing the boat spawn.
 coast=boundary.difference(old);spawn=Point(*m['spawn']);root=next(p for p in polygons(coast) if p.covers(spawn));seed=root.buffer(-30)
 flows={};areas={};barriers={};incomplete=[]
 for name in CORRIDORS:
  for kind,target in [('areas',areas),('flowlines',flows),('barriers',barriers)]:
   path=src/f'{name}-{kind}.geojson'
   if not path.exists():
    incomplete.append(name+'-'+kind);continue
   for f in json.loads(path.read_text())['features']:
    props=f['properties'];id=str(props.get('permanent_identifier',props.get('objectid')))
    g=make_valid(transform(geo.to_world,shape(f['geometry']))).intersection(boundary)
    if not g.is_empty:target[id]=(props,g)
 # Successful cached batches are authoritative even if a later request timed out.
 for path in list(src.glob('flowlines-*.json'))+list(src.glob('*-named.json')):
  for f in json.loads(path.read_text())['features']:
   props=f['properties'];id=str(props.get('permanent_identifier',props.get('objectid')));g=make_valid(transform(geo.to_world,shape(f['geometry']))).intersection(boundary)
   if not g.is_empty:flows[id]=(props,g)
 bynode=defaultdict(list)
 for id,(p,g) in flows.items():
  for node in [p.get('fromnode'),p.get('tonode')]:
   if node: bynode[node].append(id)
 connected=set();queue=deque(id for id,(p,g) in flows.items() if g.intersects(seed))
 while queue:
  id=queue.popleft()
  if id in connected:continue
  connected.add(id);p,g=flows[id]
  for node in [p.get('fromnode'),p.get('tonode')]:
   if node:queue.extend(n for n in bynode[node] if n not in connected)
 lines=[flows[id][1] for id in sorted(connected)];network=unary_union(lines)
 accepted=[];excluded=0
 # Reservoirs/lakes are only included if supplied as an authoritative polygon with a supported connection.
 for p,g in areas.values():
  if int(p.get('ftype',0)) not in [312,390,436,445,460]:continue
  if g.intersects(network) or g.intersects(seed):accepted.append(g)
  else:excluded+=1
 # Re-evaluate the old pilot's waterbodies, closing disconnected retention ponds.
 for f in json.loads((ROOT/'data/sources/hydro/waterbodies.geojson').read_text())['features']:
  g=make_valid(transform(geo.to_world,shape(f['geometry']))).intersection(boundary)
  if not g.is_empty and g.intersects(network):accepted.append(g)
  else:excluded+=1
 water=make_valid(unary_union(accepted));islands=unary_union([Polygon(r) for p in polygons(water) for r in p.interiors]);land=make_valid(old.difference(water).union(islands))
 aoi=unary_union([transform(geo.to_world,box(*b)) for b in CORRIDORS.values()]);changed=[]
 def lines_of(g,x,y):
  if g.geom_type in ['LineString','LinearRing']:return [[[round(a-x,4),round(b-y,4)] for a,b in g.coords]]
  return [v for z in getattr(g,'geoms',[]) for v in lines_of(z,x,y)]
 for level in range(cfg['max_lod']+1):
  simple=make_valid(land.simplify(cfg['simplify_m'][level],preserve_topology=True))
  for key,node in m['nodes'].items():
   if node['level']!=level:continue
   x,y,size=node['x'],node['y'],node['size'];tile=box(x,y,x+size,y+size)
   if not tile.intersects(aoi):continue
   path=out/'chunks'/f'{key}.json';obj=json.loads(path.read_text());obj['vertices'],obj['indices']=mesh(simple.intersection(tile),x,y);obj['shore']=lines_of(simple.boundary.intersection(tile),x,y)
   if level==0:
    obj['land']=[rings(p,x,y) for p in polygons(land.intersection(tile))];obj['mapped_water']=[rings(p,x,y) for p in polygons(water.intersection(tile))]
    obj['barriers']=[v for p,g in barriers.values() for v in lines_of(g.intersection(tile),x,y)]
   payload=json.dumps(obj,separators=(',',':'),sort_keys=True).encode();raw=path.with_suffix('.f32').read_bytes();digest=hashlib.sha256(payload+raw+b'3').hexdigest()
   if payload!=path.read_bytes():path.write_bytes(payload);changed.append(key)
   path.with_suffix('.sha256').write_text(digest);path.with_suffix('.input.sha256').write_text('phase3-hydro-'+digest);node.update(bytes=len(payload)+len(raw),sha256=digest)
  print('Hydro LOD',level,flush=True)
 graph=[]
 for id in sorted(connected):
  p,g=flows[id];edges=set(n for node in [p.get('fromnode'),p.get('tonode')] if node for n in bynode[node] if n in connected and n!=id)
  blocked=any(g.intersects(b) for _,b in barriers.values())
  graph.append({'id':id,'name':p.get('gnis_name'),'geometry':mapping(g),'neighbors':sorted(edges),'polygon_supported':water.covers(g),'hydrologic_connected':True,'boat_passage':'blocked' if blocked else 'requires width, depth and footprint check','fish_passage':'unknown at mapped barrier' if blocked else 'hydrologic connection only; passage unverified','barrier':blocked})
 write_json(out/'water-network.json',{'incomplete_acquisitions':incomplete,'source':'https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer','root':'existing coastal polygon containing Tampa Bay boat spawn','connection':'NHD fromnode/tonode graph; polygons must intersect connected flowline or coastal seed','nodes':graph,'excluded_unconnected_polygons':excluded,'bounds_wgs84':CORRIDORS,'water':mapping(water),'note':'Centerline-only reaches remain non-playable; no fabricated widths. Map boundary and unacquired lake polygons limit upstream extent.'})
 m['hydrography_phase3']={'connected_flowlines':len(graph),'excluded_unconnected_polygons':excluded,'barriers':len(barriers),'changed_tiles':len(changed)};write_json(out/'manifest.json',m);print(m['hydrography_phase3'])
if __name__=='__main__':build()
