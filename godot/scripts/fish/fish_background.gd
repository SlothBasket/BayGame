extends RefCounted
# Analytic water-valid travel plus infrequent ecological events. No distant strike loop.
const STRIDE := 1000000
var p
var travel: Dictionary = {}
func actor(code: int) -> int:
	return code if code<STRIDE else -(code%STRIDE)-1
func raw_position(code: int) -> Vector2:
	var kind := code/STRIDE;var i := code%STRIDE
	if kind==0: return Vector2(p.east[i],p.south[i])
	var a: Dictionary=(p.ecology.forage if kind==1 else p.ecology.predators)[i]
	return Vector2(a.x,a.y)
func sample_route(r: Dictionary,time: float) -> Vector2:
	var path: PackedVector2Array=r.path;var lengths: PackedFloat32Array=r.lengths
	if path.size()<2: return path[0]
	var distance := clampf((time-float(r.started))*float(r.speed),0,float(lengths[-1]))
	var lo := 1;var hi := path.size()-1
	while lo<hi:
		var mid := (lo+hi)/2
		if lengths[mid]<distance: lo=mid+1
		else: hi=mid
	return path[lo-1].lerp(path[lo],clampf((distance-lengths[lo-1])/maxf(.00001,lengths[lo]-lengths[lo-1]),0,1))
func position(code: int,time: float) -> Vector2:
	if not travel.has(code): return raw_position(code)
	var r: Dictionary=travel[code]
	if time<float(r.started) and r.has("previous"): return sample_route(r.previous,time)
	return sample_route(r,time)
func synchronize(code: int):
	if not travel.has(code) or not p.schedule.alive(code): return
	var r: Dictionary=travel[code]
	if float(r.synced)>=p.elapsed: return
	var at := position(code,p.elapsed);var old := raw_position(code);var kind := code/STRIDE;var i := code%STRIDE
	var node := -1
	if at.distance_squared_to(r.region_at)>4096:
		node=p.movement.nav.nearest(at);r.region_at=at
	if kind==0:
		p.east[i]=at.x;p.south[i]=at.y
		if node>=0: p.movement.update_region(i,int(p.movement.nav.nodes[node].zone))
		if at!=old: p.hunting.state(i).heading=(at-old).normalized();p.movement.headings[i]=(at-old).normalized()
	else:
		var a: Dictionary=(p.ecology.forage if kind==1 else p.ecology.predators)[i];var old_zone: int=a.zone
		a.x=at.x;a.y=at.y
		if at!=old: a.heading=(at-old).normalized()
		if node>=0: a.zone=p.movement.nav.nodes[node].zone
		if kind==1 and int(a.zone)!=old_zone: p.ecology.forage_zones[old_zone].erase(i);p.ecology.forage_zones[int(a.zone)].append(i)
	var travelled: float=maxf(0,(p.elapsed-float(r.started))*float(r.speed))
	var cursor := 1
	while cursor<r.lengths.size() and float(r.lengths[cursor])<=travelled: cursor+=1
	if kind==1: p.ecology.forage[i].path_cursor=cursor
	else: p.hunting.state(actor(code)).cursor=cursor
	r.synced=p.elapsed
	if kind<2: p.hunting.invalidate_prey(1 if kind==0 else 0,i)
	var dt := maxf(0,p.elapsed-float(r.depth_time))
	if dt>0:
		if kind==1: p.water_column.update_bait(p.ecology.forage[i],dt)
		else: p.water_column.update_actor(actor(code),dt)
	r.synced=p.elapsed;r.depth_time=p.elapsed
