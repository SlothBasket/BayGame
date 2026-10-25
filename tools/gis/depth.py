"""Reference reader for exported immutable geographic depth leaves."""
import json, math
from pathlib import Path
import numpy as np
class DepthReader:
    def __init__(self,root):
        self.root=Path(root);self.manifest=json.loads((self.root/'manifest.json').read_text());self.cache={}
    def tile(self,key):
        if key not in self.manifest['nodes']: return None
        if key not in self.cache:
            path=self.root/'chunks'/f'{key}.json';d=json.loads(path.read_text());d['values']=np.fromfile(path.with_suffix('.f32'),dtype='<f4').reshape((d['n']+3,d['n']+3));self.cache[key]=d
        return self.cache[key]
    def elevation(self,x,y):
        size=self.manifest['chunk_m'];d=self.tile(f'0_{math.floor(x/size)}_{math.floor(y/size)}')
        if d is None:return None
        fx=(x-d['x'])/d['size']*d['n']+1;fy=(y-d['y'])/d['size']*d['n']+1
        ix=math.floor(fx);iy=math.floor(fy);result=0
        for dy in (0,1):
            for dx in (0,1):
                weight=(fx-ix if dx else 1-fx+ix)*(fy-iy if dy else 1-fy+iy)
                if weight<1e-9:continue
                z=float(d['values'][iy+dy,ix+dx])
                if not math.isfinite(z):return None
                result+=z*weight
        return result
