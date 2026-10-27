class_name FishMovement
extends RefCounted
var p
var eco
var nav := FishNavigation.new()
var preferred_feed := PackedInt32Array()
var preferred_rest := PackedInt32Array()
var targets := PackedInt32Array()
var cursors := PackedInt32Array()
var headings := PackedVector2Array()
var routes: Array = []
var ready := false
func setup(population,root: String,saved: Dictionary) -> bool:
	p=population;eco=p.ecology
	if not nav.setup(root): return false
	var n: int=p.ids.size();preferred_feed.resize(n);preferred_rest.resize(n);targets.resize(n);targets.fill(-1);cursors.resize(n);headings.resize(n);routes.resize(n)
	for i in range(n): routes[i]=PackedVector2Array()
	if not saved.is_empty():
		if saved.get("fingerprint","")!=nav.fingerprint: return false
		for key in ["preferred_feed","preferred_rest","targets","cursors","headings","routes"]:
			if not saved.has(key) or saved[key].size()!=n: return false
		for i in range(n):
			if not nav.nodes.has(saved.preferred_feed[i]) or not nav.nodes.has(saved.preferred_rest[i]): return false
			if saved.targets[i]>=0 and not nav.nodes.has(saved.targets[i]): return false
			if saved.cursors[i]<0 or saved.cursors[i]>saved.routes[i].size(): return false
		for key in ["preferred_feed","preferred_rest","targets","cursors","headings","routes"]: set(key,saved[key])
	else:
		# Only locations/navigation migrate. Identity, size, home, routine phase and school stay intact.
		for i in range(n):
			var at := Vector2(p.east[i],p.south[i]);var anchor := nav.nearest(at)
			if anchor<0: anchor=nav.migration_anchor(at,int(p.region[i]))
			if anchor<0: return false
			var component: int=nav.nodes[anchor].component
			preferred_feed[i]=habitat(i,eco.feeding[i],component,int(p.ids[i]));preferred_rest[i]=habitat(i,eco.resting[i],component,int(p.ids[i])+17)
			if preferred_feed[i]<0: preferred_feed[i]=anchor
			if preferred_rest[i]<0: preferred_rest[i]=anchor
			var old_center := Vector2(p.zones[p.region[i]].x,p.zones[p.region[i]].y)
			if p.fresh_population or at.distance_to(old_center)<2 or not nav.wet(at) or nav.nearest(at)<0:
				var local := habitat(i,p.region[i],component,int(p.ids[i])+31)
				if local<0: local=anchor
				at=nav.offset(local,int(p.ids[i]),25.0);p.east[i]=at.x;p.south[i]=at.y
			p.destination[i]=-1;p.decision_at[i]=p.elapsed+float(i%23);update_region(i,nav.nodes[nav.nearest(at)].zone)
		for a in eco.forage+eco.predators:
			var at := Vector2(a.x,a.y);var anchor := nav.nearest(at)
			if anchor<0: anchor=nav.migration_anchor(at,int(a.zone))
			if anchor<0: return false
			var moved := nav.offset(anchor,int(a.id)+300,28)
			a.x=moved.x;a.y=moved.y;a.zone=nav.nodes[anchor].zone;a.destination=-1;a.erase("natural_path");a.next=p.elapsed+float(int(a.id)%30)
		eco.rebuild_forage_index()
	ready=true;return true
func habitat(i: int,zone: int,component: int,salt: int) -> int:
	var choices: Array=[]
	for z in [zone]+p.zones[zone].neighbors:
		for id in nav.zone_nodes[int(z)]:
			if nav.nodes.has(int(id)) and nav.nodes[int(id)].component==component: choices.append(int(id))
	var best := -1;var score := -INF
	for id in choices:
		var n: Dictionary=nav.nodes[id];var value := feature_score(i,id)
		value+=float(posmod(int(id)*97+salt*7919,1000))*.001
		value+=float(p.food[int(n.zone)])*p.hunger[i]-float(eco.pressure[int(n.zone)])*4
		if float(n.depth_m)+eco.tide_level_m<maxf(.2,p.size_cm[i]*.003): continue
		if n.zone!=zone: value-=1
		if value>score: score=value;best=id
	return best
func feature_score(i: int,id: int) -> float:
	var n: Dictionary=nav.nodes[id];var value := 0.0
	for tag in n.tags:
		if tag in eco.profile(i).habitats: value+=1.1
	value-=absf(float(n.depth_m)+eco.tide_level_m-p.preferred_depth[i])/maxf(1,p.preferred_depth[i])
	return value
