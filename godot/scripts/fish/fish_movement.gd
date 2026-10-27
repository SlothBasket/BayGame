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
var last_error := ""
func fail(reason: String) -> bool:
	last_error=reason;return false
func setup(population,root: String,saved: Dictionary) -> bool:
	p=population;eco=p.ecology
	if not nav.setup(root): return fail("navigation asset or water mask invalid")
	var n: int=p.ids.size();preferred_feed.resize(n);preferred_rest.resize(n);targets.resize(n);targets.fill(-1);cursors.resize(n);headings.resize(n);routes.resize(n)
	for i in range(n): routes[i]=PackedVector2Array()
	if not saved.is_empty():
		if saved.get("fingerprint","")!=nav.fingerprint: return fail("saved navigation fingerprint differs from generated navigation")
		for key in ["preferred_feed","preferred_rest","targets","cursors","headings","routes"]:
			if not saved.has(key) or saved[key].size()!=n: return fail("saved movement array invalid: "+key)
		for i in range(n):
			if not nav.nodes.has(saved.preferred_feed[i]) or not nav.nodes.has(saved.preferred_rest[i]): return fail("saved habitat reference or migration anchor invalid")
			if saved.targets[i]>=0 and not nav.nodes.has(saved.targets[i]): return fail("saved habitat reference or migration anchor invalid")
			if saved.cursors[i]<0 or (not saved.routes[i].is_empty() and saved.cursors[i]>saved.routes[i].size()): return fail("invalid route cursor for fish #"+str(p.ids[i]))
		for key in ["preferred_feed","preferred_rest","targets","cursors","headings","routes"]: set(key,saved[key])
		# Canceled paths in older saves retained a harmless cursor. Preserve all fish data.
		cursors=cursors.duplicate()
		for i in range(n):
			if routes[i].is_empty(): cursors[i]=0
	else:
		# Only locations/navigation migrate. Identity, size, home, routine phase and school stay intact.
		for i in range(n):
			var at := Vector2(p.east[i],p.south[i]);var anchor := nav.nearest(at)
			if anchor<0: anchor=nav.migration_anchor(at,int(p.region[i]))
			if anchor<0: return fail("saved habitat reference or migration anchor invalid")
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
			if anchor<0: return fail("saved habitat reference or migration anchor invalid")
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
		value+=(p.food_web.productivity(int(n.zone)) if p.food_web!=null else float(p.food[int(n.zone)]))*p.hunger[i]-float(eco.pressure[int(n.zone)])*4
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
	if candidate>=0 and (p.rng.randf()<.25 or eco.pressure[p.region[i]]>.35 or (p.hunting!=null and p.hunting.states[i].search_failures>3) or (p.food_web!=null and p.food_web.productivity(int(nav.nodes[goal].zone))<.2)): goal=candidate
	# Schoolmates follow broad habitat goals, with their own offsets and routes.
	if eco.school[i]>=0 and eco.pressure[p.region[i]]<.3:
		for member in eco.schools.get(eco.school[i],[]):
			if eco.alive[member]==0: continue
			if member!=i and targets[member]>=0 and cursors[member]<routes[member].size(): goal=targets[member]
			break
	if eco.pressure[p.region[i]]>.35:
		var low: float=eco.pressure[int(nav.nodes[goal].zone)]
		for z in p.zones[p.region[i]].neighbors:
			var escape := habitat(i,z,component,int(p.ids[i]))
			if escape>=0 and eco.pressure[z]<low: goal=escape;low=eco.pressure[z]
	if not nav.nodes.has(goal) or nav.nodes[goal].component!=component: goal=anchor
	var radius := 12.0 if eco.profile(i).style in ["ambush","bottom_ambush"] else 45.0
	var target := nav.offset(goal,int(p.ids[i])+int(p.elapsed),radius)
	if p.food_web!=null and p.food_web.ready: target=p.food_web.feature_destination(goal,"feeding" if eco.routine_goal(i)==eco.feeding[i] else "resting",int(p.ids[i])+int(p.elapsed))
	var area_goal := nav.nearest(target)
	if area_goal>=0: goal=area_goal
	var path := nav.route(at,target,goal,"shoreline_edge" in eco.profile(i).habitats or "mangrove_edge_candidate" in eco.profile(i).habitats)
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
func advance(at: Vector2,path: PackedVector2Array,index: int,distance: float,seed_value: int,heading: Vector2,near: bool,arrival_radius := 2.0) -> Dictionary:
	var remaining := distance;var steps := 0
	while index<path.size() and remaining>0 and steps<96:
		steps+=1;var delta := path[index]-at;var length := delta.length()
		if length<arrival_radius: index+=1;continue
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
		else: return
	if routes[i].is_empty(): return
	var at := Vector2(p.east[i],p.south[i]);var velocity: float=p.speed[i]*(1.7 if p.behavior[i]==5 else 1.0)
	var near := true;var heading: Vector2=headings[i]
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
	if p.hunting!=null and p.hunting.ready:
		p.hunting.states[i].energy=maxf(0,p.hunting.states[i].energy-at.distance_to(next)*.0002)
	if next.distance_squared_to(at)<.0001 and cursors[i]<routes[i].size():
		routes[i]=PackedVector2Array();cursors[i]=0;p.destination[i]=-1;p.decision_at[i]=p.elapsed+1;return
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
	var path := nav.route(at,target,goal)
	if path.is_empty(): a.destination=-1;return
	a.natural_path=path;a.path_cursor=1;a.heading=Vector2.ZERO;a.destination=nav.nodes[goal].zone;a.goal_feature=goal;a.replan_at=p.elapsed+30
func move_record(a: Dictionary,dt: float,velocity: float) -> bool:
	if not a.has("natural_path") or int(a.get("path_cursor",0))>=a.natural_path.size():
		if a.destination<0: return false
		plan_record(a,a.has("pod"))
	if not a.has("natural_path"): return false
	if a.has("pod") and a.hunger>.35 and p.elapsed>=float(a.get("replan_at",0)): plan_record(a,true)
	var result := advance(Vector2(a.x,a.y),a.natural_path,int(a.path_cursor),velocity*dt,int(a.id)+50000,a.get("heading",Vector2.ZERO),true)
	a.x=result.position.x;a.y=result.position.y;a.path_cursor=result.cursor;a.heading=result.heading
	var anchor := nav.nearest(result.position)
	if anchor>=0: a.zone=nav.nodes[anchor].zone
	if a.path_cursor>=a.natural_path.size(): a.destination=-1;a.erase("natural_path")
	return true
func serialize() -> Dictionary:
	return {"fingerprint":nav.fingerprint,"preferred_feed":preferred_feed,"preferred_rest":preferred_rest,"targets":targets,"cursors":cursors,"headings":headings,"routes":routes}
