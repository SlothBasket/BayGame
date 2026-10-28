class_name FishHunting
extends RefCounted
# Shared physical hunt sequence for game fish (>=0) and predator records (-index-1).
enum Stage { SEARCH, DETECT, APPROACH, PURSUE, AMBUSH, STRIKE, CAPTURE, MISS, CONSUME, RECOVER }
const SEARCH_LABELS := {"patrol":"patrolling shoreline edges","bottom":"searching bottom / grass edges","structure":"inspecting structure","bottom_ambush":"relocating bottom ambush","ambush":"searching cover / intercept position","intercept":"inspecting cuts / potholes","chase":"sweeping for moving bait","travel":"tracking forage concentrations","shark":"searching prey habitat","dolphin":"pod searching for schools"}
const LABELS := ["search","detect","approach / stalk","pursue","ambush / wait","strike","capture","miss / escape","consume","recover"]
var p
var eco
var web
var nav
var spatial := FishSpatialIndex.new()
var profile_cache: Dictionary = {}
var states: Array = []
var events: Array = []
var rules: Dictionary = {}
var ready := false
var last_error := ""
func fail(reason: String) -> bool:
	last_error=reason;return false
func initial() -> Dictionary:
	return {"stage":Stage.SEARCH,"kind":-1,"target":-1,"until":0.0,"detect_at":0.0,"replan_at":0.0,"energy":1.0,"velocity":0.0,"path":PackedVector2Array(),"cursor":0,"heading":Vector2.ZERO,"last_event":"","captures":0,"misses":0,"search_failures":0,"hold_until":0.0,"hold_anchor":Vector2.ZERO,"activity":"searching","meal":0.0,"prey_cm":0.0}
func setup(population,root: String,saved: Dictionary) -> bool:
	p=population;eco=p.ecology;web=p.food_web;nav=p.movement.nav
	rules=JSON.parse_string(FileAccess.get_file_as_string(root+"hunting-config.json"))
	for i in range(p.ids.size()): states.append(initial())
	if not saved.is_empty():
		if not saved.get("states") is Array or saved.states.size()!=p.ids.size(): return fail("saved hunting states incompatible")
		for state in saved.states:
			for key in initial():
				if not state.has(key): return fail("saved hunting states incompatible")
			if state.stage<0 or state.stage>=LABELS.size() or state.kind < -1 or state.kind>2: return fail("saved hunting states incompatible")
		states=saved.states;events=saved.get("events",[])
	for a in eco.predators:
		if not a.has("hunt"): a.hunt=initial()
	for i in range(eco.forage.size()): index_entity(0,i)
	for i in range(p.ids.size()): index_entity(1,i)
	for i in range(web.bottom.size()): index_entity(2,i)
	ready=true;return true
func state(actor: int) -> Dictionary:
	if actor>=0: return states[actor]
	var a: Dictionary=eco.predators[-actor-1]
	if not a.has("hunt"): a.hunt=initial()
	return a.hunt
func position(actor: int) -> Vector2:
	return Vector2(p.east[actor],p.south[actor]) if actor>=0 else Vector2(eco.predators[-actor-1].x,eco.predators[-actor-1].y)
func zone(actor: int) -> int:
	return p.region[actor] if actor>=0 else eco.predators[-actor-1].zone
func length_cm(actor: int) -> float:
	return p.size_cm[actor] if actor>=0 else eco.predators[-actor-1].size_cm
func hunger(actor: int) -> float:
	return p.hunger[actor] if actor>=0 else eco.predators[-actor-1].hunger
func set_hunger(actor: int,value: float):
	if actor>=0: p.hunger[actor]=clampf(value,0,1)
	else: eco.predators[-actor-1].hunger=clampf(value,0,1)
