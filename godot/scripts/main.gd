extends Node2D
var fish_overlay: FishDebugOverlay
var fish: FishPopulation
var fish_save_time := 0.0
var fish_save_allowed := true
var fish_save_path := "user://bay-fish-population.dat"
var structures: GeographicStructures
var imagery: AerialImageryLayer
var settings: GameSettings
var hud: GameHud
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
	settings=GameSettings.new()
	previous_frame_usec=Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): report_dir=arg.trim_prefix("--report-dir=")
	store=GeographyStore.new();depth=DepthService.new(store)
	boat=BoatModel.new(JSON.parse_string(FileAccess.get_file_as_string(store.root+"boat.json")))
	boat.geo=GeoPosition.new(store.manifest.spawn[0],store.manifest.spawn[1])
	renderer=GeographicRenderer.new();renderer.show_behind_parent=true;renderer.z_index=-1;renderer.store=store;add_child(renderer)
	imagery=AerialImageryLayer.new();imagery.show_behind_parent=true;imagery.z_index=-8;add_child(imagery);imagery.setup(store.root)
	structures=GeographicStructures.new();structures.show_behind_parent=true;add_child(structures);structures.setup(store.root);structures.visible=false
	RenderingServer.set_default_clear_color(Color(.145,.455,.447))
	camera=MapCamera.new();add_child(camera);camera.setup(store.manifest)
	overlay=DebugOverlay.new();add_child(overlay);overlay.visible=false
	hud=GameHud.new();add_child(hud);hud.setup(self,settings)
	apply_visual_mode()
	if FileAccess.file_exists(store.root+"bay-population-zones.json"):
		var ecosystem_config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(store.root+"ecosystem-config.json"))
		fish=FishPopulation.new();fish.configure(JSON.parse_string(FileAccess.get_file_as_string(store.root+"bay-population-zones.json")),int(ecosystem_config.get("default_population",8000)))
		var error := fish.load_from(fish_save_path)
		if "--fish-smoke" in OS.get_cmdline_user_args(): print("FISH_LOAD ",error," COUNT ",fish.ids.size()," PATH ",OS.get_user_data_dir())
		fish_save_allowed=(error==OK or error==ERR_FILE_NOT_FOUND)
		if not fish.setup_ecology(ecosystem_config,JSON.parse_string(FileAccess.get_file_as_string(store.root+"bay-habitats.json"))): fish_save_allowed=false
		if not fish_save_allowed: hud.tell("Fish save incompatible; saving disabled to preserve your original population.")
	fish_overlay=FishDebugOverlay.new();add_child(fish_overlay);fish_overlay.setup(self)
	bench="--benchmark" in OS.get_cmdline_user_args()
	if "--view=alafia" in OS.get_cmdline_user_args():
		view_alafia();capture_name="alafia.png"
	if "--view=close" in OS.get_cmdline_user_args():
		camera.geo=boat.geo.copy();camera.span=20;camera.target_span=20;camera.follow=true;capture_name="close-boat.png"
	if "--view=chart" in OS.get_cmdline_user_args():
		camera.geo=GeoPosition.new(26360,65500);camera.span=2000;camera.target_span=2000;renderer.chart=true;capture_name="chart.png"
func view_alafia():
	camera.follow=false;camera.anchor=null;camera.geo=GeoPosition.new(63682,37503);camera.span=1500;camera.target_span=1500;camera.index=4
func apply_visual_mode():
	depth.permissive_navigation=settings.options.permissive_navigation
	if not settings.options.developer and int(settings.options.visual_mode)==2: settings.options.visual_mode=0
	renderer.chart=int(settings.options.visual_mode)==1
	renderer.contours=bool(settings.options.contours)
	renderer.overlay_opacity=float(settings.options.depth_opacity)
	imagery.target_opacity=float(settings.options.aerial_opacity)
func teleport_to(p: GeoPosition) -> bool:
	if not depth.navigable(p,boat.settings.length_m*.5+.2):
		hud.tell("Teleport rejected: "+depth.navigation_reason+". If loading, try again shortly.");return false
	boat.geo=p.copy();boat.speed=0;boat.yaw=0;boat.throttle=0;boat.blocked=false
	camera.follow=true;camera.geo=p.copy();camera.anchor=null
	hud.tell("Boat relocated.");return true
func _unhandled_input(e):
	if e.is_action_pressed("menu",false,true): hud.toggle();return
	if hud.menu.visible: return
	if e.is_action_pressed("fish_debug",false,true): fish_overlay.toggle();return
	if fish_overlay.enabled and e is InputEventMouseButton and e.button_index==MOUSE_BUTTON_LEFT and e.pressed:
		fish_overlay.select_at(camera.world_at(e.position),camera.span/get_viewport_rect().size.y);return
	camera.event(e,boat)
	if e.is_action_pressed("teleport_boat_to_cursor",false,true):
		teleport_to(camera.world_at(camera.reticle if camera.targeting else get_viewport().get_mouse_position()))
	if e.is_action_pressed("local_soundings",false,true): settings.options.soundings=not settings.options.soundings;hud.persist()
	if e.is_action_pressed("chart",false,true): settings.options.visual_mode=0 if renderer.chart else 1;apply_visual_mode();hud.persist()
	if e.is_action_pressed("visual_mode",false,true): settings.options.visual_mode=(int(settings.options.visual_mode)+1)%2;apply_visual_mode();hud.persist()
	if e.is_action_pressed("debug_overlay",false,true): overlay.visible=not overlay.visible
	if settings.options.developer:
		if e.is_action_pressed("chunk_grid",false,true): renderer.debug=not renderer.debug
		if e.is_action_pressed("benchmark",false,true): bench=true;bench_time=0;bench_rows.clear()
