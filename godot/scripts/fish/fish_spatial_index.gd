class_name FishSpatialIndex
extends RefCounted
const CELL := 128.0
const STRIDE := 1000000
var cells: Dictionary = {}
var locations: Dictionary = {}
var covered: Dictionary = {}
var covered_bounds: Dictionary = {}
var revision := 0
var query_cache: Dictionary = {}
func membership(key: int) -> Rect2i:
	if covered_bounds.has(key): return covered_bounds[key]
	if locations.has(key): return Rect2i(locations[key],Vector2i.ONE)
	return Rect2i()
func update_bounds(key: int,bounds: Rect2i):
	var old := membership(key)
	if old==bounds: return
	for y in range(old.position.y,old.end.y):
		for x in range(old.position.x,old.end.x):
			var cell := Vector2i(x,y)
			if bounds.has_point(cell): continue
			cells[cell].erase(key)
			if cells[cell].is_empty(): cells.erase(cell)
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var cell := Vector2i(x,y)
			if old.has_point(cell): continue
			if not cells.has(cell): cells[cell]=[]
			cells[cell].append(key)
	revision+=1
func move(kind: int,index: int,at: Vector2):
	var key := kind*STRIDE+index;var cell := Vector2i(floori(at.x/CELL),floori(at.y/CELL))
	update_bounds(key,Rect2i(cell,Vector2i.ONE))
	covered.erase(key);covered_bounds.erase(key);locations[key]=cell
func cover(kind: int,index: int,bounds: Rect2):
	var key := kind*STRIDE+index
	var lo := Vector2i(floori(bounds.position.x/CELL),floori(bounds.position.y/CELL));var hi := Vector2i(floori(bounds.end.x/CELL),floori(bounds.end.y/CELL))
	var bounds_key := Rect2i(lo,hi-lo+Vector2i.ONE)
	update_bounds(key,bounds_key)
	locations.erase(key);covered[key]=true;covered_bounds[key]=bounds_key
func remove_key(key: int):
	update_bounds(key,Rect2i())
	locations.erase(key);covered.erase(key);covered_bounds.erase(key)
func query(at: Vector2,radius: float) -> Array:
	return rectangle(Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2))
func rectangle(rect: Rect2) -> Array:
	var result: Array=[];var lo := Vector2i(floori(rect.position.x/CELL),floori(rect.position.y/CELL));var hi := Vector2i(floori(rect.end.x/CELL),floori(rect.end.y/CELL))
	var key := Rect2i(lo,hi-lo+Vector2i.ONE)
	if query_cache.has(key) and int(query_cache[key].revision)==revision: return query_cache[key].members
	if (hi.x-lo.x)*(hi.y-lo.y)>cells.size()*2:
		for cell in cells:
			if cell.x>=lo.x and cell.y>=lo.y and cell.x<=hi.x and cell.y<=hi.y: result.append_array(cells[cell])
	else:
		for y in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1): result.append_array(cells.get(Vector2i(x,y),[]))
	var values: Array=result
	if not covered.is_empty() and lo!=hi:
		var unique: Dictionary={}
		values=[]
		for code in result:
			if covered.has(code):
				if unique.has(code): continue
				unique[code]=true
			values.append(code)
	if query_cache.size()>=256: query_cache.clear()
	query_cache[key]={"revision":revision,"members":values}
	return values

