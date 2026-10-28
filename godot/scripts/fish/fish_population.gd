class_name FishPopulation
extends RefCounted
var size_distribution_version := 0
var startup_error := ""
var ecology_ready := false
var startup_ready := false
func startup_failed(reason: String) -> bool:
	startup_error=reason;startup_ready=false;return false
func initialize(root: String) -> bool:
	startup_ready=false;startup_error="initialization did not complete"
	# Development sessions always generate fresh fish; serialization remains available but is not called.
	var data: Dictionary={}
	var required := {"ecosystem-config.json":["species"],"bay-population-zones.json":["zones","root_zone"],"bay-habitats.json":["habitats","zone_ids"],"fish-navigation.json":["fingerprint","origin","width","height","cell_m","mask","nodes","zone_nodes"],"habitat-areas.json":["navigation_fingerprint","areas","feature_areas","zone_areas"],"hunting-config.json":["game_fish","predators"]}
	for file in required:
		if not FileAccess.file_exists(root+file): return startup_failed("asset missing: "+file)
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(root+file))
		if not parsed is Dictionary: return startup_failed("invalid JSON asset: "+file)
		for key in required[file]:
			if not parsed.has(key): return startup_failed("asset "+file+" missing "+key)
		data[file]=parsed
	if not FileAccess.file_exists(root+str(data["fish-navigation.json"].mask)): return startup_failed("navigation: water mask missing")
	configure(data["bay-population-zones.json"],int(data["ecosystem-config.json"].get("default_population",8000)))
	if not setup_ecology(data["ecosystem-config.json"],data["bay-habitats.json"]): return startup_failed("ecology initialization failed")
	if not setup_movement(root): return startup_failed("movement: "+movement.last_error)
	if not setup_food_web(root):
		return startup_failed("food web: "+food_web.last_error if not food_web.ready else "hunting: "+hunting.last_error)
	startup_error="";startup_ready=true;return true
func initialization_problem() -> String:
	if not startup_error.is_empty(): return startup_error
	if ecology==null or not ecology_ready: return "ecology not initialized"
	if movement==null or not movement.ready: return "movement not initialized"
	if food_web==null or not food_web.ready: return "food web not initialized"
	if hunting==null or not hunting.ready: return "hunting not initialized"
	return ""
# Packed records, never scene nodes. Positions are absolute world meters.
var ids := PackedInt64Array()
var east := PackedFloat64Array()
var south := PackedFloat64Array()
var region := PackedInt32Array()
var progress := PackedFloat32Array()
var direction := PackedFloat32Array()
var habitat_depth := PackedFloat32Array()
var last_update := PackedFloat64Array()
var buckets: Dictionary = {}
var routes: Array = []
var spatial: Dictionary = {}
var fingerprint := ""
var elapsed := 0.0
var cursor := 0
var near_cursor := 0
var update_ms := 0.0
var near_region := -1
const SPECIES := ["Redfish","Speckled trout","Snook","Sheepshead","Tarpon","Jack crevalle","Flounder"]
var ecology: FishEcology
var pending_ecology: Dictionary = {}
var restored_rng_state := 0
var fresh_population := true
const WORLD_STEP := .5
var time_debt := 0.0
var sim_phase := -1
var sim_cursor := 0
var maintenance_food_dt := 0.0
var restored_pressure_pending := 0.0
var step_forage_count := 0
var completed_steps := 0
var simulation_budget_us := 12000
func pause_simulation():
	time_scale=0
func completed_time() -> float:
	return elapsed-(WORLD_STEP if sim_phase>=0 else 0.0)