func choose(i: int):
	var at := Vector2(p.east[i],p.south[i]);var anchor := nav.nearest(at)
	if anchor<0: p.decision_at[i]=p.elapsed+30;return
	var component: int=nav.nodes[anchor].component;var goal: int=preferred_feed[i] if eco.routine_goal(i)==eco.feeding[i] else preferred_rest[i]
	var candidate := habitat(i,p.region[i],component,int(p.ids[i])+int(p.elapsed/30))
	if candidate>=0 and (p.rng.randf()<.25 or eco.pressure[p.region[i]]>.35): goal=candidate
	# Schoolmates follow broad habitat goals, with their own offsets and routes.
	if eco.school[i]>=0 and eco.pressure[p.region[i]]<.3:
		for member in eco.schools.get(eco.school[i],[]):
			if member!=i and eco.alive[member]==1 and targets[member]>=0:
				goal=targets[member];break
	if eco.pressure[p.region[i]]>.35:
		var low: float=eco.pressure[int(nav.nodes[goal].zone)]
		for z in p.zones[p.region[i]].neighbors:
			var escape := habitat(i,z,component,int(p.ids[i]))
			if escape>=0 and eco.pressure[z]<low: goal=escape;low=eco.pressure[z]
	if not nav.nodes.has(goal) or nav.nodes[goal].component!=component: goal=anchor
	var radius := 12.0 if eco.profile(i).style in ["ambush","bottom_ambush"] else 45.0
	var target := nav.offset(goal,int(p.ids[i])+int(p.elapsed),radius)
	if p.hunger[i]>.4 and eco.profile(i).style in ["chase","hunt","travel"]:
		var nearest := 1200.0*1200.0
		for index in eco.forage_zones.get(int(p.region[i]),[]):
			var prey: Dictionary=eco.forage[index]
			if prey.quantity<=0 or not eco.edible(i,prey): continue
			var pos := Vector2(prey.x,prey.y);var distance := at.distance_squared_to(pos);var candidate_id := nav.nearest(pos)
			if distance<nearest and candidate_id>=0 and nav.nodes[candidate_id].component==component:
				nearest=distance;goal=candidate_id;target=pos
	var path := nav.route(at,target,goal)
	if path.is_empty(): p.decision_at[i]=p.elapsed+30;return
	targets[i]=goal;routes[i]=path;cursors[i]=1;p.destination[i]=int(nav.nodes[goal].zone)
	p.decisions+=1;eco.on_decision(i)
	p.behavior[i]=5 if eco.pressure[p.region[i]]>.35 else (4 if p.hunger[i]>.4 and eco.profile(i).style in ["chase","hunt","travel"] else 1)
func update_region(i: int,z: int):
	var old: int=p.region[i]
	if old==z: return
	if eco.alive[i]==1:
		p.buckets[old].erase(i);p.zone_counts[old]-=1;p.zone_species_counts[old][p.species[i]]-=1
		p.buckets[z].append(i);p.zone_counts[z]+=1;p.zone_species_counts[z][p.species[i]]+=1
	p.region[i]=z;p.migrations+=1
func advance(at: Vector2,path: PackedVector2Array,index: int,distance: float,seed_value: int,heading: Vector2,near: bool) -> Dictionary:
	var remaining := distance;var steps := 0
	while index<path.size() and remaining>0 and steps<96:
		steps+=1;var delta := path[index]-at;var length := delta.length()
		if length<2: index+=1;continue
		var stride := minf(remaining,minf(length,12.0 if near else 48.0))
		var forward := delta.normalized();var side := Vector2(-forward.y,forward.x)
		var wave := sin(float(seed_value)*.71+float(p.elapsed)*.025+at.x*.004+at.y*.003)*.24
		var desired := (forward+side*wave*minf(1,length/20)).normalized()
		var direction := heading.normalized().lerp(desired,.45).normalized() if heading.length_squared()>.1 else desired
		if direction.dot(forward)<.5: direction=forward
		var next := at+direction*stride
		if not nav.clear(at,next): next=at+forward*stride
		if not nav.clear(at,next): break
		heading=(next-at).normalized();at=next;remaining-=stride
	return {"position":at,"cursor":index,"heading":heading}
