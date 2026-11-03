extends RefCounted
# One startup handoff, then view-only snapshots. This adapter never advances animal biology.
const STRIDE := 53
var p
var engine
var stats: Dictionary = {}
var view := Rect2()
var marker_span := 14000.0
var candidates: Array = []
var dots: Array = []
var positions: Dictionary = {}
var previous: Dictionary = {}
var received := 0.0
var poll_at := 0.0
var revision := 0
var transfer_ms := 0.0
var cpu_limit_ms := 12.0
func initialize(population) -> bool:
 p=population
 if not ClassDB.class_exists("BaySimulation"): return false
 engine=ClassDB.instantiate("BaySimulation")
 if not engine.has_method("find_trophy"):
  push_error("Native ecosystem is older than the scripts. Rebuild with Play BayGame.bat.");engine=null;return false
 var animals: Array=[];var eco=p.ecology;var nav=p.movement.nav
 for i in range(p.ids.size()):
  animals.append({"kind":0,"index":i,"id":p.ids[i],"species":int(p.species[i]),"x":p.east[i],"y":p.south[i],"depth":p.water_column.current[i],"size":p.size_cm[i],"hunger":p.hunger[i],"energy":1.0,"home":p.movement.preferred_rest[i],"feeding":p.movement.preferred_feed[i],"zone":p.region[i],"school":eco.school[i],"habitats":eco.profile(i).habitats,"profile":p.hunting.profile(i)})
 for i in range(eco.forage.size()):
  var a: Dictionary=eco.forage[i]
  animals.append({"kind":1,"index":i,"id":a.id,"species":a.kind,"x":a.x,"y":a.y,"depth":a.swim_depth,"size":a.size_cm,"hunger":0 if a.get("individual",false) else a.get("hunger",.3),"home":nav.nearest(Vector2(a.x,a.y)),"zone":a.zone,"quantity":a.quantity,"capacity":a.capacity,"individual":a.get("individual",false),"temporary":a.get("temporary",false),"parent_id":maxi(0,int(a.get("parent_id",0)))})
 for i in range(eco.predators.size()):
  var a: Dictionary=eco.predators[i]
  animals.append({"kind":2,"index":i,"id":a.id,"species":a.kind,"x":a.x,"y":a.y,"depth":a.swim_depth,"size":a.size_cm,"hunger":a.hunger,"home":nav.nearest(Vector2(a.x,a.y)),"zone":a.zone,"school":a.get("pod",-1),"profile":p.hunting.profile(-i-1)})
 for i in range(p.food_web.bottom.size()):
  var a: Dictionary=p.food_web.bottom[i]
  animals.append({"kind":3,"index":i,"id":i+1,"species":5,"x":a.x,"y":a.y,"size":a.size_cm,"depth":eco.depth_at(a.zone),"zone":a.zone,"quantity":a.quantity,"capacity":a.capacity})
 if not engine.initialize({"origin":nav.origin,"width":nav.width,"height":nav.height,"cell":nav.cell,"mask":nav.mask,"nodes":nav.nodes.values(),"habitats":p.food_web.areas,"animals":animals,"ecology":eco.config,"attack_resolution":p.hunting.rules.get("attack_resolution",{}),"seed":18472}): engine=null;return false
 cpu_limit_ms=float(eco.config.get("native_cpu_budget_ms",12))
 p.movement.nav.shutdown()
 print("[Native ecosystem] C++ worker owns %d records; GDScript simulation disabled" % animals.size())
 return true
func selected_code() -> int:
 if p.observed_fish>=0: return p.observed_fish
 if p.food_web.observed_bait>=0: return 1000000+p.food_web.observed_bait
 if p.simulation_detail.selected_predator>=0: return 2000000+p.simulation_detail.selected_predator
 return -1
