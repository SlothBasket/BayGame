class_name FishEcology
extends RefCounted
# Persistent individual routines over the existing water graph. No render dependencies.
var population
var config: Dictionary = {}
var habitats: Array = []
var home := PackedInt32Array()
var feeding := PackedInt32Array()
var resting := PackedInt32Array()
var phase := PackedFloat32Array()
var boldness := PackedFloat32Array()
var school := PackedInt32Array()
var alive := PackedByteArray()
var spot := PackedInt32Array()
var returning := PackedByteArray()
var schools: Dictionary = {}
var ranges: Dictionary = {}
var paths: Dictionary = {}
var tide_level_m := 0.0
var current := Vector2.ZERO
var routine_cycles := 0
var returns := 0
var pressure := PackedFloat32Array()
var near_zones: Dictionary = {}
func setup(p,settings: Dictionary,habitat_data: Dictionary):
	population=p;config=settings
	habitats=habitat_data.get("habitats",[])
	if habitats.size()!=p.zones.size():
		habitats=[]
		for z in p.zones: habitats.append({"tags":["open_water"],"spots":[{"x":z.x,"y":z.y,"depth_m":z.depth_m},{"x":z.x,"y":z.y,"depth_m":z.depth_m},{"x":z.x,"y":z.y,"depth_m":z.depth_m}]})
	tide_level_m=float(config.get("tide_level_m",0));var c: Array=config.get("current_mps",[0,0]);current=Vector2(c[0],c[1])
	pressure.resize(p.zones.size());pressure.fill(0)
	initialize_individuals()
func profile(i: int) -> Dictionary:
	return config.species[population.species[i]]
func local_range(z: int,radius: int) -> Array:
	var key := Vector2i(z,radius)
	if ranges.has(key): return ranges[key]
	var seen: Dictionary={z:0};var queue: Array=[z];var head := 0
	while head<queue.size():
		var a: int=queue[head];head+=1
		if seen[a]>=radius: continue
		for b in population.zones[a].neighbors:
			if not seen.has(b): seen[b]=seen[a]+1;queue.append(b)
	ranges[key]=queue;return queue
func initialize_individuals():
	var p=population;var n: int=p.ids.size()
	home.resize(n);feeding.resize(n);resting.resize(n);phase.resize(n);boldness.resize(n);school.resize(n);alive.resize(n);spot.resize(n);returning.resize(n)
	school.fill(-1);alive.fill(1);spot.fill(-1);returning.fill(0);schools.clear()
	for i in range(n):
		home[i]=p.region[i];phase[i]=p.rng.randf()*7200;boldness[i]=p.rng.randf_range(.15,.9)
		var area: Array=local_range(home[i],int(profile(i).home_radius_hops))
		feeding[i]=area[p.rng.randi_range(0,area.size()-1)];resting[i]=home[i]
		for trial in range(4):
			var candidate: int=area[p.rng.randi_range(0,area.size()-1)]
			if affinity(i,candidate)>affinity(i,feeding[i]): feeding[i]=candidate
		# Schools share a small home range and size band; membership/leader IDs persist.
		var chance: float=profile(i).school_probability
		if p.species[i]==0: chance=.8 if p.size_cm[i]<45 else .2
		if p.rng.randf()<chance:
			var key: int=(home[i]*7+int(p.species[i]))*5+mini(4,int(p.size_cm[i]/40))
			for neighbor_home in local_range(home[i],2):
				var candidate_key: int=(neighbor_home*7+int(p.species[i]))*5+mini(4,int(p.size_cm[i]/40))
				if schools.has(candidate_key) and schools[candidate_key].size()<12:
					key=candidate_key;var leader: int=schools[key][0];home[i]=home[leader];feeding[i]=feeding[leader];resting[i]=resting[leader];break
			school[i]=key
			if not schools.has(key): schools[key]=[]
			schools[key].append(i)
func affinity(i: int,z: int) -> float:
	var value := 0.0
	for tag in habitats[z].tags:
		if tag in profile(i).habitats: value+=.65
	return value+population.suitability(i,z)
func depth_at(z: int) -> float:
	return float(population.zones[z].depth_m)+tide_level_m
func accessible(i: int,z: int) -> bool:
	return depth_at(z)>maxf(.15,population.size_cm[i]*.003)
