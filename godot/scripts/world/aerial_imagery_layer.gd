class_name AerialImageryLayer
extends Node2D
const LIMIT_BYTES := 100663296
var root_path := ""
var nodes: Dictionary = {}
var families: Dictionary = {}
var cache: Dictionary = {}
var pending: Dictionary = {}
var frame := 0
var opacity := 0.0
var target_opacity := 0.85
var bytes := 0
var upload_ms := 0.0
var last_error := ""
func setup(asset_root: String):
	root_path=asset_root+"imagery/"
	if not FileAccess.file_exists(root_path+"index.json"): return
	nodes=JSON.parse_string(FileAccess.get_file_as_string(root_path+"index.json")).nodes
	for key in nodes:
		var n: Dictionary=nodes[key];var family: String=n.get("family",key.rsplit("_",true,1)[0])
		if not families.has(family): families[family]={"levels":{},"lod":3,"current":"","previous":"","blend":1.0}
		families[family].levels[int(n.lod)]=key
	# Small full-bay mip is resident from startup, independent of camera or detail cache.
	for key in nodes:
		if int(nodes[key].lod)==3 and int(nodes[key].get("priority",0))==0:
			install(key,decode(nodes[key]),true)
func decode(record: Dictionary) -> Image:
	var img := Image.new();var file := FileAccess.open(root_path+str(record.get("pack","alafia.pack")),FileAccess.READ)
	if file!=null:
		file.seek(int(record.offset))
		if img.load_webp_from_buffer(file.get_buffer(int(record.length)))!=OK: return Image.new()
	return img
func trim(required: int) -> bool:
	var keys := cache.keys();keys.sort_custom(func(a,b): return cache[a].used<cache[b].used)
	for key in keys:
		if bytes+required<=LIMIT_BYTES: return true
		if cache[key].pinned or cache[key].sprite.visible: continue
		bytes-=cache[key].bytes;cache[key].sprite.queue_free();cache.erase(key)
	return bytes+required<=LIMIT_BYTES
func install(key: String,img: Image,pinned := false):
	if img.is_empty(): last_error="Imagery decode failed: "+key;return
	var memory := img.get_width()*img.get_height()*4
	if not pinned and not trim(memory): return
	var sprite := Sprite2D.new();sprite.centered=false;sprite.texture=ImageTexture.create_from_image(img)
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;sprite.scale=Vector2.ONE*float(nodes[key].size)/img.get_width()
	add_child(sprite);sprite.visible=pinned
	cache[key]={"sprite":sprite,"used":frame,"bytes":memory,"pinned":pinned};bytes+=memory
func request(key: String):
	if cache.has(key): cache[key].used=frame;return
	if pending.has(key) or pending.size()>=2: return
	var record: Dictionary=nodes[key];var result: Array=[]
	var task := WorkerThreadPool.add_task(func(): result.append(decode(record)))
	pending[key]={"task":task,"result":result}
func show_tile(key: String,origin: GeoPosition,alpha: float,order: int):
	if not cache.has(key): return
	var entry: Dictionary=cache[key];var n: Dictionary=nodes[key]
	entry.sprite.position=Vector2(n.x-origin.east,n.y-origin.south);entry.sprite.visible=true
	entry.sprite.modulate.a=alpha;entry.sprite.z_index=order;entry.used=frame
func tick(camera: MapCamera,origin: GeoPosition,enabled: bool):
	frame+=1;upload_ms=0
	var dt := get_process_delta_time()
	opacity=move_toward(opacity,target_opacity if enabled else 0.0,dt*.6);modulate.a=opacity
	for key in pending.keys():
		var job: Dictionary=pending[key]
		if not WorkerThreadPool.is_task_completed(job.task): continue
		WorkerThreadPool.wait_for_task_completion(job.task);pending.erase(key)
		var start := Time.get_ticks_usec();install(key,job.result[0]);upload_ms=(Time.get_ticks_usec()-start)/1000.0;break
	for key in cache:
		cache[key].sprite.visible=false
		if cache[key].pinned: show_tile(key,origin,1.0,0)
	if opacity<=0: return
	var mpp: float=camera.span/get_viewport_rect().size.y
	var predicted_mpp: float=camera.target_span/get_viewport_rect().size.y
	var half := Vector2(get_viewport_rect().size.x/get_viewport_rect().size.y,1)*camera.span*.5
	var visible_rect := Rect2(camera.geo.east-half.x,camera.geo.south-half.y,half.x*2,half.y*2)
	# Visible requests precede adjacent-family and target-zoom prefetch.
	for prefetch in [false,true]:
		for family in families.values():
			var coarse: String=family.levels[3];var n: Dictionary=nodes[coarse]
			var rect := Rect2(n.x,n.y,n.size,n.size)
			if not rect.intersects(visible_rect.grow(float(n.size) if prefetch else 0)): continue
			var base: float=n.get("base_mpp",.5);var lod: int=family.lod
			# 25% hysteresis keeps scroll-wheel oscillation from replacing the same texture.
			while lod<3 and mpp>base*pow(2,lod+1)*1.25: lod+=1
			while lod>0 and mpp<base*pow(2,lod)*.75: lod-=1
			family.lod=lod;var wanted: String=family.levels[lod]
			if prefetch:
				if bytes+8388608<LIMIT_BYTES:
					request(wanted)
					var predicted := clampi(floori(log(maxf(base,predicted_mpp)/base)/log(2)),0,3)
					request(family.levels[predicted])
				continue
			request(wanted)
			if not cache.has(family.current): family.current=coarse if cache.has(coarse) else ""
			if cache.has(wanted) and wanted!=family.current and family.blend>=1:
				family.previous=family.current;family.current=wanted;family.blend=0.0
			family.blend=minf(1,family.blend+dt/0.65)
			var order: int=1+int(n.get("priority",0))*3
			if family.blend<1 and family.previous!="": show_tile(family.previous,origin,1.0,order)
			# Never hide the old level until its replacement has finished fading in.
			if family.current!="": show_tile(family.current,origin,float(family.blend),order+1)
			if family.blend>=1: family.previous=""
	trim(0)
func _exit_tree():
	for job in pending.values(): WorkerThreadPool.wait_for_task_completion(job.task)
