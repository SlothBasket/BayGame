extends SceneTree
func _initialize():
	var _settings := GameSettings.new(false)
	var s:=GeographyStore.new()
	for x in range(39,43):
		for y in range(51,55):
			var key:="0_%d_%d"%[x,y];s._install(key,s._read(key))
	var d:=DepthService.new(s)
	var boat:=BoatModel.new(JSON.parse_string(FileAccess.get_file_as_string(s.root+"boat.json")))
	boat.geo=GeoPosition.new(42014,54322);boat.speed=12;boat.heading=-PI/4;boat.throttle=0.7
	var failures := 0
	for i in range(480):
		boat.step(1.0/60,d)
		if boat.blocked:failures+=1;print("blocked ",i," ",boat.geo.east," ",boat.geo.south," reason ",d.navigation_reason);break
	print("finish ",boat.geo.east," ",boat.geo.south)
	s.shutdown();print("REAL SEAM REGRESSION: ",failures," failures");quit(1 if failures else 0)