var presentation := FishPresentation.new()
var simulation_detail
var water_column
var hunting: FishHunting
var food_web: FishFoodWeb
var movement: FishMovement
var observed_fish := -1
var migration_backup_needed := false
var zones: Array = []
var zone_counts := PackedInt32Array()
var zone_species_counts: Array = []
var species := PackedByteArray()
var size_cm := PackedFloat32Array()
var preferred_depth := PackedFloat32Array()
var hunger := PackedFloat32Array()
var behavior := PackedByteArray()
var destination := PackedInt32Array()
var decision_at := PackedFloat64Array()
var speed := PackedFloat32Array()
var food := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var time_scale := 1.0
var zone_clock := 0.0
var migrations := 0
var decisions := 0
func configure(data: Dictionary, count := 8000):
	if data.has("zones"): configure_zones(data,count);return
	routes=data.routes;fingerprint=JSON.stringify(routes).sha256_text()
	if routes.is_empty(): return
	spatial.clear()
	for r in range(routes.size()):
		var route: Dictionary=routes[r]
		var key := Vector2i(floori((route.a[0]+route.b[0])*.5/512),floori((route.a[1]+route.b[1])*.5/512))
		if not spatial.has(key): spatial[key]=[]
		spatial[key].append(r)
	ids.resize(count);east.resize(count);south.resize(count);region.resize(count);progress.resize(count);direction.resize(count);habitat_depth.resize(count);last_update.resize(count)
	for r in range(routes.size()): buckets[r]=[]
	for i in range(count):
		ids[i]=i+1;region[i]=i%routes.size();progress[i]=float((i*7919)%100003)/100003.0;direction[i]=1.0 if i%2==0 else -1.0
		buckets[region[i]].append(i);place(i)
func place(i: int):
	var route: Dictionary=routes[region[i]]
	var a: Array=route.a;var b: Array=route.b
	east[i]=lerpf(a[0],b[0],progress[i]);south[i]=lerpf(a[1],b[1],progress[i]);habitat_depth[i]=route.depth_m
func advance(i: int,dt: float):
	var route: Dictionary=routes[region[i]]
	progress[i]+=direction[i]*dt*.15/maxf(1,float(route.length_m))
	if progress[i]>1 or progress[i]<0:
		var endpoint := 1 if progress[i]>1 else 0
		var edges: Array=route.edges[endpoint]
		if not edges.is_empty():
			var link: Array=edges[int(ids[i])%edges.size()]
			buckets[region[i]].erase(i);region[i]=int(link[0]);buckets[region[i]].append(i)
			progress[i]=float(link[1]);direction[i]=1.0 if int(link[1])==0 else -1.0
		else: progress[i]=clampf(progress[i],0,1);direction[i]*=-1
	place(i)
func tick(dt: float,player: GeoPosition,depth_service: DepthService=null):
	if not zones.is_empty(): tick_ecosystem(dt,player);return
	if ids.is_empty(): return
	var begin := Time.get_ticks_usec();elapsed+=dt
	# Spatial route index: choose nearby route once a second, independent of camera.
	if int(elapsed)!=int(elapsed-dt):
		near_region=-1;var nearest := 250000.0
		var cell := Vector2i(floori(player.east/512),floori(player.south/512))
		for y in range(-1,2):
			for x in range(-1,2):
				for r in spatial.get(cell+Vector2i(x,y),[]):
					var route: Dictionary=routes[r]
					var dx: float=(route.a[0]+route.b[0])*.5-player.east
					var dy: float=(route.a[1]+route.b[1])*.5-player.south
					var d: float=dx*dx+dy*dy
					if d<nearest: nearest=d;near_region=r

	# Bounded amortized distant updates; each fish receives actual elapsed time.
	for _n in range(mini(500,ids.size())):
		var i := cursor;cursor=(cursor+1)%ids.size()
		if elapsed-last_update[i]<1.0: continue
		advance(i,minf(elapsed-last_update[i],5));last_update[i]=elapsed
	if near_region>=0:
		var members: Array=buckets[near_region]
		for _n in range(mini(64,members.size())):
			if members.is_empty(): break
			near_cursor%=members.size();var i: int=members[near_cursor];near_cursor+=1
			if elapsed-last_update[i]<.1: continue
			if depth_service!=null:
				var d := depth_service.get_depth_metadata(GeoPosition.new(east[i],south[i]))
				if not d.available: continue
				habitat_depth[i]=d.depth
			advance(i,minf(elapsed-last_update[i],5));last_update[i]=elapsed
	update_ms=(Time.get_ticks_usec()-begin)/1000.0
