class_name MapCamera
extends Camera2D
var geo := GeoPosition.new()
var span := 100000.0
var target_span := 100000.0
var follow := false
var presets: Array = []
var index := 0
var drag := false
var anchor: GeoPosition
var cursor := Vector2.ZERO
var manifest: Dictionary
func setup(m: Dictionary):
	manifest=m
	presets=m.parameters.zoom_spans_m.duplicate()
	presets.append(overview_span())
	index=presets.size()-1
	overview()
func overview_span() -> float:
	var b: Array = manifest.bounds
	var aspect := get_viewport_rect().size.x/get_viewport_rect().size.y
	return maxf(b[3]-b[1],(b[2]-b[0])/aspect)*1.06
func overview():
	follow=false;anchor=null;index=presets.size()-1
	target_span=overview_span()
	geo.east=(manifest.bounds[0]+manifest.bounds[2])*0.5
	geo.south=(manifest.bounds[1]+manifest.bounds[3])*0.5
func world_at(screen: Vector2) -> GeoPosition:
	var offset := (screen-get_viewport_rect().size*0.5)*span/get_viewport_rect().size.y
	return GeoPosition.new(geo.east+offset.x,geo.south+offset.y)
func event(e: InputEvent,boat: BoatModel):
	if e is InputEventMouseButton:
		if e.button_index in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]: drag=e.pressed;anchor=null
		if e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if not follow: cursor=e.position;anchor=world_at(cursor)
			index=clampi(index+(-1 if e.button_index==MOUSE_BUTTON_WHEEL_UP else 1),0,presets.size()-1)
			target_span=presets[index]
	if e is InputEventMouseMotion and drag:
		follow=false
		geo.east-=e.relative.x*span/get_viewport_rect().size.y
		geo.south-=e.relative.y*span/get_viewport_rect().size.y
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode==KEY_F: follow=not follow;anchor=null
		if e.keycode==KEY_HOME: follow=true;anchor=null;geo=boat.geo.copy()
		if e.keycode==KEY_O: overview()
func tick(dt: float,boat: BoatModel,origin: GeoPosition):
	span=exp(lerpf(log(span),log(target_span),1-exp(-dt*14)))
	if follow: geo=boat.geo.copy()
	elif anchor!=null:
		var offset := (cursor-get_viewport_rect().size*0.5)*span/get_viewport_rect().size.y
		geo.east=anchor.east-offset.x;geo.south=anchor.south-offset.y
		if absf(span-target_span)<0.0001*span: anchor=null
	zoom=Vector2.ONE*get_viewport_rect().size.y/span
	position=geo.relative_to(origin)
