class_name FishNavigation
extends RefCounted
var diagnostics
var nearest_cache: Dictionary = {}
var nearest_keys: Array[Vector4] = []
var nearest_slot := 0
var worker_usec := 0
var nodes: Dictionary = {}
var route_cache: Dictionary = {}
var route_pending := false
var route_worker := Thread.new()
var route_jobs: Array[Vector3i] = []
var queued_routes: Dictionary = {}
var active_route := Vector3i(-1,-1,-1)
var cache_order: Array[Vector3i] = []
func process_routes():
	if diagnostics==null: _measured_process_routes();return
	var diagnostic_begin := Time.get_ticks_usec()
	_measured_process_routes()
	diagnostics.add("Route completion",Time.get_ticks_usec()-diagnostic_begin)
func _measured_process_routes():
	if route_worker.is_started():
		if route_worker.is_alive(): return
		var result: PackedVector2Array=route_worker.wait_to_finish()
		if diagnostics!=null: diagnostics.add("Navigation worker",worker_usec)
		route_cache[active_route]=result;cache_order.append(active_route);queued_routes.erase(active_route)
		if cache_order.size()>512: route_cache.erase(cache_order.pop_front())
	if not route_jobs.is_empty():
		active_route=route_jobs.pop_front()
		var error := route_worker.start(compute_route.bind(active_route))
		if error!=OK: queued_routes.erase(active_route)
func compute_route(key: Vector3i) -> PackedVector2Array:
	var begin := Time.get_ticks_usec()
	var result := _compute_route(key)
	worker_usec=Time.get_ticks_usec()-begin
	return result
func _compute_route(key: Vector3i) -> PackedVector2Array:
	# Single worker owns all graph searches; node geometry and water mask are immutable.
	graph.follow_edges=key.z==1
	var raw := graph.get_point_path(key.x,key.y)
	graph.follow_edges=false
	if raw.is_empty(): return raw
	var result := PackedVector2Array([raw[0]]);var index := 0
	while index<raw.size()-1:
		var next := index+1
		for candidate in range(index+2,mini(raw.size(),index+(3 if key.z==1 else 10))):
			if clear(raw[index],raw[candidate]): next=candidate
		result.append(raw[next]);index=next
	return result
func shutdown():
	if route_worker.is_started(): route_worker.wait_to_finish()
	route_jobs.clear();queued_routes.clear()
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
func _measured_nearest(p: Vector2,zone := -1,component := -1) -> int:
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
	if diagnostics==null: return _measured_route(start,target,goal,follow_edge)
	var diagnostic_begin := Time.get_ticks_usec()
	var result: PackedVector2Array=_measured_route(start,target,goal,follow_edge)
	diagnostics.add("Route requests",Time.get_ticks_usec()-diagnostic_begin)
	return result
func _measured_route(start: Vector2,target: Vector2,goal: int,follow_edge := false) -> PackedVector2Array:
	route_pending=false
	if not follow_edge and clear(start,target): return PackedVector2Array([start,target])
	var from := nearest(start)
	if from<0 or not nodes.has(goal) or nodes[from].component!=nodes[goal].component: return PackedVector2Array()
	var coastal := follow_edge and float(nodes[from].shore_m)<250 and float(nodes[goal].shore_m)<250
	var cache_key := Vector3i(from,goal,1 if coastal else 0)
	if not route_cache.has(cache_key):
		route_pending=true
		if not queued_routes.has(cache_key) and route_jobs.size()<128:
			route_jobs.append(cache_key);queued_routes[cache_key]=true
		return PackedVector2Array()
	var raw: PackedVector2Array=route_cache[cache_key].duplicate()
	if raw.is_empty(): return raw
	raw.insert(0,start);raw.append(target)
	return raw

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

func nearest(p: Vector2,zone := -1,component := -1) -> int:
	var key := Vector4(p.x,p.y,zone,component)
	if nearest_cache.has(key): return int(nearest_cache[key])
	var begin := Time.get_ticks_usec()
	var result: int=_measured_nearest(p,zone,component)
	if diagnostics!=null: diagnostics.add("Navigation nearest",Time.get_ticks_usec()-begin)
	if nearest_keys.size()<2048: nearest_keys.append(key)
	else:
		nearest_cache.erase(nearest_keys[nearest_slot]);nearest_keys[nearest_slot]=key;nearest_slot=(nearest_slot+1)%2048
	nearest_cache[key]=result
	return result
