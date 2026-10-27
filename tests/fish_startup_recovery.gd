extends SceneTree
func _initialize():
	call_deferred("check")
func check():
	# Supply an existing ecosystem save; it is read only. All writes use a scratch fixture.
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): push_error("Pass a save path after --");quit(1);return
	var path: String=args[0]
	var before := FileAccess.get_sha256(path)
	var f := FileAccess.open(path,FileAccess.READ);var d: Dictionary=f.get_var(false);f.close()
	var p := FishPopulation.new()
	assert(p.initialize("res://assets/generated/",path),p.startup_error)
	for key in ["ids","size_cm","east","south"]: assert(p.get(key)==d[key],key+" changed")
	for key in ["home","feeding","resting","phase"]:
		if d.ecology.has(key): assert(p.ecology.get(key)==d.ecology[key],key+" changed")
	for i in range(p.ids.size()):
		if p.movement.routes[i].is_empty(): assert(p.movement.cursors[i]==0)
	print("INITIALIZATION PASS: ",p.ids.size()," fish; bait=",p.ecology.forage.size()," predators=",p.ecology.predators.size()," habitat areas=",p.food_web.areas.size())
	var game := Node2D.new();game.set_script(load("res://scripts/main.gd"))
	game.fish=p;game.camera=MapCamera.new();game.camera.geo=GeoPosition.new(26000,65000);game.camera.span=2000
	var overlay := FishDebugOverlay.new();root.add_child(overlay);overlay.setup(game);overlay.toggle()
	overlay.cache_view();overlay.refresh();overlay.select_entity(1,0);overlay.selected_position();overlay.hunt_text(0)
	for component in ["ecology","movement","food_web","hunting"]:
		var saved=p.get(component);p.set(component,null)
		for repeat in range(2):
			overlay.tick(.3);overlay._draw();overlay.select_at(GeoPosition.new(),1);overlay.find_hunt();overlay.select_entity(1,0);overlay.selected_position();overlay.refresh();overlay.selected_paths(Vector2.ZERO,1);overlay.set_speed(1)
		assert(overlay.diagnostic_shown.contains(component.replace("_"," ")))
		p.set(component,saved)
		if component!="ecology":
			saved.ready=false;overlay.tick(.3);overlay.select_at(GeoPosition.new(),1);assert(not overlay.available());saved.ready=true
		else:
			p.ecology_ready=false;overlay.tick(.3);assert(not overlay.available());p.ecology_ready=true
	assert(overlay.available());overlay.cache_view();overlay.refresh()
	game.fish=null;overlay.tick(.3);overlay._draw();overlay.select_entity(1,0)
	game.fish=p
	print("PARTIAL COMPONENT GUARDS PASS")
	overlay.queue_free();game.camera.free();game.fish=null;game.free();p.dispose()
	var scratch := "res://../.local/incompatible-fish-fixture.dat"
	d.ecology.movement.fingerprint="incompatible-test"
	f=FileAccess.open(scratch,FileAccess.WRITE);f.store_var(d);f.close()
	var scratch_hash := FileAccess.get_sha256(scratch)
	p=FishPopulation.new();assert(not p.initialize("res://assets/generated/",scratch));assert(p.startup_error.contains("fingerprint"));assert(p.save_to(scratch)==ERR_UNAVAILABLE);assert(FileAccess.get_sha256(scratch)==scratch_hash);p.dispose()
	assert(FileAccess.get_sha256(path)==before)
	print("SAVE PROTECTION PASS; original save unchanged")
	quit()

