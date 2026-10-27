extends SceneTree
var main
var rows: Array[float] = []
var cpu: Array[float] = []
var elapsed := 0.0
var previous := 0
var init_ms := 0.0
var storage_delta := 0
var packed_bytes := 0
var initial_count := 0
var saved := false
func _initialize(): call_deferred("start")
func start():
	var before := OS.get_static_memory_usage();var begin := Time.get_ticks_usec()
	var population := FishPopulation.new();population.configure(JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/bay-population-zones.json")),10000)
	init_ms=(Time.get_ticks_usec()-begin)/1000.0;storage_delta=OS.get_static_memory_usage()-before;packed_bytes=population.packed_bytes()
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	# Test owns its population and never replaces the user's persistent state.
	main.fish=population;main.fish_save_path="res://../.local/bay-performance-population.dat"
	initial_count=main.fish.ids.size();main.fish.time_scale=60
	main.fish_overlay.toggle();main.fish_overlay.selected=0;main.fish_overlay.selected_zone=main.fish.region[0]
	main.camera.follow=false;main.camera.geo=GeoPosition.new(main.fish.east[0],main.fish.south[0]);main.camera.span=6000;main.camera.target_span=6000
	previous=Time.get_ticks_usec()
func _process(dt):
	if main==null: return false
	var now := Time.get_ticks_usec();var ms := (now-previous)/1000.0;previous=now;elapsed+=dt
	if elapsed<4: main.camera.target_span=main.camera.overview_span()
	elif elapsed<8: main.camera.target_span=6000
	else: main.camera.target_span=1500
	if elapsed>2: rows.append(ms);cpu.append(main.fish.update_ms)
	if elapsed>=12 and not saved:
		saved=true
		rows.sort();cpu.sort();var total := 0.0;var total_cpu := 0.0
		for v in rows: total+=v
		for v in cpu: total_cpu+=v
		var result := {"fish_count":initial_count,"zones":main.fish.zones.size(),"storage_initialization_ms":init_ms,"storage_engine_delta_bytes":storage_delta,"packed_record_bytes":packed_bytes,"mean_behavior_update_ms":total_cpu/cpu.size(),"p95_behavior_update_ms":cpu[int(cpu.size()*.95)],"mean_frame_ms":total/rows.size(),"p95_frame_ms":rows[int(rows.size()*.95)],"max_frame_ms":rows[-1],"migrations":main.fish.migrations,"decisions":main.fish.decisions,"simulated_seconds":main.fish.elapsed,"imagery_cache_mib":main.imagery.bytes/1048576.0,"adapter":RenderingServer.get_video_adapter_name(),"viewport":str(root.size),"note":"Single 12-second 10k-fish test: 60x simulation, fish debug overlay active, overview-to-close zoom. First 2 seconds excluded. Storage allocation measured separately from behavior updates."}
		var f := FileAccess.open("res://../docs/bay-ecosystem-performance.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close();print(JSON.stringify(result))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../.local/bay-ecosystem.png")
		quit()
	return false
