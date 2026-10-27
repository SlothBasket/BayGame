"""Habitat polygons from existing navigation evidence; no geographic acquisition/rebuild."""
import json,hashlib
import numpy as np
from shapely.geometry import Point,LineString,shape,mapping
from shapely.ops import unary_union
from rasterio.features import shapes
from affine import Affine
from tools.gis.build import ROOT,write_json

def build():
 out=ROOT/'godot/assets/generated';data=json.loads((out/'fish-navigation.json').read_text());nodes={n['id']:n for n in data['nodes']}
 mask=np.fromfile(out/data['mask'],dtype='uint8').reshape(data['height'],data['width'])
 water=unary_union([shape(g) for g,v in shapes(mask,mask=mask.astype(bool),transform=Affine(32,0,data['origin'][0],0,32,data['origin'][1])) if v])
 specs={'shoreline_edge':(55,['shelter','travel','hunting']),'mangrove_edge_candidate':(50,['shelter','resting','hunting']),'shoreline_point_candidate':(70,['hunting','travel']),'grass_flat_candidate':(100,['feeding','shelter','hunting']),'pothole_candidate':(65,['resting','hunting']),'channel_dropoff':(45,['travel','hunting']),'creek_mouth_candidate':(90,['feeding','hunting','travel']),'oyster_bar_candidate':(55,['feeding','shelter']),'mapped_structure':(40,['feeding','shelter','hunting']),'sheltered_rest':(85,['resting','shelter'])}
 areas=[];feature_areas={str(i):[] for i in nodes};zone_areas=[[] for _ in data['zone_nodes']]
 for z,ids in enumerate(data['zone_nodes']):
  for tag,(radius,roles) in specs.items():
   members=[nodes[i] for i in ids if tag in nodes[i]['tags']]
   if not members:continue
   member_ids={n['id'] for n in members};pieces=[Point(n['x'],n['y']).buffer(radius,quad_segs=5) for n in members]
   if tag in ['shoreline_edge','mangrove_edge_candidate','channel_dropoff']:
    for n in members:
     for j in n['neighbors']:
      if j in member_ids and j>n['id']:pieces.append(LineString([(n['x'],n['y']),(nodes[j]['x'],nodes[j]['y'])]).buffer(radius*.65,quad_segs=4))
   g=unary_union(pieces).intersection(water).simplify(1,preserve_topology=True).intersection(water)
   polygons=[g] if g.geom_type=='Polygon' else [p for p in getattr(g,'geoms',[]) if p.geom_type=='Polygon']
   if not polygons:continue
   rings=[{'outer':[[round(x,2),round(y,2)] for x,y in p.exterior.coords],'holes':[[[round(x,2),round(y,2)] for x,y in r.coords] for r in p.interiors]} for p in polygons]
   index=len(areas);key=f'habitat:{z}:{tag}';capacity=min(250,max(8,g.area*.003)) if tag in ['oyster_bar_candidate','mapped_structure'] else 0
   areas.append({'id':key,'zone':z,'kind':tag,'roles':roles,'polygons':rings,'bounds':list(g.bounds),'area_m2':round(g.area,1),'nodes':sorted(member_ids),'evidence':sorted({e for n in members for e in n['evidence']}),'inferred':tag!='mapped_structure' and tag!='shoreline_edge' and tag!='channel_dropoff','boundary_note':'Water-clipped opportunity envelope; extent inferred from existing mapped evidence, not a surveyed substrate polygon.','bottom_capacity':capacity})
   zone_areas[z].append(index)
   for i in member_ids:feature_areas[str(i)].append(index)
 # Every open-water preference still has an area, independent of the old population cell boundary.
 for z,ids in enumerate(data['zone_nodes']):
  if zone_areas[z]:continue
  members=[nodes[i] for i in ids];g=unary_union([Point(n['x'],n['y']).buffer(90,quad_segs=4) for n in members]).intersection(water)
  parts=[g] if g.geom_type=='Polygon' else [a for a in getattr(g,'geoms',[]) if a.geom_type=='Polygon']
  index=len(areas);areas.append({'id':f'habitat:{z}:open_water','zone':z,'kind':'open_water','roles':['travel','hunting','resting'],'polygons':[{'outer':list(p.exterior.coords),'holes':[list(r.coords) for r in p.interiors]} for p in parts],'bounds':list(g.bounds),'area_m2':g.area,'nodes':ids,'evidence':['existing water/depth mask'],'inferred':True,'bottom_capacity':0})
  zone_areas[z].append(index)
  for i in ids:feature_areas[str(i)].append(index)
 write_json(out/'habitat-areas.json',{'version':1,'navigation_fingerprint':data['fingerprint'],'areas':areas,'feature_areas':feature_areas,'zone_areas':zone_areas})
 print(len(areas),'overlapping habitat areas;',sum(a['bottom_capacity']>0 for a in areas),'bottom-forage habitats',flush=True)
if __name__=='__main__':build()