func tick(paused := false):
 var started := Time.get_ticks_usec();var now := started/1000000.0
 engine.set_controls({"speed":0 if paused else p.time_scale,"boat":p.simulation_detail.boat,"camera":p.simulation_detail.camera,"tide":p.ecology.tide_level_m,"lod":p.simulation_detail.enabled,"detailed":p.simulation_detail.detailed_m,"intermediate":p.simulation_detail.intermediate_m,"hysteresis":p.simulation_detail.hysteresis_m,"selected":selected_code(),"cpu_ms":cpu_limit_ms,"marker_span":marker_span})
 if now<poll_at: return
 poll_at=now+.05
 var snapshot: Dictionary=engine.read_view(view,selected_code())
 if snapshot.is_empty(): return
 stats=snapshot.stats;p.elapsed=float(stats.time);p.time_debt=float(stats.backlog);p.sim_phase=-1;p.completed_steps=int(p.elapsed/.5)
 previous.clear()
 for code in positions: previous[code]=displayed(code)
 positions.clear();received=now;candidates.clear();dots=snapshot.dots
 var rows: PackedFloat64Array=snapshot.rows
 for offset in range(0,rows.size(),STRIDE):
  var code := int(rows[offset]);var kind := code/1000000;var index := code%1000000;var at := Vector2(rows[offset+4],rows[offset+5])
  positions[code]=at
  if not previous.has(code): previous[code]=at
  var heading := Vector2(rows[offset+37],rows[offset+38]);var target := int(rows[offset+23])
  var state: Dictionary={}
  if kind==3:
   var bottom: Dictionary=p.food_web.bottom[index];bottom.x=at.x;bottom.y=at.y;bottom.quantity=rows[offset+20]
   continue
  if kind==0:
   p.east[index]=at.x;p.south[index]=at.y;p.size_cm[index]=rows[offset+12];p.hunger[index]=rows[offset+13];p.region[index]=int(rows[offset+18]);p.ecology.alive[index]=int(rows[offset+30]);p.simulation_detail.fish_levels[index]=int(rows[offset+17]);p.ecology.school[index]=int(rows[offset+19]);p.movement.headings[index]=heading
   p.water_column.current[index]=rows[offset+8];p.water_column.holding[index]=rows[offset+9];p.water_column.target[index]=rows[offset+10];p.water_column.bottom[index]=rows[offset+11]
   state=p.hunting.state(index)
   p.behavior[index]=5 if int(rows[offset+16])==10 else (4 if int(rows[offset+16]) in [2,3,5] else 3)
   if rows[offset+30]>0: candidates.append(1000000+index)
  else:
   var records: Array=p.ecology.forage if kind==1 else p.ecology.predators
   while records.size()<=index: records.append({})
   var a: Dictionary=records[index]
   if a.is_empty():
    a.merge({"id":0,"kind":int(rows[offset+3]),"zone":int(rows[offset+18]),"destination":-1,"quantity":1.0,"capacity":1.0,"size_cm":rows[offset+12],"active":true,"jump_until":0.0,"scatter_until":0.0,"preferred_area":"","last_event":"","cohesion":.7,"stretch":1.0,"formation_phase":0.0,"hunt":p.hunting.initial()})
   if int(a.id)!=int(rows[offset+1]): p.food_web.bait_slots.erase(int(a.id))
   a.native_axes=Vector2(rows[offset+39],rows[offset+40]);a.native_targeters=int(rows[offset+44]);a.native_child_targeters=int(rows[offset+45]);a.native_threat=Vector2(rows[offset+46],rows[offset+47]);a.native_destination=Vector2(rows[offset+28],rows[offset+29]);a.id=int(rows[offset+1]);a.x=at.x;a.y=at.y;a.kind=int(rows[offset+3]);a.size_cm=rows[offset+12];a.hunger=rows[offset+13];a.fear=rows[offset+15];a.swim_depth=rows[offset+8];a.holding_depth=rows[offset+9];a.target_depth=rows[offset+10];a.bottom_depth=rows[offset+11];a.heading=heading;a.detail=int(rows[offset+17]);a.zone=int(rows[offset+18]);a.quantity=rows[offset+20];a.escapees=int(rows[offset+21]);a.parent_id=int(rows[offset+22]);a.active=rows[offset+30]>0;a.temporary=rows[offset+31]>0;a.individual=rows[offset+32]>0;a.vertical_spread=rows[offset+33];a.cohesion=clampf(.8-a.fear*.4,.25,.9);a.stretch=1+Vector2(rows[offset+6],rows[offset+7]).length()*.3;a.activity=activity(int(rows[offset+16]));a.last=p.elapsed;a.last_event=event_name(int(rows[offset+34]));a.natural_path=PackedVector2Array([at,Vector2(rows[offset+28],rows[offset+29])]);a.path_cursor=1
   if kind==1:
    p.food_web.bait_slots[int(a.id)]=index
    if a.active: candidates.append(index)
   else: state=p.hunting.state(-index-1)
  if not state.is_empty():
   state.consume_remaining=rows[offset+48];state.recover_remaining=rows[offset+49];state.swimming_mph=rows[offset+50]/.44704;state.capture_age=rows[offset+51];state.motivated=rows[offset+52]>0
   state.native_detect=rows[offset+41];state.native_awareness=rows[offset+42];state.native_cone_cos=rows[offset+43];state.school_pressure=int(rows[offset+16])==12;state.stage=0 if int(rows[offset+16])>=16 else (2 if int(rows[offset+16])==12 else mini(9,int(rows[offset+16])));state.activity=activity(int(rows[offset+16]));state.energy=rows[offset+14];state.captures=int(rows[offset+25]);state.misses=int(rows[offset+26]);state.attempts=int(rows[offset+27]);state.heading=heading;state.last_event=event_name(int(rows[offset+34]));state.path=PackedVector2Array([at,Vector2(rows[offset+28],rows[offset+29])]);state.cursor=1;state.kind=-1 if target<0 else (1 if target<1000000 else (0 if target<2000000 else 2));state.target=-1 if target<0 else target%1000000;state.target_id=int(rows[offset+24]);state.capture_position=at;state.capture_depth=rows[offset+8];state.capture_time=p.elapsed
 p.hunting.prey_cache.clear();p.hunting.prey_epoch=-1
 revision+=1;transfer_ms=(Time.get_ticks_usec()-started)/1000.0;p.update_ms=transfer_ms
