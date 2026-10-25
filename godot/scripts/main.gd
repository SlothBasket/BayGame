extends Node2D
var store: GeographyStore
var depth: DepthService
var boat: BoatModel
var camera: MapCamera
var renderer: GeographicRenderer
var overlay: DebugOverlay
var origin := GeoPosition.new()
var bench := false
var bench_time := 0.0
var bench_rows: Array = []
var bench_phase := 0
var previous_bench_phase := -1
var screenshot_done := false
var previous_frame_usec := 0
var wall_dt := 0.0
var capture_name := "overview.png"
var report_dir := "user://"
func _ready():
	previous_frame_usec=Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): report_dir=arg.trim_prefix("--report-dir=")
	store=GeographyStore.new();depth=DepthService.new(store)
	boat=BoatModel.new(JSON.parse_string(FileAccess.get_file_as_string(store.root+"boat.json")))
	boat.geo=GeoPosition.new(store.manifest.spawn[0],store.manifest.spawn[1])
	renderer=GeographicRenderer.new();renderer.show_behind_parent=true;renderer.store=store;add_child(renderer)
	camera=MapCamera.new();add_child(camera);camera.setup(store.manifest)
	overlay=DebugOverlay.new();add_child(overlay)
	bench="--benchmark" in OS.get_cmdline_user_args()
	if "--view=close" in OS.get_cmdline_user_args():
		camera.geo=boat.geo.copy();camera.span=20;camera.target_span=20;camera.follow=true;capture_name="close-boat.png"
	if "--view=chart" in OS.get_cmdline_user_args():
		camera.geo=GeoPosition.new(26360,65500);camera.span=2000;camera.target_span=2000;renderer.chart=true;capture_name="chart.png"
func _unhandled_input(e):
	camera.event(e,boat)
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode>=KEY_1 and e.keycode<=KEY_7 and store.manifest.has("landmarks"):
			var point: Array = store.manifest.landmarks[e.keycode-KEY_1].world
			camera.geo=GeoPosition.new(point[0],point[1]);camera.follow=false;camera.anchor=null;camera.target_span=2000;camera.index=4
		if e.keycode==KEY_TAB: renderer.chart=not renderer.chart
		if e.keycode==KEY_C: renderer.debug=not renderer.debug
		if e.keycode==KEY_B: bench=true;bench_time=0;bench_rows.clear()
func _physics_process(dt):
	if depth!=null and not bench: boat.step(dt,depth)
func _process(dt):
	var now := Time.get_ticks_usec()
	wall_dt=(now-previous_frame_usec)/1000000.0 if previous_frame_usec>0 else dt
	previous_frame_usec=now
	store.begin_frame()
	if bench: benchmark_tick(dt)
	# Shift before float32 scene conversion. Geographic state never shifts.
	origin.east=floor(camera.geo.east/1024)*1024
	origin.south=floor(camera.geo.south/1024)*1024
	camera.tick(dt,boat,origin)
	depth.get_depth_metadata(boat.geo)
	# Prefetch simulation neighborhood before renderer requests.
	for y in range(-1,2):
		for x in range(-1,2):
			store.request(GeoPosition.new(boat.geo.east+x*store.manifest.chunk_m,boat.geo.south+y*store.manifest.chunk_m).key(0,store.manifest.chunk_m))
	renderer.tick(camera,origin);store.evict();overlay.tick(wall_dt,self)
	queue_redraw()
	if "--capture" in OS.get_cmdline_user_args() and not screenshot_done and Time.get_ticks_msec()>5000:
		screenshot_done=true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(report_dir.path_join(capture_name))
		print("CAPTURE ",ProjectSettings.globalize_path(report_dir.path_join(capture_name)))
		get_tree().quit()
