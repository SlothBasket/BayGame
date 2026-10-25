class_name RegionView
extends Node2D
var data: Dictionary
var water: Sprite2D
var land: MeshInstance2D
var chart := false
var debug := false
var meters_per_pixel := 1.0
func setup(tile: Dictionary):
	data=tile
	var n: int = tile.n
	var values: PackedFloat32Array = tile.samples.duplicate()
	for i in range(values.size()):
		if is_nan(values[i]): values[i]=10000.0
	var img := Image.create_from_data(n+3,n+3,false,Image.FORMAT_RF,values.to_byte_array())
	water=Sprite2D.new();water.texture=ImageTexture.create_from_image(img)
	water.show_behind_parent=true;water.centered=false;water.scale=Vector2.ONE*float(tile.size)/(n+3)
	water.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new();mat.shader=preload("res://shaders/depth.gdshader")
	mat.set_shader_parameter("cells",float(n));water.material=mat;add_child(water)
	if not tile.indices.is_empty():
		var verts := PackedVector3Array()
		for v in tile.vertices: verts.append(Vector3(v[0],v[1],0))
		var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=verts;arrays[Mesh.ARRAY_INDEX]=PackedInt32Array(tile.indices)
		var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		land=MeshInstance2D.new();land.show_behind_parent=true;land.mesh=mesh;add_child(land)
		var land_mat := ShaderMaterial.new();land_mat.shader=preload("res://shaders/land.gdshader")
		land_mat.set_shader_parameter("tile_origin",Vector2(tile.x,tile.y));land.material=land_mat
func refresh(origin: GeoPosition,chart_on: bool,debug_on: bool,pixel_size: float):
	position=Vector2(data.x-origin.east,data.y-origin.south)
	chart=chart_on;debug=debug_on;meters_per_pixel=pixel_size
	water.material.set_shader_parameter("chart",chart)
	if land!=null: land.material.set_shader_parameter("pixel_size",pixel_size)
	queue_redraw()
func _draw():
	# Draw after children via a separate positive z index would obscure land;
	# shoreline lines intentionally sit on top using draw order via show_behind_parent.
	for line in data.shore:
		var pts := PackedVector2Array()
		for p in line: pts.append(Vector2(p[0],p[1]))
		if pts.size()>1:
			# Decorative vegetation/shallows edge, not a classified habitat map.
			draw_polyline(pts,Color(.24,.49,.40,.26),meters_per_pixel*7.0,true)
			draw_polyline(pts,Color(.66,.72,.51,.85),meters_per_pixel*1.2,true)
	if chart:
		for line in data.channels:
			var pts := PackedVector2Array()
			for p in line: pts.append(Vector2(p[0],p[1]))
			if pts.size()>1: draw_polyline(pts,Color(0.65,0.55,0.72),meters_per_pixel,true)
	if debug:
		draw_rect(Rect2(0,0,data.size,data.size),Color(0.8,0.6,0.2,0.6),false,meters_per_pixel)
