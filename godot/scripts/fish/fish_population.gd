class_name FishPopulation
extends RefCounted
# Packed records, never scene nodes. Positions are absolute world meters.
var ids := PackedInt64Array()
var east := PackedFloat64Array()
var south := PackedFloat64Array()
var region := PackedInt32Array()
var progress := PackedFloat32Array()
var direction := PackedFloat32Array()
var habitat_depth := PackedFloat32Array()
var last_update := PackedFloat64Array()
var buckets: Dictionary = {}
var routes: Array = []
var spatial: Dictionary = {}
var fingerprint := ""
var elapsed := 0.0
var cursor := 0
var near_cursor := 0
var update_ms := 0.0
var near_region := -1
func configure(data: Dictionary, count := 100000):
	routes=data.routes;fingerprint=JSON.stringify(routes).sha256_text()
	if routes.is_empty(): return
	spatial.clear()
	for r in range(routes.size()):
		var route: Dictionary=routes[r]
		var key := Vector2i(floori((route.a[0]+route.b[0])*.5/512),floori((route.a[1]+route.b[1])*.5/512))
		if not spatial.has(key): spatial[key]=[]
		spatial[key].append(r)
	ids.resize(count);east.resize(count);south.resize(count);region.resize(count);progress.resize(count);direction.resize(count);habitat_depth.resize(count);last_update.resize(count)
	for r in range(routes.size()): buckets[r]=[]
	for i in range(count):
		ids[i]=i+1;region[i]=i%routes.size();progress[i]=float((i*7919)%100003)/100003.0;direction[i]=1.0 if i%2==0 else -1.0
		buckets[region[i]].append(i);place(i)
func place(i: int):
	var route: Dictionary=routes[region[i]]
	var a: Array=route.a;var b: Array=route.b
	east[i]=lerpf(a[0],b[0],progress[i]);south[i]=lerpf(a[1],b[1],progress[i]);habitat_depth[i]=route.depth_m
func advance(i: int,dt: float):
	var route: Dictionary=routes[region[i]]
	progress[i]+=direction[i]*dt*.15/maxf(1,float(route.length_m))
	if progress[i]>1 or progress[i]<0:
		var endpoint := 1 if progress[i]>1 else 0
		var edges: Array=route.edges[endpoint]
		if not edges.is_empty():
			var link: Array=edges[int(ids[i])%edges.size()]
			buckets[region[i]].erase(i);region[i]=int(link[0]);buckets[region[i]].append(i)
			progress[i]=float(link[1]);direction[i]=1.0 if int(link[1])==0 else -1.0
		else: progress[i]=clampf(progress[i],0,1);direction[i]*=-1
	place(i)
func tick(dt: float,player: GeoPosition,depth_service: DepthService=null):
	if ids.is_empty(): return
	var begin := Time.get_ticks_usec();elapsed+=dt
	# Spatial route index: choose nearby route once a second, independent of camera.
	if int(elapsed)!=int(elapsed-dt):
		near_region=-1;var nearest := 250000.0
		var cell := Vector2i(floori(player.east/512),floori(player.south/512))
		for y in range(-1,2):
			for x in range(-1,2):
				for r in spatial.get(cell+Vector2i(x,y),[]):
					var route: Dictionary=routes[r]
					var dx: float=(route.a[0]+route.b[0])*.5-player.east
					var dy: float=(route.a[1]+route.b[1])*.5-player.south
					var d: float=dx*dx+dy*dy
					if d<nearest: nearest=d;near_region=r

	# Bounded amortized distant updates; each fish receives actual elapsed time.
	for _n in range(mini(500,ids.size())):
		var i := cursor;cursor=(cursor+1)%ids.size()
		if elapsed-last_update[i]<1.0: continue
		advance(i,minf(elapsed-last_update[i],5));last_update[i]=elapsed
	if near_region>=0:
		var members: Array=buckets[near_region]
		for _n in range(mini(64,members.size())):
			if members.is_empty(): break
			near_cursor%=members.size();var i: int=members[near_cursor];near_cursor+=1
			if elapsed-last_update[i]<.1: continue
			if depth_service!=null:
				var d := depth_service.get_depth_metadata(GeoPosition.new(east[i],south[i]))
				if not d.available: continue
				habitat_depth[i]=d.depth
			advance(i,minf(elapsed-last_update[i],5));last_update[i]=elapsed
	update_ms=(Time.get_ticks_usec()-begin)/1000.0
func packed_bytes() -> int:
	return ids.size()*(8+8+8+4+4+4+4+8)
func save_to(path: String) -> Error:
	var f := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f==null: return FileAccess.get_open_error()
	f.store_var({"version":1,"fingerprint":fingerprint,"ids":ids,"east":east,"south":south,"region":region,"progress":progress,"direction":direction,"habitat_depth":habitat_depth,"last_update":last_update,"elapsed":elapsed});f.close()
	return DirAccess.rename_absolute(path+".tmp",path)
func load_from(path: String) -> Error:
	if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
	var f := FileAccess.open(path,FileAccess.READ)
	if f==null: return FileAccess.get_open_error()
	var d = f.get_var(false)
	if not d is Dictionary or d.get("version",0)!=1 or d.get("fingerprint","")!=fingerprint: return ERR_INVALID_DATA
	var count: int=d.ids.size()
	for key in ["east","south","region","progress","direction","habitat_depth","last_update"]:
		if not d.has(key) or d[key].size()!=count: return ERR_INVALID_DATA
	for r in d.region:
		if r<0 or r>=routes.size(): return ERR_INVALID_DATA
	ids=d.ids;east=d.east;south=d.south;region=d.region;progress=d.progress;direction=d.direction;habitat_depth=d.habitat_depth;last_update=d.last_update;elapsed=d.elapsed
	buckets.clear()
	for r in range(routes.size()): buckets[r]=[]
	for i in range(count): buckets[region[i]].append(i)
	cursor=0;near_cursor=0;return OK