func _physics_process(dt):
	if depth!=null and not bench and not hud.menu.visible: boat.step(dt,depth)
func _process(dt):
	var now := Time.get_ticks_usec()
	wall_dt=(now-previous_frame_usec)/1000000.0 if previous_frame_usec>0 else dt
	previous_frame_usec=now
	store.begin_frame()
	if bench: benchmark_tick(dt)
	# Shift before float32 scene conversion. Geographic state never shifts.
	origin.east=floor(camera.geo.east/1024)*1024
	origin.south=floor(camera.geo.south/1024)*1024
	camera.tick(0 if hud.menu.visible else dt,boat,origin)
	depth.get_depth_metadata(boat.geo)
	# Prefetch simulation neighborhood before renderer requests.
	for y in range(-1,2):
		for x in range(-1,2):
			store.request(GeoPosition.new(boat.geo.east+x*store.manifest.chunk_m,boat.geo.south+y*store.manifest.chunk_m).key(0,store.manifest.chunk_m))
	renderer.tick(camera,origin);imagery.tick(camera,origin,not renderer.chart);store.evict();overlay.tick(wall_dt,self);hud.tick(dt)
	if fish!=null and not hud.menu.visible:
		fish.tick(dt,boat.geo,depth);fish_save_time+=dt
		if fish_save_time>=60 and fish_save_allowed:
			fish_save_time=0
			if fish.save_to(fish_save_path)!=OK: hud.tell("Fish population could not be saved.")
	if fish_overlay!=null: fish_overlay.tick(dt)
	queue_redraw()
	if "--capture" in OS.get_cmdline_user_args() and not screenshot_done and Time.get_ticks_msec()>5000:
		screenshot_done=true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(report_dir.path_join(capture_name))
		var stats := {"fps":Engine.get_frames_per_second(),"mean_ms":overlay.average,"p95_ms":overlay.p95,"imagery_cache_mib":imagery.bytes/1048576.0,"imagery_cached":imagery.cache.size(),"imagery_error":imagery.last_error,"adapter":RenderingServer.get_video_adapter_name(),"viewport":str(get_viewport_rect().size),"note":"Five-second stationary capture smoke check, not sustained travel benchmark"}
		var report := FileAccess.open(report_dir.path_join("capture-stats.json"),FileAccess.WRITE)
		report.store_string(JSON.stringify(stats,"\t"))
		print("CAPTURE ",ProjectSettings.globalize_path(report_dir.path_join(capture_name))," ",JSON.stringify(stats))
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
	if settings.options.soundings and camera.span<30000:
		var spacing := sounding_spacing(mpp)
		var radius: float=minf(float(settings.options.soundings_radius),camera.span)
		var half := get_viewport_rect().size*mpp*.5
		var low := Vector2(maxf(boat.geo.east-radius,camera.geo.east-half.x),maxf(boat.geo.south-radius,camera.geo.south-half.y))
		var high := Vector2(minf(boat.geo.east+radius,camera.geo.east+half.x),minf(boat.geo.south+radius,camera.geo.south+half.y))
		for y in range(ceili(low.y/spacing),floori(high.y/spacing)+1):
			for x in range(ceili(low.x/spacing),floori(high.x/spacing)+1):
				var p := GeoPosition.new(x*spacing,y*spacing)
				if pow(p.east-boat.geo.east,2)+pow(p.south-boat.geo.south,2)>radius*radius: continue
				var d := depth.get_depth_metadata(p)
				if d.available and d.depth>0:
					draw_set_transform(p.relative_to(origin),0,Vector2.ONE*mpp)
					var text := "%.1f ft" % (d.depth*3.280839895)
					draw_string_outline(ThemeDB.fallback_font,Vector2.ZERO,text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,4,Color(.02,.06,.07,.9))
					draw_string(ThemeDB.fallback_font,Vector2.ZERO,text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(.9,.95,.91))
		draw_set_transform(Vector2.ZERO)
func sounding_spacing(mpp: float) -> float:
	var target := maxf(10,mpp*150)
	var unit := pow(10,floor(log(target)/log(10)))
	for factor in [1.0,2.0,5.0,10.0]:
		if unit*factor>=target: return unit*factor
	return unit*10

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
	if fish!=null and fish_save_allowed and fish.save_to(fish_save_path)!=OK: push_warning("Fish population save failed: "+OS.get_user_data_dir())
	if store!=null: store.shutdown()

