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
	intervals=[.5,maxf(.5,float(config.get("intermediate_seconds",2))),maxf(.5,float(config.get("background_seconds",10)))]
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
		fish_levels[actor]=level(Vector2(p.east[actor],p.south[actor]),fish_levels[actor],actor==p.observed_fish or pursuing_selected)
		return fish_levels[actor]
	var a: Dictionary=p.ecology.predators[-actor-1]
	a.detail=level(Vector2(a.x,a.y),int(a.get("detail",2)),-actor-1==selected_predator or pursuing_selected)
	return int(a.detail)
func _measured_bait_level(index: int) -> int:
	var a: Dictionary=p.ecology.forage[index];var pinned: bool=index==p.food_web.observed_bait
	if p.observed_fish>=0:
		var s: Dictionary=p.hunting.state(p.observed_fish)
		pinned=pinned or (s.kind==0 and s.target==index and int(s.get("target_id",-1))==int(a.id))
	if selected_predator>=0:
		var s: Dictionary=p.hunting.state(-selected_predator-1)
		pinned=pinned or (s.kind==0 and s.target==index and int(s.get("target_id",-1))==int(a.id))
	a.detail=level(Vector2(a.x,a.y),int(a.get("detail",2)),pinned);return int(a.detail)
func coarse_hunt(actor: int,dt: float):
	var begin := Time.get_ticks_usec()
	_timed_coarse_hunt(actor,dt)
	p.diagnostics.add("Coarse hunt",Time.get_ticks_usec()-begin)
func _timed_coarse_hunt(actor: int,dt: float):
	var h=p.hunting;var s: Dictionary=h.state(actor);var r: Dictionary=h.profile(actor)
	# Finish already-earned meals; changing detail never creates or discards them.
	if s.stage in [6,8]: h.step(actor,dt);return
	if h.hunger(actor)<.35 or s.energy<.2:
		s.energy=minf(1,s.energy+dt*.015);s.activity="background resting";s.stage=9;return
	s.stage=0;s.kind=-1;s.target=-1;s.activity="background habitat patrol"
	var at: Vector2=h.position(actor)
	if p.elapsed>=float(s.get("coarse_plan_at",0)):
		s.coarse_plan_at=p.elapsed+90
		if s.has("coarse_route_goal"):
			var replacement: PackedVector2Array=p.movement.nav.route(at,s.coarse_route_target,int(s.coarse_route_goal))
			if not replacement.is_empty(): s.path=replacement;s.cursor=1;s.erase("coarse_route_goal");s.erase("coarse_route_target")
			elif p.movement.nav.route_pending: s.coarse_plan_at=p.elapsed+1
			else: s.erase("coarse_route_goal");s.erase("coarse_route_target")
		else: plan_coarse_route(actor,s,at)
	var velocity: float=float(r.cruise_mph)*.44704
	if not s.path.is_empty():
		var moved: Dictionary=p.movement.advance(at,s.path,int(s.cursor),velocity*dt,actor,s.heading,false)
		s.cursor=moved.cursor;s.heading=moved.heading;h.set_position(actor,moved.position,moved.heading);s.energy=maxf(0,s.energy-dt*.00015)
	if p.elapsed<float(s.get("coarse_encounter_at",0)): return
	s.coarse_encounter_at=p.elapsed+30
	# Aggregated distant encounter, charged against real records. No free zone nutrition.
	var encounter_begin := Time.get_ticks_usec()
	var checked := 0;var radius: float=minf(50,float(r.detect_ft)*.3048)
	for code in h.spatial.query(h.position(actor),radius):
		var kind := int(code)/FishSpatialIndex.STRIDE;var index := int(code)%FishSpatialIndex.STRIDE
		var prey: Dictionary=h.prey(kind,index)
		if not h.suitable(actor,kind,index,prey,r): continue
		if h.position(actor).distance_squared_to(prey.position)>radius*radius: continue
		# Selected prey and nearby detailed animals retain physical-contact rules.
		if kind==0 and bait_level(index)==0: continue
		if kind==1 and actor_level(index)==0: continue
		checked+=1
		if p.water_column.separation(actor,kind,index,prey)<maxf(1,h.length_cm(actor)*.015) and p.movement.nav.clear(h.position(actor),prey.position) and p.rng.randf()<.25*(1-float(prey.cover)):
			if kind==0:
				if not p.food_web.consume_bait(index): continue
			elif kind==1: p.ecology.consume_fish(index)
			else: p.food_web.bottom[index].quantity-=1;p.ecology.forage_consumed+=1
			h.set_hunger(actor,h.hunger(actor)-clampf(.1+float(prey.size)/h.length_cm(actor)*1.3,.1,.75));s.captures+=1;s.energy=maxf(0,s.energy-.025);s.last_event="background encounter consumed "+str(prey.label)
			if actor<0: p.ecology.predator_meals+=1
			break
		if checked>=12: break
	p.diagnostics.add("Coarse encounters",Time.get_ticks_usec()-encounter_begin)
func coarse_bait(index: int,dt: float):
	var diagnostic_begin := Time.get_ticks_usec()
	_measured_coarse_bait(index,dt)
	p.diagnostics.add("Bait coarse",Time.get_ticks_usec()-diagnostic_begin)
func _measured_coarse_bait(index: int,dt: float):
	var a: Dictionary=p.ecology.forage[index];var old_zone: int=a.zone
	a.hunger=minf(1,float(a.hunger)+dt*.00015);a.fear=maxf(0,float(a.fear)-dt*.01)
	var area: int=p.food_web.area_by_id.get(a.get("preferred_area",""),-1)
	if area>=0 and p.food_web.contains(area,Vector2(a.x,a.y)):
		var grazed: float=minf(p.food_web.nutrients[area],dt*.0004*a.hunger)
		p.food_web.nutrients[area]-=grazed;a.hunger=maxf(0,a.hunger-grazed*5)
	if p.food_web.return_escapee(index): return
	if p.elapsed>=float(a.next): p.food_web.plan_bait(a);a.next=p.elapsed+(1 if a.has("pending_route_target") else 90)
	var speed: float=.04 if a.kind in [4,5] else (.45 if a.kind>=6 else .3)
	if a.has("natural_path"):
		var moved: Dictionary=p.movement.advance(Vector2(a.x,a.y),a.natural_path,int(a.path_cursor),speed*dt,int(a.id),a.get("heading",Vector2.ZERO),false)
		a.x=moved.position.x;a.y=moved.position.y;a.heading=moved.heading;a.path_cursor=moved.cursor
		var node: int=p.movement.nav.nearest(moved.position)
		if node>=0: a.zone=p.movement.nav.nodes[node].zone
		if a.path_cursor>=a.natural_path.size(): a.destination=-1;a.erase("natural_path")
	if a.zone!=old_zone: p.ecology.forage_zones[old_zone].erase(index);p.ecology.forage_zones[int(a.zone)].append(index)
	p.water_column.update_bait(a,dt);a.activity="background forage / shelter"

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
