"""Deterministic tiled build. Rasterio bundles GDAL; no osgeo CLI required.
No vertical conversions are guessed. Each raster must declare NAVD88 meters,
positive-up. Geometry LOD is simplified before clipping, avoiding tile cracks.
"""
import argparse, hashlib, json, math, struct, time
from pathlib import Path
import numpy as np
import rasterio
from rasterio.warp import reproject, Resampling, transform_bounds
from rasterio.transform import from_origin
from rasterio.features import shapes
from shapely.geometry import shape, box, Polygon, mapping
from shapely.ops import transform, unary_union
from shapely import make_valid
import mapbox_earcut as earcut
from tools.gis.coordinates import Coordinates
ROOT=Path(__file__).resolve().parents[2]
VERSION=3

def write_json(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,separators=(',',':'),sort_keys=True,allow_nan=False),encoding='utf8')

def polygons(g):
    if g.geom_type=='Polygon': yield g
    elif hasattr(g,'geoms'):
        for part in g.geoms: yield from polygons(part)

def rings(g,x=0,y=0):
    return [[[round(a-x,4),round(b-y,4)] for a,b in r.coords] for r in [g.exterior,*g.interiors]]

def mesh(g,x,y):
    verts=[];indices=[]
    for poly in polygons(g):
        rr=rings(poly,x,y);v=np.array([p for r in rr for p in r[:-1]],dtype=np.float64)
        ends=np.cumsum([len(r)-1 for r in rr],dtype=np.uint32)
        if len(v)<3: continue
        idx=earcut.triangulate_float64(v,ends)
        indices.extend((idx+len(verts)).tolist());verts.extend(v.tolist())
    return verts,indices

def load_vector(path,coords,boundary):
    if not path.exists(): return None
    data=json.loads(path.read_text(encoding='utf8'))
    gg=[make_valid(transform(coords.to_world,shape(f['geometry']))).intersection(boundary) for f in data['features'] if f.get('geometry') and (path.stem!='coverage' or f['properties'].get('CATCOV') in (1,'coverage available'))]
    return make_valid(unary_union(gg))

def validate_source(source,internal):
    if source['vertical_datum']!=internal or source.get('units')!='m' or source.get('positive')!='up':
        raise ValueError('Incompatible vertical reference: preserve source; explicit validated conversion required')