func tick_fish(i: int,dt: float):
	if not ready or eco.alive[i]==0: return
	if routes[i].is_empty() or cursors[i]>=routes[i].size():
		if p.elapsed>=p.decision_at[i]: choose(i)
		else: eco.choose_state(i);return
	if routes[i].is_empty(): return
	var at := Vector2(p.east[i],p.south[i]);var velocity: float=p.speed[i]*(1.7 if p.behavior[i]==5 else 1.0)
	var near: bool=eco.near_zones.has(p.region[i]);var heading: Vector2=headings[i]
	var result := advance(at,routes[i],cursors[i],maxf(.05,velocity+eco.current.dot(heading))*dt,int(p.ids[i]),heading,near)
	var next: Vector2=result.position
	# Local separation is bounded to actual neighbors, never the entire population.
	if near and eco.school[i]>=0:
		var separation := Vector2.ZERO
		for other in eco.schools.get(eco.school[i],[]):
			if other==i or eco.alive[other]==0: continue
			var d := next-Vector2(p.east[other],p.south[other]);var spacing: float=5+p.size_cm[i]*.05
			if d.length()>0 and d.length()<spacing: separation+=d.normalized()*(spacing-d.length())*.15
		if separation.length()>0 and nav.clear(next,next+separation): next+=separation.limit_length(2)
	p.east[i]=next.x;p.south[i]=next.y;cursors[i]=result.cursor;headings[i]=result.heading
	var anchor := nav.nearest(next)
	if anchor>=0: update_region(i,nav.nodes[anchor].zone)
	if cursors[i]>=routes[i].size():
		p.destination[i]=-1;eco.on_arrival(i);eco.choose_state(i)
		p.decision_at[i]=maxf(p.decision_at[i],p.elapsed+p.rng.randf_range(15,90))
func plan_record(a: Dictionary,predator: bool):
	var at := Vector2(a.x,a.y);var anchor := nav.nearest(at)
	if anchor<0: return
	var zone: int=a.destination if a.destination>=0 else a.zone
	var goal := anchor;var score := -INF
	for z in [zone]+p.zones[zone].neighbors:
		for value in nav.zone_nodes[int(z)]:
			var id := int(value)
			if not nav.nodes.has(id) or nav.nodes[id].component!=nav.nodes[anchor].component: continue
			var n: Dictionary=nav.nodes[id];var v: float=p.food[int(n.zone)]-eco.pressure[int(n.zone)]*2+p.rng.randf()*.8
			if predator: v=float(p.zone_counts[int(n.zone)])*.12+p.rng.randf()
			elif a.kind in [0,2,3,4,5]: v+=1 if n.shore_m<180 else 0
			elif a.kind>=6: v+=1 if n.depth_m<3 else 0
			if v>score: score=v;goal=id
	var target := nav.offset(goal,int(a.id)+int(p.elapsed),35)
	if predator and a.kind!=2:
		var nearest := INF
		for z in [int(a.zone)]+p.zones[int(a.zone)].neighbors:
			for fish in p.buckets[int(z)]:
				if p.size_cm[fish]>=a.size_cm*.55: continue
				var prey := Vector2(p.east[fish],p.south[fish]);var distance := at.distance_squared_to(prey)
				if distance<nearest:
					var intercept: Vector2=prey+headings[fish]*p.speed[fish]*20
					var candidate := nav.nearest(intercept)
					if candidate>=0 and nav.nodes[candidate].component==nav.nodes[anchor].component:
						nearest=distance;goal=candidate;target=intercept if nav.clear(nav.point(goal),intercept) else nav.point(goal)
	var path := nav.route(at,target,goal)
	if path.is_empty(): a.destination=-1;return
	a.natural_path=path;a.path_cursor=1;a.heading=Vector2.ZERO;a.destination=nav.nodes[goal].zone;a.goal_feature=goal;a.replan_at=p.elapsed+30
func move_record(a: Dictionary,dt: float,velocity: float) -> bool:
	if not a.has("natural_path") or int(a.get("path_cursor",0))>=a.natural_path.size():
		if a.destination<0: return false
		plan_record(a,a.has("hunger"))
	if not a.has("natural_path"): return false
	if a.has("hunger") and a.hunger>.35 and p.elapsed>=float(a.get("replan_at",0)): plan_record(a,true)
	var result := advance(Vector2(a.x,a.y),a.natural_path,int(a.path_cursor),velocity*dt,int(a.id)+50000,a.get("heading",Vector2.ZERO),eco.near_zones.has(int(a.zone)))
	a.x=result.position.x;a.y=result.position.y;a.path_cursor=result.cursor;a.heading=result.heading
	var anchor := nav.nearest(result.position)
	if anchor>=0: a.zone=nav.nodes[anchor].zone
	if a.path_cursor>=a.natural_path.size(): a.destination=-1;a.erase("natural_path")
	return true
func serialize() -> Dictionary:
	return {"fingerprint":nav.fingerprint,"preferred_feed":preferred_feed,"preferred_rest":preferred_rest,"targets":targets,"cursors":cursors,"headings":headings,"routes":routes}
