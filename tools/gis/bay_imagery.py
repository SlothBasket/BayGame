"""Offline bay NAIP pack: 8 m open water, 4 m shoreline; reuse Alafia pack."""
import json,math,io,hashlib,time
from concurrent.futures import ThreadPoolExecutor
import numpy as np,rasterio
from rasterio.features import rasterize
from PIL import Image
from scipy.ndimage import distance_transform_edt
from shapely.geometry import box,Polygon,mapping,shape
from shapely.ops import unary_union
from tools.gis.pilot_build import context
from tools.gis.pilot_acquire import session,query,NAIP
from tools.gis.build import ROOT,write_json,polygons
from rasterio.warp import transform_bounds
BBOX=[-82.80,27.48,-82.36,28.08]
def geometry():
 cfg,geo,out,m,boundary,land=context();water=shape(json.loads((out/'water-network.json').read_text())['water']);land=land.difference(water).union(unary_union([Polygon(r) for p in polygons(water) for r in p.interiors]));return geo,out,land

def plan():
 geo,out,land=geometry();bb=transform_bounds(4326,32617,*BBOX);records=[]
 for gy in range(math.floor(bb[1]/4096),math.ceil(bb[3]/4096)):
  for gx in range(math.floor(bb[0]/4096),math.ceil(bb[2]/4096)):
   x=gx*4096-geo.origin[0];y=geo.origin[1]-(gy+1)*4096;tile=box(x,y,x+4096,y+4096);fraction=land.intersection(tile).area/tile.area
   if fraction>.995:continue
   pixels=1024 if fraction>.005 else 512
   records.append({'id':f'bay_{gx}_{gy}','x':x,'y':y,'size':4096,'pixels':pixels,'resolution_m':4096/pixels,'bounds':[gx*4096,gy*4096,(gx+1)*4096,(gy+1)*4096]})
 src=ROOT/'data/sources/bay-naip';src.mkdir(parents=True,exist_ok=True);write_json(src/'plan.json',{'bbox_wgs84':BBOX,'tiles':records,'source':NAIP,'capture_year':2023,'license':'US public domain','license_url':'https://catalog.data.gov/dataset/national-agriculture-imagery-program-naip-imagery'});print('Bay imagery plan',len(records),'tiles; pixels',sum(r['pixels']**2 for r in records),flush=True);return records

def acquire():
 records=plan();src=ROOT/'data/sources/bay-naip'
 def one(r):
  path=src/(r['id']+'.tif')
  if path.exists():return
  s=session();d=query(s,NAIP+'/exportImage',{'f':'pjson','bbox':','.join(map(str,r['bounds'])),'bboxSR':32617,'imageSR':32617,'size':f"{r['pixels']},{r['pixels']}",'format':'tiff','bandIds':'0,1,2','interpolation':'RSP_BilinearInterpolation','adjustAspectRatio':'false'})
  response=s.get(d['href'],timeout=100);response.raise_for_status();tmp=path.with_suffix('.partial');tmp.write_bytes(response.content)
  with rasterio.open(tmp) as ds:assert ds.width==r['pixels'] and ds.crs.to_epsg()==32617 and max(abs(a-b) for a,b in zip(ds.bounds,r['bounds']))<.01
  tmp.replace(path);write_json(path.with_suffix('.receipt.json'),d);print('Downloaded',r['id'],r['resolution_m'],'m',flush=True)
 with ThreadPoolExecutor(3) as pool:list(pool.map(one,records))

