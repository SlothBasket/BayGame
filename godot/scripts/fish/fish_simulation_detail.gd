extends RefCounted
const NAMES := ["Detailed","Intermediate","Background"]
var p
var enabled := true
var boat := Vector2.ZERO
var camera := Vector2.ZERO
var detailed_m := 700.0
var intermediate_m := 2200.0
var hysteresis_m := 150.0
var intervals := [0.5,2.0,10.0]
var fish_levels := PackedByteArray()
var selected_predator := -1
var revision := 0
var prior_boat := Vector2.INF
var prior_camera := Vector2.INF
var prior_selection := Vector3i(-2,-2,-2)
var prior_enabled := true
func refresh_focus():
	var selection := Vector3i(p.observed_fish,p.food_web.observed_bait,selected_predator)
	if boat.distance_squared_to(prior_boat)>2500 or camera.distance_squared_to(prior_camera)>2500 or selection!=prior_selection or enabled!=prior_enabled:
		revision+=1;prior_boat=boat;prior_camera=camera;prior_selection=selection;prior_enabled=enabled

func setup(population):
	p=population;fish_levels.resize(p.ids.size());fish_levels.fill(2)
	var config: Dictionary=p.ecology.config.get("simulation_detail",{})
	enabled=bool(config.get("enabled",true));detailed_m=float(config.get("detailed_m",700));intermediate_m=maxf(detailed_m+100,float(config.get("intermediate_m",2200)));hysteresis_m=float(config.get("hysteresis_m",150))
	intervals=[.5,maxf(.5,float(config.get("intermediate_seconds",2))),maxf(10,float(config.get("background_event_seconds",30)))]
func level(at: Vector2,previous: int,pinned := false) -> int:
	if not enabled or pinned: return 0
	var distance := minf(at.distance_squared_to(boat),at.distance_squared_to(camera))
	if distance<=pow(detailed_m+(hysteresis_m if previous==0 else 0),2): return 0
	if distance<=pow(intermediate_m+(hysteresis_m if previous<2 else 0),2): return 1
	return 2
func _measured_actor_level(actor: int) -> int:
	var s: Dictionary=p.hunting.state(actor)
	var pursuing_selected: bool=s.kind==0 and int(s.target)==p.food_web.observed_bait and int(s.get("target_id",-1))==int(p.ecology.forage[s.target].id) if s.kind==0 and s.target>=0 and s.target<p.ecology.forage.size() else false
	if s.kind==1 and int(s.target)==p.observed_fish: pursuing_selected=true
	if actor>=0 and p.observed_fish>=0:
		var selected_hunt: Dictionary=p.hunting.state(p.observed_fish)
		pursuing_selected=pursuing_selected or (selected_hunt.kind==1 and selected_hunt.target==actor)
	if actor>=0 and selected_predator>=0:
		var selected_hunt: Dictionary=p.hunting.state(-selected_predator-1)
		pursuing_selected=pursuing_selected or (selected_hunt.kind==1 and selected_hunt.target==actor)
	if actor>=0:
		fish_levels[actor]=level(p.background.position(actor,p.elapsed),fish_levels[actor],actor==p.observed_fish or pursuing_selected)
		return fish_levels[actor]
	var a: Dictionary=p.ecology.predators[-actor-1]
	a.detail=level(p.background.position(2000000-actor-1,p.elapsed),int(a.get("detail",2)),-actor-1==selected_predator or pursuing_selected)
	return int(a.detail)
func _measured_bait_level(index: int) -> int:
	var a: Dictionary=p.ecology.forage[index];var pinned: bool=index==p.food_web.observed_bait
	if p.observed_fish>=0:
		var s: Dictionary=p.hunting.state(p.observed_fish)
		pinned=pinned or (s.kind==0 and s.target==index and int(s.get("target_id",-1))==int(a.id))
	if selected_predator>=0:
		var s: Dictionary=p.hunting.state(-selected_predator-1)
		pinned=pinned or (s.kind==0 and s.target==index and int(s.get("target_id",-1))==int(a.id))
	a.detail=level(p.background.position(1000000+index,p.elapsed),int(a.get("detail",2)),pinned);return int(a.detail)
func actor_level(actor: int) -> int:
	var begin := Time.get_ticks_usec()
	var result: int=_measured_actor_level(actor)
	p.diagnostics.add("Detail assignment",Time.get_ticks_usec()-begin)
	return result

func bait_level(index: int) -> int:
	var begin := Time.get_ticks_usec()
	var result: int=_measured_bait_level(index)
	p.diagnostics.add("Detail assignment",Time.get_ticks_usec()-begin)
	return result

func plan_coarse_route(actor: int,s: Dictionary,at: Vector2):
	var h=p.hunting
	var node: int=p.movement.nav.nearest(at)
	if node>=0:
		var goal: Vector2=p.food_web.feature_destination(node,"resting" if p.ecology.pressure[h.zone(actor)]>.35 else "feeding",actor+int(p.elapsed/90))
		var destination: int=p.movement.nav.nearest(goal)
		if destination>=0:
			var replacement: PackedVector2Array=p.movement.nav.route(at,goal,destination)
			if not replacement.is_empty(): s.path=replacement;s.cursor=1
			elif p.movement.nav.route_pending: s.coarse_plan_at=p.elapsed+1;s.coarse_route_goal=destination;s.coarse_route_target=goal
