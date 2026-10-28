class_name FishFoodWeb
extends RefCounted
var p
var eco
var nav
var areas: Array = []
var feature_areas: Dictionary = {}
var zone_areas: Array = []
var area_by_id: Dictionary = {}
var bottom: Array = []
var bottom_zones: Dictionary = {}
var nutrients := PackedFloat32Array()
var clock := 0.0
var threats: Dictionary = {}
var disturbances: Array = []
var split_count := 0
var merge_count := 0
var events: Array = []
var ready := false
var last_error := ""
func fail(reason: String) -> bool:
	last_error=reason;return false
var observed_bait := -1
var recruitment_clock := 0.0
var recruitment_due := 0
var recovery_due := 0.0
var recovery_dt := 0.0
var recovery_cursor := 0
var cleanup_at := 0.0
var cleanup_keys: Array = []
var cleanup_cursor := 0
var next_bait_id := 1
var bait_slots: Dictionary = {}
var retired_escapees: Array[int] = []
func setup(population,root: String,saved: Dictionary) -> bool:
	p=population;eco=p.ecology;nav=p.movement.nav
	var data=JSON.parse_string(FileAccess.get_file_as_string(root+"habitat-areas.json"))
	if not data is Dictionary: return fail("invalid habitat-areas.json")
	if data.navigation_fingerprint!=nav.fingerprint: return fail("habitat navigation fingerprint differs from navigation")
	areas=data.areas;feature_areas=data.feature_areas;zone_areas=data.zone_areas;nutrients.resize(areas.size());nutrients.fill(.8)
	for z in range(p.zones.size()): bottom_zones[z]=[]
	for index in range(areas.size()):
		var a: Dictionary=areas[index];a.zone=int(a.zone);a.nodes=PackedInt32Array(a.nodes);area_by_id[a.id]=index
		for polygon in a.polygons:
			polygon.outer=points(polygon.outer)
			for h in range(polygon.holes.size()): polygon.holes[h]=points(polygon.holes[h])
		if a.bottom_capacity>0:
			var at := sample(index,index*7919)
			bottom_zones[a.zone].append(bottom.size())
			bottom.append({"id":bottom.size()+1,"area":a.id,"zone":a.zone,"x":at.x,"y":at.y,"capacity":a.bottom_capacity,"quantity":a.bottom_capacity*.8,"size_cm":2.0 if a.kind=="mapped_structure" else 4.0,"kind":"barnacles / attached forage" if a.kind=="mapped_structure" else "small crabs / bottom forage"})
	if not saved.is_empty():
		if saved.get("nutrients",PackedFloat32Array()).size()!=areas.size() or not saved.get("bottom") is Array: return fail("saved food resource arrays or bottom-forage records incompatible")
		for b in saved.bottom:
			if not area_by_id.has(b.area) or not nav.wet(Vector2(b.x,b.y)) or b.quantity<0: return fail("saved food resource arrays or bottom-forage records incompatible")
		threats=saved.get("threats",{});events=saved.get("events",[]);bottom=saved.bottom;nutrients=saved.nutrients;clock=saved.get("clock",0);split_count=saved.get("split_count",0);merge_count=saved.get("merge_count",0)
		for z in bottom_zones: bottom_zones[z]=[]
		for index in range(bottom.size()): bottom_zones[int(bottom[index].zone)].append(index)
	if eco.forage.is_empty():
		var density: float=eco.config.get("bait_density_per_area",1.8)
		for index in range(areas.size()):
			var suitability := 1.6 if areas[index].kind in ["grass_flat_candidate","pothole_candidate","oyster_bar_candidate","mangrove_edge_candidate","shoreline_edge"] else .6
			var count := floori(density*suitability+p.rng.randf())
			for slot in range(count): spawn_bait(index)
	for a in eco.forage: initialize_bait(a)
	ready=true;return true
func spawn_bait(area: int) -> bool:
	var diagnostic_begin := Time.get_ticks_usec()
	var result: bool=_measured_spawn_bait(area)
	p.diagnostics.add("Spawning",Time.get_ticks_usec()-diagnostic_begin)
	return result
