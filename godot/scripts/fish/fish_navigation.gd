class_name FishNavigation
extends RefCounted
var nodes: Dictionary = {}
var zone_nodes: Array = []
var spatial: Dictionary = {}
class WaterGraph extends AStar2D:
	var follow_edges := false
	var shore: Dictionary = {}
	func _compute_cost(from_id: int,to_id: int) -> float:
		var distance := get_point_position(from_id).distance_to(get_point_position(to_id))
		return distance*(1.0+minf(3.0,float(shore.get(to_id,1000))/180.0)) if follow_edges else distance
var graph := WaterGraph.new()
var mask := PackedByteArray()
var origin := Vector2.ZERO
var width := 0
var height := 0
var cell := 32.0
var fingerprint := ""
func setup(root: String) -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(root+"fish-navigation.json"))
	if not data is Dictionary: return false
	origin=Vector2(data.origin[0],data.origin[1]);width=int(data.width);height=int(data.height);cell=float(data.cell_m)
	fingerprint=data.fingerprint;zone_nodes=data.zone_nodes;mask=FileAccess.get_file_as_bytes(root+data.mask)
	if mask.size()!=width*height: return false
	for record in data.nodes:
		var id: int=record.id;record.id=id;record.zone=int(record.zone);record.component=int(record.component)
		record.neighbors=PackedInt32Array(record.neighbors);nodes[id]=record
		var p := Vector2(record.x,record.y);graph.add_point(id,p);graph.shore[id]=float(record.shore_m)
		var key := Vector2i(floori(p.x/256),floori(p.y/256))
		if not spatial.has(key): spatial[key]=[]
		spatial[key].append(id)
	for id in nodes:
		for neighbor in nodes[id].neighbors:
			if id<neighbor and nodes.has(neighbor): graph.connect_points(id,neighbor)
	return not nodes.is_empty()
func point(id: int) -> Vector2:
	return graph.get_point_position(id)
func wet_cell(c: Vector2i) -> bool:
	return c.x>=0 and c.y>=0 and c.x<width and c.y<height and mask[c.y*width+c.x]!=0
func grid(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x-origin.x)/cell),floori((p.y-origin.y)/cell))
func wet(p: Vector2) -> bool:
	return wet_cell(grid(p))
func clear(a: Vector2,b: Vector2) -> bool:
	var c := grid(a);var end := grid(b);var delta := b-a
	var sx := 1 if delta.x>0 else -1;var sy := 1 if delta.y>0 else -1
	var tx := ((origin.x+(c.x+(1 if sx>0 else 0))*cell)-a.x)/delta.x if delta.x!=0 else INF
	var ty := ((origin.y+(c.y+(1 if sy>0 else 0))*cell)-a.y)/delta.y if delta.y!=0 else INF
	var dx := cell/absf(delta.x) if delta.x!=0 else INF;var dy := cell/absf(delta.y) if delta.y!=0 else INF
	for iteration in range(absi(end.x-c.x)+absi(end.y-c.y)+4):
		if not wet_cell(c): return false
		if c==end: return true
		if absf(tx-ty)<.0000001:
			if not wet_cell(c+Vector2i(sx,0)) or not wet_cell(c+Vector2i(0,sy)): return false
			c+=Vector2i(sx,sy);tx+=dx;ty+=dy
		elif tx<ty: c.x+=sx;tx+=dx
		else: c.y+=sy;ty+=dy
	return false
func nearest(p: Vector2,zone := -1,component := -1) -> int:
	var best := -1;var distance := INF;var key := Vector2i(floori(p.x/256),floori(p.y/256))
	for ring in range(5):
		for y in range(-ring,ring+1):
			for x in range(-ring,ring+1):
				if ring>0 and abs(x)!=ring and abs(y)!=ring: continue
				for id in spatial.get(key+Vector2i(x,y),[]):
					if component>=0 and nodes[id].component!=component: continue
					if zone>=0 and nodes[id].zone!=zone: continue
					var d := p.distance_squared_to(point(id))
					if d<distance and (not wet(p) or clear(p,point(id))): distance=d;best=id
		if best>=0 and distance<pow(maxi(1,ring)*256,2): break
	return best
func route(start: Vector2,target: Vector2,goal: int,follow_edge := false) -> PackedVector2Array:
	if not follow_edge and clear(start,target): return PackedVector2Array([start,target])
	var from := nearest(start)
	if from<0 or not nodes.has(goal) or nodes[from].component!=nodes[goal].component: return PackedVector2Array()
	graph.follow_edges=follow_edge and float(nodes[from].shore_m)<250 and float(nodes[goal].shore_m)<250
	var coastal := graph.follow_edges
	var raw := graph.get_point_path(from,goal)
	graph.follow_edges=false
	if raw.is_empty(): return raw
	raw.insert(0,start);raw.append(target)
	# Visibility smoothing removes triangulation zigzags; steering supplies natural curvature.
	var result := PackedVector2Array([start]);var index := 0
	while index<raw.size()-1:
		var next := index+1
		for candidate in range(index+2,mini(raw.size(),index+(3 if coastal else 10))):
			if clear(raw[index],raw[candidate]): next=candidate
		result.append(raw[next]);index=next
	return result
func offset(id: int,seed_value: int,radius: float) -> Vector2:
	var center := point(id)
	for attempt in range(8):
		var angle := fposmod(float(seed_value*7919+attempt*104729),6283.0)*.001
		var candidate := center+Vector2.from_angle(angle)*radius*(1.0-float(attempt)/9.0)
		if clear(center,candidate): return candidate
	return center

func migration_anchor(p: Vector2,zone: int) -> int:
	# Used only for one-time reprojection out of legacy narrow/unsupported positions.
	var best := -1;var distance := 750.0*750.0
	for value in zone_nodes[zone]:
		var id := int(value)
		if not nodes.has(id): continue
		var d := p.distance_squared_to(point(id))
		if d<distance: distance=d;best=id
	return best