func profile(actor: int) -> Dictionary:
	var band := 0 if length_cm(actor)<45 else (1 if length_cm(actor)<55 else 2)
	if profile_cache.has(actor) and profile_cache[actor]._band==band: return profile_cache[actor]
	var r: Dictionary=rules.game_fish[int(p.species[actor])].duplicate() if actor>=0 else rules.predators[int(eco.predators[-actor-1].kind)].duplicate()
	if actor>=0:
		var size: float=p.size_cm[actor]
		if p.species[actor]==0: r.style="bottom" if size<45 else "patrol"
		if p.species[actor]==1 and size>55: r.style="intercept"
		if p.species[actor]==2 and size<45: r.detect_ft*=.7;r.activity="juvenile cover ambush / surface strike"
		r.gape=float(eco.profile(actor).max_prey_ratio)
	r._band=band;profile_cache[actor]=r
	return r
func prey(kind: int,index: int) -> Dictionary:
	if kind==0:
		if index<0 or index>=eco.forage.size(): return {}
		var a: Dictionary=eco.forage[index]
		if not a.get("active",true) or a.quantity<1: return {}
		return {"position":Vector2(a.x,a.y),"size":a.size_cm,"heading":a.get("heading",Vector2.ZERO),"speed":float(a.get("speed_mps",1.3 if a.fear>.3 else .3)),"cover":.25 if a.kind in [0,2,3,4,5] else .05,"bottom":a.kind in [4,5],"label":eco.FORAGE_NAMES[int(a.kind)],"zone":int(a.zone)}
	if kind==1:
		if index<0 or index>=p.ids.size() or eco.alive[index]==0: return {}
		return {"position":Vector2(p.east[index],p.south[index]),"size":p.size_cm[index],"heading":p.movement.headings[index],"speed":p.speed[index],"cover":.25 if p.species[index] in [2,3,6] else .05,"bottom":false,"label":"Fish #"+str(p.ids[index]),"zone":int(p.region[index])}
	if kind==2:
		if index<0 or index>=web.bottom.size(): return {}
		var b: Dictionary=web.bottom[index]
		if b.quantity<1: return {}
		return {"position":Vector2(b.x,b.y),"size":b.size_cm,"heading":Vector2.ZERO,"speed":0.0,"cover":.1,"bottom":true,"label":b.kind,"zone":int(b.zone)}
	return {}
func school_radius(index: int) -> float:
	# Physical aggregate footprint in metres, independent of map zoom or UI marker size.
	return clampf(sqrt(maxf(1,eco.forage[index].quantity))*.35,1.0,12.0)
func prey_position(actor: int,kind: int,index: int,data: Dictionary) -> Vector2:
	var at: Vector2=data.position
	if kind!=0: return at
	var a: Dictionary=eco.forage[index]
	if a.get("individual",false): return at
	var member: int=int(state(actor).get("member",0))
	var seed_value := (actor+10001)*7919+int(a.id)*137+member*613
	var angle := float(posmod(seed_value,6283))*.001
	var offset: Vector2=web.member_offset(a,seed_value,school_radius(index))
	return at+offset if nav.clear(at,at+offset) else at
func attack_cooldown(r: Dictionary) -> float:
	return float(r.get("attack_cooldown_seconds",3.0))
func suitable(actor: int,kind: int,index: int,data: Dictionary,r: Dictionary) -> bool:
	if data.is_empty() or (kind==1 and actor==index): return false
	if r.style in ["structure","bottom_shark"] and not data.bottom: return false
	return float(data.size)<=length_cm(actor)*float(r.gape)
