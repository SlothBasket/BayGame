class_name GeoPosition
extends RefCounted
# Scalar GDScript floats are doubles. Never store authoritative position in Vector2.
var east: float
var south: float
func _init(x: float = 0.0, y: float = 0.0):
	east = x
	south = y
func relative_to(origin: GeoPosition) -> Vector2:
	return Vector2(east - origin.east, south - origin.south)
func copy() -> GeoPosition:
	return GeoPosition.new(east, south)
func key(level: int, base: float) -> String:
	var size := base * pow(2, level)
	return "%d_%d_%d" % [level, floori(east / size), floori(south / size)]
