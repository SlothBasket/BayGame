extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1;push_error(message)
func _initialize(): call_deferred("run")
func run():
	var settings := GameSettings.new(false)
	check(InputMap.has_action("local_soundings") and settings.describe("local_soundings").contains("L"),"Rebindable local sounding action")
	var store := GeographyStore.new();var depth := DepthService.new(store)
	var tile := {"x":0,"y":0,"size":1024,"n":64,"used":0,"land":[],"coverage":[],"mapped_water":[[[[0,0],[1024,0],[1024,1024],[0,1024],[0,0]]]]}
	var source := PackedFloat32Array();source.resize(67*67);source.fill(NAN)
	var combined := source.duplicate();combined.fill(-3.5)
	var provenance := PackedByteArray();provenance.resize(67*67);provenance.fill(3)
	tile.samples=source;tile.combined=combined;tile.provenance=provenance
	store.manifest.nodes["0_0_0"]={"bytes":20000,"level":0};store.cache["0_0_0"]=tile
	var p := GeoPosition.new(500,500);var d := depth.get_depth_metadata(p)
	check(d.available and d.classification=="procedurally reconstructed" and d.depth==3.5,"Reconstruction queried and classified")
	check(depth.navigable(p),"Connected reconstructed water supports conservative navigation")
	provenance.fill(2);tile.provenance=provenance
	check(depth.get_depth_metadata(p).classification=="interpolated survey data","Survey interpolation classified")
	depth.corrections=[{"id":"test","easting":300500.0,"northing":3119500.0,"radius_m":20,"elevation_m":-2,"note":"test"}]
	check(depth.get_depth_metadata(p).classification=="manually corrected" and depth.get_depth_at(p)==2,"Manual correction wins")
	var routes := [{"a":[0,0],"b":[100,0],"length_m":100,"depth_m":3,"edges":[[],[[1,0]]]},{"a":[100,0],"b":[200,0],"length_m":100,"depth_m":3,"edges":[[[0,1]],[]]}]
	var before := OS.get_static_memory_usage();var start := Time.get_ticks_usec();var fish := FishPopulation.new();fish.configure({"routes":routes},100000)
	var init_ms := (Time.get_ticks_usec()-start)/1000.0;var memory := OS.get_static_memory_usage()-before
	check(fish.ids.size()==100000 and fish.ids[99999]==100000,"100k stable identities")
	fish.progress[0]=.9999;fish.direction[0]=1;fish.advance(0,2)
	check(fish.region[0]==1 and fish.east[0]>=100,"Cross connected region without teleport across land")
	start=Time.get_ticks_usec();var worst := 0.0
	for i in range(360): fish.tick(1.0/60,GeoPosition.new(50,0));worst=maxf(worst,fish.update_ms)
	var mean := (Time.get_ticks_usec()-start)/1000.0/360
	var save_path := "res://../.local/phase3-fish-test.dat";DirAccess.make_dir_recursive_absolute("res://../.local")
	check(fish.save_to(save_path)==OK,"Fish save succeeds")
	var clone := FishPopulation.new();clone.configure({"routes":routes},1)
	check(clone.load_from(save_path)==OK and clone.ids==fish.ids and clone.east==fish.east and clone.region==fish.region,"Fish identity / position / regions round-trip")
	var report := {"fish_count":100000,"initialization_ms":init_ms,"mean_update_ms":mean,"max_update_ms":worst,"packed_bytes":fish.packed_bytes(),"engine_memory_delta_bytes":memory,"failures":failures,"note":"360 simulation updates; two connected fixture routes, not full gameplay profiling"}
	var file := FileAccess.open("res://../docs/phase3-fish-test.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close();print(JSON.stringify(report));store.shutdown();quit(failures)
