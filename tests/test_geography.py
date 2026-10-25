import hashlib,json,math
from pathlib import Path
import numpy as np
import pytest
from shapely.geometry import Polygon,box,Point
from shapely.ops import unary_union
from tools.gis.build import mesh,rings,validate_source
from tools.gis.depth import DepthReader
ROOT=Path('godot/assets/generated')
@pytest.fixture(scope='module')
def reader():return DepthReader(ROOT)
def test_bilinear_and_nodata(reader):
    d={'x':0,'y':0,'size':1024,'n':64,'values':np.full((67,67),-4.0)}
    reader.cache['0_0_0']=d;reader.manifest['nodes']['0_0_0']={}
    assert reader.elevation(8,8)==-4
    d['values'][1,1]=np.nan
    assert reader.elevation(8,8) is None
    assert reader.elevation(32,32)==-4
    assert reader.elevation(-10000,-10000) is None
    del reader.cache['0_0_0'];del reader.manifest['nodes']['0_0_0']
def test_real_depth_and_halo_continuity(reader):
    x,y=reader.manifest['spawn'];z=reader.elevation(x,y)
    assert z is not None and -50<z<0
    checked=0
    for key,info in list(reader.manifest['nodes'].items())[::23]:
        if info['level']!=0:continue
        _,ix,iy=map(int,key.split('_'));other=f'0_{ix+1}_{iy}'
        a=reader.tile(key);b=reader.tile(other)
        if b is None:continue
        np.testing.assert_equal(a['values'][:,-3:],b['values'][:,:3])
        edge=info['x']+info['size'];middle=info['y']+512
        left=reader.elevation(edge-1e-5,middle);right=reader.elevation(edge+1e-5,middle)
        if left is not None and right is not None:assert abs(left-right)<1e-3
        checked+=1
    assert checked>100

def test_mesh_preserves_hole_and_island():
    lake=Polygon([(0,0),(100,0),(100,100),(0,100)],holes=[[(20,20),(20,80),(80,80),(80,20)]])
    island=box(40,40,60,60);land=unary_union([lake,island])
    v,idx=mesh(land,0,0);triangles=[Polygon([v[j] for j in idx[i:i+3]]) for i in range(0,len(idx),3)]
    merged=unary_union(triangles)
    assert merged.symmetric_difference(land).area<1e-7
    assert not merged.contains(Point(30,30)) and merged.contains(Point(50,50))

def test_adjacent_mesh_seam():
    land=Polygon([(0,0),(2048,0),(2048,450),(1700,430),(1000,650),(0,400)])
    for tolerance in [0,1,4,32]:
        g=land.simplify(tolerance,preserve_topology=True)
        parts=[g.intersection(box(x,0,x+1024,1024)) for x in (0,1024)]
        assert unary_union(parts).symmetric_difference(g).area<1e-7
        a=parts[0].intersection(box(1024,0,1024,1024).boundary)
        assert parts[0].boundary.intersection(parts[1].boundary).length>0
        assert g.hausdorff_distance(land)<=tolerance+1e-6

def test_reject_vertical_mixing():
    for datum in ['MLLW','ellipsoidal','unknown']:
        with pytest.raises(ValueError):validate_source({'vertical_datum':datum,'units':'m','positive':'up'},'NAVD88')
    validate_source({'vertical_datum':'NAVD88','units':'m','positive':'up'},'NAVD88')
def test_manifest_assets_and_real_provenance(reader):
    assert not reader.manifest['synthetic']
    assert reader.manifest['sources'][0]['sha256']
    for key,info in reader.manifest['nodes'].items():
        p=ROOT/'chunks'/f'{key}.json'
        assert p.exists() and p.with_suffix('.f32').exists()
        assert p.stat().st_size+p.with_suffix('.f32').stat().st_size==info['bytes']
def test_lod_does_not_mutate_depth(reader):
    p=reader.manifest['spawn'];before=reader.elevation(*p)
    for level in range(8):
        size=reader.manifest['chunk_m']*2**level
        reader.tile(f'{level}_{math.floor(p[0]/size)}_{math.floor(p[1]/size)}')
        assert reader.elevation(*p)==before
