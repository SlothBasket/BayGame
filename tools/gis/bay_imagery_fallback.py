"""Fill NAIP open-water NoData using CC BY 4.0 EOX Sentinel-2 2016 imagery.
Only missing source tiles are downloaded. WMS images are reprojected to the
same UTM grid; they supply visual imagery, never numerical depths.
"""
import json,io
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import requests,numpy as np,rasterio
from PIL import Image
from rasterio.warp import transform_bounds,reproject,Resampling
from rasterio.transform import from_bounds
from tools.gis.build import ROOT,write_json
URL='https://tiles.maps.eox.at/wms'
def acquire():
 src=ROOT/'data/sources/bay-naip';records=json.loads((src/'plan.json').read_text())['tiles'];needed=[]
 for r in records:
  with rasterio.open(src/(r['id']+'.tif')) as ds:rgb=ds.read([1,2,3])
  if np.any(rgb.max(axis=0)==0):needed.append(r)
 def one(r):
  path=src/(r['id']+'.sentinel.tif')
  if path.exists():return
  bb=transform_bounds(32617,3857,*r['bounds'],densify_pts=21);pixels=512
  response=requests.get(URL,params={'SERVICE':'WMS','REQUEST':'GetMap','VERSION':'1.1.1','LAYERS':'s2cloudless_3857','STYLES':'','FORMAT':'image/jpeg','SRS':'EPSG:3857','BBOX':','.join(map(str,bb)),'WIDTH':pixels,'HEIGHT':pixels},timeout=60);response.raise_for_status();image=np.asarray(Image.open(io.BytesIO(response.content)).convert('RGB')).transpose(2,0,1);target=np.zeros((3,r['pixels'],r['pixels']),np.uint8);transform=from_bounds(*r['bounds'],r['pixels'],r['pixels'])
  for band in range(3):reproject(image[band],target[band],src_transform=from_bounds(*bb,pixels,pixels),src_crs=3857,dst_transform=transform,dst_crs=32617,resampling=Resampling.bilinear)
  assert target.max()>0
  with rasterio.open(path,'w',driver='GTiff',width=r['pixels'],height=r['pixels'],count=3,dtype='uint8',crs=32617,transform=transform,compress='deflate') as ds:ds.write(target)
  print('Filled imagery source',r['id'],flush=True)
 with ThreadPoolExecutor(3) as pool:list(pool.map(one,needed))
 write_json(src/'sentinel-source.json',{'source':URL,'layer':'s2cloudless_3857','year':2016,'license':'CC BY 4.0','license_url':'https://creativecommons.org/licenses/by/4.0/','attribution':'Sentinel-2 cloudless - https://s2maps.eu by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2016 & 2017)','note':'2016 vintage retained to permit commercial reuse with attribution. Older satellite fallback only for missing NAIP pixels, resampled from ~10 m source.','tiles':[r['id'] for r in needed]})
if __name__=='__main__':acquire()