func packed_bytes() -> int:
	return ids.size()*8+east.size()*8+south.size()*8+region.size()*4+progress.size()*4+direction.size()*4+habitat_depth.size()*4+last_update.size()*8+(ids.size()*30+food.size()*4 if not zones.is_empty() else 0)
func save_to(path: String) -> Error:
	if not startup_error.is_empty(): return ERR_UNAVAILABLE
	if not zones.is_empty(): return save_ecosystem(path)
	var f := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f==null: return FileAccess.get_open_error()
	f.store_var({"version":1,"fingerprint":fingerprint,"ids":ids,"east":east,"south":south,"region":region,"progress":progress,"direction":direction,"habitat_depth":habitat_depth,"last_update":last_update,"elapsed":elapsed});f.close()
	return DirAccess.rename_absolute(path+".tmp",path)
func load_from(path: String) -> Error:
	if not zones.is_empty(): return load_ecosystem(path)
	if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
	var f := FileAccess.open(path,FileAccess.READ)
	if f==null: return FileAccess.get_open_error()
	var d = f.get_var(false)
	if not d is Dictionary or d.get("version",0)!=1 or d.get("fingerprint","")!=fingerprint: return ERR_INVALID_DATA
	var count: int=d.ids.size()
	for key in ["east","south","region","progress","direction","habitat_depth","last_update"]:
		if not d.has(key) or d[key].size()!=count: return ERR_INVALID_DATA
	for r in d.region:
		if r<0 or r>=routes.size(): return ERR_INVALID_DATA
	ids=d.ids;east=d.east;south=d.south;region=d.region;progress=d.progress;direction=d.direction;habitat_depth=d.habitat_depth;last_update=d.last_update;elapsed=d.elapsed
	buckets.clear()
	for r in range(routes.size()): buckets[r]=[]
	for i in range(count): buckets[region[i]].append(i)
	cursor=0;near_cursor=0;return OK

func configure_zones(data: Dictionary,count: int):
	zones=data.zones
	for zone in zones: zone.neighbors=Array(PackedInt32Array(zone.neighbors))
	fingerprint=JSON.stringify(zones).sha256_text();rng.randomize()
	ids.resize(count);east.resize(count);south.resize(count);region.resize(count);last_update.resize(count)
	species.resize(count);size_cm.resize(count);preferred_depth.resize(count);hunger.resize(count);behavior.resize(count);destination.resize(count);decision_at.resize(count);speed.resize(count)
	food.resize(zones.size());zone_counts.resize(zones.size());zone_counts.fill(0);zone_species_counts.resize(zones.size());buckets.clear();spatial.clear()
	for z in range(zones.size()):
		buckets[z]=[];zone_species_counts[z]=PackedInt32Array([0,0,0,0,0,0,0]);food[z]=float(zones[z].food_capacity)*rng.randf_range(.4,1)
		var key := Vector2i(floori(float(zones[z].x)/750),floori(float(zones[z].y)/750))
		spatial[key]=z
	for i in range(count):
		ids[i]=i+1;species[i]=i%SPECIES.size();size_cm[i]=rng.randf_range(25,95)
		preferred_depth[i]=[2.0,3.0,4.5,2.0,4.0,4.0,2.5][species[i]]*rng.randf_range(.55,1.6)
		hunger[i]=rng.randf_range(.15,.95);speed[i]=rng.randf_range(.35,.85)*(size_cm[i]/60.0)
		var z := rng.randi_range(0,zones.size()-1)
		for _attempt in range(5):
			var candidate := rng.randi_range(0,zones.size()-1)
			if suitability(i,candidate)>suitability(i,z): z=candidate
		region[i]=z;destination[i]=-1;east[i]=zones[z].x;south[i]=zones[z].y;buckets[z].append(i);zone_counts[z]+=1;zone_species_counts[z][species[i]]+=1
		decision_at[i]=rng.randf_range(0,20)
func suitability(i: int,z: int) -> float:
	return exp(-absf((float(zones[z].depth_m)+(ecology.tide_level_m if ecology!=null else 0.0))-preferred_depth[i])/maxf(.8,preferred_depth[i]*.65))
