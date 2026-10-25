extends SceneTree
var checks := 0
var failures := 0
func check(condition: bool, name: String):
	checks+=1
	if not condition:
		failures+=1;push_error("FAIL "+name)
func _initialize():
	call_deferred("run")
func run():
	var store := GeographyStore.new()
	var depth := DepthService.new(store)
	var values := PackedFloat32Array();values.resize(67*67);values.fill(-4)
	var tile := {"x":0,"y":0,"size":1024,"n":64,"samples":values,"used":0,"land":[],"coverage":[[[[0,0],[1024,0],[1024,1024],[0,1024],[0,0]]]]}
	store.manifest.nodes["0_0_0"]={"bytes":20000,"level":0}
	store.cache["0_0_0"]=tile
	var p := GeoPosition.new(500,500)
	check(depth.get_depth_at(p)==4,"bilinear depth")
	check(depth.get_elevation_at(p)==-4,"elevation sign")
	check(depth.get_depth_at(GeoPosition.new(-10000,-10000))==null,"missing stays null")
	values[32*67+32]=NAN;tile.samples=values
	check(depth.get_depth_at(p)==null,"NoData stencil")
	depth.corrections=[{"id":"test correction","easting":300500.0,"northing":3119500.0,"radius_m":20,"elevation_m":-2,"note":"TEST ONLY"}]
	check(depth.get_depth_metadata(p).quality=="manually corrected" and depth.get_depth_at(p)==2,"correction provenance")
	depth.corrections=[];values.fill(-4);tile.samples=values
	check(depth.get_depth_profile(p,GeoPosition.new(520,500),6).size()==5,"profile spacing/endpoints")
	check(depth.navigable(p),"known water navigable")
	tile.land=[[[[499,450],[501,450],[501,550],[499,550],[499,450]]]]
	check(not depth.navigable(p),"thin land barrier collision")
	tile.land=[[[[450,450],[550,450],[550,550],[450,550],[450,450]],[[470,470],[470,530],[530,530],[530,470],[470,470]]]]
	check(depth.navigable(p),"water hole remains water")
	check(not depth.navigable(GeoPosition.new(460,460)),"land around hole")
	tile.land=[]
	var boat := BoatModel.new(JSON.parse_string(FileAccess.get_file_as_string(store.root+"boat.json")))
	boat.geo=p.copy();boat.throttle=1
	for i in range(60): boat.step(1.0/60,depth)
	check(boat.speed>1 and boat.geo.south<500,"throttle accelerates in meters")
	var speed := boat.speed;boat.throttle=0;boat.step(1.0/60,depth)
	check(boat.speed>0 and boat.speed<speed,"momentum under neutral")
	tile.land=[[[[0,0],[1024,0],[1024,499],[0,499],[0,0]]]]
	boat.geo=p.copy();boat.speed=100;boat.step(0.1,depth)
	check(boat.blocked and boat.geo.south==500,"swept movement blocks tunneling")
	var geo := GeoPosition.new(87654.123456,92345.987654)
	var origin := GeoPosition.new(87040,92160)
	var local := geo.relative_to(origin)
	check(abs(local.x+origin.east-geo.east)<0.0001,"floating origin precision")
	check(GeoPosition.new(-0.1,1024).key(0,1024)=="0_-1_1","negative chunk floor")
	var scene := Node2D.new();root.add_child(scene)
	var cam := MapCamera.new();scene.add_child(cam);cam.setup(store.manifest)
	cam.geo=p.copy();cam.span=500;cam.target_span=20
	cam.cursor=Vector2(1300,600);cam.anchor=cam.world_at(cam.cursor)
	var anchor := cam.anchor.copy();cam.tick(0.2,boat,origin)
	check(cam.world_at(cam.cursor).relative_to(anchor).length()<0.001,"free zoom cursor anchor")
	scene.queue_free();store.shutdown()
	print("RUNTIME TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