func _draw():
	if boat==null: return
	var pos := boat.geo.relative_to(origin)
	var mpp := camera.span/get_viewport_rect().size.y
	if mpp<1:
		draw_set_transform(pos,boat.heading,Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([Vector2(0,-2.6),Vector2(1.05,-1),Vector2(1.05,2.6),Vector2(-1.05,2.6),Vector2(-1.05,-1)]),Color(0.95,0.91,0.72))
		draw_rect(Rect2(-0.6,-0.5,1.2,1.4),Color(0.15,0.25,0.27))
		draw_set_transform(Vector2.ZERO)
	else:
		draw_circle(pos,4*mpp,Color(1,0.83,0.4),false,mpp)
	if renderer.chart and camera.span<=2000:
		var spacing := maxf(10,pow(10,floor(log(camera.span/5)/log(10))))
		for y in range(-2,3):
			for x in range(-3,4):
				var p := GeoPosition.new(floor(camera.geo.east/spacing)*spacing+x*spacing,floor(camera.geo.south/spacing)*spacing+y*spacing)
				var d := depth.get_depth_metadata(p)
				if d.available and d.elevation<0:
					draw_set_transform(p.relative_to(origin),0,Vector2.ONE*mpp)
					draw_string(ThemeDB.fallback_font,Vector2.ZERO,"%.1f" % d.depth,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(0.8,0.88,0.8))
		draw_set_transform(Vector2.ZERO)
func benchmark_tick(dt: float):
	bench_time+=dt
	bench_phase=mini(6,int(bench_time/8))
	if bench_phase!=previous_bench_phase:
		if bench_phase==2:
			boat.geo=GeoPosition.new(floor(store.manifest.spawn[0]/1024)*1024+30,floor(store.manifest.spawn[1]/1024)*1024+50)
			boat.speed=12;boat.heading=-PI/4;boat.throttle=0.7
		previous_bench_phase=bench_phase
	var t := fmod(bench_time,8.0)/8.0
	var b: Array = store.manifest.bounds
	camera.follow=false;camera.anchor=null
	match bench_phase:
		0: camera.target_span=camera.overview_span();camera.geo=GeoPosition.new((b[0]+b[2])/2,(b[1]+b[3])/2)
		1: camera.geo=boat.geo.copy();camera.target_span=exp(lerpf(log(camera.overview_span()),log(20),t))
		2:
			camera.target_span=1500;boat.step(minf(dt,0.05),depth);camera.geo=boat.geo.copy()
		3: camera.target_span=10000;camera.geo=GeoPosition.new(store.manifest.spawn[0]+sin(t*TAU)*12000,store.manifest.spawn[1]+cos(t*TAU)*12000)
		4: camera.target_span=500;camera.geo=GeoPosition.new(lerpf(b[0]+2000,b[2]-2000,float(int(t*8)%2)),lerpf(b[1]+2000,b[3]-2000,float(int(t*8)%2)))
		5: camera.target_span=50;camera.geo=GeoPosition.new(b[2]-2000,b[3]-2000)
		6: camera.geo=GeoPosition.new(store.manifest.spawn[0]-7000,store.manifest.spawn[1]+13000);camera.target_span=exp(lerpf(log(20),log(20000),(sin(t*TAU*3)+1)/2))
	bench_rows.append({"phase":bench_phase,"ms":wall_dt*1000,"loaded":store.cache.size(),"visible":renderer.visible_count,"bytes_est":store.bytes_loaded+renderer.visual_bytes,"load_ms":store.load_ms,"engine_static_bytes":OS.get_static_memory_usage(),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"boat_east":boat.geo.east,"boat_south":boat.geo.south,"boat_blocked":boat.blocked,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	if bench_time>=56:
		var file := FileAccess.open(report_dir.path_join("benchmark.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"engine":Engine.get_version_info(),"os":OS.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"viewport":str(get_viewport_rect().size),"headless":DisplayServer.get_name()=="headless","rows":bench_rows}))
		print("BENCHMARK ",ProjectSettings.globalize_path(report_dir.path_join("benchmark.json")))
		bench=false
		if "--benchmark" in OS.get_cmdline_user_args(): get_tree().quit()
func _exit_tree():
	if store!=null: store.shutdown()