func choose_destination(i: int):
	var z := region[i];var choices: Array=[z];choices.append_array(zones[z].neighbors)
	var weights: Array[float]=[];var total := 0.0
	for candidate in choices:
		# Softmax plus a nonzero exploration floor avoids a deterministic best-zone herd.
		var score: float=2.5*suitability(i,candidate)+(1.0+3.0*hunger[i])*food[candidate]
		score-=minf(1.5,float(buckets[int(candidate)].size())/25.0)
		if candidate!=z: score-=.45
		if ecology!=null: score+=ecology.destination_score(i,candidate)
		var weight := .12+exp(score)
		if ecology!=null and not ecology.accessible(i,candidate): weight=0
		weights.append(weight);total+=weight
	var roll := rng.randf()*total;var chosen := z
	for n in range(choices.size()):
		roll-=weights[n]
		if roll<=0: chosen=choices[n];break
	decisions+=1
	if chosen!=z: destination[i]=chosen;behavior[i]=1
	else: behavior[i]=2 if hunger[i]>.2 and food[z]>.05 else 0
	decision_at[i]=elapsed+rng.randf_range(45,150)
	if ecology!=null: ecology.on_decision(i)
func update_fish(i: int,dt: float):
	if ecology!=null and not ecology.is_alive(i): return
	hunger[i]=minf(1,hunger[i]+dt*.00006*clampf(60.0/maxf(20,size_cm[i]),.5,1.5)*(1.25 if species[i] in [4,5] else 1.0))
	var z := region[i]
	if ecology!=null:
		if water_column!=null: water_column.update_actor(i,dt)
		ecology.interact(i,dt)
		if simulation_detail!=null and simulation_detail.fish_levels[i]==2: simulation_detail.coarse_hunt(i,dt);return
		if hunting!=null and hunting.ready and hunting.step(i,dt): return
		if movement!=null and movement.ready:
			movement.tick_fish(i,dt);return
		if ecology.move_local(i,dt): return
	if destination[i]>=0:
		var target: Dictionary=zones[destination[i]]
		var dx: float=float(target.x)-east[i];var dy: float=float(target.y)-south[i];var distance := sqrt(dx*dx+dy*dy)
		var travel := speed[i]*dt
		if ecology!=null:
			var flow := ecology.current.dot(Vector2(dx,dy).normalized())
			travel=maxf(.05,speed[i]*(1.7 if behavior[i]==5 else 1.0)+flow)*dt
		if travel>=distance:
			buckets[z].erase(i);zone_counts[z]-=1;zone_species_counts[z][species[i]]-=1;region[i]=destination[i];buckets[region[i]].append(i);zone_counts[region[i]]+=1;zone_species_counts[region[i]][species[i]]+=1;east[i]=target.x;south[i]=target.y;destination[i]=-1;behavior[i]=3;decision_at[i]=elapsed;migrations+=1
			if ecology!=null: ecology.on_arrival(i)
		else:
			east[i]+=dx/distance*travel;south[i]+=dy/distance*travel
		return
	if elapsed>=decision_at[i]: choose_destination(i)