func _measured_spawn_bait(area: int) -> bool:
	if eco.forage.size()>=int(eco.config.get("bait_record_limit",24000)): return false
	var habitat: Dictionary=areas[area]
	var kinds: Array=[1,6,7]
	if habitat.kind in ["grass_flat_candidate","pothole_candidate"]: kinds=[0,1,2,3,3,4,5,6]
	elif habitat.kind in ["oyster_bar_candidate","mapped_structure"]: kinds=[2,3,4,5,5]
	elif "shelter" in habitat.roles or habitat.kind in ["mangrove_edge_candidate","shoreline_edge","creek_mouth_candidate"]: kinds=[0,0,2,3,4,5,6]
	var kind: int=kinds[p.rng.randi_range(0,kinds.size()-1)]
	var at := sample(area,p.rng.randi());var node: int=nav.nearest(at)
	if node<0 or not nav.wet(at): return false
	if float(nav.nodes[node].depth_m)>6 and kind in [0,2,3,4,5]: return false
	var individual: bool=kind in [0,2,3,4,5] and p.rng.randf()<float(eco.config.get("bait_solitary_fraction",.55))
	var quantity: int = 1 if individual else (p.rng.randi_range(70,240) if kind in [1,6,7] else p.rng.randi_range(4,18))
	var a := {"id":0,"kind":kind,"individual":individual,"zone":int(nav.nodes[node].zone),"destination":-1,"x":at.x,"y":at.y,"quantity":float(quantity),"capacity":float(quantity),"size_cm":eco.FORAGE_SIZES[kind]*p.rng.randf_range(.65,1.15),"last":p.elapsed,"next":p.elapsed+p.rng.randf_range(1,30),"jump_at":p.elapsed+p.rng.randf_range(20,120),"jump_until":0.0,"scatter_until":0.0,"preferred_area":habitat.id}
	if p.water_column!=null: p.water_column.initialize_record(a,false)
	initialize_bait(a)
	return register_bait(a)>=0
func register_bait(a: Dictionary,temporary := false) -> int:
	var index := -1
	if temporary:
		for n in range(retired_escapees.size()-1,-1,-1):
			if retired_escapees[n]!=observed_bait: index=retired_escapees[n];retired_escapees.remove_at(n);break
	if index<0:
		if eco.forage.size()>=int(eco.config.get("bait_record_limit",24000)): return -1
		index=eco.forage.size();eco.forage.append(a)
	else: eco.forage[index]=a
	a.id=next_bait_id;next_bait_id+=1;a.temporary=temporary;a.active=true
	bait_slots[int(a.id)]=index;eco.forage_zones[int(a.zone)].append(index)
	if p.hunting!=null and p.hunting.ready: p.hunting.index_entity(0,index)
	p.presentation.reset_record(1,index,Vector2(a.x,a.y))
	return index
func retire_bait(index: int,reason: String):
	var a: Dictionary=eco.forage[index]
	if not a.active: return
	a.quantity=0;a.active=false;a.activity=reason;a.last_event=reason;eco.forage_zones[int(a.zone)].erase(index)
	if p.hunting!=null: p.hunting.index_entity(0,index)
	if a.get("temporary",false):
		var parent: int=bait_slots.get(int(a.parent_id),-1)
		if parent>=0: eco.forage[parent].escapees=maxi(0,int(eco.forage[parent].get("escapees",0))-1)
		bait_slots.erase(int(a.id));retired_escapees.append(index)
func consume_bait(index: int) -> bool:
	var a: Dictionary=eco.forage[index]
	if not a.active or a.quantity<1: return false
	a.quantity=maxf(0,a.quantity-1);eco.forage_consumed+=1
	if a.quantity<1: retire_bait(index,"consumed permanently")
	return true