func detect(actor: int,s: Dictionary,r: Dictionary) -> bool:
	var at := position(actor);var best := -INF;var selected_kind := -1;var selected_id := -1
	var radius: float=float(r.detect_ft)*.3048*(.75+.25*s.energy)
	for code in spatial.query(at,radius*1.5):
		var candidate := Vector2i(int(code)/FishSpatialIndex.STRIDE,int(code)%FishSpatialIndex.STRIDE)
		var data := prey(candidate.x,candidate.y)
		if not suitable(actor,candidate.x,candidate.y,data,r): continue
		var target := prey_position(actor,candidate.x,candidate.y,data);var distance: float=p.water_column.distance_to_prey(actor,candidate.x,candidate.y,data)
		var senses: float=1.3 if r.sense in ["electroreception / scent","echolocation"] else 1.0
		var detection: float=radius*senses*(1.0-float(data.cover)*.5)*(1.1 if data.speed>.4 else .9)
		if distance>detection or not nav.clear(at,target): continue
		var score: float=(.5 if candidate.x==0 and eco.forage[candidate.y].get("individual",false) else 0.0)+hunger(actor)*2+float(data.size)/maxf(1,length_cm(actor))-distance/maxf(1,detection)-float(data.cover)
		if candidate.x==2 and r.style in ["bottom","structure","bottom_shark"]: score+=1
		if r.style=="chase" and actor>=0 and eco.school[actor]>=0:
			for member in eco.schools.get(eco.school[actor],[]):
				if member!=actor and states[member].kind==candidate.x and states[member].target==candidate.y and states[member].stage in [Stage.APPROACH,Stage.PURSUE]: score+=.7;break
		if r.style=="dolphin":
			for other in eco.predators:
				if other.kind==3 and other.pod==eco.predators[-actor-1].pod and other.has("hunt") and other.hunt.kind==candidate.x and other.hunt.target==candidate.y: score+=.7;break
		if score>best: best=score;selected_kind=candidate.x;selected_id=candidate.y
	if selected_kind<0: s.search_failures+=1;return false
	s.traffic_position=prey(selected_kind,selected_id).position;s.traffic_seen=p.elapsed;s.kind=selected_kind;s.target=selected_id;s.target_id=eco.forage[selected_id].id if selected_kind==0 else -1;s.hunt_until=p.elapsed+90;s.progress_at=p.elapsed;s.best_distance=INF;s.ambush_until=p.elapsed+minf(12,float(r.wait_seconds));s.stage=Stage.DETECT;s.until=p.elapsed+.5;s.search_failures=0
	event(actor,s,"detected "+prey(selected_kind,selected_id).label);return true
func event(actor: int,s: Dictionary,text: String):
	s.last_event=text
	events.append({"time":p.elapsed,"actor":actor,"position":position(actor),"kind":s.kind,"target":s.target,"text":text})
	if events.size()>80: events.pop_front()
func scare(actor: int,s: Dictionary):
	web.feeding_disturbance(actor,position(actor))
	web.threaten(actor,position(actor),35 if actor>=0 else 80)
	if s.kind==0 and s.target>=0 and s.target<eco.forage.size(): web.flee(eco.forage[s.target],position(actor))
	if s.kind==1 and s.target>=0 and eco.alive[s.target]==1:
		p.behavior[s.target]=5;p.decision_at[s.target]=p.elapsed;eco.pressure[p.region[s.target]]=maxf(.5,eco.pressure[p.region[s.target]])
func set_position(actor: int,at: Vector2,heading: Vector2):
	var anchor: int=nav.nearest(at)
	if actor>=0:
		p.east[actor]=at.x;p.south[actor]=at.y;p.movement.headings[actor]=heading
		if anchor>=0: p.movement.update_region(actor,int(nav.nodes[anchor].zone))
	else:
		var a: Dictionary=eco.predators[-actor-1];a.x=at.x;a.y=at.y;a.heading=heading
		if anchor>=0: a.zone=int(nav.nodes[anchor].zone)
	if p.water_column!=null: p.water_column.constrain_actor(actor,at)
func move_hunter(actor: int,s: Dictionary,target: Vector2,dt: float,r: Dictionary,fast: bool):
	var at := position(actor);var limit: float=float(r.burst_mph if fast else r.cruise_mph)*.44704*(.7+.3*minf(1.5,length_cm(actor)/70.0))
	s.velocity=move_toward(float(s.velocity),limit,dt*2.0)
	if nav.clear(at,target):
		s.path=PackedVector2Array([at,target]);s.cursor=1
	elif s.path.is_empty() or (s.cursor>=s.path.size() and at.distance_squared_to(target)>.25) or (p.elapsed>=s.replan_at and target.distance_squared_to(s.get("planned_target",Vector2.INF))>9):
		var goal: int=nav.nearest(target)
		if goal>=0: s.path=nav.route(at,target,goal);s.cursor=1
		s.replan_at=p.elapsed+2;s.planned_target=target
	if s.path.is_empty(): return
	var moved: Dictionary=p.movement.advance(at,s.path,int(s.cursor),s.velocity*dt,actor+90000,s.heading,true,.12)
	s.cursor=moved.cursor;s.heading=moved.heading;set_position(actor,moved.position,moved.heading)
	s.energy=maxf(0,s.energy-dt*(.0015 if fast else .00015))