func finish_meal(aid: int,s: Dictionary,r: Dictionary) -> bool:
	if s.stage==6: s.stage=8;s.until=p.elapsed+float(r.consume_seconds)
	if s.stage!=8: return false
	if p.elapsed<float(s.until): return true
	p.hunting.set_hunger(aid,p.hunting.hunger(aid)-float(s.meal))
	if aid>=0: p.size_cm[aid]=maxf(p.size_cm[aid],minf(float(p.ecology.profile(aid).size_max_cm),p.size_cm[aid]+minf(.02,float(s.prey_cm)*.002)))
	s.stage=0;s.kind=-1;s.target=-1;s.last_event="consumed previously captured prey";return false
func event(code: int,encounters := true):
	var kind := code/STRIDE;var i := code%STRIDE
	var dt: float=maxf(0,p.elapsed-p.schedule.last_time(code))
	synchronize(code)
	if kind==1:
		bait_event(i,dt,encounters)
	else:
		fish_event(actor(code),dt,encounters)
	if kind==0: p.last_update[i]=p.elapsed
	else: (p.ecology.forage if kind==1 else p.ecology.predators)[i].last=p.elapsed
func fish_event(aid: int,dt: float,encounters: bool):
	var h=p.hunting;var s: Dictionary=h.state(aid);var r: Dictionary=h.profile(aid)
	var code: int=aid if aid>=0 else 2*STRIDE-aid-1
	var hunger_rate := .000035
	if aid>=0: hunger_rate=.00006*clampf(60.0/maxf(20,p.size_cm[aid]),.5,1.5)*(1.25 if p.species[aid] in [4,5] else 1.0)
	h.set_hunger(aid,h.hunger(aid)+dt*hunger_rate)
	if not travel.has(code): p.water_column.update_actor(aid,dt)
	if aid<0:
		var zone: int=h.zone(aid);p.ecology.pressure[zone]=minf(1,p.ecology.pressure[zone]+dt*.035)
		for neighbor in p.zones[zone].neighbors: p.ecology.pressure[neighbor]=minf(1,p.ecology.pressure[neighbor]+dt*.006)
	var eating := finish_meal(aid,s,r)
	var resting: bool=s.energy<.2 or h.hunger(aid)<.08
	s.energy=clampf(float(s.energy)+dt*(.015 if resting else -.00015),0,1)
	if not encounters: return
	# Hold cover/rest or continue a route. Reconsider habitat only on its own decision event.
	var at := raw_position(code);var path := PackedVector2Array([at]);var velocity: float=float(r.cruise_mph)*.44704
	if resting: velocity*=.35
	if eating or (resting and r.style in ["ambush","bottom_ambush","intercept"]): velocity=0
	if not eating:
		s.stage=9 if resting else 0;s.kind=-1;s.target=-1;s.activity="background holding / recovery" if resting else "background habitat travel"
		if p.elapsed>=float(s.get("coarse_plan_at",0)):
			s.coarse_plan_at=p.elapsed+90
			if r.get("rock_resident",false) and p.food_web.resident_site.has(aid):
				var home: Vector2=p.food_web.home_position(aid)
				var goal: int=p.food_web.areas[int(p.food_web.resident_site[aid])].nodes[0]
				var route: PackedVector2Array=p.movement.nav.route(at,home,goal)
				if not route.is_empty(): s.path=route;s.cursor=1
				elif p.movement.nav.route_pending: s.coarse_plan_at=p.elapsed+2
			elif s.has("coarse_route_goal"):
				var route: PackedVector2Array=p.movement.nav.route(at,s.coarse_route_target,int(s.coarse_route_goal))
				if not route.is_empty(): s.path=route;s.cursor=1;s.erase("coarse_route_goal");s.erase("coarse_route_target")
				elif p.movement.nav.route_pending: s.coarse_plan_at=p.elapsed+2
			else: p.simulation_detail.plan_coarse_route(aid,s,at)
		if not resting and p.elapsed>=float(s.get("coarse_encounter_at",0)):
			s.coarse_encounter_at=p.elapsed+30;encounter(aid,s,r)
	if not s.path.is_empty(): path=remaining_path(at,s.path,int(s.cursor))
	install(code,path,velocity)
	# Store the remaining validated polyline for the eventual detailed handoff.
	s.path=path;s.cursor=1