func detach_escapees(school: Dictionary,threat: Vector2):
	if p.simulation_detail!=null and p.simulation_detail.bait_level(int(bait_slots[school.id]))>0: return
	if school.get("individual",false) or school.quantity<=1 or p.elapsed<float(school.get("detach_at",0)): return
	school.detach_at=p.elapsed+4
	var limit: int=int(eco.config.get("escapees_per_school",6))-int(school.get("escapees",0))
	for n in range(mini(2,limit)):
		if school.quantity<=1: break
		var a: Dictionary=school.duplicate();a.erase("natural_path")
		a.parent_id=school.id;a.quantity=1.0;a.capacity=1.0;a.individual=true;a.escapees=0;a.school_id=-1;a.fear=1.0;a.flee_from=threat;a.next=p.elapsed;a.turn_at=0;a.last=p.elapsed;a.path_cursor=0;a.destination=-1;a.return_at=p.elapsed+25;a.speed_mps=1.2;a.vertical_spread=0.0;a.activity="escapee fleeing"
		var at := Vector2(school.x,school.y);var offset := member_offset(school,next_bait_id*613,p.hunting.school_radius(int(bait_slots[school.id])))
		if nav.clear(at,at+offset): at+=offset
		a.x=at.x;a.y=at.y;a.heading=(at-threat).normalized()
		var index := register_bait(a,true)
		if index<0: break
		school.quantity-=1;school.escapees=int(school.get("escapees",0))+1
		events.append({"time":p.elapsed,"kind":"escape","id":a.id,"other":school.id,"position":at})
func return_escapee(index: int) -> bool:
	var a: Dictionary=eco.forage[index]
	if not a.get("temporary",false) or a.fear>.15 or p.elapsed<float(a.return_at): return false
	var parent: int=bait_slots.get(int(a.parent_id),-1)
	for hop in range(8):
		if parent<0 or eco.forage[parent].active: break
		parent=bait_slots.get(int(eco.forage[parent].get("merged_into",-1)),-1)
	var at := Vector2(a.x,a.y)
	if parent<0 or not eco.forage[parent].active:
		parent=-1
		for code in p.hunting.spatial.query(at,50):
			if int(code)>=FishSpatialIndex.STRIDE: continue
			var other: Dictionary=eco.forage[int(code)]
			if other.active and not other.get("individual",false) and other.kind==a.kind: parent=int(code);break
	if parent<0: return false
	var school: Dictionary=eco.forage[parent];var goal := Vector2(school.x,school.y)
	if not nav.clear(at,goal): return false
	a.activity="escapee returning to school #%d" % school.id
	a.natural_path=PackedVector2Array([at,goal]);a.path_cursor=1;a.destination=school.zone;a.return_school=school.id
	if at.distance_to(goal)<=3 and absf(float(a.swim_depth)-float(school.swim_depth))<=.5:
		school.quantity+=1;school.capacity=maxf(school.capacity,school.quantity);a.merged_into=school.id
		events.append({"time":p.elapsed,"kind":"rejoined","id":a.id,"other":school.id,"position":at});retire_bait(index,"returned to school #%d" % school.id);return true
	return false
func points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for v in values: result.append(Vector2(v[0],v[1]))
	return result
func contains(index: int,at: Vector2) -> bool:
	for polygon in areas[index].polygons:
		if not Geometry2D.is_point_in_polygon(at,polygon.outer): continue
		var hole := false
		for ring in polygon.holes:
			if Geometry2D.is_point_in_polygon(at,ring): hole=true;break
		if not hole: return true
	return false
func area_for_feature(feature: int,role: String) -> String:
	var choices: Array=feature_areas.get(str(feature),[])
	if choices.is_empty(): choices=zone_areas[int(nav.nodes[feature].zone)]
	for value in choices:
		if role in areas[int(value)].roles: return areas[int(value)].id
	return areas[int(choices[0])].id if not choices.is_empty() else ""
func sample(index: int,seed_value: int,component := -1) -> Vector2:
	var begin := Time.get_ticks_usec()
	var result: Vector2=_timed_sample(index,seed_value,component)
	p.diagnostics.add("Habitat sampling",Time.get_ticks_usec()-begin)
	return result
func _timed_sample(index: int,seed_value: int,component := -1) -> Vector2:
	var a: Dictionary=areas[index];var ids: PackedInt32Array=a.nodes
	for trial in range(mini(20,ids.size()+8)):
		var id: int=ids[posmod(seed_value+trial*137,ids.size())]
		if component>=0 and nav.nodes[id].component!=component: continue
		var at: Vector2=nav.offset(id,seed_value+trial*17,35.0+float(posmod(seed_value,65)))
		if contains(index,at): return at
	for id in ids:
		if component<0 or nav.nodes[id].component==component: return nav.point(id)
	return nav.point(ids[0])
