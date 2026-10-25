"""Restartable acquisition of georeferenced public NAIP and USGS hydrography."""
import json,time,hashlib,argparse,math
import requests,rasterio
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from rasterio.warp import transform_bounds
from tools.gis.build import ROOT,write_json
NAIP='https://imagery.geoplatform.gov/iipp/rest/services/NAIP/NAIP2023_CONUS/ImageServer'
NHD='https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer'
PILOT=[-82.42,27.84,-82.37,27.88]
HYDRO=[-82.43,27.80,-82.23,27.94]
def session():
 s=requests.Session();s.mount('https://',HTTPAdapter(max_retries=Retry(total=2,backoff_factor=1,status_forcelist=[429,500,502,503,504])));return s
def query(s,url,params):
 r=s.get(url,params=params,timeout=35);r.raise_for_status();d=r.json()
 if 'error' in d: raise RuntimeError(d['error'])
 return d
def acquire_imagery():
 s=session();out=ROOT/'data/sources/naip';out.mkdir(parents=True,exist_ok=True)
 write_json(out/'service.json',query(s,NAIP,{'f':'pjson'}))
 catalog=query(s,NAIP+'/query',{'f':'pjson','geometry':json.dumps(dict(zip(['xmin','ymin','xmax','ymax'],PILOT)) | {'spatialReference':{'wkid':4326}}),'spatialRel':'esriSpatialRelIntersects','geometryType':'esriGeometryEnvelope','inSR':4326,'outFields':'*','returnGeometry':'false','where':'1=1'})
 write_json(out/'catalog.json',catalog)
 bb=transform_bounds('EPSG:4326','EPSG:32617',*PILOT);tiles=[]
 for y in range(math.floor(bb[1]/1024),math.ceil(bb[3]/1024)):
  for x in range(math.floor(bb[0]/1024),math.ceil(bb[2]/1024)):
   path=out/f'{x}_{y}.tif';bounds=[x*1024,y*1024,(x+1)*1024,(y+1)*1024]
   if not path.exists():
    d=query(s,NAIP+'/exportImage',{'f':'pjson','bbox':','.join(map(str,bounds)),'bboxSR':32617,'imageSR':32617,'size':'2048,2048','format':'tiff','bandIds':'0,1,2','interpolation':'RSP_BilinearInterpolation','adjustAspectRatio':'false'})
    r=s.get(d['href'],timeout=120);r.raise_for_status();tmp=path.with_suffix('.partial');tmp.write_bytes(r.content)
    with rasterio.open(tmp) as src:
     assert src.crs.to_epsg()==32617 and src.width==2048
     assert max(abs(a-b) for a,b in zip(src.bounds,bounds))<.01
    tmp.replace(path);write_json(path.with_suffix('.receipt.json'),d)
   with rasterio.open(path) as src: assert src.crs.to_epsg()==32617
   tiles.append({'file':path.name,'bounds':bounds,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()});print('NAIP',path.name,flush=True)
 write_json(out/'index.json',{'bbox_wgs84':PILOT,'source':NAIP,'capture_year':2023,'source_native_resolution_m':'0.3–0.6 (service); catalog lowps per source','output_resolution_m':.5,'crs':'EPSG:32617','license':'US public domain','license_url':'https://catalog.data.gov/dataset/national-agriculture-imagery-program-naip-imagery','tiles':tiles,'catalog':catalog})
def acquire_hydro():
 s=session();out=ROOT/'data/sources/hydro';out.mkdir(parents=True,exist_ok=True)
 for layer,name in [(8,'areas'),(9,'waterbodies'),(3,'flowlines'),(7,'lines'),(2,'points')]:
  url=NHD+'/'+str(layer)
  if not (out/(name+'.service.json')).exists(): write_json(out/(name+'.service.json'),query(s,url,{'f':'pjson'}))
  ids=query(s,url+'/query',{'f':'pjson','where':'1=1','geometry':','.join(map(str,HYDRO)),'geometryType':'esriGeometryEnvelope','inSR':4326,'returnIdsOnly':'true'}).get('objectIds') or [];features=[]
  for i in range(0,len(ids),50):
   batch=sorted(ids)[i:i+50];cache=out/(name+'-'+hashlib.sha256(str(batch).encode()).hexdigest()[:12]+'.json')
   if cache.exists(): d=json.loads(cache.read_text())
   else:
    d=query(s,url+'/query',{'f':'geojson','where':'OBJECTID IN ('+','.join(map(str,batch))+')','outFields':'*','outSR':4326,'returnGeometry':'true'});write_json(cache,d)
   features.extend(d['features'])
  write_json(out/(name+'.geojson'),{'type':'FeatureCollection','features':features});print('NHD',name,len(features),flush=True)
 write_json(out/'index.json',{'bbox_wgs84':HYDRO,'source':NHD,'license':'USGS public domain','license_url':'https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits','retrieved_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())})
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('kind',choices=['imagery','hydro']);a=p.parse_args();(acquire_imagery if a.kind=='imagery' else acquire_hydro)()
