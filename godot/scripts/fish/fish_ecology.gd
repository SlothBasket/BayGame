class_name FishEcology
extends RefCounted
# Persistent individual routines over the existing water graph. No render dependencies.
var population
var pending_movement: Dictionary = {}
var pending_food_web: Dictionary = {}
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
const FORAGE_NAMES := ["Fry pod","Scaled sardines","Mojarra","Pinfish","Shrimp","Crabs","Small mullet","Large mullet"]
const FORAGE_SIZES := [1.5,8.0,7.0,10.0,4.0,6.0,12.0,35.0]
const PREDATOR_NAMES := ["Bull shark","Blacktip shark","Bonnethead shark","Bottlenose dolphin"]
var forage: Array = []
var predators: Array = []
var forage_zones: Dictionary = {}
var forage_cursor := 0
var predator_clock := 0.0
var forage_consumed := 0.0
var game_fish_consumed := 0
var predator_meals := 0
var jumps := 0
var pressure_clock := 0.0
var predator_ratio := .01
func setup(p,settings: Dictionary,habitat_data: Dictionary):
	population=p;config=settings
	habitats=habitat_data.get("habitats",[])
	if habitats.size()!=p.zones.size():
		habitats=[]
		for z in p.zones: habitats.append({"tags":["open_water"],"spots":[{"x":z.x,"y":z.y,"depth_m":z.depth_m},{"x":z.x,"y":z.y,"depth_m":z.depth_m},{"x":z.x,"y":z.y,"depth_m":z.depth_m}]})
	tide_level_m=float(config.get("tide_level_m",0));var c: Array=config.get("current_mps",[0,0]);current=Vector2(c[0],c[1])
	pressure.resize(p.zones.size());pressure.fill(0)
	initialize_individuals()
	initialize_food_web()
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
			for member in members:
				if alive[member]==1: leader=member;break
			if alive[leader]==1 and leader!=i:
				var target: int=p.destination[leader] if p.destination[leader]>=0 else p.region[leader]
				if z==target: score+=1.8
	var style: String=profile(i).style
	if z==p.region[i] and style in ["ambush","bottom_ambush","graze"] and prey_available(i,z)>5: score+=1.3
	if z!=p.region[i] and style in ["chase","travel"]: score+=.8
	return score+minf(1.5,prey_available(i,z)*.02)*p.hunger[i]
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
	var intervals: Dictionary={"ambush":Vector2(150,360),"bottom_ambush":Vector2(240,600),"chase":Vector2(15,50),"travel":Vector2(30,70),"graze":Vector2(90,240)}
	var interval: Vector2=intervals.get(profile(i).style,Vector2(45,150))
	if population.behavior[i]==5: interval=Vector2(5,15)
	population.decision_at[i]=population.elapsed+population.rng.randf_range(interval.x,interval.y)
func on_arrival(i: int):
	if population.movement!=null and population.movement.ready:
		if population.movement.targets[i] in [population.movement.preferred_feed[i],population.movement.preferred_rest[i]]: returns+=1
	elif population.region[i]==routine_goal(i): returns+=1
func is_alive(i: int) -> bool:
	return alive[i]==1
func serialize() -> Dictionary:
	return {"food_web":population.food_web.serialize() if population.food_web!=null and population.food_web.ready else {},"movement":population.movement.serialize() if population.movement!=null and population.movement.ready else {},"food_web_version":1,"forage":forage,"predators":predators,"pressure":pressure,"forage_cursor":forage_cursor,"predator_clock":predator_clock,"forage_consumed":forage_consumed,"game_fish_consumed":game_fish_consumed,"predator_meals":predator_meals,"jumps":jumps,"predator_ratio":predator_ratio,"home":home,"feeding":feeding,"resting":resting,"phase":phase,"boldness":boldness,"school":school,"alive":alive,"spot":spot,"returning":returning,"tide_level_m":tide_level_m,"current":current,"returns":returns}