func distance_to(target: int) -> PackedInt32Array:
	if paths.has(target): return paths[target]
	var distances := PackedInt32Array();distances.resize(population.zones.size());distances.fill(99999);distances[target]=0
	var queue: Array[int]=[target];var head := 0
	while head<queue.size():
		var z: int=queue[head];head+=1
		for neighbor in population.zones[z].neighbors:
			if distances[neighbor]!=99999: continue
			distances[neighbor]=distances[z]+1;queue.append(neighbor)
	if paths.size()>=128: paths.erase(paths.keys()[0])
	paths[target]=distances;return distances
func routine_goal(i: int) -> int:
	# Four phases per two-hour individual cycle, with hunger overriding the clock.
	var p=population;var cycle: int=int((p.elapsed+phase[i])/1800.0)%4
	if p.hunger[i]>.65 or cycle==1 or cycle==2: return feeding[i]
	return resting[i]
func destination_score(i: int,z: int) -> float:
	if not accessible(i,z): return -100.0
	var p=population;var goal := routine_goal(i);var distances := distance_to(goal)
	var score := affinity(i,z)-minf(10,distances[z])*.7-pressure[z]*(4.0-2.0*boldness[i])
	if not z in local_range(home[i],int(profile(i).home_radius_hops)): score-=2
	if school[i]>=0 and pressure[p.region[i]]<.3:
		var members: Array=schools.get(school[i],[])
		if members.size()>1:
			var leader: int=members[0]
			if alive[leader]==1 and leader!=i:
				var target: int=p.destination[leader] if p.destination[leader]>=0 else p.region[leader]
				if z==target: score+=1.8
	return score
func choose_state(i: int):
	var p=population;var z: int=p.region[i]
	if pressure[z]>.35 or not accessible(i,z): p.behavior[i]=5;return
	if p.destination[i]>=0: p.behavior[i]=1;return
	var style: String=profile(i).style
	if p.hunger[i]<.3 and routine_goal(i)==resting[i]: p.behavior[i]=0
	elif p.hunger[i]>.3:
		p.behavior[i]=4 if style in ["ambush","bottom_ambush","chase","hunt","travel"] else 2
	else: p.behavior[i]=3
	var next_spot := 0 if p.behavior[i]==0 else (2 if p.behavior[i]==4 else 1)
	if spot[i]!=next_spot: returning[i]=1;spot[i]=next_spot
func move_local(i: int,dt: float) -> bool:
	var p=population
	if p.destination[i]>=0: return false
	var z: int=p.region[i];var target: Dictionary=population.zones[z]
	# Always return via the zone center before choosing another corridor/spot.
	if p.elapsed<p.decision_at[i] and returning[i]==0 and spot[i]>=0: target=habitats[z].spots[spot[i]]
	var delta := Vector2(float(target.x)-p.east[i],float(target.y)-p.south[i]);var distance := delta.length()
	if distance<.5:
		if returning[i]==1: returning[i]=0
		return false
	var travel: float=minf(distance,p.speed[i]*dt)
	var offset := delta/distance*travel;p.east[i]+=offset.x;p.south[i]+=offset.y
	return true
func on_decision(i: int):
	choose_state(i)
	func on_arrival(i: int):
	if population.region[i]==routine_goal(i): returns+=1
func is_alive(i: int) -> bool:
	return alive[i]==1
func serialize() -> Dictionary:
	return {"home":home,"feeding":feeding,"resting":resting,"phase":phase,"boldness":boldness,"school":school,"alive":alive,"spot":spot,"returning":returning,"tide_level_m":tide_level_m,"current":current,"returns":returns}
func restore(d: Dictionary) -> bool:
	var count: int=population.ids.size()
	for key in ["home","feeding","resting","phase","boldness","school","alive","spot","returning"]:
		if not d.has(key) or d[key].size()!=count: return false
	for i in range(count):
		for key in ["home","feeding","resting"]:
			if d[key][i]<0 or d[key][i]>=population.zones.size(): return false
		if d.spot[i]<-1 or d.spot[i]>2: return false
	for key in ["home","feeding","resting","phase","boldness","school","alive","spot","returning"]: set(key,d[key])
	tide_level_m=d.get("tide_level_m",0);current=d.get("current",Vector2.ZERO);returns=d.get("returns",0);schools.clear()
	for i in range(count):
		if school[i]<0: continue
		if not schools.has(school[i]): schools[school[i]]=[]
		schools[school[i]].append(i)
	return true
func describe(i: int) -> String:
	return "Home %s · school %s\nRoutine: %s → %s\nSpot: %s · %s" % [population.zones[home[i]].id,str(school[i]) if school[i]>=0 else "solo",population.zones[resting[i]].id,population.zones[feeding[i]].id,["rest","feed","hunt"][maxi(0,spot[i])],"alive" if alive[i]==1 else "consumed"]
