"""Derive conservative habitat candidates from existing geography; no acquisition/rebuild."""
import json,math
from shapely.geometry import Point,shape
from tools.gis.bay_imagery import geometry
from tools.gis.build import write_json

def build():
 _,out,land=geometry();zones=json.loads((out/'bay-population-zones.json').read_text())['zones']
 structures=json.loads((out/'structures.json').read_text()).get('features',[])
 network=json.loads((out/'water-network.json').read_text())
 mouths=[shape(n['geometry']) for n in network['nodes'] if not n.get('barrier')]
 # Reuse water corridors for every sub-zone spot, so no new navigation geometry is needed.
 result=[]
 for z in zones:
  shore=land.distance(Point(z['x'],z['y']));depth=z['depth_m'];neighbors=[zones[n] for n in z['neighbors']]
  relief=max([abs(depth-n['depth_m']) for n in neighbors] or [0]);tags=[]
  if shore<850:tags+=['shoreline_edge','mangrove_edge_candidate']
  if shore<500 and len(neighbors)<=2:tags+=['shoreline_point_candidate']
  if depth<2.5 and relief<1.2:tags+=['grass_flat_candidate']
  if depth<4 and any(n['depth_m']<depth-.7 for n in neighbors):tags+=['pothole_candidate']
  if relief>1.5:tags+=['channel_dropoff']
  if shore<600 and depth<2.5:tags+=['oyster_bar_candidate']
  if shore<1000 and any(g.distance(Point(z['x'],z['y']))<300 for g in mouths):tags+=['creek_mouth_candidate']
  if any(math.hypot(f.get('position',[1e9,1e9])[0]-z['x'],f.get('position',[1e9,1e9])[1]-z['y'])<500 for f in structures):tags+=['mapped_structure']
  if not tags:tags=['open_water']
  spots=[]
  for k,role in enumerate(['resting','feeding','hunting']):
   neighbor=neighbors[k%len(neighbors)] if neighbors else z;t=[.08,.17,.25][k]
   spots.append({'id':z['id']+':'+role,'role':role,'x':z['x']+(neighbor['x']-z['x'])*t,'y':z['y']+(neighbor['y']-z['y'])*t,'depth_m':depth+(neighbor['depth_m']-depth)*t})
  result.append({'tags':tags,'shore_distance_m':round(shore,1),'relief_m':round(relief,2),'spots':spots})
 write_json(out/'bay-habitats.json',{'version':1,'zone_ids':[z['id'] for z in zones],'habitats':result,'note':'Heuristic holding-area candidates from existing shoreline, depth relief, mapped structures and flowlines; vegetation/substrate labels are NOT surveyed occurrence. Spots lie on existing validated navigation corridors.'})
 print(len(result),'habitats /',sum(len(h['spots']) for h in result),'spots')
if __name__=='__main__':build()
