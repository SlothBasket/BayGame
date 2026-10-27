"""Incremental fish navigation/habitat asset; reads existing water, depths and structures only."""
import json,math,hashlib
import numpy as np
from pathlib import Path
from shapely.geometry import Point,LineString,shape,box
from shapely import prepare
from rasterio.features import rasterize
from affine import Affine
from scipy.spatial import Delaunay,cKDTree
from tools.gis.bay_imagery import geometry
from tools.gis.build import write_json

def build():
 _,out,land=geometry();zones=json.loads((out/'bay-population-zones.json').read_text())['zones'];xy=np.array([[z['x'],z['y']] for z in zones])
 water=shape(json.loads((out/'bay-estuary-mask.json').read_text())['geometry']).difference(land)
 lo=(np.floor((xy.min(axis=0)-900)/1024)*1024).astype(int);hi=(np.ceil((xy.max(axis=0)+900)/1024)*1024).astype(int);w,h=((hi-lo)//32).tolist()
 mask=rasterize([(water.buffer(-24),1)],out_shape=(h,w),transform=Affine(32,0,int(lo[0]),0,32,int(lo[1])),fill=0,dtype='uint8')
 depths=np.full((h,w),np.nan,dtype=np.float32)
 for gy in range(lo[1]//1024,hi[1]//1024):
  for gx in range(lo[0]//1024,hi[0]//1024):
   p=out/'chunks'/f'0_{gx}_{gy}.f32'
   if not p.exists():continue
   v=np.fromfile(p,dtype='<f4').reshape(67,67)
   for layer in ['survey','recon']:
    q=p.with_suffix('.'+layer+'.f32')
    if q.exists():
     a=np.fromfile(q,dtype='<f4').reshape(67,67);v=np.where(np.isfinite(a),a,v) if layer=='survey' else np.where(np.isfinite(v),v,a)
   ix=(gx*1024-lo[0])//32;iy=(gy*1024-lo[1])//32;depths[iy:iy+32,ix:ix+32]=-v[2:66:2,2:66:2]
 mask &= (np.isfinite(depths)&(depths>.2)).astype('uint8')
 # Erode at mapped barriers; unknown/narrow water remains excluded rather than crossed.
 network=json.loads((out/'water-network.json').read_text());barriers=[shape(n['geometry']).buffer(20) for n in network['nodes'] if n.get('barrier')]
 if barriers:mask &= 1-rasterize([(g,1) for g in barriers],out_shape=(h,w),transform=Affine(32,0,int(lo[0]),0,32,int(lo[1])),fill=0,dtype='uint8')
 def cell(p):return int((p[0]-lo[0])//32),int((p[1]-lo[1])//32)
 def valid(p):
  x,y=cell(p);return 0<=x<w and 0<=y<h and mask[y,x]!=0
 def segment(a,b):
  # Supercover raster walk, also checks both cells at a diagonal corner.
  x,y=cell(a);ex,ey=cell(b);dx=b[0]-a[0];dy=b[1]-a[1];sx=1 if dx>0 else -1;sy=1 if dy>0 else -1
  tx=((lo[0]+(x+(1 if sx>0 else 0))*32)-a[0])/dx if dx else math.inf
  ty=((lo[1]+(y+(1 if sy>0 else 0))*32)-a[1])/dy if dy else math.inf
  dtx=32/abs(dx) if dx else math.inf;dty=32/abs(dy) if dy else math.inf
  for _ in range(abs(ex-x)+abs(ey-y)+4):
   if not (0<=x<w and 0<=y<h and mask[y,x]):return False
   if x==ex and y==ey:return True
   if abs(tx-ty)<1e-9:
    if not (0<=x+sx<w and 0<=y+sy<h and mask[y,x+sx] and mask[y+sy,x]):return False
    x+=sx;y+=sy;tx+=dtx;ty+=dty
   elif tx<ty:x+=sx;tx+=dtx
   else:y+=sy;ty+=dty
  return False
 # Deterministic irregular samples avoid placing destinations on population-grid centers.
 points=[];rng=np.random.default_rng(90427)
 for y in np.arange(lo[1]+80,hi[1],160):
  for x in np.arange(lo[0]+80,hi[0],160):
   p=(float(x+rng.uniform(-55,55)),float(y+rng.uniform(-55,55)))
   if valid(p):points.append(p)
 points=np.array(points);tri=Delaunay(points);edges=set()
 for t in tri.simplices:
  for a,b in [(t[0],t[1]),(t[1],t[2]),(t[2],t[0])]:edges.add(tuple(sorted((int(a),int(b)))))
 links=[[] for _ in points]
 for a,b in sorted(edges):
  if np.linalg.norm(points[a]-points[b])<440 and segment(points[a],points[b]):links[a].append(b);links[b].append(a)
 # Only connected components associated with existing bay zones; retain IDs in the original graph.
 zone_tree=cKDTree(xy);_,zone_ids=zone_tree.query(points);structures=json.loads((out/'structures.json').read_text()).get('features',[])
 mouth_geoms=[shape(n['geometry']) for n in network['nodes'] if not n.get('barrier')]
 boundary=water.boundary;nodes=[];by_zone=[[] for _ in zones]
 for i,p in enumerate(points):
  if not links[i]:continue
  x,y=cell(p);d=float(depths[y,x]);shore=boundary.distance(Point(*p));neighbors=links[i]
  relief=max(abs(d-float(depths[cell(points[n])[1],cell(points[n])[0]])) for n in neighbors)
  tags=[];evidence=[]
  if shore<180:tags+=['shoreline_edge','mangrove_edge_candidate'];evidence+=['mapped water/land boundary; vegetation inferred']
  if shore<140 and len(neighbors)<4:tags+=['shoreline_point_candidate','sheltered_rest']
  if d<2.5 and relief<.65:tags+=['grass_flat_candidate']
  if d<5 and sum(d>float(depths[cell(points[n])[1],cell(points[n])[0]])+.6 for n in neighbors)>=3:tags+=['pothole_candidate']
  if relief>1:tags+=['channel_dropoff'];evidence+=['existing bathymetric gradient']
  if shore<130 and .4<d<2:tags+=['oyster_bar_candidate']
  if shore<220 and any(g.distance(Point(*p))<100 for g in mouth_geoms):tags+=['creek_mouth_candidate'];evidence+=['existing mapped flowline proximity']
  matched=[f for f in structures if math.hypot(f.get('position',[1e9,1e9])[0]-p[0],f.get('position',[1e9,1e9])[1]-p[1])<100]
  if matched:tags+=['mapped_structure'];evidence += [f.get('id','structure') for f in matched]
  if not tags:tags=['open_water']
  zone=int(zone_ids[i]);by_zone[zone].append(i)
  nodes.append({'id':i,'x':round(p[0],3),'y':round(p[1],3),'zone':zone,'depth_m':round(d,3),'shore_m':round(shore,1),'tags':tags,'evidence':evidence,'neighbors':neighbors})
 # Remove dangling IDs and record connected components so runtime never teleports across water barriers.
 lookup={n['id']:n for n in nodes};component=0
 for n in nodes:
  if 'component' in n:continue
  pending=[n['id']];n['component']=component
  while pending:
   a=lookup[pending.pop()]
   for b in a['neighbors']:
    if b in lookup and 'component' not in lookup[b]:lookup[b]['component']=component;pending.append(b)
  component+=1
 mask.tofile(out/'fish-water-mask.bin')
 data={'version':1,'origin':lo.tolist(),'cell_m':32,'width':w,'height':h,'nodes':nodes,'zone_nodes':by_zone,'mask':'fish-water-mask.bin','note':'Conservative continuous-water navigation from existing land/water and depth assets. Mapped shoreline/structures and bathymetric relief are evidence; vegetation/substrate/creek-mouth classifications are inferred candidates. No river or world rebuild.'}
 data['fingerprint']=hashlib.sha256(json.dumps(nodes,separators=(',',':')).encode()).hexdigest()
 write_json(out/'fish-navigation.json',data);print(len(nodes),'irregular habitat/navigation points;',component,'water components;',mask.nbytes,'mask bytes',flush=True)
if __name__=='__main__':build()