func feature_destination(feature: int,role: String,seed_value: int) -> Vector2:
	var key := area_for_feature(feature,role)
	if key=="": return nav.offset(feature,seed_value,30)
	return sample(area_by_id[key],seed_value,int(nav.nodes[feature].component))
func productivity(zone: int) -> float:
	var food := 0.0
	for index in eco.forage_zones.get(zone,[]):
		var a: Dictionary=eco.forage[index]
		if a.get("active",true): food+=float(a.quantity)
	for index in bottom_zones.get(zone,[]): food+=float(bottom[index].quantity)
	return minf(1,food/150.0)
func initialize_bait(a: Dictionary):
	for key in {"active":true,"hunger":.3,"fear":0.0,"split_after":0.0,"merge_after":0.0,"parent_id":-1,"merged_into":-1,"activity":"searching","last_event":"","flee_from":Vector2.ZERO,"turn_at":0.0}:
		if not a.has(key): a[key]={"active":true,"hunger":.3,"fear":0.0,"split_after":0.0,"merge_after":0.0,"parent_id":-1,"merged_into":-1,"activity":"searching","last_event":"","flee_from":Vector2.ZERO,"turn_at":0.0}[key]
func member_offset(a: Dictionary,seed_value: int,radius: float) -> Vector2:
	if a.get("individual",false): return Vector2.ZERO
	var angle := float(posmod(seed_value,6283))*.001
	var cohesion: float=a.get("cohesion",1.0);var stretch: float=a.get("stretch",1.0)
	var heading: Vector2=a.get("heading",Vector2.RIGHT)
	return Vector2(cos(angle)*stretch,sin(angle)/sqrt(stretch))*radius*(.3+.6*float(posmod(seed_value,997))/997.0)/maxf(.5,cohesion) if heading.length_squared()<.01 else Vector2(cos(angle)*stretch,sin(angle)/sqrt(stretch)).rotated(heading.angle())*radius*(.3+.6*float(posmod(seed_value,997))/997.0)/maxf(.5,cohesion)
func formation(index: int,dt: float):
	var a: Dictionary=eco.forage[index];var at := Vector2(a.x,a.y)
	a.cohesion=move_toward(float(a.get("cohesion",1)),.45 if a.fear>.3 else 1.0,dt*.12)
	a.stretch=lerpf(float(a.get("stretch",1)),1.0+a.fear*1.5+absf(sin(p.elapsed*.03+a.id))*.35, minf(1,dt*.3))
	if p.elapsed<float(a.get("formation_at",0)): return
	a.formation_at=p.elapsed+2
	var aligned := Vector2.ZERO;var separation := Vector2.ZERO;var neighbors := 0;var buddy := -1
	for other_index in eco.forage_zones[int(a.zone)]:
		if other_index==index: continue
		var other: Dictionary=eco.forage[other_index]
		if not other.active or other.kind!=a.kind: continue
		var delta := at-Vector2(other.x,other.y);var distance := delta.length()
		if distance>25: continue
		aligned+=Vector2(other.get("heading",Vector2.ZERO));neighbors+=1
		if distance<4 and distance>.01: separation+=delta.normalized()*(4-distance)*.15
		if not other.get("individual",false) and distance<8: buddy=other_index
		if neighbors>=6: break
	if neighbors>0 and a.fear<.3: a.heading=Vector2(a.get("heading",Vector2.ZERO)).lerp(aligned.normalized(),.25).normalized()
	if a.get("individual",false) and buddy>=0 and a.fear<.1 and a.hunger<.6:
		if p.elapsed>=float(a.get("leave_school_at",0)):
			a.school_id=-1;a.leave_school_at=p.elapsed+90;a.next=p.elapsed
		elif p.elapsed<float(a.leave_school_at)-30:
			a.school_id=eco.forage[buddy].id;a.activity="loosely accompanying school"
			var goal := Vector2(eco.forage[buddy].x,eco.forage[buddy].y)+Vector2.from_angle(float(a.id))*2
			if nav.clear(at,goal): a.natural_path=PackedVector2Array([at,goal]);a.path_cursor=1;a.destination=a.zone
	var shifted := at+separation.limit_length(.6)
	if nav.clear(at,shifted): a.x=shifted.x;a.y=shifted.y
