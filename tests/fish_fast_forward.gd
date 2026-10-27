extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var p := FishPopulation.new();var assets := "res://assets/generated/"
	p.configure(JSON.parse_string(FileAccess.get_file_as_string(assets+"bay-population-zones.json")),42)
	assert(p.setup_ecology(JSON.parse_string(FileAccess.get_file_as_string(assets+"ecosystem-config.json")),JSON.parse_string(FileAccess.get_file_as_string(assets+"bay-habitats.json"))))
	assert(p.setup_movement(assets));assert(p.setup_food_web(assets));p.startup_ready=true
	var h=p.hunting;var s: Dictionary=h.states[0]
	p.hunger[0]=.9;s.stage=FishHunting.Stage.CONSUME;s.until=p.elapsed;s.meal=.5;s.prey_cm=4
	h.step(0,.5);assert(is_equal_approx(p.hunger[0],.4));assert(s.stage==FishHunting.Stage.SEARCH)
	s.stage=FishHunting.Stage.RECOVER;s.energy=.3;var before_energy: float=s.energy;h.step(0,.5);assert(s.energy>before_energy)
	# Legacy hunts lack deadline fields. An expired hunt must release the target.
	s.stage=FishHunting.Stage.APPROACH;s.kind=0;s.target=0;s.hunt_until=p.elapsed-1;s.energy=1;p.ecology.pressure.fill(0)
	h.step(0,.5);assert(s.stage==FishHunting.Stage.SEARCH)
	# A distant school cannot be consumed, even if an attack was already in STRIKE.
	p.ecology.forage[0].x=p.east[0]+100;p.ecology.forage[0].y=p.south[0]
	s.stage=FishHunting.Stage.STRIKE;s.kind=0;s.target=0;s.until=p.elapsed;p.hunger[0]=.9;s.energy=1
	var prey_count: float=p.ecology.forage[0].quantity
	h.step(0,.5);assert(s.stage==FishHunting.Stage.MISS);assert(p.ecology.forage[0].quantity==prey_count)
	s.until=p.elapsed;h.step(0,.5);assert(s.stage==FishHunting.Stage.SEARCH)
	var prey_data: Dictionary=h.prey(0,0);var member: Vector2=h.prey_position(0,0,0,prey_data)
	assert(member.distance_to(prey_data.position)<=h.school_radius(0)+.001)
	assert(h.nav.clear(prey_data.position,member) or member==prey_data.position)
	var ids := p.ids.duplicate();p.time_debt=2;p.pause_simulation();p.tick_ecosystem(1,GeoPosition.new());assert(p.time_debt==2)
	p.time_debt=0;p.simulate_ahead(1.0/3600);var before := p.completed_steps
	for i in range(1000):
		p.tick_ecosystem(.016,GeoPosition.new())
		if not p.ahead_active: break
	assert(not p.ahead_active);assert(p.completed_steps-before==2);assert(p.time_scale==0);assert(p.ids==ids)
	p.fast_forward=true;p.max_throughput=true;before=p.completed_steps
	for i in range(100):
		p.tick_ecosystem(.016,GeoPosition.new())
		if p.completed_steps>before: break
	assert(p.completed_steps>before)
	p.simulate_ahead(2);p.pause_simulation();var queued := p.time_debt
	var path := "res://../.local/fast-forward-fixture.dat";assert(p.save_to(path)==OK)
	var restored := FishPopulation.new();assert(restored.initialize(assets,path));assert(restored.ids==ids);assert(restored.ahead_active);assert(restored.time_debt==queued);assert(restored.time_scale==0)
	p.dispose();restored.dispose();print("PASS: meal satisfaction, energy recovery, expired target release, pause retains debt, exact ahead steps, Max advances, paused queued work round-trips with identities");quit()
