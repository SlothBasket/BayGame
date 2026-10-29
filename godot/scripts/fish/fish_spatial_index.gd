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
func move(kind: int,index: int,at: Vector2):
	var key := kind*STRIDE+index;var cell := Vector2i(floori(at.x/CELL),floori(at.y/CELL))
	if not covered.has(key) and locations.get(key,Vector2i(-99999,-99999))==cell: return
	remove_key(key)
	if not cells.has(cell): cells[cell]=[]
	cells[cell].append(key);locations[key]=cell;revision+=1
func cover(kind: int,index: int,bounds: Rect2):
	var key := kind*STRIDE+index
	var lo := Vector2i(floori(bounds.position.x/CELL),floori(bounds.position.y/CELL));var hi := Vector2i(floori(bounds.end.x/CELL),floori(bounds.end.y/CELL))
	var bounds_key := Rect2i(lo,hi-lo+Vector2i.ONE)
	if covered_bounds.get(key,Rect2i())==bounds_key: return
	remove_key(key);covered_bounds[key]=bounds_key;revision+=1
	var occupied: Array[Vector2i]=[]
	for y in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			var cell := Vector2i(x,y)
			if not cells.has(cell): cells[cell]=[]
			cells[cell].append(key);occupied.append(cell)
	covered[key]=occupied
func remove_key(key: int):
	if covered.has(key):
		revision+=1;covered_bounds.erase(key)
		for cell in covered[key]:
			cells[cell].erase(key)
			if cells[cell].is_empty(): cells.erase(cell)
		covered.erase(key)
	if not locations.has(key): return
	revision+=1
	var cell: Vector2i=locations[key];cells[cell].erase(key)
	if cells[cell].is_empty(): cells.erase(cell)
	locations.erase(key)
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
	var unique: Dictionary={}
	for code in result: unique[code]=true
	var values: Array=unique.keys()
	if query_cache.size()>=256: query_cache.clear()
	query_cache[key]={"revision":revision,"members":values}
	return values