func restore(d: Dictionary) -> bool:
	pending_movement=d.get("movement",{})
	pending_food_web=d.get("food_web",{})
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
	if d.has("food_web_version"):
		if not d.get("forage") is Array or not d.get("predators") is Array: return false
		for records in [d.forage,d.predators]:
			for a in records:
				if not a is Dictionary: return false
				for key in ["id","zone","destination","x","y","last","next"]:
					if not a.has(key): return false
				if a.zone<0 or a.zone>=population.zones.size() or a.destination < -1 or a.destination>=population.zones.size(): return false
				if pending_movement.is_empty() and a.destination>=0 and not a.destination in population.zones[a.zone].neighbors: return false
		if d.get("pressure",PackedFloat32Array()).size()!=population.zones.size(): return false
		forage=d.forage;predators=d.predators;pressure=d.pressure
		forage_cursor=int(d.get("forage_cursor",0))%maxi(1,forage.size());predator_clock=d.get("predator_clock",0)
		forage_consumed=d.get("forage_consumed",0);game_fish_consumed=d.get("game_fish_consumed",0);predator_meals=d.get("predator_meals",0);jumps=d.get("jumps",0);predator_ratio=d.get("predator_ratio",.01)
		rebuild_forage_index()
	return true
func describe(i: int) -> String:
	return "Home %s · school %s\nRoutine: %s → %s\nSpot: %s · %s" % [population.zones[home[i]].id,str(school[i]) if school[i]>=0 else "solo",population.zones[resting[i]].id,population.zones[feeding[i]].id,["rest","feed","hunt"][maxi(0,spot[i])],"alive" if alive[i]==1 else "consumed"]

func initialize_food_web():
	var p=population;forage.clear();predators.clear()
	for z in range(p.zones.size()):
		for slot in range(2):
			var kind: int=(z*3+slot)%FORAGE_NAMES.size();var capacity := 80.0 if kind!=7 else 25.0
			forage.append({"id":forage.size()+1,"kind":kind,"zone":z,"destination":-1,"x":float(p.zones[z].x),"y":float(p.zones[z].y),"quantity":capacity*p.rng.randf_range(.4,1),"capacity":capacity,"size_cm":FORAGE_SIZES[kind],"last":p.elapsed,"next":p.elapsed+p.rng.randf_range(30,180),"jump_at":p.elapsed+p.rng.randf_range(20,120),"jump_until":0.0,"scatter_until":0.0})
	rebuild_forage_index();set_predator_ratio(float(config.get("predators_per_game_fish",.01)))
func rebuild_forage_index():
	forage_zones.clear()
	for z in range(population.zones.size()): forage_zones[z]=[]
	for index in range(forage.size()):
		if forage[index].get("active",true): forage_zones[int(forage[index].zone)].append(index)
func set_predator_ratio(value: float):
	predator_ratio=clampf(value,0,.03)
	var target := roundi(population.ids.size()*predator_ratio);var p=population
	# Inactive predator records retain identities when the developer lowers the density.
	for index in range(predators.size()): predators[index].active=index<target
	while predators.size()<target:
		var index := predators.size();var kind := index%4;var z: int=p.rng.randi_range(0,p.zones.size()-1)
		var pod: int=floori(index/12.0) if kind==3 else -1
		if kind==3:
			for other in predators:
				if other.kind==3 and other.pod==pod: z=other.zone;break
		predators.append({"id":index+1,"kind":kind,"pod":pod,"active":true,"zone":z,"destination":-1,"x":float(p.zones[z].x),"y":float(p.zones[z].y),"last":p.elapsed,"next":p.elapsed+p.rng.randf()*90,"hunger":p.rng.randf_range(.2,.8),"size_cm":[180.0,140.0,90.0,250.0][kind]})
		if p.movement!=null and p.movement.ready:
			var nav=p.movement.nav;var anchor: int=nav.nearest(Vector2(p.zones[z].x,p.zones[z].y))
			if anchor<0: anchor=nav.migration_anchor(Vector2(p.zones[z].x,p.zones[z].y),z)
			if anchor>=0:
				var at: Vector2=nav.offset(anchor,index+700,30);predators[-1].x=at.x;predators[-1].y=at.y
				p.movement.plan_record(predators[-1],true)
