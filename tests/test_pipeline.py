import json,math
from pathlib import Path
import numpy as np
import rasterio
from rasterio.transform import from_origin
from shapely.geometry import mapping,box
from shapely.ops import transform
from tools.gis.coordinates import Coordinates
from tools.gis import build as module

def test_incremental_regional_rebuild_and_fixture_isolation(tmp_path,monkeypatch):
    monkeypatch.setattr(module,'ROOT',tmp_path)
    (tmp_path/'config').mkdir();(tmp_path/'data/sources').mkdir(parents=True)
    (tmp_path/'config/corrections.json').write_text('{"crs":"EPSG:32617","vertical_datum":"NAVD88","corrections":[]}')
    (tmp_path/'config/boat.json').write_text('{}')
    c={'name':'unit fixture','crs':'EPSG:32617','origin_projected':[300000,3120000],'chunk_m':128,'depth_cell_m':16,'max_lod':2,'texture_cells':8,'simplify_m':[0,1,2],'vertical_datum':'NAVD88','depth_sources':[]}
    geo=Coordinates(c);a=geo.to_wgs84(64,64);b=geo.to_wgs84(448,448);c['bbox_wgs84']=[a[0],b[1],b[0],a[1]];c['spawn_wgs84']=geo.to_wgs84(256,256)
    source=tmp_path/'data/sources/test.tif';values=np.full((40,40),-4,dtype='float32');values[10,10]=-9999
    def write():
        with rasterio.open(source,'w',driver='GTiff',height=40,width=40,count=1,dtype='float32',crs=c['crs'],transform=from_origin(300000,3120000,16,16),nodata=-9999) as ds:ds.write(values,1)
    write();c['depth_sources']=[{'id':'unit-test','path':'data/sources/test.tif','vertical_datum':'NAVD88','units':'m','positive':'up'}]
    first=module.build(c);out=tmp_path/'godot/assets/generated';before={p.name:(p.read_bytes(),p.stat().st_mtime_ns) for p in (out/'chunks').glob('*.f32')}
    module.build(c);stats=json.loads((tmp_path/'docs/build-results.json').read_text());assert stats['rebuilt']==0
    assert all(p.stat().st_mtime_ns==before[p.name][1] for p in (out/'chunks').glob('*.f32'))
    values[20,20]=-9;write();module.build(c);stats=json.loads((tmp_path/'docs/build-results.json').read_text());assert 0<stats['rebuilt']<stats['tiles']
    assert stats['unchanged']>0
    fixture=module.build(c,synthetic=True)
    assert fixture['synthetic'] and not fixture['sources'] and 'SYNTHETIC' in fixture['shoreline']
    assert json.loads((out/'manifest.json').read_text())['synthetic'] is False
