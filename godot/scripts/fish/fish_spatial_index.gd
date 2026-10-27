class_name FishSpatialIndex
extends RefCounted
const CELL := 128.0
const STRIDE := 1000000
var cells: Dictionary = {}
var locations: Dictionary = {}
func move(kind: int,index: int,at: Vector2):
	var key := kind*STRIDE+index;var cell := Vector2i(floori(at.x/CELL),floori(at.y/CELL))
	if locations.get(key,Vector2i(-99999,-99999))==cell: return
	remove_key(key)
	if not cells.has(cell): cells[cell]=[]
	cells[cell].append(key);locations[key]=cell
func remove_key(key: int):
	if not locations.has(key): return
	var cell: Vector2i=locations[key];cells[cell].erase(key)
	if cells[cell].is_empty(): cells.erase(cell)
	locations.erase(key)
func query(at: Vector2,radius: float) -> Array:
	return rectangle(Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2))
func rectangle(rect: Rect2) -> Array:
	var result: Array=[];var lo := Vector2i(floori(rect.position.x/CELL),floori(rect.position.y/CELL));var hi := Vector2i(floori(rect.end.x/CELL),floori(rect.end.y/CELL))
	if (hi.x-lo.x)*(hi.y-lo.y)>cells.size()*2:
		for cell in cells:
			if cell.x>=lo.x and cell.y>=lo.y and cell.x<=hi.x and cell.y<=hi.y: result.append_array(cells[cell])
	else:
		for y in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1): result.append_array(cells.get(Vector2i(x,y),[]))
	return result