func tick(dt: float):
	while not disturbances.is_empty() and disturbances[0].until<p.elapsed: disturbances.pop_front()
	clock+=dt;recruitment_clock+=dt
	var recruitment_interval: float=maxf(1,eco.config.get("bait_recruitment_seconds",300))
	if recruitment_clock>=recruitment_interval:
		var batches := floori(recruitment_clock/recruitment_interval);recruitment_clock-=batches*recruitment_interval
		recruitment_due+=batches*int(eco.config.get("bait_recruits_per_interval",12))
	if clock>=10: recovery_due+=clock;clock=0
func process_maintenance(deadline: int):
	var diagnostic_begin := Time.get_ticks_usec()
	_measured_process_maintenance(deadline)
	p.diagnostics.add("Maintenance",Time.get_ticks_usec()-diagnostic_begin)
func _measured_process_maintenance(deadline: int):
	if recovery_dt<=0 and recovery_due>0: recovery_dt=recovery_due;recovery_due=0;recovery_cursor=0
	while recovery_dt>0 and Time.get_ticks_usec()<deadline:
		if recovery_cursor<nutrients.size(): nutrients[recovery_cursor]=move_toward(nutrients[recovery_cursor],1,recovery_dt*.00005)
		elif recovery_cursor<nutrients.size()+bottom.size():
			var b: Dictionary=bottom[recovery_cursor-nutrients.size()];b.quantity=move_toward(b.quantity,b.capacity,recovery_dt*float(b.capacity)*.000025)
		else: recovery_dt=0;break
		recovery_cursor+=1
	if cleanup_cursor>=cleanup_keys.size() and p.elapsed>=cleanup_at:
		cleanup_keys=threats.keys();cleanup_cursor=0;cleanup_at=p.elapsed+2
	while cleanup_cursor<cleanup_keys.size() and Time.get_ticks_usec()<deadline:
		var key=cleanup_keys[cleanup_cursor];cleanup_cursor+=1
		if threats.has(key) and threats[key].until<p.elapsed: threats.erase(key)
	if recruitment_due>0 and Time.get_ticks_usec()<deadline:
		spawn_bait(p.rng.randi_range(0,areas.size()-1));recruitment_due-=1

func feeding_disturbance(actor: int,at: Vector2):
	# Bounded short-lived acoustic/visual cues, not omniscient prey locations.
	disturbances.append({"actor":actor,"position":at,"until":p.elapsed+15})
	if disturbances.size()>48: disturbances.pop_front()
func nearby_disturbance(at: Vector2,radius: float) -> Vector2:
	for i in range(disturbances.size()-1,-1,-1):
		var d: Dictionary=disturbances[i]
		if d.until>=p.elapsed and at.distance_squared_to(d.position)<=radius*radius: return d.position
	return Vector2.INF
func threaten(key: int,at: Vector2,radius: float):
	threats[key]={"position":at,"radius":radius,"until":p.elapsed+8}
func flee(a: Dictionary,at: Vector2):
	detach_escapees(a,at)
	a.fear=1.0;a.scatter_until=p.elapsed+35;a.flee_from=at;a.next=p.elapsed;a.activity="scattering";a.last_event="escaped / scattered from nearby attack"
func plan_bait(a: Dictionary):
	var begin := Time.get_ticks_usec()
	_timed_plan_bait(a)
	p.diagnostics.add("Bait planning",Time.get_ticks_usec()-begin)