func tick(dt: float,player: GeoPosition):
	var p=population;near_zones.clear()
	if p.food_web!=null and p.food_web.ready: p.food_web.tick(dt)
	var cell := Vector2i(roundi(player.east/750),roundi(player.south/750))
	for y in range(-1,2):
		for x in range(-1,2):
			var z: int=p.spatial.get(cell+Vector2i(x,y),-1)
			if z>=0: near_zones[z]=true
	pressure_clock+=dt
	if pressure_clock>=2:
		for z in range(pressure.size()): pressure[z]*=exp(-pressure_clock/120.0)
		pressure_clock=0
	for n in range(mini(96,forage.size())):
		var index := forage_cursor;forage_cursor=(forage_cursor+1)%forage.size();var a: Dictionary=forage[index]
		var age: float=p.elapsed-a.last
		if age<2: continue
		update_forage(index,age);a.last=p.elapsed
	predator_clock+=dt
	if predator_clock>=1:
		for a in predators:
			if not a.active: continue
			update_predator(a,p.elapsed-a.last);a.last=p.elapsed
		predator_clock=0
func move_record(a: Dictionary,dt: float,velocity: float) -> bool:
	if population.movement!=null and population.movement.ready: return population.movement.move_record(a,dt,velocity)
	if a.destination<0: return false
	var target: Dictionary=population.zones[int(a.destination)]
	var delta := Vector2(float(target.x)-float(a.x),float(target.y)-float(a.y));var distance := delta.length()
	var travel := maxf(.05,velocity+current.dot(delta.normalized()))*dt
	if travel>=distance:
		a.x=float(target.x);a.y=float(target.y);a.zone=int(a.destination);a.destination=-1
	else:
		var offset := delta.normalized()*travel;a.x+=offset.x;a.y+=offset.y
	return true
func update_forage(index: int,dt: float):
	if population.food_web!=null and population.food_web.ready: population.food_web.update_bait(index,dt);return
	var a: Dictionary=forage[index];var p=population;var z: int=a.zone
	if a.quantity<=0: a.quantity=0 # Empty pods persist; slow recruitment refills them.
	a.quantity=minf(a.capacity,a.quantity+dt*.003*p.food[z])
	if a.kind>=6:
		# Mullet consume abstract algae/detritus, never fish.
		p.food[z]=maxf(0,p.food[z]-dt*.000001*a.quantity)
		if p.elapsed>=a.jump_at:
			a.jump_until=p.elapsed+2;a.jump_at=p.elapsed+p.rng.randf_range(40,180);jumps+=1
	if pressure[z]>.25: a.scatter_until=p.elapsed+45;a.next=p.elapsed
	if move_record(a,dt,1.6 if a.scatter_until>p.elapsed else (.65 if a.kind>=6 else .3)):
		if a.zone!=z: forage_zones[z].erase(index);forage_zones[int(a.zone)].append(index)
		return
	if p.elapsed<a.next: return
	a.next=p.elapsed+p.rng.randf_range(60,240)
	if a.kind in [4,5] and pressure[z]<.25: return
	var choices: Array=[z];choices.append_array(p.zones[z].neighbors)
	var best: int=z;var score := -INF
	for candidate in choices:
		if depth_at(candidate)<.15: continue
		var value: float=p.food[candidate]-pressure[candidate]*3+p.rng.randf_range(-.8,.8)
		if value>score: score=value;best=candidate
	if best!=z: a.destination=best
	if p.movement!=null and p.movement.ready: p.movement.plan_record(a,a.has("hunger"))
func prey_available(i: int,z: int) -> float:
	var total := 0.0
	for index in forage_zones.get(z,[]):
		var a: Dictionary=forage[index]
		if edible(i,a): total+=float(a.quantity)
	return total
func edible(i: int,a: Dictionary) -> bool:
	if population.species[i]==3: return a.kind in [4,5] # Sheepshead favor benthic forage.
	return a.size_cm<population.size_cm[i]*float(profile(i).max_prey_ratio)
