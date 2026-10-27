class_name FishPresentation
extends RefCounted
# Read-only visual interpolation of completed world snapshots. Never used by simulation.
var previous: Array = [PackedVector2Array(),PackedVector2Array(),PackedVector2Array()]
var current: Array = [PackedVector2Array(),PackedVector2Array(),PackedVector2Array()]
var alpha := 1.0
var since_snapshot := 0.0
var interval := .5
func tick(dt: float):
	since_snapshot+=dt;alpha=minf(1,alpha+dt/maxf(.016,interval))
func position(kind: int,index: int,fallback: Vector2) -> Vector2:
	if index>=current[kind].size(): return fallback
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
		previous[kind]=start;current[kind]=targets[kind]
	interval=clampf(since_snapshot,.016,2.0);since_snapshot=0;alpha=0
