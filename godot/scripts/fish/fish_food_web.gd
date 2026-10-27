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
var split_count := 0
var merge_count := 0
var ready := false
func setup(population,root: String,saved: Dictionary) -> bool:
	p=population;eco=p.ecology;nav=p.movement.nav
	var data=JSON.parse_string(FileAccess.get_file_as_string(root+"habitat-areas.json"))
	if not data is Dictionary or data.navigation_fingerprint!=nav.fingerprint: return false
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
		if saved.get("nutrients",PackedFloat32Array()).size()!=areas.size() or not saved.get("bottom") is Array: return false
		for b in saved.bottom:
			if not area_by_id.has(b.area) or not nav.wet(Vector2(b.x,b.y)) or b.quantity<0: return false
		bottom=saved.bottom;nutrients=saved.nutrients;clock=saved.get("clock",0);split_count=saved.get("split_count",0);merge_count=saved.get("merge_count",0)
		for z in bottom_zones: bottom_zones[z]=[]
		for index in range(bottom.size()): bottom_zones[int(bottom[index].zone)].append(index)
	for a in eco.forage: initialize_bait(a)
	ready=true;return true
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
func tick(dt: float):
	clock+=dt
	if clock>=10:
		for index in range(nutrients.size()): nutrients[index]=move_toward(nutrients[index],1,clock*.00005)
		for b in bottom: b.quantity=move_toward(b.quantity,b.capacity,clock*float(b.capacity)*.000025)
		clock=0
	for key in threats.keys():
		if threats[key].until<p.elapsed: threats.erase(key)
func threaten(key: int,at: Vector2,radius: float):
	threats[key]={"position":at,"radius":radius,"until":p.elapsed+8}
func flee(a: Dictionary,at: Vector2):
	a.fear=1.0;a.scatter_until=p.elapsed+35;a.flee_from=at;a.next=p.elapsed;a.activity="scattering";a.last_event="escaped / scattered from nearby attack"
func plan_bait(a: Dictionary):
	var at := Vector2(a.x,a.y);var anchor: int=nav.nearest(at)
	if anchor<0: return
	var target := at;var chosen := -1;var score := -INF
	if a.fear>.3:
		var away := (at-Vector2(a.flee_from)).normalized()
		if away==Vector2.ZERO: away=Vector2.from_angle(float(a.id))
		var escape: int=nav.nearest(at+away*160)
		if escape>=0 and nav.nodes[escape].component==nav.nodes[anchor].component: target=nav.point(escape);chosen=escape
	if chosen<0:
		for z in [int(a.zone)]+p.zones[int(a.zone)].neighbors:
			for value in zone_areas[int(z)]:
				var index := int(value);var habitat: Dictionary=areas[index]
				var v: float=float(nutrients[index])+p.rng.randf()*.5-eco.pressure[int(z)]*3
				if "shelter" in habitat.roles and a.kind in [0,2,3,4,5]: v+=.8
				if a.kind>=6 and habitat.kind=="grass_flat_candidate": v+=1.0
				var candidate := sample(index,int(a.id)+int(p.elapsed),int(nav.nodes[anchor].component));var id: int=nav.nearest(candidate)
				if id<0 or nav.nodes[id].component!=nav.nodes[anchor].component: continue
				v-=absf(float(nav.nodes[id].depth_m)-(1.5 if a.kind in [0,2,4,5,6] else 3.0))*.15
				if v>score: score=v;target=candidate;chosen=id;a.preferred_area=habitat.id
	if chosen<0: return
	var path: PackedVector2Array=nav.route(at,target,chosen)
	if path.is_empty(): return
	a.natural_path=path;a.path_cursor=1;a.destination=nav.nodes[chosen].zone;a.goal_feature=chosen;a.turn_at=p.elapsed+10
func update_bait(index: int,dt: float):
	var a: Dictionary=eco.forage[index]
	if not a.active: return
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
		a.quantity=minf(a.capacity,a.quantity+dt*.001*nutrients[area])
		a.activity="grazing algae / detritus" if a.kind>=6 else "foraging / regrouping"
		break
	if a.kind>=6 and p.elapsed>=a.jump_at:
		a.jump_until=p.elapsed+2;a.jump_at=p.elapsed+p.rng.randf_range(40,180);eco.jumps+=1;a.last_event="mullet jump"
	if a.fear>.3: a.activity="fleeing / scattered"
	if p.elapsed>=float(a.next) or (a.fear>.3 and p.elapsed>=a.turn_at):
		plan_bait(a);a.next=p.elapsed+p.rng.randf_range(30,100)
	var velocity := (1.8 if a.kind>=6 else 1.0) if a.fear>.3 else (.45 if a.kind>=6 else (.05 if a.kind in [4,5] else .3))
	p.movement.move_record(a,dt,velocity)
	if a.zone!=z: eco.forage_zones[z].erase(index);eco.forage_zones[int(a.zone)].append(index)
	if a.fear>.6 and a.quantity>=24 and p.elapsed>=a.split_after and eco.forage.size()<6000:
		a.quantity*=.5;a.capacity*=.5;a.split_after=p.elapsed+300;a.merge_after=p.elapsed+80
		var child: Dictionary=a.duplicate(true);child.id=eco.forage.size()+1;child.parent_id=a.id;child.next=p.elapsed;child.turn_at=p.elapsed;child.erase("natural_path")
		eco.forage_zones[int(a.zone)].append(eco.forage.size());eco.forage.append(child);split_count+=1;a.last_event="school split; individuals conserved"
	if a.fear<.1 and p.elapsed>=a.merge_after:
		for other_index in eco.forage_zones[int(a.zone)].duplicate():
			if other_index==index: continue
			var other: Dictionary=eco.forage[other_index]
			if not other.active or other.kind!=a.kind or other.fear>.1 or other.quantity+a.quantity>160: continue
			if Vector2(a.x-other.x,a.y-other.y).length()>12 or not nav.clear(Vector2(a.x,a.y),Vector2(other.x,other.y)): continue
			other.quantity+=a.quantity;other.capacity+=a.capacity;other.merge_after=p.elapsed+60;other.last_event="school regrouped / merged"
			a.quantity=0;a.active=false;a.merged_into=other.id;a.activity="merged";eco.forage_zones[int(a.zone)].erase(index);merge_count+=1;break
		a.merge_after=p.elapsed+30
func serialize() -> Dictionary:
	return {"nutrients":nutrients,"bottom":bottom,"clock":clock,"split_count":split_count,"merge_count":merge_count}

