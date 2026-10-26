"""Deterministic canonical river raster; source samples are never modified.
Constrained to mapped connected polygons and a bounded neighborhood of known
below-zero survey elevations. No upstream sea-level extrapolation beyond that bound.
"""
import json,math,hashlib
import numpy as np
import rasterio
from rasterio.features import rasterize
from scipy.ndimage import distance_transform_edt
from shapely.geometry import shape,mapping
from tools.gis.build import ROOT,write_json

def build():
 out=ROOT/'godot/assets/generated';m=json.loads((out/'manifest.json').read_text());cfg=json.loads((ROOT/'config/reconstruction.json').read_text(encoding='utf-8-sig'));water=shape(json.loads((out/'water-network.json').read_text())['water']);cell=cfg['cell_m'];bounds=m['bounds'];x0,y0,x1,y1=bounds;w=round((x1-x0)/cell)+1;h=round((y1-y0)/cell)+1
 # Raster pixels are centered on the same geographic nodes used by every tile halo.
 mask=rasterize([(mapping(water),1)],out_shape=(h,w),transform=rasterio.Affine(cell,0,x0-cell/2,0,cell,y0-cell/2),dtype='uint8').astype(bool)
 source=np.full((h,w),np.nan,np.float32)
 for key,node in m['nodes'].items():
  if node['level']!=0:continue
  p=out/'chunks'/f'{key}.f32';v=np.fromfile(p,dtype='<f4').reshape(67,67)[1:66,1:66].copy();s=p.with_suffix('.survey.f32')
  if s.exists():sv=np.fromfile(s,dtype='<f4').reshape(67,67)[1:66,1:66];v=np.where(np.isfinite(sv),sv,v)
  xx=round((node['x']-x0)/cell);yy=round((node['y']-y0)/cell);source[yy:yy+65,xx:xx+65]=v
 anchors=mask & np.isfinite(source) & (source<cfg['maximum_anchor_elevation_m'])
 if not anchors.any():raise RuntimeError('No compatible depth anchors')
 shore=distance_transform_edt(mask)*cell;distance,indices=distance_transform_edt(~anchors,return_indices=True);distance*=cell
 near=source[indices[0],indices[1]];del indices
 depth=np.clip(cfg['minimum_depth_m']+cfg['shore_depth_scale']*np.sqrt(shore),cfg['minimum_depth_m'],cfg['maximum_depth_m'])
 # Preserve near-survey shape with a C1 smoothstep transition to bank-distance form.
 t=np.clip(distance/cfg['survey_blend_m'],0,1);t=t*t*(3-2*t);v=-(np.maximum(0,-near)*(1-t)+depth*t)
 valid=mask & ~np.isfinite(source) & (distance<=cfg['maximum_anchor_distance_m']);v[~valid]=np.nan;v=v.astype('<f4');changed=[];leaf_samples=0
 for key,node in m['nodes'].items():
  n=64;size=node['size'];xx=np.rint((node['x']+(np.arange(n+3)-1)*size/n-x0)/cell).astype(int);yy=np.rint((node['y']+(np.arange(n+3)-1)*size/n-y0)/cell).astype(int)
  tile=v[np.clip(yy,0,h-1)[:,None],np.clip(xx,0,w-1)[None,:]].copy();tile[(yy<0)|(yy>=h),:]=np.nan;tile[:,(xx<0)|(xx>=w)]=np.nan
  if not np.isfinite(tile).any():continue
  (out/'chunks'/f'{key}.recon.f32').write_bytes(tile.tobytes());changed.append(key)
  if node['level']==0:leaf_samples+=int(np.isfinite(tile[1:65,1:65]).sum())
 meta={'parameters':cfg,'source_reference':'NOAA-5163 and USF-Hillsborough-2022; NHDPlus HR connected water polygons','classification':'procedurally reconstructed','vertical_reference':'NAVD88 bed estimate with game water surface at zero only in bounded lower reaches','uncertainty':'high; does not establish surveyed depth, upstream level or fish passage','algorithm':'global 16 m shore-distance channel profile, capped width-derived depth, smoothstep blend to nearest known wet survey node; identical canonical nodes at tile seams','tiles':changed,'leaf_nodes_filled':leaf_samples,'canonical_sha256':hashlib.sha256(v.tobytes()).hexdigest()}
 from tools.gis.phase3_acquire import CORRIDORS
 from tools.gis.coordinates import Coordinates
 from shapely.geometry import box
 from shapely.ops import transform
 geo=Coordinates(json.loads((ROOT/'config/region.json').read_text()));coverage={}
 for name,bb in CORRIDORS.items():
  g=transform(geo.to_world,box(*bb));a,b,c,d=g.bounds;ix0=max(0,int((a-x0)/cell));iy0=max(0,int((b-y0)/cell));ix1=min(w,int((c-x0)/cell)+1);iy1=min(h,int((d-y0)/cell)+1)
  sl=np.s_[iy0:iy1,ix0:ix1];wet=mask[sl];src=source[sl];rec=v[sl]
  coverage[name]={'mapped_water_nodes':int(wet.sum()),'source_nodes':int((wet & np.isfinite(src)).sum()),'source_at_or_above_zero':int((wet & np.isfinite(src) & (src>=0)).sum()),'reconstructed_nodes':int(np.isfinite(rec).sum()),'unavailable_nodes':int((wet & ~np.isfinite(src) & ~np.isfinite(rec)).sum())}
 meta['coverage_by_corridor']=coverage
 write_json(out/'reconstruction.json',meta);print('Reconstruction',len(changed),'tiles',leaf_samples,'leaf nodes',flush=True)
if __name__=='__main__':build()
