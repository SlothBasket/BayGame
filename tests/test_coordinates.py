import json, math
from pathlib import Path
from pyproj import Geod
from tools.gis.coordinates import Coordinates
C=json.loads(Path('config/region.json').read_text())
def test_roundtrip():
    g=Coordinates(C)
    for p in [(-82.65,27.62),(-82.4,27.9),(-82.9,28.18),(-82.15,27.35)]:
        assert max(abs(a-b) for a,b in zip(p,g.to_wgs84(*g.to_world(*p))))<1e-9
def test_distance_and_scale():
    g=Coordinates(C); a=(-82.65,27.62); b=(-82.4,27.9)
    planar=math.dist(g.to_world(*a),g.to_world(*b)); true=Geod(ellps='WGS84').inv(*a,*b)[2]
    assert abs(planar/true-1)<0.001
    assert math.dist(g.to_scene((123456.125,234567.25),(123455.125,234567.25)),(0,0))==1

def test_shift_and_chunks():
    p=(123456.125,234567.25)
    for origin in [(0,0),(123450,234560),(-1000,90000)]:
        s=Coordinates.to_scene(p,origin)
        assert tuple(a+b for a,b in zip(s,origin))==p
    assert Coordinates.chunk((-0.01,1024),1024)==(-1,1)


def test_sourced_landmark_distances():
    landmarks=json.loads(Path('config/landmarks.json').read_text());geo=Coordinates(C);geod=Geod(ellps='WGS84')
    for a,b in zip(landmarks,landmarks[1:]):
        pa=(a['longitude'],a['latitude']);pb=(b['longitude'],b['latitude'])
        assert a['source'].startswith('https://')
        distance=math.dist(geo.to_world(*pa),geo.to_world(*pb))
        reference=geod.inv(*pa,*pb)[2]
        assert abs(distance/reference-1)<0.001
