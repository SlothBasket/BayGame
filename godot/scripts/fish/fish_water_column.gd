extends RefCounted
# Metres below the water surface. No nodes, camera tiers or independent physics bodies.
var p
var current := PackedFloat32Array()
var holding := PackedFloat32Array()
var target := PackedFloat32Array()
var bottom := PackedFloat32Array()
var bathymetry: Dictionary = {}
func setup(population):
	p=population
	current.resize(p.ids.size());holding.resize(p.ids.size());target.resize(p.ids.size());bottom.resize(p.ids.size())
	for i in range(p.ids.size()):
		bottom[i]=bottom_at(Vector2(p.east[i],p.south[i]),int(p.region[i]));holding[i]=holding_for(i,bottom[i]);current[i]=holding[i];target[i]=holding[i]
	for a in p.ecology.forage: initialize_record(a,false)
	for a in p.ecology.predators: initialize_record(a,true)
func bottom_at(at: Vector2,zone: int) -> float:
	var key := Vector2i(floori(at.x/32),floori(at.y/32))
	if not bathymetry.has(key):
		var node: int=p.movement.nav.nearest(at)
		var depth: float=p.movement.nav.nodes[node].depth_m if node>=0 else p.zones[zone].depth_m
		if bathymetry.size()>=16384: bathymetry.clear()
		bathymetry[key]=depth
	return maxf(.05,float(bathymetry[key])+float(p.ecology.tide_level_m))
func within(value: float,bed: float) -> float:
	return clampf(value,0,maxf(0,bed-.02))
func actor_depth(actor: int) -> float:
	return current[actor] if actor>=0 else float(p.ecology.predators[-actor-1].swim_depth)
func holding_for(actor: int,bed: float) -> float:
	var hunger: float=p.hunting.hunger(actor);var ratio := .5
	var personality: float=p.ecology.boldness[actor] if actor>=0 else .5+.2*sin(float(actor))
	if actor>=0:
		match int(p.species[actor]):
			0: ratio=.9 if hunger>.4 else .6
			1: ratio=.65 if p.size_cm[actor]>55 else .45
			2: ratio=.55
			3: ratio=.92
			4: ratio=.2
			5: ratio=.35
			7: ratio=.85 if p.size_cm[actor]>=43.18 else .65
			6: return within(bed-.05,bed)
	else: ratio=.9 if p.ecology.predators[-actor-1].kind==2 else .4
	if p.ecology.pressure[p.hunting.zone(actor)]>.4: ratio=minf(.96,ratio+.15*(1-personality))
	var variation := sin(p.elapsed*.008+float(actor)*1.7)*minf(.25,bed*.05)
	return within(bed*clampf(ratio+(personality-.5)*.12,.05,.98)+variation,bed)
func initialize_record(a: Dictionary,predator: bool):
	var bed := bottom_at(Vector2(a.x,a.y),int(a.zone))
	var desired := holding_for(-int(a.id),bed) if predator else bait_holding(a,bed)
	a.bottom_depth=bed;a.holding_depth=desired;a.target_depth=desired;a.swim_depth=desired;a.vertical_spread=0.0
func bait_holding(a: Dictionary,bed: float) -> float:
	if a.kind in [4,5]: return within(bed-(.06 if a.kind==5 else .15),bed)
	var ratio := .12 if a.kind in [0,6,7] else (.7 if a.kind in [2,3] else .4)
	if float(a.get("fear",0))>.3: ratio+=sin(float(a.id)*2.1)*.25
	return within(bed*ratio+sin(p.elapsed*.012+a.id)*minf(.15,bed*.04),bed)
