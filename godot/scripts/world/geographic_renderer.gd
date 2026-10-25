class_name GeographicRenderer
extends Node2D
var store: GeographyStore
var views: Dictionary = {}
var visible_count := 0
var active_lod := 7
var requested_lod := 7
var render_build_ms := 0.0
var visual_bytes := 0
var chart := false
var debug := false
func keys_for(level: int,camera: MapCamera) -> Array:
	var size: float = store.manifest.chunk_m*pow(2,level)
	var half_y := camera.span*0.5
	var half_x := half_y*get_viewport_rect().size.x/get_viewport_rect().size.y
	var keys: Array = []
	for y in range(floori((camera.geo.south-half_y)/size),floori((camera.geo.south+half_y)/size)+1):
		for x in range(floori((camera.geo.east-half_x)/size),floori((camera.geo.east+half_x)/size)+1):
			var key := "%d_%d_%d" % [level,x,y]
			if store.manifest.nodes.has(key): keys.append(key)
	return keys
func ensure_view(key: String,begin: int) -> bool:
	if views.has(key): return true
	if not store.cache.has(key): return false
	if (Time.get_ticks_usec()-begin)/1000.0>store.budget_ms: return false
	var view := RegionView.new();view.setup(store.cache[key]);view.visible=false;add_child(view);views[key]=view
	visual_bytes+=int(store.manifest.nodes[key].bytes)*3
	return true
func tick(camera: MapCamera,origin: GeoPosition):
	var begin := Time.get_ticks_usec()
	var mpp := camera.span/get_viewport_rect().size.y
	requested_lod=clampi(ceili(log(mpp*store.manifest.parameters.lod_pixel_threshold/store.manifest.chunk_m)/log(2)),0,int(store.manifest.max_lod))
	# A uniform visible LOD prevents mismatched polygon edges at mixed-LOD seams.
	# A complete parent level stays visible until every visible child is ready.
	var selected: Array = []
	for level in range(requested_lod,int(store.manifest.max_lod)+1):
		var keys := keys_for(level,camera)
		var ready := true
		for key in keys:
			store.request(key)
			if not ensure_view(key,begin): ready=false
		if ready:
			selected=keys;active_lod=level;break
	for key in views:
		views[key].visible=key in selected
	for key in selected:
		views[key].refresh(origin,chart,debug,mpp)
	visible_count=selected.size()
	# Bound visual cache separately from data cache; keep parent overview resident.
	if views.size()>128:
		for key in views.keys():
			if key in selected or int(store.manifest.nodes[key].level)==int(store.manifest.max_lod): continue
			views[key].queue_free();views.erase(key);visual_bytes-=int(store.manifest.nodes[key].bytes)*3
			if views.size()<=128: break
	render_build_ms=(Time.get_ticks_usec()-begin)/1000.0
