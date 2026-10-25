class_name GeographicStructures
extends Node2D
var features: Array=[]
var origin := GeoPosition.new()
var pixel_size := 1.0
var labels := false
func setup(asset_root: String):
	if FileAccess.file_exists(asset_root+"structures.json"):
		features=JSON.parse_string(FileAccess.get_file_as_string(asset_root+"structures.json")).features
func tick(camera: MapCamera,world_origin: GeoPosition,chart: bool):
	origin=world_origin;pixel_size=camera.span/get_viewport_rect().size.y;labels=chart and camera.span<2000;queue_redraw()
func _draw():
	if not labels: return
	for f in features:
		var p := GeoPosition.new(f.position[0],f.position[1]).relative_to(origin)
		draw_circle(p,3*pixel_size,Color(1,.8,.4))
		draw_set_transform(p,0,Vector2.ONE*pixel_size)
		draw_string(ThemeDB.fallback_font,Vector2(8,-8),f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(1,.9,.7))
		draw_set_transform(Vector2.ZERO)
