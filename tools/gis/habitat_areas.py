"""Compact, water-clipped habitat areas using existing navigation/depth evidence only."""
import json
import numpy as np
from shapely.geometry import Point, shape, box
from shapely.ops import unary_union
from rasterio.features import shapes
from affine import Affine
from scipy.spatial import cKDTree
from scipy.ndimage import distance_transform_edt
from tools.gis.build import ROOT, write_json


def build():
    out = ROOT / 'godot/assets/generated'
    data = json.loads((out / 'fish-navigation.json').read_text())
    nodes = data['nodes']; lookup = {n['id']: n for n in nodes}
    cell = data['cell_m']; ox, oy = data['origin']
    wet = np.fromfile(out / data['mask'], dtype='uint8').reshape(data['height'], data['width']).astype(bool)
    transform = Affine(cell, 0, ox, 0, cell, oy)
    water = unary_union([shape(g) for g, v in shapes(wet.astype('uint8'), mask=wet, transform=transform) if v])
    # Nearest evidence fills cells instead of joining graph edges with tubes. Shore distance
    # independently bounds coastal bands, so a navigation link cannot bridge two shores.
    yy, xx = np.nonzero(wet)
    distance, nearest = cKDTree([(n['x'], n['y']) for n in nodes]).query(np.column_stack((ox+(xx+.5)*cell, oy+(yy+.5)*cell)))
    shore = distance_transform_edt(wet)*cell
    specs = {
        'shoreline_edge':['shelter','travel','hunting'],
        'mangrove_edge_candidate':['shelter','resting','hunting'],
        'shoreline_point_candidate':['hunting','travel'],
        'grass_flat_candidate':['feeding','shelter','hunting'],
        'channel_dropoff':['travel','hunting'],
        'creek_mouth_candidate':['feeding','hunting','travel'],
        'oyster_bar_candidate':['feeding','shelter'],
        'mapped_structure':['feeding','shelter','hunting'],
        'sheltered_rest':['resting','shelter'], 'open_water':['travel','hunting','resting']}
    areas=[]; feature_areas={str(n['id']):[] for n in nodes}; zone_areas=[[] for _ in data['zone_nodes']]
    tree=cKDTree([(n['x'],n['y']) for n in nodes])

    def add(g, zone, tag, roles, members, extra=None):
        if g.is_empty or g.area<180: return
        # Keep each disconnected patch separate; never assign one area across a channel.
        parts=[g] if g.geom_type=='Polygon' else [p for p in getattr(g,'geoms',[]) if p.geom_type=='Polygon']
        for poly in parts:
            if poly.area<180: continue
            ids=[i for i in members if poly.covers(Point(lookup[i]['x'],lookup[i]['y']))]
            if not ids:
                q=poly.representative_point(); _, k=tree.query([q.x,q.y]); ids=[nodes[int(k)]['id']]
            samples=[]
            # Stable interior samples shared with the native patrol planner.
            minx,miny,maxx,maxy=poly.bounds
            for fy in [.15,.38,.62,.85]:
                for fx in [.15,.38,.62,.85]:
                    q=Point(minx+(maxx-minx)*fx,miny+(maxy-miny)*fy)
                    if poly.covers(q): samples.append([round(q.x,2),round(q.y,2)])
            q=poly.representative_point(); samples.append([round(q.x,2),round(q.y,2)])
            index=len(areas)
            a={'id':f'habitat:{zone}:{tag}:{len(zone_areas[zone])}', 'zone':zone,'kind':tag,'roles':roles,
               'polygons':[{'outer':list(poly.exterior.coords),'holes':[list(r.coords) for r in poly.interiors]}],
               'bounds':list(poly.bounds),'area_m2':round(poly.area,1),'nodes':ids,'patrol_samples':samples,
               'evidence':sorted({e for i in ids for e in lookup[i]['evidence']}),
               'inferred':True,'boundary_note':'Inferred water-clipped habitat extent. Vegetation and substrate are candidates, not surveyed coverage.',
               'bottom_capacity':min(250,max(8,poly.area*.003)) if tag in ['oyster_bar_candidate','mapped_structure'] else 0}
            if extra: a.update(extra)
            areas.append(a);zone_areas[zone].append(index)
            for i in ids: feature_areas[str(i)].append(index)

    for tag,roles in specs.items():
        eligible=np.array([tag in n['tags'] for n in nodes])[nearest] & (distance<230)
        if tag in ['shoreline_edge','mangrove_edge_candidate','shoreline_point_candidate','oyster_bar_candidate']:
            eligible &= shore[yy,xx]<=128
        labels=np.zeros(wet.shape,dtype='int32')
        zones=np.array([n['zone']+1 for n in nodes],dtype='int32')[nearest]
        labels[yy[eligible],xx[eligible]]=zones[eligible]
        for raw,z in shapes(labels,mask=labels>0,transform=transform):
            g=shape(raw)
            if g.area<1800: continue
            # Rounded filled patches, with small protrusions removed, then clipped to water.
            g=g.buffer(-12).buffer(24,quad_segs=3).buffer(-12,quad_segs=3).simplify(8).intersection(water)
            zone=int(z)-1
            add(g,zone,tag,roles,data['zone_nodes'][zone])

    # Potholes are grass-free openings, NOT depth anomalies. Keep them small and inside
    # inferred grass; subtract their footprint from the containing grass polygon.
    for a in list(areas):
        if a['kind']!='grass_flat_candidate' or a['area_m2']<15000: continue
        poly=shape({'type':'Polygon','coordinates':[a['polygons'][0]['outer']]+a['polygons'][0]['holes']})
        inner=poly.buffer(-24)
        if inner.is_empty: continue
        center=inner.representative_point(); radius=12+(int(a['nodes'][0])*17%13)
        hole=center.buffer(radius,quad_segs=12).intersection(poly)
        add(hole,a['zone'],'pothole_candidate',['hunting','resting'],a['nodes'],{'evidence':['inferred grass-free patch in inferred grass flat'],'boundary_note':'Grass-free opening; no added bathymetric depression.'})
        remaining=poly.difference(hole)
        if remaining.geom_type=='Polygon':
            a['polygons']=[{'outer':list(remaining.exterior.coords),'holes':[list(r.coords) for r in remaining.interiors]}]
            a['area_m2']=round(remaining.area,1)
            a['patrol_samples']=[q for q in a['patrol_samples'] if remaining.covers(Point(*q))]
            if not a['patrol_samples']:
                q=remaining.representative_point();a['patrol_samples']=[[q.x,q.y]]

    # Sand holes require existing bathymetric evidence of 1–3 ft relief. Do not deepen
    # the world or call ordinary bare patches depressions. Sparse node evidence means
    # these are explicitly inferred candidates, not measured hole boundaries.
    for n in nodes:
        if 'grass_flat_candidate' in n['tags'] or 'pothole_candidate' not in n['tags']: continue
        nearby=[lookup[j]['depth_m'] for j in n['neighbors'] if j in lookup]
        if not nearby: continue
        relief=n['depth_m']-float(np.median(nearby))
        if not .3048<=relief<=.9144: continue
        g=Point(n['x'],n['y']).buffer(18,quad_segs=12)
        if not water.covers(g): continue
        add(g,n['zone'],'sand_hole',['hunting','resting'],[n['id']],{'relief_m':round(relief,3),'evidence':['existing depth relative to neighboring navigation samples; sandy substrate inferred']})
    # Guarantee usable habitat in otherwise unclassified management regions.
    for z,ids in enumerate(data['zone_nodes']):
        if zone_areas[z] or not ids: continue
        for i in ids:
            n=lookup[i];g=box(n['x']-65,n['y']-65,n['x']+65,n['y']+65).intersection(water)
            add(g,z,'open_water',specs['open_water'],[i])
    result={'version':2,'navigation_fingerprint':data['fingerprint'],'areas':areas,'feature_areas':feature_areas,'zone_areas':zone_areas}
    finish(result)
    write_json(out/'habitat-areas.json',result)
    print(f'{len(areas)} compact habitat areas generated from existing assets',flush=True)

def finish(data):
    # Interior discs allow continuous patrol destinations without runtime polygon searches.
    import math
    for a in data['areas']:
        rings=a['polygons'][0]
        poly=shape({'type':'Polygon','coordinates':[rings['outer']]+rings['holes']})
        if a['kind']=='pothole_candidate':
            c=poly.centroid; r=min(poly.bounds[2]-poly.bounds[0],poly.bounds[3]-poly.bounds[1])*.4
            a['patrol_samples']=[[c.x+r*math.cos(i*math.tau/8),c.y+r*math.sin(i*math.tau/8)] for i in range(8)]+[[c.x,c.y]]
        a['patrol_radii']=[round(max(0,min(24,poly.boundary.distance(Point(*q))*.8)),2) for q in a['patrol_samples']]
        a['patrol_samples']=[[round(x,2),round(y,2)] for x,y in a['patrol_samples']]
        for polygon in a['polygons']:
            polygon['outer']=[[round(x,2),round(y,2)] for x,y in polygon['outer']]
            polygon['holes']=[[[round(x,2),round(y,2)] for x,y in ring] for ring in polygon['holes']]

if __name__=='__main__': build()
