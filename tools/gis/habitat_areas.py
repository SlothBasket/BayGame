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
    # Local connected neighbors provide relief and channel context without crossing land.
    for n in nodes:
        neighbors=[lookup[i] for i in n['neighbors'] if i in lookup]
        depths=[v['depth_m'] for v in neighbors] or [n['depth_m']]
        n['local_relief']=max(depths)-min(depths)
        n['edge_depth']=min(depths)<2.5 and max(depths)>3.5
        if .5<n['depth_m']<3.5 and n['local_relief']<.7 and 'grass_flat_candidate' not in n['tags']:
            n['tags'].append('sand_flat_candidate')
        if 'grass_flat_candidate' in n['tags'] and any('grass_flat_candidate' not in v['tags'] for v in neighbors):
            n['tags'].append('grass_edge_candidate')
        deep=[v for v in neighbors if v['depth_m']>=n['depth_m']-.5]
        if n['depth_m']>2 and n['shore_m']<160 and len(deep)>=2 and n['local_relief']>.6:
            n['tags'].append('tidal_cut_candidate')
        if n['edge_depth'] and n['local_relief']>1:
            n['tags'].append('channel_margin_candidate')
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
        'sand_flat_candidate':['feeding','hunting','resting'],
        'grass_edge_candidate':['feeding','hunting','travel'],
        'tidal_cut_candidate':['travel','hunting'],
        'channel_margin_candidate':['travel','hunting','resting'],
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
            measured=[lookup[i]['depth_m'] for i in ids]
            a['depth_min_m']=round(min(measured),2);a['depth_max_m']=round(max(measured),2)
            a['relief_m']=round(max(lookup[i]['local_relief'] for i in ids),2)
            a['shore_distance_m']=round(sum(lookup[i]['shore_m'] for i in ids)/len(ids),1)
            a['evidence'].append('Connected-water neighborhood depth and shoreline-distance classification')
            if extra: a.update(extra)
            areas.append(a);zone_areas[zone].append(index)
            for i in ids: feature_areas[str(i)].append(index)

    for tag,roles in specs.items():
        eligible=np.array([tag in n['tags'] for n in nodes])[nearest] & (distance<230)
        if tag in ['shoreline_edge','mangrove_edge_candidate','shoreline_point_candidate','oyster_bar_candidate']:
            eligible &= shore[yy,xx]<=128
        depth=np.array([n['depth_m'] for n in nodes])[nearest]
        relief=np.array([n['local_relief'] for n in nodes])[nearest]
        if tag=='grass_flat_candidate': eligible &= (depth<2.5)&(relief<.8)
        if tag=='oyster_bar_candidate': eligible &= (depth>.4)&(depth<2)&(relief<1.2)
        if tag=='mangrove_edge_candidate': eligible &= (depth<2.5)&(shore[yy,xx]<96)
        if tag=='sheltered_rest': eligible &= (relief<.8)&(shore[yy,xx]<160)
        if tag=='tidal_cut_candidate': eligible &= shore[yy,xx]<192
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
    grass_detail(result, data)
    finish(result)
    write_json(out/'habitat-areas.json',result)
    print(f'{len(areas)} compact habitat areas generated from existing assets',flush=True)

def grass_detail(data, navigation):
    """Embedded microhabitats: no additional population zones or runtime nodes."""
    import random, math, zlib
    old={}
    for a in data['areas']:
        if a['kind']=='pothole_candidate': old.setdefault(a['zone'],[]).extend(shape({'type':'Polygon','coordinates':[p['outer']]+p['holes']}) for p in a['polygons'])
    data['areas']=[a for a in data['areas'] if a['kind']!='pothole_candidate']
    tree=cKDTree([(n['x'],n['y']) for n in navigation['nodes']])
    for a in data['areas']:
        if a['kind']!='grass_flat_candidate': continue
        ring=a['polygons'][0];poly=shape({'type':'Polygon','coordinates':[ring['outer']]+ring['holes']})
        for hole in old.get(a['zone'],[]):
            if poly.distance(hole)<.05: poly=poly.union(hole)
        if poly.geom_type!='Polygon': continue
        a['polygons']=[{'outer':list(poly.exterior.coords),'holes':[list(r.coords) for r in poly.interiors]}]
        rng=random.Random(zlib.crc32(a['id'].encode()))
        depth=max(.3,(a.get('depth_min_m',1)+a.get('depth_max_m',2))*.5)
        height=min(depth*.85,rng.uniform(.12,.85));density=rng.uniform(.35,.95)
        a.update(grass_height_m=round(height,3),grass_density=round(density,3),grass_clearance_m=round(max(0,depth-height),3))
        a['grass_environment']='tall dense canopy' if height/depth>.45 and density>.65 else ('short sparse grass' if density<.55 else 'submerged meadow')
        a['potholes']=[];x0,y0,x1,y1=poly.bounds
        count=min(96,max(4,int(poly.area/800)))
        for attempt in range(count*12):
            if len(a['potholes'])>=count: break
            center=Point(rng.uniform(x0,x1),rng.uniform(y0,y1));diameter=rng.uniform(.3048,1.524)
            if not poly.contains(center) or poly.boundary.distance(center)<diameter: continue
            if any(math.hypot(center.x-h['center'][0],center.y-h['center'][1])<3 for h in a['potholes']): continue
            offsets=[(math.cos(i*math.tau/8)*rng.uniform(.7,1),math.sin(i*math.tau/8)*rng.uniform(.7,1)) for i in range(8)]
            scale=diameter/max(max(x for x,y in offsets)-min(x for x,y in offsets),max(y for x,y in offsets)-min(y for x,y in offsets))
            points=[[round(center.x+x*scale,3),round(center.y+y*scale,3)] for x,y in offsets]
            _,n=tree.query([center.x,center.y])
            a['potholes'].append({'center':[round(center.x,3),round(center.y,3)],'width_m':round(diameter,3),'node':navigation['nodes'][int(n)]['id'],'boundary':points})
        a['boundary_note']='Inferred grass canopy and 1–5 ft grass-free micro-openings; no bathymetric depression.'
    data['feature_areas']={str(n['id']):[] for n in navigation['nodes']}
    data['zone_areas']=[[] for _ in navigation['zone_nodes']]
    for i,a in enumerate(data['areas']):
        data['zone_areas'][a['zone']].append(i)
        for n in a['nodes']: data['feature_areas'][str(n)].append(i)

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
