"""Geographic state uses float64 local metric east/south coordinates.
Projection origin is fixed in the manifest; render origin is transient.
"""
import math
from pyproj import Transformer
class Coordinates:
    def __init__(self, config):
        self.origin = config['origin_projected']
        self.forward = Transformer.from_crs('EPSG:4326', config['crs'], always_xy=True)
        self.inverse = Transformer.from_crs(config['crs'], 'EPSG:4326', always_xy=True)
    def to_world(self, lon, lat):
        e,n=self.forward.transform(lon,lat)
        return e-self.origin[0], self.origin[1]-n
    def to_wgs84(self,x,y):
        return self.inverse.transform(x+self.origin[0],self.origin[1]-y)
    @staticmethod
    def to_scene(position, render_origin):
        return tuple(a-b for a,b in zip(position,render_origin))
    @staticmethod
    def chunk(position,size):
        return tuple(math.floor(x/size) for x in position)
