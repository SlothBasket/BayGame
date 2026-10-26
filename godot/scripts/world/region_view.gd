class_name RegionView
extends Node2D
var data: Dictionary
var water: Sprite2D
var land: MeshInstance2D
var chart := false
var overlay_opacity := 0.55
var provenance_view := false
var contours := false
var debug := false
var meters_per_pixel := 1.0
var shore_lines: Array[PackedVector2Array] = []
var channel_lines: Array[PackedVector2Array] = []
func setup(tile: Dictionary):
	data=tile
	for source in [tile.shore,tile.channels]:
		var target: Array[PackedVector2Array]=shore_lines if source==tile.shore else channel_lines
		for line in source:
			var pts := PackedVector2Array()
			for p in line: pts.append(Vector2(p[0],p[1]))
			if pts.size()>1: target.append(pts)
	var n: int = tile.n
	var values: PackedFloat32Array = tile.get("combined",tile.samples).duplicate()
	for i in range(values.size()):
		if is_nan(values[i]): values[i]=10000.0
	var img := Image.create_from_data(n+3,n+3,false,Image.FORMAT_RF,values.to_byte_array())
	water=Sprite2D.new();water.texture=ImageTexture.create_from_image(img)
	water.show_behind_parent=true;water.centered=false;water.scale=Vector2.ONE*float(tile.size)/(n+3)
	water.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new();mat.shader=preload("res://shaders/depth.gdshader")
	var classes := PackedByteArray();classes.resize((n+3)*(n+3))
	for i in range(classes.size()): classes[i]=int(tile.get("provenance",classes)[i])*64
	mat.set_shader_parameter("provenance_texture",ImageTexture.create_from_image(Image.create_from_data(n+3,n+3,false,Image.FORMAT_R8,classes)))
	mat.set_shader_parameter("cells",float(n));water.material=mat;add_child(water)
	if not tile.indices.is_empty():
		var verts := PackedVector3Array()
		for v in tile.vertices: verts.append(Vector3(v[0],v[1],0))
		var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=verts;arrays[Mesh.ARRAY_INDEX]=PackedInt32Array(tile.indices)
		var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		land=MeshInstance2D.new();land.show_behind_parent=true;land.mesh=mesh;add_child(land)
		land.modulate=Color(.33,.43,.32)
func refresh(origin: GeoPosition,chart_on: bool,debug_on: bool,pixel_size: float):
	position=Vector2(data.x-origin.east,data.y-origin.south)
	var redraw := chart!=chart_on or debug!=debug_on or absf(pixel_size-meters_per_pixel)>meters_per_pixel*.01
	chart=chart_on;debug=debug_on
	if redraw: meters_per_pixel=pixel_size;queue_redraw()
	water.material.set_shader_parameter("chart",chart or contours)
	water.material.set_shader_parameter("provenance_view",provenance_view)
	water.material.set_shader_parameter("overlay_opacity",1.0 if chart else overlay_opacity)
func _draw():
	# Draw after children via a separate positive z index would obscure land;
	# shoreline lines intentionally sit on top using draw order via show_behind_parent.
	for pts in shore_lines:
		draw_polyline(pts,Color(.33,.43,.32),meters_per_pixel,true)
	if chart:
		for pts in channel_lines: draw_polyline(pts,Color(0.65,0.55,0.72),meters_per_pixel,true)

	if debug:
		draw_rect(Rect2(0,0,data.size,data.size),Color(0.8,0.6,0.2,0.6),false,meters_per_pixel)
