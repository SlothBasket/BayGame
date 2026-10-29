extends RefCounted
# Indexed heaps: one live entry per record, no stale-event accumulation on promotion/reuse.
const STRIDE := 1000000
var p
var ready := false
var heaps: Array = [[],[],[]]
var due: Dictionary = {}
var tier: Dictionary = {}
var slot: Dictionary = {}
var focus_rects: Array[Rect2i] = []
var focus_cell := Vector2i.ZERO
var focus_members: Array = []
var focus_cursor := 0
var focus_revision := -1
var force_cursor := -1
var pinned: Dictionary = {}
var urgent: Dictionary = {}
func setup(population):
	p=population;ready=true
	for i in range(p.ids.size()): register(0,i)
	for i in range(p.ecology.forage.size()): register(1,i)
	for i in range(p.ecology.predators.size()): register(2,i)
func alive(code: int) -> bool:
	var kind := code/STRIDE;var i := code%STRIDE
	if kind==0: return i<p.ids.size() and p.ecology.alive[i]!=0
	var records: Array=p.ecology.forage if kind==1 else p.ecology.predators
	return i<records.size() and records[i].get("active",true)
func level(code: int) -> int:
	var kind := code/STRIDE;var i := code%STRIDE
	if pinned.has(code) or float(urgent.get(code,0))>p.elapsed:
		if kind==0: p.simulation_detail.fish_levels[i]=0
		elif kind==1: p.ecology.forage[i].detail=0
		else: p.ecology.predators[i].detail=0
		return 0
	return p.simulation_detail.bait_level(i) if kind==1 else p.simulation_detail.actor_level(i if kind==0 else -i-1)
func register(kind: int,index: int):
	if not ready: return
	var code := kind*STRIDE+index
	if not alive(code): cancel(code);return
	var detail := level(code);var interval: float=p.simulation_detail.intervals[detail]
	# Spread first events across their interval. Integrate from last update, never drop time.
	put(code,p.elapsed+maxf(.5,interval*float(1+posmod(index*7919,997))/998.0),detail)
func before(a: int,b: int) -> bool:
	return due[a]<due[b] or (due[a]==due[b] and a<b)
func swap_at(t: int,a: int,b: int):
	var value: int=heaps[t][a];heaps[t][a]=heaps[t][b];heaps[t][b]=value
	slot[heaps[t][a]]=a;slot[value]=b
func up(t: int,at: int):
	while at>0:
		var parent := (at-1)/2
		if not before(heaps[t][at],heaps[t][parent]): break
		swap_at(t,at,parent);at=parent
func down(t: int,at: int):
	while at*2+1<heaps[t].size():
		var child := at*2+1
		if child+1<heaps[t].size() and before(heaps[t][child+1],heaps[t][child]): child+=1
		if not before(heaps[t][child],heaps[t][at]): break
		swap_at(t,at,child);at=child
func cancel(code: int):
	if slot.has(code):
		var t: int=tier[code];var at: int=slot[code];var last: int=heaps[t].pop_back()
		slot.erase(code)
		if at<heaps[t].size():
			heaps[t][at]=last;slot[last]=at;up(t,at);down(t,int(slot[last]))
	due.erase(code);tier.erase(code)
func put(code: int,at: float,detail: int):
	cancel(code);due[code]=at;tier[code]=detail;slot[code]=heaps[detail].size();heaps[detail].append(code);up(detail,heaps[detail].size()-1)
func peek() -> int:
	var best := -1
	for t in range(3):
		if not heaps[t].is_empty() and (best<0 or before(heaps[t][0],best)): best=heaps[t][0]
	return best
func take() -> int:
	var code := peek()
	if code>=0: cancel(code)
	return code
func last_time(code: int) -> float:
	var kind := code/STRIDE;var i := code%STRIDE
	if kind==0: return p.last_update[i]
	return float((p.ecology.forage if kind==1 else p.ecology.predators)[i].last)
