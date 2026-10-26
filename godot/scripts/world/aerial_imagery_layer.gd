class_name AerialImageryLayer
extends Node2D
const LIMIT_BYTES := 100663296
var root_path := ""
var nodes: Dictionary = {}
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
	if FileAccess.file_exists(root_path+"index.json"):
		var manifest = JSON.parse_string(FileAccess.get_file_as_string(root_path+"index.json"));nodes=manifest.nodes
func request(key: String):
	if cache.has(key): cache[key].used=frame;return
	if pending.has(key) or pending.size()>=2: return
	var record: Dictionary=nodes[key];var result: Array=[]
	var task := WorkerThreadPool.add_task(func():
		var file := FileAccess.open(root_path+"alafia.pack",FileAccess.READ)
		var img := Image.new()
		if file!=null:
			file.seek(int(record.offset));var error := img.load_webp_from_buffer(file.get_buffer(int(record.length)))
			if error!=OK: img=Image.new()
		result.append(img))
	pending[key]={"task":task,"result":result}
func tick(camera: MapCamera,origin: GeoPosition,enabled: bool):
	frame+=1;upload_ms=0
	opacity=move_toward(opacity,target_opacity*smoothstep(12000.0,8000.0,camera.span) if enabled else 0.0,get_process_delta_time()*.6)
	modulate.a=opacity
	# At most one GPU upload per frame, with two bounded CPU decode jobs.
	for key in pending.keys():
		var job: Dictionary=pending[key]
		if not WorkerThreadPool.is_task_completed(job.task): continue
		WorkerThreadPool.wait_for_task_completion(job.task);pending.erase(key)
		var img: Image=job.result[0]
		if img.is_empty(): last_error="Imagery decode failed: "+key;break
		var start := Time.get_ticks_usec()
		var sprite := Sprite2D.new();sprite.centered=false;sprite.texture=ImageTexture.create_from_image(img);sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale=Vector2.ONE*1024/img.get_width();add_child(sprite);sprite.visible=false;sprite.modulate.a=0
		var memory := img.get_width()*img.get_height()*4
		cache[key]={"sprite":sprite,"used":frame,"bytes":memory};bytes+=memory
		upload_ms=(Time.get_ticks_usec()-start)/1000.0;break
	for entry in cache.values():
		entry.sprite.visible=false;entry.sprite.modulate.a=minf(1,entry.sprite.modulate.a+get_process_delta_time()*2)
	var wanted := {}
	if opacity>0:
		var mpp: float=camera.span/get_viewport_rect().size.y
		var lod := clampi(floori(log(maxf(.5,mpp)/.5)/log(2)),0,3)
		var half := Vector2(get_viewport_rect().size.x/get_viewport_rect().size.y,1)*camera.span*.5
		var visible_rect := Rect2(camera.geo.east-half.x,camera.geo.south-half.y,half.x*2,half.y*2)
		# Visible first, then one adjacent tile ring. Never request full-resolution overview.
		for prefetch in [false,true]:
			for key in nodes:
				var n: Dictionary=nodes[key]
				if int(n.lod)!=lod: continue
				var rect := Rect2(n.x,n.y,n.size,n.size)
				if not rect.intersects(visible_rect.grow(1024 if prefetch else 0)): continue
				if prefetch and bytes+pending.size()*int(n.pixels)*int(n.pixels)*4>=LIMIT_BYTES: continue
				wanted[key]=true;request(key)
				if not prefetch:
					var ready: bool=cache.has(key) and cache[key].sprite.modulate.a>=1.0
					if not ready:
						for alternate in cache:
							var old: Dictionary=nodes[alternate]
							if old.x==n.x and old.y==n.y and alternate!=key:
								cache[alternate].sprite.position=Vector2(n.x-origin.east,n.y-origin.south);cache[alternate].sprite.visible=true;cache[alternate].sprite.z_index=0
								cache[alternate].used=frame;break
					if cache.has(key):
						cache[key].sprite.position=Vector2(n.x-origin.east,n.y-origin.south);cache[key].sprite.visible=true;cache[key].sprite.z_index=1
	# Strict memory bound; LRU may evict prefetch before visible imagery.
	var keys := cache.keys();keys.sort_custom(func(a,b): return cache[a].used<cache[b].used)
	for key in keys:
		if bytes<=LIMIT_BYTES: break
		if cache[key].sprite.visible: continue
		bytes-=cache[key].bytes;cache[key].sprite.queue_free();cache.erase(key)
func _exit_tree():
	for job in pending.values(): WorkerThreadPool.wait_for_task_completion(job.task)
