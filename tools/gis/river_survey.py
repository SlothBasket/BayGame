"""CC0 USF 2022 survey importer; original NOAA elevations remain stored separately."""
import json,zipfile,io,hashlib
import numpy as np
from scipy.spatial import cKDTree
from pyproj import Transformer
from tools.gis.build import ROOT,write_json

def build():
 out=ROOT/'godot/assets/generated';m=json.loads((out/'manifest.json').read_text());src=ROOT/'data/sources/phase3/usf-survey.zip'
 if not src.exists():
  import requests
  src.parent.mkdir(parents=True,exist_ok=True);response=requests.get('https://data.griidc.org/api/datasets/zip/5061',timeout=120);response.raise_for_status();src.write_bytes(response.content)
 raw=zipfile.ZipFile(src).read('Hillsborough_River_Bathymetry.txt');rows=[r for r in raw.decode().splitlines() if r.strip()]
 assert 'NAVD88 (m)' in rows[1]
 data=np.loadtxt(io.StringIO('\n'.join(rows[3:])),dtype=np.float64);assert len(data)==519436
 e,n=Transformer.from_crs(26959,32617,always_xy=True).transform(data[:,0],data[:,1]);xy=np.column_stack([e-m['origin_projected'][0],m['origin_projected'][1]-n]);tree=cKDTree(xy);bounds=[xy[:,0].min(),xy[:,1].min(),xy[:,0].max(),xy[:,1].max()]
 counts={};changed=[]
 for key,node in m['nodes'].items():
  x,y,size=node['x'],node['y'],node['size']
  if x+size<bounds[0]-32 or x>bounds[2]+32 or y+size<bounds[1]-32 or y>bounds[3]+32:continue
  p=out/'chunks'/f'{key}.json';tile=json.loads(p.read_text());cells=tile['n'];xx=x+(np.arange(cells+3)-1)*size/cells;yy=y+(np.arange(cells+3)-1)*size/cells;gx,gy=np.meshgrid(xx,yy)
  d,i=tree.query(np.column_stack([gx.ravel(),gy.ravel()]),k=4,workers=2);w=1/np.maximum(d,.05)**2;v=(data[i,2]*w).sum(axis=1)/w.sum(axis=1);v[d[:,0]>16]=np.nan
  if not np.isfinite(v).any():continue
  v.astype('<f4').tofile(p.with_suffix('.survey.f32'));changed.append(key)
  if node['level']==0:counts[key]=int(np.isfinite(v).sum())
 meta={'id':'USF-Hillsborough-2022','citation':'Wang, Ping, Kendal Jackson, Elizabeth Royer (2024). DOI 10.7266/j1gj835p','url':'https://data.griidc.org/data/B1.x126.000:0001','download':'https://data.griidc.org/api/datasets/zip/5061','license':'CC0','license_url':'https://www.griidc.org/terms-and-conditions/','survey_dates':['2022-09-09','2022-10-14'],'units':'meters positive up','vertical_datum':'NAVD88','horizontal_crs':'EPSG:26959','horizontal_caveat':'File states State Plane Florida West meters, without NAD83 realization; NAD83 assumed, no claim of survey-grade horizontal accuracy.','sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'point_count':len(data),'bounds_world':bounds,'interpolation':'inverse-distance nearest four within 16 m; newer measured USF survey takes precedence over older composite NOAA DEM where supplied','tiles':changed,'leaf_sample_counts':counts}
 write_json(out/'river-surveys.json',meta);print('USF imported',len(changed),'tiles',sum(counts.values()),'leaf samples',bounds)
if __name__=='__main__':build()