func tick_ecosystem(dt: float,_player: GeoPosition):
	if time_scale>0: presentation.tick(dt)
	if ids.is_empty() or time_scale<=0: update_ms=0;return
	var begin := Time.get_ticks_usec()
	time_debt+=dt*time_scale
	var budget: int=clampi(simulation_budget_us,1000,8000)
	var finished_this_frame := 0
	movement.nav.process_routes()
	food_web.process_maintenance(mini(begin+budget,Time.get_ticks_usec()+750))
	# Deterministic phases and a persistent cursor: frame budgets change throughput, not outcomes.
	while Time.get_ticks_usec()-begin<budget:
		if sim_phase<0:
			if time_debt+0.0000001<WORLD_STEP: break
			time_debt=maxf(0,time_debt-WORLD_STEP);elapsed+=WORLD_STEP;zone_clock+=WORLD_STEP
			if ecology!=null: ecology.tick(WORLD_STEP,null)
			maintenance_food_dt=zone_clock if zone_clock>=2 else 0.0
			if maintenance_food_dt>0: zone_clock=0
			sim_phase=3 if maintenance_food_dt>0 or ecology.pressure_pending>0 else 0;sim_cursor=0;step_forage_count=ecology.forage.size()
		if sim_phase==3:
			if sim_cursor>=zones.size(): ecology.pressure_pending=0;maintenance_food_dt=0;sim_phase=0;sim_cursor=0;continue
			if maintenance_food_dt>0: food[sim_cursor]=move_toward(food[sim_cursor],float(zones[sim_cursor].food_capacity),maintenance_food_dt*.0002)
			if ecology.pressure_pending>0: ecology.pressure[sim_cursor]*=exp(-ecology.pressure_pending/120.0)
			sim_cursor+=1;continue
		if sim_phase==0:
			if sim_cursor>=step_forage_count: sim_phase=1;sim_cursor=0;continue
			var a: Dictionary=ecology.forage[sim_cursor]
			if not a.get("active",true): a.last=elapsed;sim_cursor+=1;continue
			var tier: int=simulation_detail.bait_level(sim_cursor);var interval: float=simulation_detail.intervals[tier];var age: float=maxf(0,elapsed-float(a.last))
			if age+.000001<interval: sim_cursor+=1;continue
			var step := minf(interval,age);var before := Vector2(a.x,a.y)
			if tier==2: simulation_detail.coarse_bait(sim_cursor,step)
			else: ecology.update_forage(sim_cursor,step)
			a.last=minf(elapsed,float(a.last)+step);hunting.index_entity(0,sim_cursor)
			presentation.publish(self,1,sim_cursor,before,Vector2(a.x,a.y),step)
			if age-step+.000001<interval or not a.active: sim_cursor+=1
		elif sim_phase==1:
			if sim_cursor>=ids.size(): sim_phase=2;sim_cursor=0;continue
			if ecology.alive[sim_cursor]==0: last_update[sim_cursor]=elapsed;sim_cursor+=1;continue
			var tier: int=simulation_detail.actor_level(sim_cursor);var interval: float=simulation_detail.intervals[tier];var age := maxf(0,elapsed-last_update[sim_cursor])
			if age+.000001<interval: sim_cursor+=1;continue
			var step := minf(interval,age);var before := Vector2(east[sim_cursor],south[sim_cursor]);update_fish(sim_cursor,step)
			presentation.publish(self,0,sim_cursor,before,Vector2(east[sim_cursor],south[sim_cursor]),step)
			last_update[sim_cursor]=minf(elapsed,last_update[sim_cursor]+step);hunting.index_entity(1,sim_cursor)
			if age-step+.000001<interval: sim_cursor+=1
		else:
			if sim_cursor>=ecology.predators.size():
				sim_phase=-1;sim_cursor=0;completed_steps+=1;finished_this_frame+=1
				if finished_this_frame>=2: break
				continue
			var a: Dictionary=ecology.predators[sim_cursor]
			if not a.active: a.last=elapsed;sim_cursor+=1;continue
			var tier: int=simulation_detail.actor_level(-sim_cursor-1);var interval: float=simulation_detail.intervals[tier];var age: float=maxf(0,elapsed-float(a.last))
			if age+.000001<interval: sim_cursor+=1;continue
			var step := minf(interval,age);var before := Vector2(a.x,a.y);ecology.update_predator(a,step)
			presentation.publish(self,2,sim_cursor,before,Vector2(a.x,a.y),step)
			a.last=minf(elapsed,float(a.last)+step)
			if age-step+.000001<interval: sim_cursor+=1
	update_ms=(Time.get_ticks_usec()-begin)/1000.0
func displayed(kind: int,index: int) -> Vector2:
	var at := Vector2(east[index],south[index]) if kind==0 else Vector2.ZERO
	if kind>0:
		var a: Dictionary=ecology.forage[index] if kind==1 else ecology.predators[index];at=Vector2(a.x,a.y)
	return presentation.position(kind,index,at)
func inspect_fish(i: int) -> Dictionary:
	return {"id":ids[i],"species":SPECIES[species[i]],"size_cm":size_cm[i],"preferred_depth_m":preferred_depth[i],"hunger":hunger[i],"east":east[i],"south":south[i],"zone":zones[region[i]].id,"destination":zones[destination[i]].id if destination[i]>=0 else "staying","state":["resting","traveling","feeding","searching","hunting","fleeing","consumed"][behavior[i]]}