func promote(code: int):
	if not alive(code): return
	urgent[code]=p.elapsed+6
	wake(code)
func wake(code: int):
	if not alive(code): cancel(code);return
	if due.has(code) and float(due[code])<=p.elapsed+.5: return
	var detail := level(code)
	var at: float=maxf(p.elapsed,last_time(code)+float(p.simulation_detail.intervals[detail]))
	if not due.has(code) or at<float(due[code]): put(code,at,detail)
func spatial_code(code: int) -> int:
	var kind := code/STRIDE;var i := code%STRIDE
	return STRIDE+i if kind==0 else (i if kind==1 else -1)
func from_spatial(code: int) -> int:
	var kind := code/STRIDE;var i := code%STRIDE
	return i if kind==1 else (STRIDE+i if kind==0 else -1)
func pin(code: int):
	if code<0 or not alive(code): return
	pinned[code]=true;wake(code)
func update_pins():
	for code in urgent.keys():
		if float(urgent[code])<=p.elapsed or not alive(code): urgent.erase(code)
	pinned.clear()
	if p.observed_fish>=0: pin(p.observed_fish);pin_target(p.hunting.state(p.observed_fish))
	if p.food_web.observed_bait>=0: pin(STRIDE+p.food_web.observed_bait)
	if p.simulation_detail.selected_predator>=0:
		pin(2*STRIDE+p.simulation_detail.selected_predator);pin_target(p.hunting.state(-p.simulation_detail.selected_predator-1))
func pin_target(state: Dictionary):
	var index := int(state.get("target",-1));var kind := int(state.get("kind",-1))
	if index<0: return
	if kind==1: pin(index)
	elif kind==0 and index<p.ecology.forage.size() and int(state.get("target_id",-1))==int(p.ecology.forage[index].id): pin(STRIDE+index)
func refresh_focus(deadline: int):
	p.simulation_detail.refresh_focus();update_pins()
	if focus_revision!=p.simulation_detail.revision:
		focus_revision=p.simulation_detail.revision;focus_rects.clear();focus_members=[];focus_cursor=0
		if not p.simulation_detail.enabled: force_cursor=0
		else:
			force_cursor=-1
			var radius: float=p.simulation_detail.intermediate_m+p.simulation_detail.hysteresis_m+256
			for center in [p.simulation_detail.boat,p.simulation_detail.camera]:
				var lo := Vector2i(floori((center.x-radius)/128),floori((center.y-radius)/128))
				var hi := Vector2i(floori((center.x+radius)/128),floori((center.y+radius)/128))
				focus_rects.append(Rect2i(lo,hi-lo+Vector2i.ONE))
			if not focus_rects.is_empty(): focus_cell=focus_rects[0].position
		# Predators are a small fixed population, separately scheduled like other records.
		for i in range(p.ecology.predators.size()): wake(2*STRIDE+i)
	while Time.get_ticks_usec()<deadline:
		if force_cursor>=0:
			var count: int=p.ids.size()+p.ecology.forage.size()
			if force_cursor>=count: force_cursor=-1;continue
			var code: int=force_cursor if force_cursor<p.ids.size() else STRIDE+force_cursor-p.ids.size()
			force_cursor+=1;wake(code);continue
		if focus_cursor<focus_members.size():
			var code := from_spatial(int(focus_members[focus_cursor]));focus_cursor+=1
			if code>=0: wake(code)
			continue
		if focus_rects.is_empty(): break
		focus_members=p.hunting.spatial.cells.get(focus_cell,[]).duplicate();focus_cursor=0
		focus_cell.x+=1
		if focus_cell.x>=focus_rects[0].end.x: focus_cell.x=focus_rects[0].position.x;focus_cell.y+=1
		if focus_cell.y>=focus_rects[0].end.y:
			focus_rects.pop_front()
			if not focus_rects.is_empty(): focus_cell=focus_rects[0].position
