"""Fish habitat segments retain source flowline geometry; no over-land shortcuts."""
import json,math
from collections import defaultdict
import numpy as np
from shapely.geometry import shape,LineString,Point
from tools.gis.build import ROOT,write_json

def build():
 out=ROOT/'godot/assets/generated';network=json.loads((out/'water-network.json').read_text());water=shape(network['water']);cache={}
 def depth(x,y):
  key=f'0_{math.floor(x/1024)}_{math.floor(y/1024)}'
  if key not in cache:
   p=out/'chunks'/f'{key}.f32'
   if not p.exists():return None
   v=np.fromfile(p,dtype='<f4').reshape(67,67)
   for layer in ['survey','recon']:
    q=p.with_suffix('.'+layer+'.f32')
    if q.exists():
     extra=np.fromfile(q,dtype='<f4').reshape(67,67);v=np.where(np.isfinite(extra),extra,v) if layer=='survey' else np.where(np.isfinite(v),v,extra)
   cache[key]=v
  fx=(x%1024)/16+1;fy=(y%1024)/16+1;ix=int(fx);iy=int(fy);v=cache[key][iy:iy+2,ix:ix+2]
  if not np.isfinite(v).all():return None
  z=v[0,0]*(1-fx+ix)*(1-fy+iy)+v[0,1]*(fx-ix)*(1-fy+iy)+v[1,0]*(1-fx+ix)*(fy-iy)+v[1,1]*(fx-ix)*(fy-iy)
  return float(max(0,-z))
 routes=[];endpoints=defaultdict(list)
 for node in network['nodes']:
  if node['barrier']:continue
  g=shape(node['geometry']);lines=[g] if g.geom_type=='LineString' else list(getattr(g,'geoms',[]))
  for line in lines:
   coords=list(line.coords)
   for a,b in zip(coords,coords[1:]):
    seg=LineString([a,b]);length=seg.length
    if length<2 or not water.covers(seg):continue
    ds=[depth(*seg.interpolate(t,normalized=True).coords[0]) for t in [0,.25,.5,.75,1]]
    if any(d is None or d<.15 for d in ds):continue
    i=len(routes);routes.append({'a':list(a),'b':list(b),'length_m':length,'depth_m':sum(ds)/len(ds),'source_region':node['id'],'edges':[[],[]]})
    for end,p in enumerate([a,b]):endpoints[(round(p[0],2),round(p[1],2))].append([i,end])
 for links in endpoints.values():
  for i,end in links:routes[i]['edges'][end]=[p for p in links if p[0]!=i]
 write_json(out/'fish-habitat.json',{'routes':routes,'note':'Conservative initial habitat: mapped connected NHD segments with positive sampled game depths; mapped barrier flowlines excluded. Species, migration and passage biology incomplete.'});print('Fish habitat',len(routes),'segments',sum(len(e) for r in routes for e in r['edges']),'directed links')
if __name__=='__main__':build()