func search_habitat(actor: int,s: Dictionary,r: Dictionary,dt: float):
	var at := position(actor)
	var waiting: bool=r.style in ["ambush","bottom_ambush","intercept"]
	if waiting and p.elapsed<float(s.get("search_wait_until",0)):
		s.activity="waiting in ambush";s.energy=minf(1,s.energy+dt*.001);return
	if not s.has("search_goal") or at.distance_to(s.search_goal)<2 or p.elapsed>=float(s.get("search_until",0)):
		if waiting and s.has("search_goal") and at.distance_to(s.search_goal)<2:
			s.erase("search_goal");s.search_wait_until=p.elapsed+minf(45,float(r.wait_seconds));return
		var feature: int=nav.nearest(at)
		if actor>=0:
			# Inspect multiple positions within stable preferred areas before relocating.
			if s.search_failures>=12: feature=p.movement.preferred_feed[actor]
			if s.search_failures>=18:
				var anchor: int=nav.nearest(at)
				if anchor>=0:
					var alternative: int=p.movement.habitat(actor,zone(actor),int(nav.nodes[anchor].component),actor+int(p.elapsed/30))
					if alternative>=0: feature=alternative
		if feature<0: s.activity="searching for reachable habitat";return
		var goal: Vector2=web.feature_destination(feature,"feeding",actor+int(p.elapsed/15))
		var cue: Vector2=web.nearby_disturbance(at,float(r.detect_ft)*.3048)
		if cue!=Vector2.INF and hunger(actor)>.4 and p.rng.randf()<(.65 if r.style in ["chase","travel","dolphin"] else .2) and nav.clear(at,cue):
			goal=cue;s.activity="investigating nearby feeding disturbance";s.detect_at=p.elapsed
		# Only locations witnessed during actual detection become learned traffic sites.
		if waiting and p.elapsed-float(s.get("traffic_seen",-1000))<180 and s.search_failures<12:
			var learned: int=nav.nearest(s.traffic_position)
			if learned>=0 and nav.nodes[learned].component==nav.nodes[feature].component:
				goal=nav.offset(learned,actor+int(p.elapsed/30),12)
		if actor>=0 and eco.school[actor]>=0 and r.style=="chase":
			for member in eco.schools.get(eco.school[actor],[]):
				if member!=actor and eco.alive[member]==1 and states[member].has("search_goal"):
					var shared: Vector2=states[member].search_goal+Vector2.from_angle(float(actor))*3
					if nav.clear(goal,shared): goal=shared
					break
		s.search_goal=goal;s.search_until=p.elapsed+60;s.path=PackedVector2Array();s.cursor=0

	s.activity=SEARCH_LABELS.get(r.style,"searching habitat")
	if actor>=0: p.behavior[actor]=3
	move_hunter(actor,s,s.search_goal,dt,r,false)
func abandon(actor: int,s: Dictionary,reason: String):
	s.stage=Stage.SEARCH;s.kind=-1;s.target=-1;s.detect_at=p.elapsed+2;s.path=PackedVector2Array();s.cursor=0;s.search_failures+=1;s.erase("search_goal");s.search_wait_until=0
	event(actor,s,reason)
