class_name FishPresentation
extends RefCounted
# Read-only visual interpolation of completed world snapshots. Never used by simulation.
var previous: Array = [PackedVector2Array(),PackedVector2Array(),PackedVector2Array()]
var current: Array = [PackedVector2Array(),PackedVector2Array(),PackedVector2Array()]
var bends: Array = [{},{},{}]
var alpha := 1.0
var since_snapshot := 0.0
var interval := .5
func tick(dt: float):
	since_snapshot+=dt;alpha=minf(1,alpha+dt/maxf(.016,interval))
func position(kind: int,index: int,fallback: Vector2) -> Vector2:
	if index>=current[kind].size(): return fallback
	if bends[kind].has(index):
		var path: PackedVector2Array=bends[kind][index];var length := 0.0
		for n in range(1,path.size()): length+=path[n-1].distance_to(path[n])
		var travel := length*alpha
		for n in range(1,path.size()):
			var segment := path[n-1].distance_to(path[n])
			if travel<=segment: return path[n-1].lerp(path[n],travel/maxf(.0001,segment))
			travel-=segment
		return path[-1]
	return previous[kind][index].lerp(current[kind][index],alpha)
func snapshot(p):
	var targets: Array=[PackedVector2Array(),PackedVector2Array(),PackedVector2Array()]
	targets[0].resize(p.ids.size())
	for i in range(p.ids.size()): targets[0][i]=Vector2(p.east[i],p.south[i])
	for a in p.ecology.forage: targets[1].append(Vector2(a.x,a.y))
	for a in p.ecology.predators: targets[2].append(Vector2(a.x,a.y))
	for kind in range(3):
		var start := PackedVector2Array();start.resize(targets[kind].size())
		for i in range(start.size()): start[i]=position(kind,i,targets[kind][i])
		bends[kind].clear()
		if p.movement!=null and p.movement.ready:
			var nav=p.movement.nav
			for i in range(start.size()):
				var end: Vector2=targets[kind][i]
				if nav.grid(start[i])==nav.grid(end) or nav.clear(start[i],end): continue
				var corner := Vector2(start[i].x,end.y)
				if nav.clear(start[i],corner) and nav.clear(corner,end): bends[kind][i]=PackedVector2Array([start[i],corner,end]);continue
				corner=Vector2(end.x,start[i].y)
				if nav.clear(start[i],corner) and nav.clear(corner,end): bends[kind][i]=PackedVector2Array([start[i],corner,end]);continue
				var goal: int=nav.nearest(end)
				if goal>=0:
					var path: PackedVector2Array=nav.route(start[i],end,goal)
					if not path.is_empty(): bends[kind][i]=path
		previous[kind]=start;current[kind]=targets[kind]
	interval=maxf(since_snapshot,.5/maxf(1,p.time_scale));since_snapshot=0;alpha=0

func reset_record(kind: int,index: int,at: Vector2):
	if index<current[kind].size():
		current[kind][index]=at;previous[kind][index]=at;bends[kind].erase(index)
