"""Incremental Alafia vector patch and masked imagery pack; leaves bathymetry untouched."""
import json,hashlib,io,math
from pathlib import Path
import numpy as np,rasterio
from rasterio.features import rasterize
from PIL import Image,ImageFilter
from shapely.geometry import shape,box,Polygon,mapping
from shapely.ops import transform,unary_union
from shapely import make_valid
from tools.gis.build import ROOT,write_json,load_vector,polygons,rings,mesh
from tools.gis.coordinates import Coordinates
from tools.gis.pilot_acquire import HYDRO

def context():
 config=json.loads((ROOT/'config/region.json').read_text());geo=Coordinates(config)
 out=ROOT/'godot/assets/generated';manifest=json.loads((out/'manifest.json').read_text());boundary=box(*manifest['bounds'])
 land=load_vector(ROOT/'data/sources/land.geojson',geo,boundary)
 for name in ['rivers','lakes']: land=land.difference(load_vector(ROOT/f'data/sources/{name}.geojson',geo,boundary))
 return config,geo,out,manifest,boundary,make_valid(land)
def hydro_geometry(geo):
 src=ROOT/'data/sources/hydro';aoi=transform(geo.to_world,box(*HYDRO));features=[];waters=[]
 for name in ['areas','waterbodies']:
  for f in json.loads((src/(name+'.geojson')).read_text())['features']:
   # Exclude inundation areas (403), wetlands (466), and miscellaneous special-use areas.
   if int(f['properties'].get('ftype',0)) not in [312,390,436,445,460]: continue
   g=make_valid(transform(geo.to_world,shape(f['geometry']))).intersection(aoi)
   if g.is_empty: continue
   waters.append(g);features.append((f,g))
 return make_valid(unary_union(waters)),features,aoi

def patch_hydro():
 config,geo,out,m,boundary,old=context();water,features,aoi=hydro_geometry(geo)
 islands=unary_union([Polygon(r) for p in polygons(water) for r in p.interiors])
 land=make_valid(old.difference(water).union(islands))
 parts=list(polygons(water));sea=unary_union([g for f,g in features if int(f['properties']['ftype']) in [312,445]])
 connected=unary_union([p for p in parts if p.intersection(sea).area>1])
 components=[{'id':'alafia-component-'+hashlib.sha256(p.wkb).hexdigest()[:12],'bounds':list(p.bounds),'water_exists':True,'hydrologic_connection':'polygon connected to mapped estuary' if p.intersects(sea) else 'unverified','boat_navigability':'footprint and barrier checks required; depth may be unknown','fish_passage':'unknown','bathymetry':'queried independently from NOAA'} for p in parts]
 lines=[];barriers=[]
 for name in ['flowlines','lines','points']:
  for f in json.loads((ROOT/'data/sources/hydro'/(name+'.geojson')).read_text())['features']:
   g=make_valid(transform(geo.to_world,shape(f['geometry']))).intersection(aoi)
   if g.is_empty: continue
   props=f['properties'];record={'id':str(props.get('permanent_identifier',props.get('OBJECTID'))),'properties':props,'geometry':mapping(g)}
   if name=='flowlines':
    record.update(width_status='polygon supported' if water.covers(g) else 'requires width information; no invented buffer',fish_passage='unknown');lines.append(record)
   if int(props.get('ftype',0)) in [343,369]: barriers.append(record)
 changed=[]
 for level in range(config['max_lod']+1):
  simplified=make_valid(land.simplify(config['simplify_m'][level],preserve_topology=True))
  for key,node in m['nodes'].items():
   if node['level']!=level: continue
   x,y,size=node['x'],node['y'],node['size'];tile=box(x,y,x+size,y+size)
   if not tile.intersects(aoi): continue
   path=out/'chunks'/f'{key}.json';obj=json.loads(path.read_text());geom=simplified.intersection(tile)
   obj['vertices'],obj['indices']=mesh(geom,x,y)
   def lines_of(g):
    if g.geom_type in ['LineString','LinearRing']: return [[[round(a-x,4),round(b-y,4)] for a,b in g.coords]]
    return [v for z in getattr(g,'geoms',[]) for v in lines_of(z)]
   obj['shore']=lines_of(simplified.boundary.intersection(tile))
   if level==0:
    obj['land']=[rings(p,x,y) for p in polygons(land.intersection(tile))]
    obj['mapped_water']=[rings(p,x,y) for p in polygons(connected.intersection(tile))]
    obj['barriers']=[v for b in barriers if shape(b['geometry']).geom_type in ['LineString','MultiLineString'] for v in lines_of(shape(b['geometry']).intersection(tile))]
   payload=json.dumps(obj,separators=(',',':'),sort_keys=True).encode();raw=path.with_suffix('.f32').read_bytes()
   if payload!=path.read_bytes():
    path.write_bytes(payload);changed.append(key)
   digest=hashlib.sha256(payload+raw+b'3').hexdigest();path.with_suffix('.sha256').write_text(digest)
   # Prevent an original base build from incorrectly skipping the patched vector tile.
   path.with_suffix('.input.sha256').write_text('hydro-patch-'+digest)
   node.update(bytes=len(payload)+len(raw),sha256=digest)
 provenance=json.loads((ROOT/'data/sources/hydro/index.json').read_text())
 write_json(out/'waterways.json',{'source':provenance,'components':components,'flowlines':lines,'barriers':barriers,'note':'Only mapped polygons become water. Centerlines have no inferred width. Connectivity does not assert navigability or fish passage.'})
 m['hydrography']=dict(provenance,changed_tiles=len(changed),water_polygon_features=len(features),barrier_features=len(barriers));write_json(out/'manifest.json',m)
 write_json(ROOT/'docs/hydro-patch.json',{'changed_tiles':changed,'water_features':len(features),'components':len(components),'flowlines':len(lines),'barriers':len(barriers)})
 print('Patched',len(changed),'tiles; components',len(components),'flowlines',len(lines),'barriers',len(barriers))