func _timed_plan_bait(a: Dictionary):
	if a.has("pending_route_target"):
		var pending: PackedVector2Array=nav.route(Vector2(a.x,a.y),a.pending_route_target,int(a.pending_route_goal))
		if not pending.is_empty():
			a.natural_path=pending;a.path_cursor=1;a.destination=nav.nodes[int(a.pending_route_goal)].zone;a.erase("pending_route_target");a.erase("pending_route_goal")
		elif not nav.route_pending: a.erase("pending_route_target");a.erase("pending_route_goal")
		return
	var at := Vector2(a.x,a.y);var anchor: int=nav.nearest(at)
	if anchor<0: return
	var target := at;var chosen := -1;var score := -INF
	if a.fear>.3:
		var away := (at-Vector2(a.flee_from)).normalized()
		if away==Vector2.ZERO: away=Vector2.from_angle(float(a.id))
		away=away.rotated(float(posmod(int(a.id),5)-2)*.2)
		var escape: int=nav.nearest(at+away*160)
		if escape>=0 and nav.nodes[escape].component==nav.nodes[anchor].component: target=nav.point(escape);chosen=escape
	if chosen<0:
		for z in [int(a.zone)]+p.zones[int(a.zone)].neighbors:
			for value in zone_areas[int(z)]:
				var index := int(value);var habitat: Dictionary=areas[index]
				var v: float=float(nutrients[index])+p.rng.randf()*.5-eco.pressure[int(z)]*3
				if habitat.id==a.get("preferred_area","") and nutrients[index]>.3: v+=.7
				if "shelter" in habitat.roles and a.kind in [0,2,3,4,5]: v+=.8
				if a.kind>=6 and habitat.kind=="grass_flat_candidate": v+=1.0
				# Depth only subtracts from v: a losing upper bound cannot win.
				if v<=score: continue
				var candidate := sample(index,int(a.id)+int(p.elapsed),int(nav.nodes[anchor].component));var id: int=nav.nearest(candidate)
				if id<0 or nav.nodes[id].component!=nav.nodes[anchor].component: continue
				v-=absf(float(nav.nodes[id].depth_m)-(1.5 if a.kind in [0,2,4,5,6] else 3.0))*.15
				if v>score: score=v;target=candidate;chosen=id;a.preferred_area=habitat.id
	if chosen<0: return
	var path: PackedVector2Array=nav.route(at,target,chosen)
	if path.is_empty():
		if nav.route_pending: a.pending_route_target=target;a.pending_route_goal=chosen
		return
	a.natural_path=path;a.path_cursor=1;a.destination=nav.nodes[chosen].zone;a.goal_feature=chosen;a.turn_at=p.elapsed+10
