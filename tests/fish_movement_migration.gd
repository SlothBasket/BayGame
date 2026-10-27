extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var root := "res://assets/generated/"
	var zones: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(root+"bay-population-zones.json"))
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(root+"ecosystem-config.json"))
	var habitats: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(root+"bay-habitats.json"))
	var legacy := FishPopulation.new();legacy.configure(zones,42);legacy.setup_ecology(config,habitats)
	var path := "res://../.local/migration-fixture.dat"
	if legacy.save_to(path)!=OK: fail("fixture save");return
	var ids := legacy.ids.duplicate();var sizes := legacy.size_cm.duplicate();var homes := legacy.ecology.home.duplicate();var phases := legacy.ecology.phase.duplicate()
	var migrated := FishPopulation.new();migrated.configure(zones,42)
	if migrated.load_from(path)!=OK or not migrated.setup_ecology(config,habitats) or not migrated.setup_movement(root): fail("legacy load/migration");return
	if migrated.ids!=ids or migrated.size_cm!=sizes or migrated.ecology.home!=homes or migrated.ecology.phase!=phases: fail("identity/routine changed");return
	for i in range(42):
		migrated.movement.choose(i)
		var route: PackedVector2Array=migrated.movement.routes[i]
		if route.is_empty(): fail("missing route");return
		for n in range(1,route.size()):
			if not migrated.movement.nav.clear(route[n-1],route[n]): fail("unsafe migration route");return
	if migrated.save_to(path)!=OK or not FileAccess.file_exists(path+".before-natural-movement"): fail("migration backup/save");return
	var restored := FishPopulation.new();restored.configure(zones,42)
	if restored.load_from(path)!=OK or not restored.setup_ecology(config,habitats) or not restored.setup_movement(root): fail("version 4 restore");return
	if restored.ids!=ids or restored.size_cm!=sizes or restored.ecology.home!=homes or restored.ecology.phase!=phases or restored.east!=migrated.east or restored.movement.preferred_feed!=migrated.movement.preferred_feed: fail("round trip mismatch");return
	legacy.dispose();migrated.dispose();restored.dispose()
	print("PASS: 42 legacy IDs, sizes, homes, phases, migrated positions and preferred habitats retained; backup created; planned routes water-valid.");quit()
func fail(message: String):
	push_error(message);quit(1)
