"""Validate bay-only zone geometry without rebuilding any river data."""
import json
from pathlib import Path
from shapely.geometry import LineString,shape
from shapely import prepare
from tools.gis.bay_imagery import geometry
ROOT=Path(__file__).resolve().parents[1]
def test_zone_links_stay_in_connected_water():
 geo,out,land=geometry();data=json.loads((out/'bay-population-zones.json').read_text());zones=data['zones'];assert len(zones)>500
 barriers=[shape(n['geometry']) for n in json.loads((out/'water-network.json').read_text())['nodes'] if n.get('barrier')]
 prepare(land);ids=set();seen=set();pending=[data['root_zone']]
 while pending:
  i=pending.pop()
  if i in seen:continue
  seen.add(i);pending.extend(zones[i]['neighbors'])
 assert len(seen)==len(zones)
 for i,z in enumerate(zones):
  assert z['id'] not in ids;ids.add(z['id']);assert z['depth_m']>0
  for j in z['neighbors']:
   assert i in zones[j]['neighbors'];q=zones[j];line=LineString([(z['x'],z['y']),(q['x'],q['y'])])
   assert not land.intersects(line.buffer(2.9)),(i,j)
   assert not any(line.intersects(b) for b in barriers),(i,j,'barrier')