func boost_food(z: int):
	if z>=0 and z<food.size():
		food[z]=1.0
		if ecology!=null:
			for index in ecology.forage_zones.get(z,[]): ecology.forage[index].quantity=ecology.forage[index].capacity
func save_ecosystem(path: String) -> Error:
	if not startup_error.is_empty(): return ERR_UNAVAILABLE
	if migration_backup_needed and FileAccess.file_exists(path):
		var backup := path+".before-world-scheduler"
		if not FileAccess.file_exists(backup):
			var error := DirAccess.copy_absolute(path,backup)
			if error!=OK: return error
		migration_backup_needed=false
	var d := {"version":6 if hunting!=null and hunting.ready else (4 if movement!=null and movement.ready else (3 if ecology!=null else 2)),"fingerprint":fingerprint,"size_distribution_version":size_distribution_version,"elapsed":elapsed,"zone_clock":zone_clock,"rng_state":rng.state,"cursor":cursor,"migrations":migrations,"decisions":decisions}
	for key in ["ids","east","south","region","last_update","species","size_cm","preferred_depth","hunger","behavior","destination","decision_at","speed","food"]: d[key]=get(key)
	d["scheduler"]={"debt":time_debt,"phase":sim_phase,"cursor":sim_cursor,"forage_count":step_forage_count,"completed_steps":completed_steps,"maintenance_food_dt":maintenance_food_dt,"pressure_pending":ecology.pressure_pending if ecology!=null else 0.0}
	if ecology!=null: d["ecology"]=ecology.serialize()
	if water_column!=null: d["water_column"]=water_column.serialize()
	var f := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f==null: return FileAccess.get_open_error()
	f.store_var(d);f.close();return DirAccess.rename_absolute(path+".tmp",path)
func load_ecosystem(path: String) -> Error:
	if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
	var f := FileAccess.open(path,FileAccess.READ)
	if f==null: return FileAccess.get_open_error()
	var d = f.get_var(false)
	if not d is Dictionary or not d.get("version",0) in [2,3,4,5,6] or d.get("fingerprint","")!=fingerprint: return ERR_INVALID_DATA
	if not d.get("ids") is PackedInt64Array or d.ids.is_empty(): return ERR_INVALID_DATA
	var count: int=d.ids.size()
	for key in ["east","south","region","last_update","species","size_cm","preferred_depth","hunger","behavior","destination","decision_at","speed"]:
		if not d.has(key) or d[key].size()!=count: return ERR_INVALID_DATA
	if not d.has("food") or d.food.size()!=zones.size(): return ERR_INVALID_DATA
	for i in range(count):
		if d.region[i]<0 or d.region[i]>=zones.size() or d.destination[i]>=zones.size() or d.destination[i]<-1 or d.species[i]>=SPECIES.size() or d.behavior[i]>6: return ERR_INVALID_DATA
		if d.version<4 and d.destination[i]>=0 and not d.destination[i] in zones[d.region[i]].neighbors: return ERR_INVALID_DATA
	for key in ["ids","east","south","region","last_update","species","size_cm","preferred_depth","hunger","behavior","destination","decision_at","speed","food"]: set(key,d[key])
	size_distribution_version=int(d.get("size_distribution_version",0))
	pending_ecology=d.get("ecology",{})
	var schedule: Dictionary=d.get("scheduler",{})
	time_debt=float(schedule.get("debt",0));sim_phase=int(schedule.get("phase",-1));sim_cursor=int(schedule.get("cursor",0));step_forage_count=int(schedule.get("forage_count",0));completed_steps=int(schedule.get("completed_steps",0))
	maintenance_food_dt=float(schedule.get("maintenance_food_dt",0));restored_pressure_pending=float(schedule.get("pressure_pending",0))
	if sim_phase < -1 or sim_phase>3 or sim_cursor<0 or time_debt<0: return ERR_INVALID_DATA
	restored_rng_state=d.rng_state;fresh_population=false
	migration_backup_needed=int(d.version)<6
	elapsed=d.elapsed;zone_clock=d.zone_clock;rng.state=d.rng_state;cursor=int(d.cursor)%count;migrations=d.migrations;decisions=d.decisions
	buckets.clear()
	for z in range(zones.size()): buckets[z]=[];zone_counts[z]=0;zone_species_counts[z]=PackedInt32Array([0,0,0,0,0,0,0])
	for i in range(count): buckets[region[i]].append(i);zone_counts[region[i]]+=1;zone_species_counts[region[i]][species[i]]+=1
	return OK