func update_bait(index: int,dt: float):
	var a: Dictionary=eco.forage[index]
	if not a.active or a.quantity<1: return
	var z: int=a.zone;a.hunger=minf(1,a.hunger+dt*.00015);a.fear=maxf(0,a.fear-dt*.01)
	var danger := Vector2.ZERO;var nearby_threats := 0
	for threat in threats.values():
		if Vector2(a.x,a.y).distance_squared_to(threat.position)<float(threat.radius)*float(threat.radius): danger+=Vector2(threat.position);nearby_threats+=1
	if nearby_threats>0: flee(a,danger/nearby_threats)
	if eco.pressure[z]>.4: a.fear=maxf(a.fear,eco.pressure[z]);a.scatter_until=p.elapsed+15
	var local: Array=zone_areas[z]
	for value in local:
		var area := int(value)
		if not contains(area,Vector2(a.x,a.y)): continue
		var grazed := minf(nutrients[area],dt*.0004*a.hunger)
		nutrients[area]-=grazed;a.hunger=maxf(0,a.hunger-grazed*5)
		a.activity="grazing algae / detritus" if a.kind>=6 else "foraging / regrouping"
		break
	if a.kind>=6 and p.elapsed>=a.jump_at:
		a.jump_until=p.elapsed+2;a.jump_at=p.elapsed+p.rng.randf_range(40,180);eco.jumps+=1;a.last_event="mullet jump"
	if a.fear>.3: a.activity="fleeing / scattered"
	if p.elapsed>=float(a.next) or (a.fear>.3 and p.elapsed>=a.turn_at):
		plan_bait(a);a.next=p.elapsed+(1 if a.has("pending_route_target") else p.rng.randf_range(30,100))
	if return_escapee(index): return
	var velocity := (1.8 if a.kind>=6 else 1.0) if a.fear>.3 else (.45 if a.kind>=6 else (.05 if a.kind in [4,5] else .3))
	if a.get("temporary",false): velocity=1.2 if a.fear>.3 else .45
	a.speed_mps=velocity
	if int(a.get("detail",0))==0 and not a.get("temporary",false): formation(index,dt)
	p.movement.move_record(a,dt,velocity)
	if p.water_column!=null: p.water_column.update_bait(a,dt)
	if a.zone!=z: eco.forage_zones[z].erase(index);eco.forage_zones[int(a.zone)].append(index)
	if not a.get("individual",false) and a.quantity>=4 and (a.fear>.6 or p.rng.randf()<dt*.0002) and p.elapsed>=a.split_after and eco.forage.size()<int(eco.config.get("bait_record_limit",24000)):
		var split_quantity := floorf(a.quantity*.4) if a.fear>.6 else 1.0
		a.quantity-=split_quantity;a.capacity=maxf(a.quantity,a.capacity-split_quantity);a.split_after=p.elapsed+300;a.merge_after=p.elapsed+80
		var child: Dictionary=a.duplicate(true);child.individual=split_quantity==1
		if child.individual: child.vertical_spread=0.0
		child.quantity=split_quantity;child.capacity=split_quantity;child.id=0;child.escapees=0;child.parent_id=a.id;child.last=p.elapsed;child.next=p.elapsed;child.turn_at=p.elapsed;child.heading=Vector2.from_angle(float(child.id));child.erase("natural_path")
		if register_bait(child)<0: a.quantity+=split_quantity;return
		events.append({"time":p.elapsed,"kind":"split","id":a.id,"other":child.id,"position":Vector2(a.x,a.y)})
		if events.size()>40: events.pop_front()
		split_count+=1;a.last_event="school split; individuals conserved"
	if not a.get("individual",false) and int(a.get("escapees",0))==0 and a.fear<.1 and p.elapsed>=a.merge_after:
		for other_index in eco.forage_zones[int(a.zone)].duplicate():
			if other_index==index: continue
			var other: Dictionary=eco.forage[other_index]
			if int(other.get("escapees",0))>0 or other.get("individual",false) or not other.active or other.kind!=a.kind or other.fear>.1 or other.quantity+a.quantity>160: continue
			if Vector2(a.x-other.x,a.y-other.y).length()>12 or not nav.clear(Vector2(a.x,a.y),Vector2(other.x,other.y)): continue
			other.quantity+=a.quantity;other.capacity+=a.capacity;other.merge_after=p.elapsed+60;other.last_event="school regrouped / merged"
			a.quantity=0;a.active=false;a.merged_into=other.id;a.activity="merged";events.append({"time":p.elapsed,"kind":"merge","id":a.id,"other":other.id,"position":Vector2(a.x,a.y)});eco.forage_zones[int(a.zone)].erase(index);merge_count+=1;break
		a.merge_after=p.elapsed+30
	while events.size()>40: events.pop_front()
func serialize() -> Dictionary:
	return {"threats":threats,"events":events,"nutrients":nutrients,"bottom":bottom,"clock":clock,"split_count":split_count,"merge_count":merge_count,"next_bait_id":next_bait_id}


func spawn_single(kind: int,at: Vector2) -> int:
	if kind<0 or kind>=eco.FORAGE_NAMES.size() or not nav.wet(at): return -1
	var node: int=nav.nearest(at)
	if node<0: return -1
	var a := {"id":0,"kind":kind,"individual":true,"zone":int(nav.nodes[node].zone),"destination":-1,"x":at.x,"y":at.y,"quantity":1.0,"capacity":1.0,"size_cm":float(eco.FORAGE_SIZES[kind]),"last":p.elapsed,"next":p.elapsed,"jump_at":p.elapsed+30,"jump_until":0.0,"scatter_until":0.0,"preferred_area":area_for_feature(node,"feeding")}
	initialize_bait(a)
	var index := register_bait(a)
	if index>=0:
		p.water_column.initialize_record(a,false);a.detail=0;a.update_due=p.elapsed;a.activity="foraging alone";a.last_event="placed from Fish Lab"
	return index