func step(actor: int,dt: float) -> bool:
	var s := state(actor);var r := profile(actor);var at := position(actor)
	if actor>=0 and eco.pressure[zone(actor)]>.45 and eco.boldness[actor]<.8:
		if s.stage!=Stage.SEARCH: s.stage=Stage.SEARCH;s.kind=-1;p.movement.routes[actor]=PackedVector2Array();p.movement.cursors[actor]=0;p.decision_at[actor]=p.elapsed
		return false
	if s.stage==Stage.RECOVER:
		s.energy=minf(1,s.energy+dt*.015);s.activity="recovering / resting"
		if p.elapsed>=s.until and s.energy>=.65 and hunger(actor)>=.40+float(posmod(actor,11))*.008: s.stage=Stage.SEARCH;s.kind=-1;s.detect_at=p.elapsed+2
		if actor>=0: p.behavior[actor]=0
		return true
	if s.stage==Stage.CAPTURE:
		s.stage=Stage.CONSUME;s.until=p.elapsed+float(r.consume_seconds);return true
	if s.stage==Stage.CONSUME:
		if p.elapsed>=s.until:
			set_hunger(actor,hunger(actor)-s.meal)
			if actor>=0:
				p.size_cm[actor]=maxf(p.size_cm[actor],minf(float(eco.profile(actor).size_max_cm),p.size_cm[actor]+minf(.02,s.prey_cm*.002)))
			s.activity="fed; digesting";event(actor,s,"consumed captured prey")
			if hunger(actor)>.35 and s.energy>.25:
				abandon(actor,s,"still hungry; resuming patrol");s.detect_at=p.elapsed+attack_cooldown(r)
			else: s.stage=Stage.RECOVER;s.until=p.elapsed+float(r.recovery_seconds)
		return true
	if s.stage==Stage.MISS:
		if s.energy<.15: s.stage=Stage.RECOVER;s.until=p.elapsed+10;return true
		s.activity="repositioning after missed strike"
		search_habitat(actor,s,r,dt)
		if p.elapsed>=s.until:
			s.member=int(s.get("member",0))+1;abandon(actor,s,"retrying another prey member");s.detect_at=p.elapsed
		return true
	if hunger(actor)<.25 or s.energy<.15:
		s.stage=Stage.RECOVER;s.until=p.elapsed+20;s.kind=-1;s.activity="resting; satisfied or tired";return true
	if s.stage==Stage.SEARCH:
		if p.elapsed>=s.detect_at:
			s.detect_at=p.elapsed+5
			if detect(actor,s,r):
				if actor>=0: p.movement.routes[actor]=PackedVector2Array();p.movement.cursors[actor]=0;p.destination[actor]=-1
				return true
		search_habitat(actor,s,r,dt);return true
	var data := prey(int(s.kind),int(s.target))
	if data.is_empty() or (s.kind==0 and int(s.get("target_id",-1))!=int(eco.forage[s.target].id)):
		abandon(actor,s,"prey lost or consumed by another hunter");return true
	var target := prey_position(actor,int(s.kind),int(s.target),data);var distance: float=p.water_column.distance_to_prey(actor,int(s.kind),int(s.target),data)
	var reach: float=maxf(.35,minf(2.5,float(r.strike_ft)*.3048+length_cm(actor)*.003))
	if s.stage==Stage.STRIKE:
		if p.elapsed<s.until: return true
		# No region-based exception: both near and distant captures require physical contact.
		if distance<=reach and p.water_column.separation(actor,int(s.kind),int(s.target),data)<=reach and nav.clear(at,target):
			var chance: float=clampf(float(r.capture_chance)+s.energy*.08-float(data.speed)*.08,.1,.95)
			if p.rng.randf()<chance:
				if s.kind==0: web.consume_bait(int(s.target))
				elif s.kind==1: eco.consume_fish(s.target)
				else: web.bottom[s.target].quantity-=1;eco.forage_consumed+=1
				s.capture_depth=p.water_column.prey_depth(actor,int(s.kind),int(s.target),data);s.capture_position=target;s.capture_time=p.elapsed;s.captures+=1;s.prey_cm=data.size;s.meal=clampf(.10+float(data.size)/length_cm(actor)*1.3,.10,.75);s.stage=Stage.CAPTURE
				if actor<0: eco.predator_meals+=1
				scare(actor,s);event(actor,s,"capture: "+data.label);return true
		s.misses+=1;s.energy=maxf(0,s.energy-.08);set_hunger(actor,hunger(actor)+.02);s.stage=Stage.MISS;s.until=p.elapsed+attack_cooldown(r)
		scare(actor,s);event(actor,s,"miss / prey escape");return true
	if distance<float(s.get("best_distance",INF))-1:
		s.best_distance=distance;s.progress_at=p.elapsed
	if not s.has("hunt_until"): s.hunt_until=p.elapsed+90;s.progress_at=p.elapsed
	if p.elapsed>=s.hunt_until or p.elapsed-float(s.get("progress_at",p.elapsed))>20:
		abandon(actor,s,"target unproductive; searching another position");return true
	if distance>float(r.detect_ft)*.3048*3 or s.energy<.1:
		abandon(actor,s,"pursuit lost; resuming patrol");return true
	if s.stage==Stage.DETECT:
		if p.elapsed<s.until: return true
		s.stage=Stage.APPROACH;s.activity="stalking detected prey"
	if r.style in ["ambush","bottom_ambush","intercept"] and distance>float(r.lunge_ft)*.3048:
		if not s.has("ambush_until"): s.ambush_until=p.elapsed+12
		var approaching: bool=Vector2(data.heading).dot((at-target).normalized())>.3
		if approaching and p.elapsed<s.ambush_until:
			s.stage=Stage.AMBUSH;s.activity="waiting in ambush for approaching prey";return true
		# Out-of-range or receding prey requires a new intercept, never indefinite waiting.
		s.stage=Stage.APPROACH;s.activity="repositioning to intercept"
		move_hunter(actor,s,target,dt,r,false);return true
	var fast: bool=distance<float(r.lunge_ft)*.3048 or r.style in ["chase","travel","shark","dolphin"]
	s.stage=Stage.PURSUE if fast else Stage.APPROACH
	s.activity="tailing / bottom foraging" if actor>=0 and p.species[actor]==0 and s.kind==2 and eco.depth_at(zone(actor))<1.2 else ("coordinated pursuit" if r.style in ["chase","dolphin"] else LABELS[s.stage])
	if actor>=0: p.behavior[actor]=4
	var lead: Vector2=data.heading*float(data.speed)*minf(2,distance/maxf(.1,float(r.burst_mph)*.44704)*.4)
	var intercept := target+lead
	if r.style in ["chase","dolphin"] and distance>10:
		var side := Vector2(-(target-at).y,(target-at).x).normalized()
		intercept+=side*float(posmod(actor,3)-1)*5.0
	if not nav.clear(target,intercept): intercept=target
	move_hunter(actor,s,intercept,dt,r,fast)
	if fast: web.threaten(actor,position(actor),20 if actor>=0 else 65)
	if p.water_column.distance_to_prey(actor,int(s.kind),int(s.target),data)<=reach:
		s.energy=maxf(0,s.energy-.025);web.feeding_disturbance(actor,position(actor));s.stage=Stage.STRIKE;s.until=p.elapsed+.25;s.activity="rapid surface strike" if actor>=0 and p.species[actor]==2 and p.size_cm[actor]<45 else "strike"
		event(actor,s,s.activity)
	return true
func serialize() -> Dictionary:
	return {"states":states,"events":events}

func index_entity(kind: int,index: int):
	if kind==2: spatial.move(kind,index,Vector2(web.bottom[index].x,web.bottom[index].y));return
	if kind==1:
		if eco.alive[index]==0: spatial.remove_key(kind*FishSpatialIndex.STRIDE+index)
		else: spatial.move(kind,index,Vector2(p.east[index],p.south[index]))
		return
	var a: Dictionary=eco.forage[index]
	if not a.get("active",true) or a.quantity<1: spatial.remove_key(index)
	else: spatial.move(kind,index,Vector2(a.x,a.y))
