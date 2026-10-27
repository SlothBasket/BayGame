extends SceneTree
var zones: Dictionary
var config: Dictionary
var habitats: Dictionary
const ROOT := "res://assets/generated/"
func _initialize(): call_deferred("run")
func load_population(path: String) -> FishPopulation:
	var p := FishPopulation.new();p.configure(zones,42)
	if p.load_from(path)!=OK or not p.setup_ecology(config,habitats) or not p.setup_movement(ROOT) or not p.setup_food_web(ROOT): push_error("restore failed");quit(1)
	return p
func drain(p: FishPopulation,boat: GeoPosition):
	var guard := 0
	while (p.time_debt>.00001 or p.sim_phase>=0) and guard<20000:
		p.tick_ecosystem(0,boat);guard+=1
	if guard>=20000: push_error("scheduler failed to drain");quit(1)
func run():
	zones=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"bay-population-zones.json"));config=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"ecosystem-config.json"));habitats=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"bay-habitats.json"))
	var original := FishPopulation.new();original.configure(zones,42);original.setup_ecology(config,habitats);original.setup_movement(ROOT);original.setup_food_web(ROOT)
	original.time_debt=2;var file := "res://../.local/world-schedule-fixture.dat";original.save_to(file);original.dispose()
	var a := load_population(file);var b := load_population(file)
	a.simulation_budget_us=100;b.simulation_budget_us=5000;a.observed_fish=0;b.observed_fish=41
	# Save and restore partway through the same deterministic world step.
	a.tick_ecosystem(0,GeoPosition.new(0,0));a.save_to(file);a.dispose();a=load_population(file);a.simulation_budget_us=100
	drain(a,GeoPosition.new(0,0));drain(b,GeoPosition.new(90000,90000))
	if a.completed_steps!=4 or b.completed_steps!=4 or a.east!=b.east or a.south!=b.south or a.hunger!=b.hunger or a.rng.state!=b.rng.state:
		push_error("budget/observation/save changed world outcomes");quit(1);return
	for i in range(a.ecology.forage.size()):
		if a.ecology.forage[i].x!=b.ecology.forage[i].x or a.ecology.forage[i].quantity!=b.ecology.forage[i].quantity:
			push_error("prey diverged");quit(1);return
	a.dispose();b.dispose();print("PASS: all queued time processed; identical fish/prey outcomes across frame budgets, boat/selection positions and mid-step save/load.");quit()