func update_bait(a: Dictionary,dt: float):
	if not a.has("swim_depth"): initialize_record(a,false)
	var bed := bottom_at(Vector2(a.x,a.y),int(a.zone));a.bottom_depth=bed
	a.holding_depth=move_toward(float(a.holding_depth),bait_holding(a,bed),dt*.08)
	a.target_depth=within(float(a.holding_depth),bed)
	var school_index: int=p.food_web.bait_slots.get(int(a.get("return_school",a.get("school_id",-1))),-1)
	if school_index>=0 and school_index<p.ecology.forage.size() and p.ecology.forage[school_index].active and a.fear<.3:
		a.target_depth=within(float(p.ecology.forage[school_index].swim_depth)+sin(float(a.id))*.1,bed)
	var rate := .04 if a.kind in [4,5] else .12+float(a.fear)*.35
	a.swim_depth=within(move_toward(float(a.swim_depth),float(a.target_depth),dt*rate),bed)
	var spread := 0.0 if a.get("individual",false) or a.kind in [4,5] else minf(bed*.2,.25+float(a.fear)*.6)
	a.vertical_spread=move_toward(float(a.vertical_spread),spread,dt*.12)
func update_actor(actor: int,dt: float):
	var begin := Time.get_ticks_usec()
	_timed_update_actor(actor,dt)
	p.diagnostics.add("Fish depth",Time.get_ticks_usec()-begin)
func _timed_update_actor(actor: int,dt: float):
	var at: Vector2=p.hunting.position(actor);var bed := bottom_at(at,p.hunting.zone(actor))
	var desired := holding_for(actor,bed);var old_hold: float=holding[actor] if actor>=0 else p.ecology.predators[-actor-1].holding_depth
	var hold := within(move_toward(old_hold,desired,dt*.04),bed);var goal := hold
	var s: Dictionary=p.hunting.state(actor)
	if s.stage in [1,2,3,4,5]:
		var prey: Dictionary=p.hunting.tracked_prey(s)
		if not prey.is_empty(): goal=within(prey_depth(actor,int(s.kind),int(s.target),prey),bed)
	var rate := clampf(.04+p.hunting.length_cm(actor)*.0015,.06,.55)
	if actor>=0 and p.species[actor] in [3,6]: rate=minf(rate,.12)
	if s.stage in [3,5]: rate*=1.5
	var depth := within(move_toward(actor_depth(actor),goal,dt*rate),bed)
	if actor>=0: current[actor]=depth;holding[actor]=hold;target[actor]=goal;bottom[actor]=bed
	else:
		var a: Dictionary=p.ecology.predators[-actor-1];a.swim_depth=depth;a.holding_depth=hold;a.target_depth=goal;a.bottom_depth=bed
func constrain_actor(actor: int,at: Vector2):
	var bed := bottom_at(at,p.hunting.zone(actor))
	if actor>=0: current[actor]=within(current[actor],bed);holding[actor]=within(holding[actor],bed);target[actor]=within(target[actor],bed);bottom[actor]=bed
	else:
		var a: Dictionary=p.ecology.predators[-actor-1];a.swim_depth=within(a.swim_depth,bed);a.target_depth=within(a.target_depth,bed);a.holding_depth=within(a.holding_depth,bed);a.bottom_depth=bed
func prey_depth(actor: int,kind: int,index: int,data: Dictionary) -> float:
	if kind==1: return current[index]
	if kind==2: return within(bottom_at(data.position,int(data.zone))-.04,bottom_at(data.position,int(data.zone)))
	var a: Dictionary=p.ecology.forage[index];var s: Dictionary=p.hunting.state(actor)
	var offset := sin(float((actor+10001)*7919+int(a.id)*137+int(s.get("member",0))*613)*.001)*float(a.get("vertical_spread",0))
	if a.get("individual",false): offset=0
	var at: Vector2=p.hunting.prey_position(actor,kind,index,data)
	return within(float(a.swim_depth)+offset,bottom_at(at,int(a.zone)))
func separation(actor: int,kind: int,index: int,data: Dictionary) -> float:
	return absf(actor_depth(actor)-prey_depth(actor,kind,index,data))
func distance_to_prey(actor: int,kind: int,index: int,data: Dictionary) -> float:
	var horizontal: float=p.hunting.position(actor).distance_to(p.hunting.prey_position(actor,kind,index,data))
	return sqrt(horizontal*horizontal+pow(separation(actor,kind,index,data),2))
func serialize() -> Dictionary:
	return {"current":current,"holding":holding,"target":target,"bottom":bottom}
