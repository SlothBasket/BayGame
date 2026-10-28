class_name FishPresentation
extends RefCounted
# Read-only visual interpolation of completed world snapshots. Never used by simulation.
var previous: Array = [PackedVector2Array(),PackedVector2Array(),PackedVector2Array()]
var current: Array = [PackedVector2Array(),PackedVector2Array(),PackedVector2Array()]
var bends: Array = [{},{},{}]
var clock := 0.0
var changed_at: Array = [PackedFloat64Array(),PackedFloat64Array(),PackedFloat64Array()]
var durations: Array = [PackedFloat64Array(),PackedFloat64Array(),PackedFloat64Array()]
var alpha := 1.0
var since_snapshot := 0.0
var interval := .5
func tick(dt: float):
	clock+=dt;since_snapshot+=dt;alpha=minf(1,alpha+dt/maxf(.016,interval))
func position(kind: int,index: int,fallback: Vector2) -> Vector2:
	if index>=current[kind].size(): return fallback
	var blend := clampf((clock-changed_at[kind][index])/maxf(.016,durations[kind][index]),0,1)
	if bends[kind].has(index):
		var path: PackedVector2Array=bends[kind][index];var length := 0.0
		for n in range(1,path.size()): length+=path[n-1].distance_to(path[n])
		var travel := length*blend
		for n in range(1,path.size()):
			var segment := path[n-1].distance_to(path[n])
			if travel<=segment: return path[n-1].lerp(path[n],travel/maxf(.0001,segment))
			travel-=segment
		return path[-1]
	return previous[kind][index].lerp(current[kind][index],blend)
func snapshot(p):
	var targets: Array=[PackedVector2Array(),PackedVector2Array(),PackedVector2Array()]
	targets[0].resize(p.ids.size())
	for i in range(p.ids.size()): targets[0][i]=Vector2(p.east[i],p.south[i])
	for a in p.ecology.forage: targets[1].append(Vector2(a.x,a.y))
	for a in p.ecology.predators: targets[2].append(Vector2(a.x,a.y))
	for kind in range(3):
		var old_count: int=current[kind].size()
		previous[kind].resize(targets[kind].size());current[kind].resize(targets[kind].size());changed_at[kind].resize(targets[kind].size());durations[kind].resize(targets[kind].size())
		for i in range(targets[kind].size()):
			var end: Vector2=targets[kind][i]
			if i>=old_count:
				previous[kind][i]=end;current[kind][i]=end;changed_at[kind][i]=clock;durations[kind][i]=.5;continue
			if current[kind][i].is_equal_approx(end): continue
			var start := position(kind,i,end)
			var duration: float=maxf(.016,clock-changed_at[kind][i]);changed_at[kind][i]=clock;durations[kind][i]=minf(duration,10/maxf(1,p.time_scale))
			previous[kind][i]=start;current[kind][i]=end;bends[kind].erase(i)
			if p.movement!=null and p.movement.ready:
				var nav=p.movement.nav
				if nav.grid(start)==nav.grid(end) or nav.clear(start,end): continue
				var corner := Vector2(start.x,end.y)
				if nav.clear(start,corner) and nav.clear(corner,end): bends[kind][i]=PackedVector2Array([start,corner,end]);continue
				corner=Vector2(end.x,start.y)
				if nav.clear(start,corner) and nav.clear(corner,end): bends[kind][i]=PackedVector2Array([start,corner,end]);continue
				var goal: int=nav.nearest(end)
				if goal>=0:
					var path: PackedVector2Array=nav.route(start,end,goal)
					if not path.is_empty(): bends[kind][i]=path
	since_snapshot=0
func reset_record(kind: int,index: int,at: Vector2):
	if index<current[kind].size():
		current[kind][index]=at;previous[kind][index]=at;bends[kind].erase(index);changed_at[kind][index]=clock;durations[kind][index]=.5