func interact(i: int,dt: float):
	var p=population;var z: int=p.region[i]
	if pressure[z]>.35 and p.behavior[i]!=5:
		p.behavior[i]=5;p.decision_at[i]=p.elapsed
	if (p.destination[i]>=0 and p.movement==null) or p.behavior[i] not in [2,4] or p.hunger[i]<.15: return
	var close: bool=near_zones.has(z) or p.observed_fish==i;var reach := 90.0 if profile(i).style=="chase" else 45.0
	if profile(i).style in ["ambush","bottom_ambush"]: reach=25.0
	for index in forage_zones.get(z,[]):
		var a: Dictionary=forage[index]
		if not edible(i,a) or a.quantity<=0: continue
		if close and Vector2(a.x-p.east[i],a.y-p.south[i]).length()>reach: continue
		var eaten := minf(float(a.quantity),minf(p.hunger[i]/.04,dt*.08))
		a.quantity-=eaten;p.hunger[i]=maxf(0,p.hunger[i]-eaten*.04);forage_consumed+=eaten;p.behavior[i]=2
		if a.kind>=6: a.scatter_until=p.elapsed+30;a.next=p.elapsed
		return
	# Stationary inferred oyster habitat provides finite replenishing benthic food.
	if p.species[i] in [0,3] and "oyster_bar_candidate" in habitats[z].tags:
		var eaten := minf(p.hunger[i],p.food[z]*dt*.001)
		p.hunger[i]-=eaten;p.food[z]=maxf(0,p.food[z]-eaten*.05)
		if eaten>0: p.behavior[i]=2;return
	if p.species[i]==3 or p.hunger[i]<.5: return
	var members: Array=p.buckets[z]
	for trial in range(mini(5,members.size())):
		var prey: int=members[p.rng.randi_range(0,members.size()-1)]
		if prey==i or alive[prey]==0 or p.size_cm[prey]>=p.size_cm[i]*float(profile(i).max_prey_ratio): continue
		if close and Vector2(p.east[prey]-p.east[i],p.south[prey]-p.south[i]).length()>reach: continue
		if p.rng.randf()<1-exp(-dt*.002):
			consume_fish(prey);p.hunger[i]=maxf(0,p.hunger[i]-.55);p.behavior[i]=2
		break
func consume_fish(i: int):
	if alive[i]==0: return
	var p=population;var z: int=p.region[i];alive[i]=0;p.behavior[i]=6;p.destination[i]=-1
	p.buckets[z].erase(i);p.zone_counts[z]-=1;p.zone_species_counts[z][p.species[i]]-=1;game_fish_consumed+=1
func update_predator(a: Dictionary,dt: float):
	var p=population;var z: int=a.zone;a.hunger=minf(1,a.hunger+dt*.0003)
	pressure[z]=minf(1,pressure[z]+dt*.035)
	for neighbor in p.zones[z].neighbors: pressure[neighbor]=minf(1,pressure[neighbor]+dt*.006)
	if move_record(a,dt,1.8 if a.kind==3 else 1.1): return
	if a.hunger>.35:
		if a.kind==2: # Bonnetheads draw primarily from the crab/shrimp pool.
			for index in forage_zones[z]:
				var prey: Dictionary=forage[index]
				if prey.kind not in [4,5] or prey.quantity<=0: continue
				var eaten := minf(prey.quantity,dt*.2);prey.quantity-=eaten;a.hunger=maxf(0,a.hunger-eaten*.02);forage_consumed+=eaten;break
		else:
			var members: Array=p.buckets[z]
			if not members.is_empty():
				var prey: int=members[p.rng.randi_range(0,members.size()-1)]
				var in_reach: bool=not near_zones.has(z) or Vector2(p.east[prey]-a.x,p.south[prey]-a.y).length()<90
				if p.size_cm[prey]<a.size_cm*.55 and in_reach and p.rng.randf()<1-exp(-dt*.003):
					consume_fish(prey);a.hunger=maxf(0,a.hunger-.6);predator_meals+=1
	if p.elapsed<a.next: return
	a.next=p.elapsed+p.rng.randf_range(30,90)
	var choices: Array=[z];choices.append_array(p.zones[z].neighbors);var best: int=z;var score := -INF
	for candidate in choices:
		if depth_at(candidate)<(.5 if a.kind==2 else 1.0): continue
		var value: float=float(p.zone_counts[candidate])*.1*a.hunger+p.rng.randf_range(-1,1)
		if a.kind==3:
			for other in predators:
				if other.id<a.id and other.kind==3 and other.pod==a.pod and other.active:
					if candidate==(other.destination if other.destination>=0 else other.zone): value+=2
					break
		if value>score: score=value;best=candidate
	if best!=z: a.destination=best
	if p.movement!=null and p.movement.ready: p.movement.plan_record(a,a.has("hunger"))


