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
	var original: Array=presets.duplicate()
	for i in range(original.size()-1):
		var value: float=original[i]*1.3
		while value<minf(float(original[i+1]),2000.0)*.98:
			presets.append(value);value*=1.3
	presets.sort()
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
var targeting := false
var reticle := Vector2(960,540)
func event(e: InputEvent,boat: BoatModel):
	if e.is_action("pan_map",true): drag=e.is_pressed();anchor=null
	if e.is_action_pressed("zoom_in",false,true) or e.is_action_pressed("zoom_out",false,true):
		if not follow:
			cursor=reticle if targeting else get_viewport().get_mouse_position();anchor=world_at(cursor)
		var nearest := INF
		for i in range(presets.size()):
			var distance := absf(log(float(presets[i])/target_span))
			if distance<nearest: nearest=distance;index=i
		index=clampi(index+(-1 if e.is_action_pressed("zoom_in",false,true) else 1),0,presets.size()-1)
		target_span=presets[index]
	if e is InputEventMouseMotion and drag:
		follow=false
		geo.east-=e.relative.x*span/get_viewport_rect().size.y
		geo.south-=e.relative.y*span/get_viewport_rect().size.y
	if e.is_action_pressed("follow",false,true): follow=not follow;anchor=null
	if e.is_action_pressed("recenter",false,true): follow=true;anchor=null;geo=boat.geo.copy()
	if e.is_action_pressed("overview",false,true): overview()
	if e.is_action_pressed("target_mode",false,true):
		targeting=not targeting;reticle=get_viewport_rect().size*.5;follow=false;anchor=null
func tick(dt: float,boat: BoatModel,origin: GeoPosition):
	var movement := Input.get_vector("map_left","map_right","map_up","map_down")
	if movement.length()>0:
		anchor=null;follow=false
		if targeting: reticle=(reticle+movement*650*dt).clamp(Vector2.ZERO,get_viewport_rect().size)
		else: geo.east+=movement.x*span*.6*dt;geo.south+=movement.y*span*.6*dt
	span=exp(lerpf(log(span),log(target_span),1-exp(-dt*14)))
	if follow: geo=boat.geo.copy()
	elif anchor!=null:
		var offset := (cursor-get_viewport_rect().size*0.5)*span/get_viewport_rect().size.y
		geo.east=anchor.east-offset.x;geo.south=anchor.south-offset.y
		if absf(span-target_span)<0.0001*span: anchor=null
	zoom=Vector2.ONE*get_viewport_rect().size.y/span
	position=geo.relative_to(origin)