def build_imagery():
 config,geo,out,m,boundary,land=context();water,_,_=hydro_geometry(geo)
 land=make_valid(land.difference(water).union(unary_union([Polygon(r) for p in polygons(water) for r in p.interiors])))
 structures=json.loads((ROOT/'config/structures.json').read_text())
 land=land.union(unary_union([Polygon(f['visual_polygon']) for f in structures['features'] if f['visual_polygon']]))
 src=ROOT/'data/sources/naip';meta=json.loads((src/'index.json').read_text());index={};destination=out/'imagery';destination.mkdir(exist_ok=True)
 with (destination/'alafia.pack').open('wb') as pack:
  for record in meta['tiles']:
   with rasterio.open(src/record['file']) as ds:
    rgb=ds.read([1,2,3]).transpose(1,2,0);x=ds.bounds.left-geo.origin[0];y=geo.origin[1]-ds.bounds.top
    clip=land.intersection(box(x,y,x+1024,y+1024))
    # Rasterize in world coordinates (south-positive); half-pixel coastal feather.
    mask=rasterize([(mapping(clip),255)],out_shape=(2048,2048),transform=rasterio.Affine(.5,0,x,0,.5,y),fill=0,dtype='uint8') if not clip.is_empty else np.zeros((2048,2048),np.uint8)
    image=Image.fromarray(rgb,'RGB').convert('RGBA');image.putalpha(Image.fromarray(mask).filter(ImageFilter.GaussianBlur(.5)))
    for lod in range(4):
     im=image if lod==0 else image.resize((2048>>lod,2048>>lod),Image.Resampling.LANCZOS)
     buf=io.BytesIO();im.save(buf,format='WEBP',quality=85,method=4);data=buf.getvalue();key=record['file'].replace('.tif','')+'_'+str(lod)
     index[key]={'x':x,'y':y,'size':1024,'lod':lod,'pixels':2048>>lod,'offset':pack.tell(),'length':len(data)};pack.write(data)
   print('Packed',record['file'],flush=True)
 write_json(destination/'index.json',{'nodes':index,'source':meta,'pack':'alafia.pack','mask':'NOAA ENC land minus USGS NHD mapped water; 0.25 m feather; no inferred structure collision'})
 print('Imagery bytes',(destination/'alafia.pack').stat().st_size)
if __name__=='__main__':
 import sys
 (patch_hydro if sys.argv[1]=='hydro' else build_imagery)()
