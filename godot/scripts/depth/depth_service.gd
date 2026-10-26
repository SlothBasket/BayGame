class_name DepthService
extends RefCounted
var store: GeographyStore
var corrections: Array = []
var navigation_reason := ""
var permissive_navigation := false
func _init(s: GeographyStore):
	store = s
	var c = JSON.parse_string(FileAccess.get_file_as_string(store.root + "corrections.json"))
	assert(c.crs == store.manifest.crs and c.vertical_datum == store.manifest.vertical_datum)
	corrections = c.corrections
func get_depth_metadata(p: GeoPosition) -> Dictionary:
	var result := {"available":false,"elevation":null,"depth":null,"classification":"unavailable","quality":"unavailable","source":"none","datum":store.manifest.vertical_datum,"reason":"outside coverage"}
	var key := p.key(0, store.manifest.chunk_m)
	if not store.manifest.nodes.has(key): return _correct(p,result)
	var tile := store.get_chunk(key)
	if tile.is_empty():
		result.reason = "loading"
		return _correct(p,result)
	var n: int = tile.n
	var fx: float = (p.east - tile.x) / tile.size * n + 1.0
	var fy: float = (p.south - tile.y) / tile.size * n + 1.0
	var ix := floori(fx)
	var iy := floori(fy)
	var z := 0.0
	var values: PackedFloat32Array = tile.get("combined",tile.samples)
	var kind := 1
	var contributors := 0
	for dy in range(2):
		for dx in range(2):
			var weight: float = (fx-ix if dx else 1.0-fx+ix) * (fy-iy if dy else 1.0-fy+iy)
			if weight < 0.000000001: continue
			var value := values[(iy+dy)*(n+3)+ix+dx]
			if is_nan(value):
				result.reason = "NoData"
				return _correct(p, result)
			z += weight * value
			contributors+=1
			if tile.has("provenance"): kind=maxi(kind,int(tile.provenance[(iy+dy)*(n+3)+ix+dx]))
	result.merge({"available":true,"elevation":z,"depth":maxf(0.0,-z),"quality":store.manifest.quality,"source":source_label(),"reason":"","resolution_m":store.manifest.depth_cell_m},true)
	result.classification="procedurally reconstructed" if kind==3 else ("interpolated survey data" if contributors>1 or kind==2 else "source-derived")
	if kind==2: result.source="USF-Hillsborough-2022 (NOAA at stencil edges)";result.quality="interpolated survey"
	if kind==3: result.source="river reconstruction v1 (gameplay; survey at stencil edges)";result.quality="estimated riverbed; high uncertainty"
	return _correct(p,result)
func _correct(p: GeoPosition, result: Dictionary) -> Dictionary:
	for c in corrections:
		if not c.get("enabled",true): continue
		var e: float = p.east + store.manifest.origin_projected[0]
		var n: float = store.manifest.origin_projected[1] - p.south
		if pow(e-c.easting,2)+pow(n-c.northing,2) <= pow(c.radius_m,2):
			result.merge({"available":true,"elevation":c.elevation_m,"depth":maxf(0,-c.elevation_m),"classification":"manually corrected","quality":"manually corrected","source":c.id,"reason":"","note":c.note},true)
	return result
func get_depth_at(p: GeoPosition):
	return get_depth_metadata(p).depth
func get_elevation_at(p: GeoPosition):
	return get_depth_metadata(p).elevation
func get_depth_profile(a: GeoPosition,b: GeoPosition,spacing: float) -> Array:
	assert(spacing>0)
	var count := maxi(1,ceili(sqrt(pow(a.east-b.east,2)+pow(a.south-b.south,2))/spacing))
	var profile: Array = []
	for i in range(count+1):
		var t := float(i)/count
		profile.append(get_depth_metadata(GeoPosition.new(lerpf(a.east,b.east,t),lerpf(a.south,b.south,t))))
	return profile
func inside(p: Vector2, polys: Array) -> bool:
	for rings in polys:
		if not point_in_ring(p, rings[0]): continue
		var in_hole := false
		for j in range(1,rings.size()):
			if point_in_ring(p,rings[j]): in_hole=true
		if not in_hole: return true
	return false
func packed(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points: out.append(Vector2(p[0],p[1]))
	return out
func navigable(p: GeoPosition, radius: float = 2.8) -> bool:
	# Disc footprint, continuous edge-distance check; unknown/loading blocks travel.
	navigation_reason=""
	var base: float = store.manifest.chunk_m
	for yy in range(floori((p.south-radius)/base),floori((p.south+radius)/base)+1):
		for xx in range(floori((p.east-radius)/base),floori((p.east+radius)/base)+1):
			var tile := store.get_chunk("0_%d_%d" % [xx,yy])
			if tile.is_empty():
				navigation_reason="collision chunk unavailable";return false
			var local := Vector2(p.east-tile.x,p.south-tile.y)
			for line in tile.get("barriers",[]):
				var points := packed(line)
				for j in range(points.size()-1):
					if local.distance_to(Geometry2D.get_closest_point_to_segment(local,points[j],points[j+1]))<=radius:
						navigation_reason="mapped physical barrier";return false
			for poly in tile.land:
				if inside(local,[poly]):
					navigation_reason="land containment";return false
				for ring in poly:
					var pts := packed(ring)
					for i in range(pts.size()-1):
						if local.distance_to(Geometry2D.get_closest_point_to_segment(local,pts[i],pts[i+1]))<=radius:
							navigation_reason="shoreline proximity";return false
	# Require coverage at center and perimeter. No guessed water outside chart coverage.
	for i in range(9):
		var a := TAU*i/8.0
		var q := GeoPosition.new(p.east+(cos(a)*radius if i<8 else 0),p.south+(sin(a)*radius if i<8 else 0))
		var tile := store.get_chunk(q.key(0,base))
		if tile.is_empty(): navigation_reason="collision chunk unavailable";return false
		var local := Vector2(q.east-tile.x,q.south-tile.y)
		var known_water := inside(local,tile.coverage) or inside(local,tile.get("mapped_water",[]))
		if permissive_navigation: known_water=known_water or inside(local,tile.get("mapped_water",[]))
		elif not get_depth_metadata(q).available:
			navigation_reason="Unknown depth (conservative navigation)";return false
		if not known_water:
			navigation_reason="coverage unavailable at %s / %.9f %.9f" % [q.key(0,base),q.east,q.south];return false
	return true

func source_label() -> String:
	if store.manifest.synthetic: return "synthetic"
	var names := PackedStringArray()
	for source in store.manifest.sources: names.append(source.id)
	return ", ".join(names) + (" (composite contributors)" if names.size()>1 else "")

func point_in_ring(p: Vector2, ring: Array) -> bool:
	# Scalar-double parity avoids Geometry2D's near-edge ray ambiguity.
	var within := false
	for i in range(ring.size()-1):
		var ax: float = ring[i][0];var ay: float = ring[i][1]
		var bx: float = ring[i+1][0];var by: float = ring[i+1][1]
		var cross_value: float = (p.x-ax)*(by-ay)-(p.y-ay)*(bx-ax)
		if absf(cross_value)<0.0000001 and p.x>=minf(ax,bx) and p.x<=maxf(ax,bx) and p.y>=minf(ay,by) and p.y<=maxf(ay,by): return true
		if (ay>p.y)!=(by>p.y):
			if p.x < (bx-ax)*(p.y-ay)/(by-ay)+ax: within=not within
	return within
