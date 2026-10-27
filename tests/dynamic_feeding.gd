extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var root := "res://assets/generated/"
	var zones: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(root+"bay-population-zones.json"))
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(root+"ecosystem-config.json"))
	var habitat: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(root+"bay-habitats.json"))
	var p := FishPopulation.new();p.configure(zones,42);p.setup_ecology(config,habitat)
	if not p.setup_movement(root) or not p.setup_food_web(root): fail("setup");return
	var actor := 3;var s: Dictionary=p.hunting.states[actor];var bottom: Dictionary=p.food_web.bottom[0]
	var quantity: float=bottom.quantity;p.hunger[actor]=.8
	p.east[actor]=bottom.x+200;p.south[actor]=bottom.y;s.stage=FishHunting.Stage.STRIKE;s.kind=2;s.target=0;s.until=0
	p.hunting.step(actor,1)
	if bottom.quantity!=quantity or p.hunger[actor]<.8 or s.stage!=FishHunting.Stage.MISS: fail("remote feeding occurred");return
	var before: float=p.hunger[actor];p.ecology.interact(actor,600)
	if p.hunger[actor]!=before: fail("zone feeding remains");return
	p.east[actor]=bottom.x;p.south[actor]=bottom.y
	for attempt in range(12):
		s.stage=FishHunting.Stage.STRIKE;s.until=0;s.energy=1;p.hunting.step(actor,.1)
		if s.stage==FishHunting.Stage.CAPTURE: break
	if s.stage!=FishHunting.Stage.CAPTURE or not is_equal_approx(quantity-bottom.quantity,1): fail("physical capture / stock debit");return
	before=p.hunger[actor];p.hunting.step(actor,.1);p.elapsed+=10;p.hunting.step(actor,10)
	if p.hunger[actor]>=before or s.stage!=FishHunting.Stage.RECOVER: fail("consume/recovery");return
	before=bottom.quantity;p.hunting.step(actor,.1)
	if bottom.quantity!=before: fail("recovery bypass");return
	var a: Dictionary=p.ecology.forage[0];a.quantity=64;a.capacity=80;a.fear=1;a.split_after=0;p.elapsed=1000
	var original_count := p.ecology.forage.size();p.food_web.update_bait(0,0)
	if p.ecology.forage.size()!=original_count+1 or not is_equal_approx(a.quantity+p.ecology.forage[-1].quantity,64): fail("split conservation");return
	var child: Dictionary=p.ecology.forage[-1];a.fear=0;child.fear=0;a.merge_after=0;child.merge_after=0;p.food_web.threats.clear()
	p.food_web.update_bait(p.ecology.forage.size()-1,0)
	if child.active or not is_equal_approx(a.quantity,64): fail("merge conservation / identity tombstone");return
	var path := "res://../.local/dynamic-feeding-fixture.dat"
	if p.save_to(path)!=OK: fail("save");return
	var restored := FishPopulation.new();restored.configure(zones,42)
	if restored.load_from(path)!=OK or not restored.setup_ecology(config,habitat) or not restored.setup_movement(root) or not restored.setup_food_web(root): fail("restore");return
	if p.ids!=restored.ids or p.size_cm!=restored.size_cm or restored.hunting.states[actor].stage!=s.stage or restored.food_web.bottom[0].quantity!=bottom.quantity or restored.ecology.forage[-1].active: fail("persistent identities / food / hunt state");return
	p.dispose();restored.dispose();print("PASS: no remote/zone feeding; contact capture debits prey; consumption/recovery; split/merge conservation; identity and food-web save/load.");quit()
func fail(message: String):
	push_error(message);quit(1)