func bait_event(i: int,dt: float,encounters: bool):
	var a: Dictionary=p.ecology.forage[i];var code := STRIDE+i
	a.hunger=minf(1,float(a.hunger)+dt*.00015);a.fear=maxf(0,float(a.fear)-dt*.01)
	a.fear=maxf(a.fear,float(p.ecology.pressure[int(a.zone)]))
	var area: int=p.food_web.area_by_id.get(a.get("preferred_area",""),-1)
	if area>=0 and p.food_web.contains(area,Vector2(a.x,a.y)):
		var grazed: float=minf(p.food_web.nutrients[area],dt*.0004*float(a.hunger));p.food_web.nutrients[area]-=grazed;a.hunger=maxf(0,float(a.hunger)-grazed*5)
	if not travel.has(code): p.water_column.update_bait(a,dt)
	if not encounters: return
	if p.food_web.return_escapee(i): return
	if p.elapsed>=float(a.next): p.food_web.plan_bait(a);a.next=p.elapsed+(2 if a.has("pending_route_target") else 90)
	var at := Vector2(a.x,a.y);var path := remaining_path(at,a.natural_path,int(a.path_cursor)) if a.has("natural_path") else PackedVector2Array([at])
	var velocity := .04 if a.kind in [4,5] else (.45 if a.kind>=6 else .3)
	if a.fear>.3: velocity*=2
	if a.kind>=6 and p.elapsed>=float(a.jump_at): a.jump_until=p.elapsed+2;a.jump_at=p.elapsed+p.rng.randf_range(40,180);p.ecology.jumps+=1
	a.speed_mps=velocity;a.activity="background forage / shelter";a.natural_path=path;a.path_cursor=1
	install(code,path,velocity)
func remaining_path(at: Vector2,path: PackedVector2Array,cursor: int) -> PackedVector2Array:
	# The previous event committed its path cursor analytically; no per-stride loop.
	var result := PackedVector2Array([at])
	for n in range(maxi(1,cursor),path.size()): result.append(path[n])
	if result.size()>1 and not p.movement.nav.clear(at,result[1]): return PackedVector2Array([at])
	return result
func install(code: int,path: PackedVector2Array,velocity: float):
	var previous: Dictionary=travel.get(code,{})
	# Strip older history: at most one prior segment set is retained for presentation.
	var history: Dictionary={}
	if not previous.is_empty(): history={"path":previous.path,"lengths":previous.lengths,"started":previous.started,"speed":previous.speed}
	elif p.presentation.simulation_clock<p.elapsed:
		var bridge: PackedVector2Array=p.presentation.remaining_path(code/STRIDE,code%STRIDE,path[0])
		# Retain the existing water-valid visual route, including its unfinished corners.
		if not bridge[-1].is_equal_approx(path[0]) and p.movement.nav.clear(bridge[-1],path[0]): bridge.append(path[0])
		if bridge[-1].is_equal_approx(path[0]):
			var distances := PackedFloat32Array();distances.resize(bridge.size())
			for n in range(1,bridge.size()): distances[n]=distances[n-1]+bridge[n-1].distance_to(bridge[n])
			history={"path":bridge,"lengths":distances,"started":p.presentation.simulation_clock,"speed":float(distances[-1])/maxf(.001,p.elapsed-p.presentation.simulation_clock)}
	var lengths := PackedFloat32Array();lengths.resize(path.size())
	for n in range(1,path.size()): lengths[n]=lengths[n-1]+path[n-1].distance_to(path[n])
	var r := {"path":path,"lengths":lengths,"started":p.elapsed,"speed":velocity,"synced":p.elapsed,"depth_time":p.elapsed,"region_at":previous.get("region_at",path[0])}
	if not history.is_empty(): r.previous=history
	travel[code]=r
	var kind := code/STRIDE;var i := code%STRIDE
	if kind<2:
		var bounds := Rect2(path[0],Vector2.ZERO);var limit: float=velocity*30
		for n in range(1,path.size()):
			if lengths[n]>limit: bounds=bounds.expand(sample_route(r,p.elapsed+30));break
			bounds=bounds.expand(path[n])
		p.hunting.spatial.cover(1 if kind==0 else 0,i,bounds.grow(1))