func setup_ecology(settings: Dictionary,habitat_data: Dictionary) -> bool:
	# Existing populations are never enlarged during save migration.
	if fresh_population:
		for i in range(ids.size()):
			var profile: Dictionary=settings.species[species[i]]
			size_cm[i]=sample_size_cm(profile,rng)
			preferred_depth[i]=float(profile.depth_m)*rng.randf_range(.6,1.5)
			if species[i] in [4,5] and size_cm[i]<76.2: preferred_depth[i]=rng.randf_range(.8,2.0)
		size_distribution_version=int(settings.get("size_distribution_version",0))
	ecology=FishEcology.new();ecology.setup(self,settings,habitat_data)
	if not pending_ecology.is_empty():
		if not ecology.restore(pending_ecology): return false
		ecology.pressure_pending=restored_pressure_pending
		for i in range(ids.size()):
			if ecology.alive[i]==0:
				buckets[region[i]].erase(i);zone_counts[region[i]]-=1;zone_species_counts[region[i]][species[i]]-=1
		rng.state=restored_rng_state
		ecology_ready=true;return true
	for i in range(ids.size()):
		var profile: Dictionary=settings.species[species[i]]
		# Preserve existing size and depth preferences on migration; calibrate speeds per species.
		speed[i]=float(profile.speed_mps)*rng.randf_range(.75,1.25)
	ecology_ready=true;return true

func setup_movement(root: String) -> bool:
	movement=FishMovement.new()
	return movement.setup(self,root,ecology.pending_movement)

func dispose():
	if simulation_detail!=null: simulation_detail.p=null;simulation_detail=null
	if water_column!=null: water_column.p=null;water_column=null
	if hunting!=null: hunting.p=null;hunting.eco=null;hunting.web=null
	hunting=null
	if food_web!=null: food_web.p=null;food_web.eco=null
	food_web=null
	if movement!=null: movement.nav.shutdown();movement.p=null;movement.eco=null
	if ecology!=null: ecology.population=null
	movement=null;ecology=null

func setup_food_web(root: String) -> bool:
	food_web=FishFoodWeb.new()
	if not food_web.setup(self,root,ecology.pending_food_web): return false
	hunting=FishHunting.new()
	var valid := hunting.setup(self,root,ecology.pending_hunting)
	if valid:
		water_column=preload("res://scripts/fish/fish_water_column.gd").new();water_column.setup(self)
		simulation_detail=preload("res://scripts/fish/fish_simulation_detail.gd").new();simulation_detail.setup(self)
	return valid

static func sample_size_cm(profile: Dictionary,random: RandomNumberGenerator) -> float:
	var bands: Array=profile.get("size_bands_in",[])
	if bands.is_empty(): return random.randf_range(profile.size_min_cm,profile.size_max_cm)
	var total := 0.0
	for b in bands: total+=float(b.weight)
	var choice := random.randf()*total;var band: Dictionary=bands[-1]
	for b in bands:
		choice-=float(b.weight)
		if choice<=0: band=b;break
	var low: float=band.min;var high: float=band.max;var mode: float=band.mode;var u := random.randf()
	var inches := low+sqrt(u*(high-low)*(mode-low)) if u<(mode-low)/(high-low) else high-sqrt((1-u)*(high-low)*(high-mode))
	return inches*2.54
func size_cohort(i: int) -> String:
	var inches := size_cm[i]/2.54
	for band in ecology.config.species[species[i]].get("size_bands_in",[]):
		if inches>=float(band.min) and inches<=float(band.max): return str(band.cohort)
	return "legacy / exceptional individual"
