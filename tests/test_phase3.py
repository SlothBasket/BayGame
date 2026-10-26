"""Targeted Phase 3 generated-data checks; no full base rebuild."""
import json
from pathlib import Path
import numpy as np
from shapely.geometry import shape,LineString
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'godot/assets/generated'
def test_reconstruction_halos_and_precedence():
 files=list((OUT/'chunks').glob('0_*.recon.f32'));assert files
 for p in files:
  a=np.fromfile(p,dtype='<f4').reshape(67,67);_,x,y=p.name.split('.')[0].split('_');x=int(x);y=int(y)
  original=np.fromfile(p.with_name(p.name.replace('.recon','')),dtype='<f4').reshape(67,67)
  assert not np.any(np.isfinite(a)&np.isfinite(original)),p.name
  for dx,dy in [(1,0),(0,1)]:
   q=p.with_name(f'0_{x+dx}_{y+dy}.recon.f32')
   if not q.exists():continue
   b=np.fromfile(q,dtype='<f4').reshape(67,67)
   assert np.array_equal(a[:,-3:] if dx else a[-3:,:],b[:,:3] if dx else b[:3,:],equal_nan=True),(p.name,q.name)
def test_network_and_habitat():
 graph=json.loads((OUT/'water-network.json').read_text());nodes={n['id']:n for n in graph['nodes']};assert nodes and graph['excluded_unconnected_polygons']>0
 for n in nodes.values():
  assert n['hydrologic_connected']
  for neighbor in n['neighbors']:assert neighbor in nodes and n['id'] in nodes[neighbor]['neighbors']
 routes=json.loads((OUT/'fish-habitat.json').read_text())['routes'];assert routes
 water=shape(graph['water'])
 for r in routes:
  assert r['depth_m']>0 and water.covers(LineString([r['a'],r['b']]))
  for end,edges in enumerate(r['edges']):
   for target,target_end in edges:
    p=r['a'] if end==0 else r['b'];q=routes[target]['a'] if target_end==0 else routes[target]['b']
    assert np.linalg.norm(np.array(p)-q)<.03