def pack():
 geo,out,land=geometry();src=ROOT/'data/sources/bay-naip';meta=json.loads((src/'plan.json').read_text());destination=out/'imagery';index={};total=0
 xmin=min(r['x'] for r in meta['tiles']);ymin=min(r['y'] for r in meta['tiles']);xmax=max(r['x']+4096 for r in meta['tiles']);ymax=max(r['y']+4096 for r in meta['tiles'])
 with (destination/'bay.pack').open('wb') as pack:
  for r in meta['tiles']:
   path=src/(r['id']+'.tif');total+=path.stat().st_size
   with rasterio.open(path) as ds:rgb=ds.read([1,2,3]).transpose(1,2,0)
   size=r['pixels'];res=r['resolution_m'];x,y=r['x'],r['y'];water=box(x,y,x+4096,y+4096).difference(land)
   mask=rasterize([(mapping(water),255)],out_shape=(size,size),transform=rasterio.Affine(res,0,x,0,res,y),fill=0,dtype='uint8') if not water.is_empty else np.zeros((size,size),np.uint8)
   xx=x+(np.arange(size)+.5)*res;yy=y+(np.arange(size)+.5)*res;fade=np.clip(np.minimum(np.minimum(xx-xmin,xmax-xx)[None,:],np.minimum(yy-ymin,ymax-yy)[:,None])/512,0,1);fade=fade*fade*(3-2*fade);mask=(mask*fade).astype('uint8')
   valid=rgb.max(axis=2)>0
   if not valid.all():
    source_fade=np.clip(distance_transform_edt(valid)*res/256,0,1);source_fade=source_fade*source_fade*(3-2*source_fade)
    fallback=src/(r['id']+'.sentinel.tif')
    if fallback.exists():
     with rasterio.open(fallback) as ds:background=ds.read([1,2,3]).transpose(1,2,0)
     rgb=(rgb*source_fade[:,:,None]+background*(1-source_fade[:,:,None])).astype('uint8')
    else:mask=(mask*source_fade).astype('uint8')
   im=Image.fromarray(rgb).convert('RGBA');im.putalpha(Image.fromarray(mask))
   for lod in range(4):
    image=im if lod==0 else im.resize((size>>lod,size>>lod),Image.Resampling.LANCZOS);buf=io.BytesIO();image.save(buf,format='WEBP',quality=82,method=4);raw=buf.getvalue();key=r['id']+'_'+str(lod)
    index[key]={'x':x,'y':y,'size':4096,'lod':lod,'pixels':size>>lod,'base_mpp':res,'offset':pack.tell(),'length':len(raw),'pack':'bay.pack','family':r['id'],'priority':0};pack.write(raw)
   print('Packed',r['id'],flush=True)
 pilot=json.loads((destination/'index.json').read_text())
 # Preserve the original Alafia pack/index once, allowing repeatable merged builds.
 backup=destination/'alafia-index.json'
 if not backup.exists():write_json(backup,pilot)
 pilot=json.loads(backup.read_text())
 for key,r in pilot['nodes'].items():
  r.update(pack='alafia.pack',base_mpp=.5,family=key.rsplit('_',1)[0],priority=1);index[key]=r
 size=(destination/'bay.pack').stat().st_size
 write_json(destination/'index.json',{'nodes':index,'bay':dict(meta,pack_bytes=size,raw_download_bytes=total),'fallback_source':json.loads((src/'sentinel-source.json').read_text()) if (src/'sentinel-source.json').exists() else None,'pilot_source':pilot.get('source'),'mask':'Water only; NAIP NoData blended over attributed EOX Sentinel-2 with a 256 m fade, outer footprint 512 m fade; no internal tile-edge feather'})
 write_json(ROOT/'docs/bay-imagery.json',{'bbox_wgs84':BBOX,'tiles':len(meta['tiles']),'shore_tiles_4m':sum(r['resolution_m']==4 for r in meta['tiles']),'open_tiles_8m':sum(r['resolution_m']==8 for r in meta['tiles']),'bay_pack_bytes':size,'alafia_pack_bytes':(destination/'alafia.pack').stat().st_size,'raw_download_bytes':total,'fallback_cache_bytes':sum(p.stat().st_size for p in src.glob('*.sentinel.tif')),'fallback_source':json.loads((src/'sentinel-source.json').read_text()) if (src/'sentinel-source.json').exists() else None,'source':NAIP,'note':'Aligned tiles cover the entire requested bounding area wherever source geometry identifies water. Existing Alafia high-detail overlay retained.'})
if __name__=='__main__':
 import sys
 {'plan':plan,'acquire':acquire,'pack':pack}[sys.argv[1]]()
