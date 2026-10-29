class_name FishPresentation
extends RefCounted
# Per-record visual state: simulation publishes only records it actually advances.
var records: Array = [{},{},{}]
var clock := 0.0
var simulation_clock := 0.0
func tick(dt: float,completed: float,multiplier: float):
	# A stalled frame must not finish every animation in one jump. Simulation retains full dt.
	clock+=minf(maxf(dt,0),.05)
	simulation_clock=move_toward(simulation_clock,completed,minf(maxf(dt,0),.05)*maxf(1,multiplier))
func position(kind: int,index: int,fallback: Vector2) -> Vector2:
	if not records[kind].has(index): return fallback
	var r: Dictionary=records[kind][index]
	var t := clampf((clock-float(r.started))/maxf(.016,float(r.duration)),0,1)
	var distances: PackedFloat32Array=r.distances;var path: PackedVector2Array=r.path
	if path.size()<2: return path[0]
	var travel: float=distances[-1]*t;var low := 1;var high := path.size()-1
	while low<high:
		var mid := (low+high)/2
		if distances[mid]<travel: low=mid+1
		else: high=mid
	var length: float=distances[low]-distances[low-1]
	return path[low-1].lerp(path[low],clampf((travel-distances[low-1])/maxf(.0001,length),0,1))
func publish(p,kind: int,index: int,before: Vector2,at: Vector2,simulated_dt: float):
	if p.diagnostics.publishing_disabled: return
	var diagnostic_begin := Time.get_ticks_usec()
	_measured_publish(p,kind,index,before,at,simulated_dt)
	p.diagnostics.add("Visual publishing",Time.get_ticks_usec()-diagnostic_begin)
func _measured_publish(p,kind: int,index: int,before: Vector2,at: Vector2,simulated_dt: float):
	if not records[kind].has(index): reset_record(kind,index,before)
	var r: Dictionary=records[kind][index]
	if Vector2(r.target).is_equal_approx(at): return
	var start := position(kind,index,before)
	var nav=p.movement.nav;var path := PackedVector2Array()
	if nav.clear(start,at): path=PackedVector2Array([start,at])
	else:
		var corner := Vector2(start.x,at.y)
		if nav.clear(start,corner) and nav.clear(corner,at): path=PackedVector2Array([start,corner,at])
		else:
			corner=Vector2(at.x,start.y)
			if nav.clear(start,corner) and nav.clear(corner,at): path=PackedVector2Array([start,corner,at])
			else:
				var goal: int=nav.nearest(at)
				if goal>=0: path=nav.route(start,at,goal)
	# Deferred route: retain the last continuous animation rather than snapping over land.
	if path.is_empty(): return
	var distances := PackedFloat32Array();distances.resize(path.size())
	for i in range(1,path.size()): distances[i]=distances[i-1]+path[i-1].distance_to(path[i])
	var duration := maxf(.05,simulated_dt/maxf(1,p.time_scale))
	# Retarget from the visible position; a detail transition cannot accelerate a large backlog instantly.
	var physical_speed := maxf(.05,before.distance_to(at)/maxf(.001,simulated_dt))
	duration=maxf(duration,float(distances[-1])/maxf(.05,physical_speed*maxf(1,p.time_scale)))
	r.path=path;r.distances=distances;r.started=clock;r.duration=duration;r.target=at
func reset_record(kind: int,index: int,at: Vector2):
	records[kind][index]={"path":PackedVector2Array([at]),"distances":PackedFloat32Array([0]),"started":clock,"duration":.5,"target":at}

func remaining_path(kind: int,index: int,fallback: Vector2) -> PackedVector2Array:
	var path := PackedVector2Array([position(kind,index,fallback)])
	if not records[kind].has(index): return path
	var r: Dictionary=records[kind][index]
	var fraction := clampf((clock-float(r.started))/maxf(.016,float(r.duration)),0,1)
	var distance: float=r.distances[-1]*fraction
	for i in range(1,r.path.size()):
		if float(r.distances[i])>distance: path.append(r.path[i])
	return path