def build(config,synthetic=False):
    start=time.perf_counter();geo=Coordinates(config);base=config['chunk_m'];cell=config['depth_cell_m']
    west,south,east,north=config['bbox_wgs84']
    # Densified geographic boundary, then aligned rectangular storage extent.
    bb=transform_bounds('EPSG:4326',config['crs'],west,south,east,north,densify_pts=41)
    x0=math.floor((bb[0]-geo.origin[0])/base)*base;y0=math.floor((geo.origin[1]-bb[3])/base)*base
    x1=math.ceil((bb[2]-geo.origin[0])/base)*base;y1=math.ceil((geo.origin[1]-bb[1])/base)*base
    boundary=box(x0,y0,x1,y1);w=round((x1-x0)/cell);h=round((y1-y0)/cell)
    assert base%cell==0
    dst_t=from_origin(geo.origin[0]+x0,geo.origin[1]-y0,cell,cell)
    raster=np.full((h,w),np.nan,np.float32);sources=[]
    for source in ([] if synthetic else config['depth_sources']):
        validate_source(source,config['vertical_datum'])
        path=ROOT/source['path']
        with rasterio.open(path) as src:
            if not src.crs: raise ValueError('Source has no horizontal CRS')
            source_sha=hashlib.sha256(path.read_bytes()).hexdigest()
            cache_key=hashlib.sha256((source_sha+str(dst_t)+str((h,w))+config['crs']+str(VERSION)+'mask-v1').encode()).hexdigest()
            cached=ROOT/'data/processed'/f'{cache_key}.npy'
            if cached.exists(): tmp=np.load(cached)
            else:
                tmp=np.full_like(raster,np.nan)
                reproject(rasterio.band(src,1),tmp,src_transform=src.transform,src_crs=src.crs,src_nodata=src.nodata,dst_transform=dst_t,dst_crs=config['crs'],dst_nodata=np.nan,resampling=Resampling.bilinear)
                valid=np.zeros_like(tmp,dtype='uint8')
                reproject(src.read_masks(1),valid,src_transform=src.transform,src_crs=src.crs,dst_transform=dst_t,dst_crs=config['crs'],resampling=Resampling.nearest)
                tmp[valid==0]=np.nan
                cached.parent.mkdir(parents=True,exist_ok=True);np.save(cached,tmp)
            raster[np.isfinite(tmp)]=tmp[np.isfinite(tmp)]
            sources.append(dict(source,sha256=source_sha,source_crs=str(src.crs),source_bounds=list(src.bounds),source_resolution=list(src.res),nodata=str(src.nodata)))
    land=None if synthetic else load_vector(ROOT/'data/sources/land.geojson',geo,boundary)
    coverage=None if synthetic else load_vector(ROOT/'data/sources/coverage.geojson',geo,boundary)
    channels=None if synthetic else load_vector(ROOT/'data/sources/channels.geojson',geo,boundary)
    provenance='NOAA ENC coastal land polygons'
    if land is not None:
        for name in ['rivers','lakes']:
            water=load_vector(ROOT/f'data/sources/{name}.geojson',geo,boundary)
            if water is not None: land=make_valid(land.difference(water))
    elif np.isfinite(raster).any():
        provenance='DEM zero-NAVD88 contour proxy; NOT a surveyed shoreline'
        land=unary_union([shape(g) for g,v in shapes((raster>=0).astype('uint8'),mask=np.isfinite(raster)&(raster>=0),transform=rasterio.Affine(cell,0,x0,0,cell,y0)) if v==1])
        coverage=unary_union([shape(g) for g,v in shapes(np.isfinite(raster).astype('uint8'),transform=rasterio.Affine(cell,0,x0,0,cell,y0)) if v==1])
    elif synthetic:
        provenance='SYNTHETIC TEST FIXTURE - not Tampa Bay'
        land=box(x0,y0,x0+base*5,y1).union(Polygon([(x0+base*15,y0+base*20),(x0+base*30,y0+base*20),(x0+base*30,y0+base*35),(x0+base*15,y0+base*35)],holes=[[(x0+base*18,y0+base*23),(x0+base*18,y0+base*28),(x0+base*22,y0+base*28),(x0+base*22,y0+base*23)]]))
        coverage=boundary
        yy,xx=np.indices((h,w));raster[:]=-3-2*np.sin(xx/100)*np.cos(yy/100);raster[:5,:5]=np.nan
    else: raise RuntimeError('No real geometry/depth. Acquire sources or explicitly use --synthetic.')
    if coverage is None: coverage=box(0,0,0,0)  # fail closed if imported vectors lack coverage
    out=ROOT/('godot/assets/synthetic' if synthetic else 'godot/assets/generated');out.mkdir(parents=True,exist_ok=True);(out/'.gdignore').touch()
    # Single canonical raster, windowed into immutable simulation leaves with halo.
    def grid(x,y,size,n):
        xs=x+np.arange(-1,n+2)*size/n;ys=y+np.arange(-1,n+2)*size/n
        # Samples on grid nodes, derived from canonical pixel centers.
        fx=(xs-x0)/cell-.5;fy=(ys-y0)/cell-.5
        ix=np.floor(fx).astype(int);iy=np.floor(fy).astype(int);tx=fx-ix;ty=fy-iy
        result=np.zeros((n+3,n+3),np.float64);valid=np.ones_like(result,dtype=bool)
        for dy in [0,1]:
            for dx in [0,1]:
                ok=(iy[:,None]+dy>=0)&(iy[:,None]+dy<h)&(ix[None,:]+dx>=0)&(ix[None,:]+dx<w)
                v=raster[np.clip(iy+dy,0,h-1)[:,None],np.clip(ix+dx,0,w-1)[None,:]]
                weight=(ty if dy else 1-ty)[:,None]*(tx if dx else 1-tx)[None,:]
                valid &= (ok & np.isfinite(v)) | (weight<1e-12)
                result+=np.nan_to_num(v)*weight
        result[~valid]=np.nan
        return result.astype('<f4')
    nodes={};rebuilt=0;skipped=0;max_lod=config['max_lod']
    meta_digest=hashlib.sha256(json.dumps({'config':config,'sources':sources,'provenance':provenance,'version':VERSION},sort_keys=True).encode()).hexdigest()
    for level in range(max_lod+1):
        size=base*2**level
        simplified=make_valid(land.simplify(config['simplify_m'][level],preserve_topology=True))
        for iy in range(math.floor(y0/size),math.ceil(y1/size)):
            for ix in range(math.floor(x0/size),math.ceil(x1/size)):
                x=ix*size;y=iy*size;tile=box(x,y,x+size,y+size);key=f'{level}_{ix}_{iy}'
                geom=simplified.intersection(tile)
                n=base//cell if level==0 else config['texture_cells'];samples=grid(x,y,size,n)
                path=out/'chunks'/f'{key}.json';stamp=out/'chunks'/f'{key}.sha256';input_stamp=out/'chunks'/f'{key}.input.sha256'
                local_land=land.intersection(tile) if level==0 else None
                local_coverage=coverage.intersection(tile) if level==0 else None
                local_channels=channels.boundary.intersection(tile) if channels is not None else None
                raw=samples.tobytes()
                fingerprint=hashlib.sha256(geom.wkb+raw+str((VERSION,n)).encode()+b''.join(g.wkb for g in [local_land,local_coverage,local_channels] if g is not None)).hexdigest()
                if input_stamp.exists() and input_stamp.read_text()==fingerprint and path.exists() and path.with_suffix('.f32').exists():
                    nodes[key]={'x':x,'y':y,'size':size,'level':level,'bytes':path.stat().st_size+len(raw),'sha256':stamp.read_text()}
                    skipped+=1;continue
                verts,indices=mesh(geom,x,y)
                obj={'x':x,'y':y,'size':size,'level':level,'vertices':verts,'indices':indices,'n':n,'shore':[],'channels':[]}
                # Only true coastlines, never clipping edges, for seam-free outlines.
                lines=(simplified.boundary if simplified.boundary is not None else Polygon().boundary).intersection(tile)
                def line_coords(g):
                    if g.geom_type in ('LineString','LinearRing'): return [[[round(a-x,4),round(b-y,4)] for a,b in g.coords]]
                    return [v for z in getattr(g,'geoms',[]) for v in line_coords(z)]
                obj['shore']=line_coords(lines)
                if channels is not None: obj['channels']=line_coords(local_channels)
                if level==0:
                    obj['land']=[rings(p,x,y) for p in polygons(local_land)]
                    obj['coverage']=[rings(p,x,y) for p in polygons(local_coverage)]
                payload=json.dumps(obj,separators=(',',':'),sort_keys=True).encode();raw=samples.tobytes()
                digest=hashlib.sha256(payload+raw+str(VERSION).encode()).hexdigest()
                path=out/'chunks'/f'{key}.json';stamp=out/'chunks'/f'{key}.sha256'
                if stamp.exists() and stamp.read_text()==digest and path.exists() and path.with_suffix('.f32').exists(): skipped+=1
                else:
                    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(payload);path.with_suffix('.f32').write_bytes(raw);stamp.write_text(digest);rebuilt+=1
                input_stamp.write_text(fingerprint)
                nodes[key]={'x':x,'y':y,'size':size,'level':level,'bytes':len(payload)+len(raw),'sha256':digest}
        print('LOD',level,'complete',flush=True)
    vector_sources=[]
    for path in ([] if synthetic else sorted((ROOT/'data/sources').glob('*.metadata.json'))): vector_sources.append(json.loads(path.read_text()))
    manifest={'asset_version':VERSION,'synthetic':synthetic,'name':config['name'],'crs':config['crs'],'origin_projected':geo.origin,'vertical_datum':config['vertical_datum'],'depth_meaning':'negative elevation relative to NAVD88 zero; no tides; not chart depth','quality':'synthetic' if synthetic else 'interpolated composite DEM; not individual soundings','coverage_wgs84':config['bbox_wgs84'],'bounds':[x0,y0,x1,y1],'spawn':geo.to_world(*config['spawn_wgs84']),'chunk_m':base,'max_lod':max_lod,'depth_cell_m':cell,'shoreline':provenance,'sources':sources,'vector_sources':vector_sources,'parameters':config,'build_fingerprint':meta_digest,'nodes':nodes}
    landmarks_path=ROOT/'config/landmarks.json'
    if landmarks_path.exists():
        manifest['landmarks']=[dict(p,world=geo.to_world(p['longitude'],p['latitude'])) for p in json.loads(landmarks_path.read_text())]
    write_json(out/'manifest.json',manifest)
    write_json(out/'corrections.json',json.loads((ROOT/'config/corrections.json').read_text()))
    write_json(out/'boat.json',json.loads((ROOT/'config/boat.json').read_text()))
    stats={'seconds':time.perf_counter()-start,'rebuilt':rebuilt,'unchanged':skipped,'tiles':len(nodes),'valid_depth_fraction':float(np.isfinite(raster).mean()),'gdal':rasterio.__gdal_version__}
    write_json(ROOT/'docs/build-results.json',stats);print(stats)
    return manifest
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--config',default=str(ROOT/'config/region.json'));p.add_argument('--synthetic',action='store_true');a=p.parse_args()
    build(json.loads(Path(a.config).read_text()),a.synthetic)
