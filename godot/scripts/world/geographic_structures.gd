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
	origin=world_origin;pixel_size=camera.span/get_viewport_rect().size.y;labels=camera.span<2000;queue_redraw()
func _draw():
	if not labels: return
	var occupied: Array[Rect2]=[]
	for f in features:
		var p := GeoPosition.new(f.position[0],f.position[1]).relative_to(origin)
		var tint := Color(.90,.81,.56) if f.category=="boat_ramp" else Color(.72,.78,.76)
		if not f.visual_polygon.is_empty():
			var polygon := PackedVector2Array()
			for v in f.visual_polygon: polygon.append(GeoPosition.new(v[0],v[1]).relative_to(origin))
			draw_colored_polygon(polygon,tint)
		draw_rect(Rect2(p-Vector2.ONE*3*pixel_size,Vector2.ONE*6*pixel_size),tint)
		var label_size := ThemeDB.fallback_font.get_string_size(f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,14)
		var bounds := Rect2(p+Vector2(8,-22)*pixel_size,label_size*pixel_size).grow(5*pixel_size)
		var overlaps := false
		for used in occupied:
			if bounds.intersects(used): overlaps=true;break
		if overlaps: continue
		occupied.append(bounds)
		draw_set_transform(p,0,Vector2.ONE*pixel_size)
		draw_string(ThemeDB.fallback_font,Vector2(8,-8),f.name,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(1,.9,.7))
		draw_set_transform(Vector2.ZERO)