func next_event(code: int,tier: int) -> float:
	var delay: float=p.simulation_detail.intervals[tier]
	if travel.has(code):
		var r: Dictionary=travel[code];var length: float=r.lengths[-1]
		# Wake before the route could cross into a higher-detail radius, even with a stationary camera.
		if float(r.speed)>0 and p.simulation_detail.enabled:
			var at := position(code,p.elapsed)
			var distance: float=minf(at.distance_to(p.simulation_detail.boat),at.distance_to(p.simulation_detail.camera))
			var radius: float=p.simulation_detail.intermediate_m if tier==2 else p.simulation_detail.detailed_m
			delay=minf(delay,maxf(.5,(distance-radius)/float(r.speed)))
		if float(r.speed)>0 and length>0: delay=minf(delay,maxf(.5,float(r.started)+length/float(r.speed)-p.elapsed))
	var kind := code/STRIDE;var i := code%STRIDE
	if kind==1: delay=minf(delay,maxf(.5,float(p.ecology.forage[i].next)-p.elapsed))
	else:
		var s: Dictionary=p.hunting.state(actor(code))
		delay=minf(delay,maxf(.5,float(s.get("coarse_plan_at",p.elapsed+delay))-p.elapsed))
		if s.stage==8: delay=minf(delay,maxf(.5,float(s.until)-p.elapsed))
	return p.elapsed+maxf(.5,delay)
func encounter(aid: int,s: Dictionary,r: Dictionary):
	var h=p.hunting;var at: Vector2=h.position(aid);var radius: float=minf(50,float(r.detect_ft)*.3048)
	var eligible := 0
	for code in h.spatial.query(at,radius):
		var kind := int(code)/STRIDE;var index := int(code)%STRIDE
		if kind==1 and index==aid: continue
		var scheduled := index if kind==1 else STRIDE+index
		if kind<2:
			if not p.schedule.alive(scheduled): continue
			synchronize(scheduled)
			if p.schedule.level(scheduled)==0: continue
		if not h.candidate_fits(aid,kind,index,h.length_cm(aid)*float(r.gape),r.style): continue
		if at.distance_squared_to(h.candidate_position(kind,index))>radius*radius: continue
		var prey: Dictionary=h.prey(kind,index)
		if not h.suitable(aid,kind,index,prey,r) or at.distance_squared_to(prey.position)>radius*radius: continue
		eligible+=1
		if p.water_column.separation(aid,kind,index,prey)<maxf(1,h.length_cm(aid)*.015) and p.movement.nav.clear(at,prey.position) and p.rng.randf()<.25*(1-float(prey.cover)):
			if kind==0:
				if not p.food_web.consume_bait(index): continue
			elif kind==1: p.ecology.consume_fish(index)
			else:
				if p.food_web.bottom[index].quantity<1: continue
				p.food_web.bottom[index].quantity-=1;p.ecology.forage_consumed+=1
			h.set_hunger(aid,h.hunger(aid)-clampf(.1+float(prey.size)/h.length_cm(aid)*1.3,.1,.75));s.captures+=1;s.energy=maxf(0,s.energy-.025);s.last_event="background encounter consumed "+str(prey.label)
			if aid<0: p.ecology.predator_meals+=1
			break
		if eligible>=12: break
func release(code: int):
	if not travel.has(code): return
	# Commit route cursor as well as position before detailed steering resumes.
	synchronize(code);travel.erase(code)