func find_active_hunt() -> Dictionary:
 return observe_found(engine.find_active_hunt())
func find_trophy(excluded: int) -> Dictionary:
 return observe_found(engine.find_trophy(excluded))
func observe_found(found: Dictionary) -> Dictionary:
 if found.is_empty(): return found
 var code: int=found.code;var at: Vector2=found.position
 # Seed observation only, so first selection/follow cannot jump to a stale shadow position.
 positions[code]=at;previous[code]=at
 if code<1000000: p.east[code]=at.x;p.south[code]=at.y
 else:
  var a: Dictionary=p.ecology.predators[code-2000000];a.x=at.x;a.y=at.y
 return found
func displayed(code: int) -> Vector2:
 var at: Vector2=positions.get(code,Vector2.ZERO)
 return Vector2(previous.get(code,at)).lerp(at,clampf((Time.get_ticks_usec()/1000000.0-received)/.05,0,1))
func activity(state: int) -> String:
 return ["searching / habitat patrol","detecting prey","approaching prey","pursuing / intercepting","holding ambush","strike","capture","miss","consuming prey","resting / slow patrol","evading predator","returning to school","pressuring school","traveling to shelter","seeking school / sheltering","holding at shelter","cruising near detected food","investigating fading bait trail / feeding sound","returning to remembered food location","investigating prey size / suitability"][clampi(state,0,19)]
func event_name(event: int) -> String:
 return ["native ecological activity","mathematical capture","predator disturbance","miss; pursuit may continue","consumed / rejoined","prey detected"][clampi(event,0,5)]
func shutdown():
 if engine!=null: engine.shutdown();engine=null
 p=null
func report() -> String:
 if stats.is_empty(): return "Native simulation initializing"
 return "BayGame native worker | FPS %.1f | requested %.0fx\nSimulation %.2f s | queued %.2f s | CPU %.2f ms/s | transfer %.2f ms\nD/I/B %s | fish/bait/predators/bottom %s\nEvents %d | consumed %d | detached %d | rejoined %d\nNative record/mask allocation %.1f MiB | navigation %.1f ms total\n" % [Engine.get_frames_per_second(),p.time_scale,p.elapsed,p.time_debt,float(stats.cpu_ms)/maxf(.001,float(stats.wall)),transfer_ms,str(stats.levels),str(stats.population),stats.events,stats.consumed,stats.detached,stats.rejoined,float(stats.memory_bytes)/1048576.0,stats.navigation_ms]
