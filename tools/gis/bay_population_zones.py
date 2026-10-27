"""Stable 750 m bay population zones, independent of renderer tiles.
All links are checked against unchanged geographic water geometry and barriers.
"""
import json,math
import numpy as np
from shapely.geometry import box,Point,LineString,shape
from shapely.ops import transform,unary_union
from shapely import prepare
from tools.gis.bay_imagery import geometry,BBOX
from tools.gis.build import ROOT,write_json
from tools.gis.coordinates import Coordinates

def build():
 geo,out,land=geometry();area=transform(geo.to_world,box(*BBOX));water=area.difference(land).intersection(shape(json.loads((out/"bay-estuary-mask.json").read_text())["geometry"]));prepare(water);m=json.loads((out/'manifest.json').read_text());cache={};zones=[];lookup={};step=750
 barrier_paths=[shape(n["geometry"]) for n in json.loads((out/"water-network.json").read_text())["nodes"] if n.get("barrier")]
 def depth(x,y):
  key=f'0_{math.floor(x/1024)}_{math.floor(y/1024)}'
  if key not in cache:
   p=out/'chunks'/f'{key}.f32'
   if not p.exists():return None
   v=np.fromfile(p,dtype='<f4').reshape(67,67)
   for kind in ['survey','recon']:
    q=p.with_suffix('.'+kind+'.f32')
    if q.exists():
     z=np.fromfile(q,dtype='<f4').reshape(67,67);v=np.where(np.isfinite(z),z,v) if kind=='survey' else np.where(np.isfinite(v),v,z)
   cache[key]=v
  fx=(x%1024)/16+1;fy=(y%1024)/16+1;ix=int(fx);iy=int(fy);a=cache[key][iy:iy+2,ix:ix+2]
  if not np.isfinite(a).all():return None
  z=a[0,0]*(1-fx+ix)*(1-fy+iy)+a[0,1]*(fx-ix)*(1-fy+iy)+a[1,0]*(1-fx+ix)*(fy-iy)+a[1,1]*(fx-ix)*(fy-iy)
  return float(max(0,-z))
 bb=area.bounds
 for gy in range(math.ceil(bb[1]/step),math.floor(bb[3]/step)+1):
  for gx in range(math.ceil(bb[0]/step),math.floor(bb[2]/step)+1):
   x,y=gx*step,gy*step;d=depth(x,y)
   if d is None or d<.25 or not water.covers(Point(x,y).buffer(15)):continue
   i=len(zones);lookup[(gx,gy)]=i;zones.append({'id':f'bay750:{gx}:{gy}','x':x,'y':y,'depth_m':d,'neighbors':[],'food_capacity':round(.35+.6*((gx*73856093^gy*19349663)%1000)/999,3)})
 # Keep only bay-rooted connected zones; no diagonal corner cutting.
 for (gx,gy),i in lookup.items():
  a=zones[i]
  for dx,dy in [(1,0),(0,1)]:
   j=lookup.get((gx+dx,gy+dy))
   if j is None:continue
   b=zones[j];line=LineString([(a['x'],a['y']),(b['x'],b['y'])])
   if not water.covers(line.buffer(3)) or any(line.intersects(b) for b in barrier_paths):continue
   samples=[depth(*line.interpolate(t,normalized=True).coords[0]) for t in [.25,.5,.75]]
   if any(v is None or v<.2 for v in samples):continue
   a['neighbors'].append(j);b['neighbors'].append(i)
 root=min(range(len(zones)),key=lambda i:(zones[i]['x']-m['spawn'][0])**2+(zones[i]['y']-m['spawn'][1])**2);seen=set();pending=[root]
 while pending:
  i=pending.pop()
  if i in seen:continue
  seen.add(i);pending.extend(zones[i]['neighbors'])
 order=sorted(seen);remap={old:new for new,old in enumerate(order)};selected=[]
 for i in order:
  z=zones[i];z['neighbors']=[remap[j] for j in z['neighbors'] if j in remap];selected.append(z)
 write_json(out/'bay-population-zones.json',{'version':1,'spacing_m':step,'zones':selected,'root_zone':remap[root],'bbox_wgs84':BBOX,'note':'750 m fixed geographic population centers with verified 6 m water corridors. Narrow passages not represented at this spacing are intentionally disconnected. Existing geographic depths only; no new river construction.'});print('Bay zones',len(selected),'links',sum(len(z['neighbors']) for z in selected)//2,flush=True)
if __name__=='__main__':build()
