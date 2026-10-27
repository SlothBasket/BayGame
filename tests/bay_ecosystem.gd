extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1;push_error(message)
func _initialize(): call_deferred("run")
func run():
	var zones := [{"id":"a","x":0.0,"y":0.0,"depth_m":2.0,"food_capacity":.5,"neighbors":[1,2]},{"id":"b","x":100.0,"y":0.0,"depth_m":2.0,"food_capacity":.8,"neighbors":[0]},{"id":"c","x":0.0,"y":100.0,"depth_m":10.0,"food_capacity":.5,"neighbors":[0]}]
	zones=JSON.parse_string(JSON.stringify(zones))
	var fish := FishPopulation.new();fish.configure({"zones":zones},20)
	fish.region[0]=0;fish.east[0]=0;fish.south[0]=0;fish.preferred_depth[0]=2;fish.hunger[0]=.95;fish.food=PackedFloat32Array([0,1,0])
	var food_choices := 0;var alternatives := 0
	for i in range(1000):
		fish.destination[0]=-1;fish.choose_destination(0)
		if fish.destination[0]==1: food_choices+=1
		else: alternatives+=1
	check(food_choices>700 and alternatives>0,"Hungry fish favor food without deterministic destination choice")
	check(fish.suitability(0,1)>fish.suitability(0,2),"Individual depth preference changes suitability")
	fish.destination[0]=1;fish.speed[0]=1;fish.update_fish(0,50)
	check(absf(fish.east[0]-50)<.01 and fish.south[0]==0,"Fish travels on verified neighbor corridor")
	fish.update_fish(0,50);check(fish.region[0]==1 and fish.destination[0]==-1,"Fish migrates between stable zones")
	fish.behavior[0]=2;fish.hunger[0]=.8;fish.food[1]=1;fish.decision_at[0]=10000;fish.update_fish(0,10)
	check(fish.hunger[0]<.8 and fish.food[1]<1,"Feeding consumes food and reduces hunger")
	# Reset fixture buckets after deliberately relocating a record directly above.
	fish.buckets={0:[],1:[],2:[]}
	for i in range(fish.ids.size()): fish.buckets[fish.region[i]].append(i)
	var path := "res://../.local/bay-ecosystem-test.dat"
	check(fish.save_to(path)==OK,"Save complete ecosystem state")
	var restored := FishPopulation.new();restored.configure({"zones":zones},1)
	check(restored.load_from(path)==OK,"Restore ecosystem state")
	check(restored.ids==fish.ids and restored.east==fish.east and restored.hunger==fish.hunger and restored.species==fish.species and restored.food==fish.food,"IDs, positions, species, hunger and food round-trip")
	for i in range(60): fish.tick(1.0/60,GeoPosition.new(99999,99999));restored.tick(1.0/60,GeoPosition.new(99999,99999))
	check(restored.east==fish.east and restored.destination==fish.destination and restored.hunger==fish.hunger,"Saved random state reproduces future movement after reload")
	var before := fish.ids.duplicate();fish.tick(1,GeoPosition.new(-99999,-99999));check(before==fish.ids,"Player relocation preserves identities")
	print("ECOSYSTEM TARGETED TESTS: ",failures," failures; food choices ",food_choices," / 1000, alternatives ",alternatives);quit(failures)
