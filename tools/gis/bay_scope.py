"""Bay scope from existing authoritative estuary polygons; no river edits."""
import json
from shapely.geometry import shape,mapping,box
from shapely.ops import transform,unary_union
from shapely import make_valid
from tools.gis.build import ROOT,write_json
from tools.gis.coordinates import Coordinates
from tools.gis.bay_imagery import BBOX
geo=Coordinates(json.loads((ROOT/'config/region.json').read_text()));seen={}
for path in (ROOT/'data/sources/phase3/hydro').glob('*-areas.geojson'):
 for f in json.loads(path.read_text())['features']:
  p=f['properties']
  if p.get('ftype')==312:seen[p['permanent_identifier']]=f
area=transform(geo.to_world,box(*BBOX));water=make_valid(unary_union([transform(geo.to_world,shape(f['geometry'])) for f in seen.values()])).intersection(area)
write_json(ROOT/'godot/assets/generated/bay-estuary-mask.json',{'source':'https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer/8','selection':'Previously acquired FType 312 estuaries, clipped to bay acquisition bounds; open Gulf/ocean FType 445 excluded. Population graph separately retains only the bay-connected component.','geometry':mapping(water),'names':sorted(set(f['properties']['gnis_name'] for f in seen.values() if f['properties'].get('gnis_name')))})
print('Bay estuary mask',water.area/1e6,'square km')
