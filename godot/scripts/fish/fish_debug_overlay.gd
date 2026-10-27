class_name FishDebugOverlay
extends Node2D
# Observation-only UI. Selection, follow and rendering never schedule simulation work.
enum Entity { NONE, FISH, BAIT, PREDATOR, AREA }
var main
var enabled := false
var entity := Entity.NONE
var entity_index := -1
var selected: int:
	get: return entity_index if entity==Entity.FISH else -1
	set(value): select_entity(Entity.FISH,value)
var selected_zone := -1
var mode := 0
var show_paths := true
var show_areas := false
var show_grid := false
var advanced := false
var following := false
var follow_lock := false
var inspector_open := true
var canvas: CanvasLayer
var toolbar: PanelContainer
var panel: PanelContainer
var scroll: ScrollContainer
var heading: Label
var info: Label
var status: Label
var follow_toggle: CheckButton
var speed_picker: OptionButton
var simulation_mode: OptionButton
var budget_picker: SpinBox
var draw_clock := 0.0
var refresh_clock := 0.0
var real_time := 0.0
var rate_clock := 0.0
var prior_sim := 0.0
var actual_rate := 0.0
var candidates: Array = []
var visible_areas: Array[int] = []
var view_bounds := Rect2()
var trail := PackedVector2Array()
var event_seen: Dictionary = {}
const SPEEDS := [0.0,1.0,5.0,10.0,30.0,60.0,300.0,-1.0]
const HUNT_RANK := {5:10,6:9,8:8,3:7,2:6,1:4}
const COLORS := [Color(.98,.48,.22),Color(.35,.83,.96),Color(.77,.54,.96),Color(.85,.85,.7),Color(.7,.9,1),Color(1,.9,.2),Color(.6,.45,.25)]
const BAIT_COLORS := [Color(.8,1,.9),Color(.35,.7,1),Color(1,.7,.4),Color(1,.9,.25),Color(1,.5,.7),Color(.8,.5,.3),Color(.55,1,.6),Color(.25,.8,.45)]
var diagnostic_shown := ""
func available() -> bool:
	var reason := "population not initialized" if main==null or main.fish==null else str(main.fish.initialization_problem())
	if reason.is_empty():
		diagnostic_shown=""
		return true
	candidates.clear();visible_areas.clear();trail.clear();entity=Entity.NONE;entity_index=-1;selected_zone=-1;following=false
	if info!=null and reason!=diagnostic_shown:
		diagnostic_shown=reason;heading.text="Fish Lab unavailable";info.text=reason+".\n\nSimulation paused; original save preserved.";status.text="Ecology initialization incomplete"
		follow_toggle.set_pressed_no_signal(false)
	return false
func valid_entity(kind: int,index: int) -> bool:
	if not available() or index<0: return false
	var p=main.fish
	match kind:
		Entity.FISH: return index<p.ids.size()
		Entity.BAIT: return index<p.ecology.forage.size()
		Entity.PREDATOR: return index<p.ecology.predators.size()
		Entity.AREA: return index<p.food_web.areas.size()
	return false
func set_speed(value: int):
	if not available(): return
	var p=main.fish
	if SPEEDS[value]<0: p.fast_forward=true;p.max_throughput=true;p.ahead_active=false;p.time_scale=1
	else: p.max_throughput=false;p.time_scale=SPEEDS[value]
	refresh()
func style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new();s.bg_color=Color(.025,.045,.06,.95)
	for side in ["left","right","top","bottom"]: s.set("content_margin_"+side,12)
	s.corner_radius_top_left=6;s.corner_radius_top_right=6;s.corner_radius_bottom_left=6;s.corner_radius_bottom_right=6
	return s
func toggle_button(body: Control,text: String,value: bool,fn: Callable) -> CheckButton:
	var b := CheckButton.new();b.text=text;b.button_pressed=value;b.toggled.connect(fn);body.add_child(b);return b
func button(body: Control,text: String,fn: Callable):
	var b := Button.new();b.text=text;b.pressed.connect(fn);body.add_child(b)
func setup(game):
	main=game;z_index=5;canvas=CanvasLayer.new();canvas.layer=9;add_child(canvas)
	toolbar=PanelContainer.new();toolbar.position=Vector2(16,110);toolbar.add_theme_stylebox_override("panel",style());canvas.add_child(toolbar)
	var controls := VBoxContainer.new();toolbar.add_child(controls)
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",10);controls.add_child(row)
	var title := Label.new();title.text="FISH LAB";title.add_theme_font_size_override("font_size",20);row.add_child(title)
	var modes := OptionButton.new()
	for text in ["All life","Game fish","Bait schools","Predators","Habitat / food"]: modes.add_item(text)
	row.add_child(modes);modes.item_selected.connect(func(value): mode=value;cache_view();queue_redraw())
	speed_picker=OptionButton.new()
	for speed in SPEEDS: speed_picker.add_item("Max Throughput" if speed<0 else ("Paused" if speed==0 else "%d×" % speed))
	speed_picker.select(1);row.add_child(speed_picker);speed_picker.item_selected.connect(set_speed)
	toggle_button(row,"Paths",true,func(v): show_paths=v)
	toggle_button(row,"Areas",false,func(v): show_areas=v;cache_view())
	toggle_button(row,"Grid",false,func(v): show_grid=v)
	toggle_button(row,"Advanced",false,func(v): advanced=v;refresh())
	button(row,"Inspector",func(): inspector_open=not inspector_open;panel.visible=enabled and inspector_open)
	status=Label.new();status.custom_minimum_size.x=330;status.add_theme_font_size_override("font_size",16);row.add_child(status)
	var simulation_row := HBoxContainer.new();simulation_row.add_theme_constant_override("separation",10);controls.add_child(simulation_row)
	simulation_mode=OptionButton.new();simulation_mode.add_item("Live Mode");simulation_mode.add_item("Fast-Forward Mode");simulation_row.add_child(simulation_mode)
	simulation_mode.item_selected.connect(func(value):
		if not available(): return
		main.fish.fast_forward=value==1
		if value==0: main.fish.max_throughput=false
		refresh())
	var budget_label := Label.new();budget_label.text="CPU budget (ms/frame)";simulation_row.add_child(budget_label)
	budget_picker=SpinBox.new();budget_picker.min_value=1;budget_picker.max_value=100;budget_picker.step=1;simulation_row.add_child(budget_picker)
	budget_picker.value_changed.connect(func(value):
		if not available(): return
		if main.fish.fast_forward: main.fish.fast_forward_budget_us=int(value*1000)
		else: main.fish.simulation_budget_us=int(value*1000))
	var hours := SpinBox.new();hours.min_value=.25;hours.max_value=168;hours.step=.25;hours.value=1;hours.suffix="hours";simulation_row.add_child(hours)
	button(simulation_row,"Simulate Ahead",func():
		if available(): main.fish.simulate_ahead(hours.value);refresh())
	button(simulation_row,"Stop / Pause",func():
		if available(): main.fish.pause_simulation();refresh())
	panel=PanelContainer.new();panel.position=Vector2(16,270);panel.custom_minimum_size=Vector2(390,660);panel.size=Vector2(390,660);panel.add_theme_stylebox_override("panel",style());canvas.add_child(panel)
	var column := VBoxContainer.new();column.add_theme_constant_override("separation",10);panel.add_child(column)
	heading=Label.new();heading.add_theme_font_size_override("font_size",22);heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;heading.custom_minimum_size.x=365;column.add_child(heading)
	var actions := HBoxContainer.new();column.add_child(actions)
	follow_toggle=toggle_button(actions,"Follow Selected",false,func(v): following=v)
	button(actions,"Center",center_selected)
	toggle_button(column,"Lock selection on empty clicks",false,func(v): follow_lock=v)
	scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	info=Label.new();info.custom_minimum_size.x=360;info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.add_theme_font_size_override("font_size",18);scroll.add_child(info)
	var find := LineEdit.new();find.placeholder_text="Find persistent fish ID → Enter";column.add_child(find)
	find.text_submitted.connect(func(value):
		if not available(): return
		var index: int=main.fish.ids.find(str(value).to_int())
		if index>=0: select_entity(Entity.FISH,index))
	button(column,"Find active hunt",find_hunt)
	toolbar.hide();panel.hide();refresh()
func toggle():
	enabled=not enabled;toolbar.visible=enabled;panel.visible=enabled and inspector_open
	if enabled and available(): prior_sim=main.fish.completed_time();rate_clock=0;actual_rate=0;cache_view();refresh()
	queue_redraw()
func select_entity(kind: int,index: int):
	if not available(): return
	if not valid_entity(kind,index): kind=Entity.NONE;index=-1
	entity=kind if index>=0 else Entity.NONE;entity_index=index;selected_zone=-1;trail.clear()
	if main!=null and main.fish!=null:
		var fish=main.fish
		if entity==Entity.FISH: selected_zone=fish.region[index]
		elif entity==Entity.BAIT: selected_zone=fish.ecology.forage[index].zone
		elif entity==Entity.PREDATOR: selected_zone=fish.ecology.predators[index].zone
		elif entity==Entity.AREA: selected_zone=fish.food_web.areas[index].zone
	if entity==Entity.NONE:
		following=false
		if follow_toggle!=null: follow_toggle.set_pressed_no_signal(false)
	if scroll!=null: scroll.scroll_vertical=0
	if panel!=null and entity!=Entity.NONE: inspector_open=true;panel.visible=enabled
	refresh();queue_redraw()
func observed_position(kind: int,index: int) -> Vector2:
	# Fish Lab uses current world state for both predator and prey, not delayed display snapshots.
	var p=main.fish
	if kind==0: return Vector2(p.east[index],p.south[index])
	var a: Dictionary=p.ecology.forage[index] if kind==1 else p.ecology.predators[index]
	return Vector2(a.x,a.y)
func selected_position() -> Vector2:
	if not valid_entity(entity,entity_index): return Vector2.ZERO
	var fish=main.fish
	if entity==Entity.FISH: return observed_position(0,entity_index)
	if entity==Entity.BAIT: return observed_position(1,entity_index)
	if entity==Entity.PREDATOR: return observed_position(2,entity_index)
	if entity==Entity.AREA:
		var b: Array=fish.food_web.areas[entity_index].bounds;return Vector2((b[0]+b[2])*.5,(b[1]+b[3])*.5)
	return Vector2.ZERO
func center_selected():
	if not valid_entity(entity,entity_index): return
	var at := selected_position();main.camera.follow=false;main.camera.anchor=null;main.camera.geo=GeoPosition.new(at.x,at.y)
func tick(dt: float):
	real_time+=dt
	if not enabled or not available(): return
	if following and entity!=Entity.NONE and (not main.fish.fast_forward or draw_clock>=.2):
		var at := selected_position();var t := 1-exp(-10*dt)
		main.camera.follow=false;main.camera.anchor=null;main.camera.geo.east=lerpf(main.camera.geo.east,at.x,t);main.camera.geo.south=lerpf(main.camera.geo.south,at.y,t)
	refresh_clock+=dt;rate_clock+=dt;draw_clock+=dt
	if rate_clock>=1:
		actual_rate=maxf(0,(main.fish.completed_time()-prior_sim)/rate_clock);prior_sim=main.fish.completed_time();rate_clock=0
	if refresh_clock>=(.5 if main.fish.fast_forward else .25):
		refresh_clock=0;cache_view();refresh()
		if entity in [Entity.FISH,Entity.BAIT,Entity.PREDATOR]:
			var at := selected_position()
			if trail.is_empty() or trail[-1].distance_to(at)>.2: trail.append(at)
			if trail.size()>100: trail.remove_at(0)
		for event in main.fish.food_web.events:
			if main.fish.elapsed-event.time>10: continue
			var key: String="%s:%s:%s" % [event.time,event.id,event.kind]
			if not event_seen.has(key): event_seen[key]=real_time
	for key in event_seen.keys():
		if real_time-float(event_seen[key])>10: event_seen.erase(key)
	if not main.fish.fast_forward or draw_clock>=.2: draw_clock=0;queue_redraw()
func cache_view():
	if not available(): return
	var size := get_viewport_rect().size;var half: Vector2=Vector2(size.x/size.y,1)*main.camera.span*.5
	view_bounds=Rect2(Vector2(main.camera.geo.east,main.camera.geo.south)-half,half*2).grow(250)
	candidates=main.fish.hunting.spatial.rectangle(view_bounds)
	visible_areas.clear()
	if show_areas or mode==4 or entity==Entity.AREA:
		for index in range(main.fish.food_web.areas.size()):
			var b: Array=main.fish.food_web.areas[index].bounds
			if view_bounds.intersects(Rect2(b[0],b[1],b[2]-b[0],b[3]-b[1])): visible_areas.append(index)
func refresh():
	if info==null or not available(): return
	var p=main.fish;var eco=p.ecology;var web=p.food_web
	status.text="%s · %.2f× achieved\nSimulated %.2f h · queued %.2f h\nProcessing %.1f ms/frame" % [p.requested_speed(),actual_rate,p.completed_time()/3600.0,p.time_debt/3600.0,p.update_ms]
	simulation_mode.select(1 if p.fast_forward else 0)
	budget_picker.set_value_no_signal((p.fast_forward_budget_us if p.fast_forward else p.simulation_budget_us)/1000.0)
	var speed_index := SPEEDS.find(-1.0 if p.max_throughput else p.time_scale)
	if speed_index>=0: speed_picker.select(speed_index)
	if entity==Entity.NONE:
		heading.text="Explore the ecosystem";info.text="Click a fish, bait school, predator or habitat.\n\nOne entity is inspected at a time. Empty clicks clear selection unless locked.\n\nFollowing and zooming never change simulation behavior.";return
	var at := selected_position();var text := "Location E %.2f / S %.2f mi\n" % [at.x/1609.344,at.y/1609.344]
	if entity==Entity.FISH:
		var i := entity_index;heading.text="%s #%d" % [p.SPECIES[p.species[i]],p.ids[i]]
		text+="%.1f in · hunger %.0f%% (100 = starving)\nPreferred depth %.1f ft\n" % [p.size_cm[i]/2.54,p.hunger[i]*100,p.preferred_depth[i]/.3048]
		if eco.alive[i]==0: text+="Consumed — identity retained\n"
		else: text+=hunt_text(i)
		text+="\nPreferred areas\nRest: %s\nFeed: %s\nSchool: %s\n" % [web.area_for_feature(p.movement.preferred_rest[i],"resting"),web.area_for_feature(p.movement.preferred_feed[i],"feeding"),str(eco.school[i]) if eco.school[i]>=0 else "solo"]
		if advanced: text+="\n"+eco.describe(i)+"\nNavigation target: "+str(p.movement.targets[i])
	elif entity==Entity.BAIT:
		var a: Dictionary=eco.forage[entity_index];heading.text="%s school #%d" % [eco.FORAGE_NAMES[int(a.kind)],a.id]
		text+="Approximately %.0f prey · %.1f in\n%s\nHunger %.0f%% · danger %.0f%%\nTarget habitat: %s\n\nRecent: %s\n" % [a.quantity,a.size_cm/2.54,a.get("activity","moving"),a.get("hunger",0)*100,a.get("fear",0)*100,a.get("preferred_area","searching"),a.get("last_event","")]
		if not a.get("active",true): text+="Merged into school #%d; original identity retained.\n" % a.merged_into
		if advanced: text+="\nParent #%d · capacity %.0f\nDestination region %s" % [a.get("parent_id",-1),a.capacity,str(a.destination)]
	elif entity==Entity.PREDATOR:
		var a: Dictionary=eco.predators[entity_index];heading.text="%s #%d" % [eco.PREDATOR_NAMES[int(a.kind)],a.id]
		text+="%.1f in · hunger %.0f%% (100 = starving)\n" % [a.size_cm/2.54,a.hunger*100];text+=hunt_text(-int(a.id))
		if a.pod>=0: text+="\nDolphin pod %d" % a.pod
	else:
		var a: Dictionary=web.areas[entity_index];heading.text=str(a.kind).replace("_"," ")
		var stock := 0.0
		for b in web.bottom:
			if b.area==a.id: stock+=b.quantity
		text="%s\n\nFunctions: %s\nExtent %.0f × %.0f ft\nBottom prey %.0f / %.0f capacity\nNutrients %.0f%%; replenishes gradually\n" % ["Inferred habitat" if a.inferred else "Mapped evidence; inferred opportunity boundary",", ".join(a.roles),(a.bounds[2]-a.bounds[0])/.3048,(a.bounds[3]-a.bounds[1])/.3048,stock,a.bottom_capacity,web.nutrients[entity_index]*100]
		if advanced: text+="\nEvidence: "+", ".join(a.evidence)+"\n"+a.id
	info.text=text
func hunt_text(actor: int) -> String:
	if not available(): return "Hunting unavailable"
	var p=main.fish;var h=p.hunting;var s: Dictionary=h.state(actor);var target: Dictionary=h.prey(int(s.kind),int(s.target))
	var text := "%s\n%s\nEnergy %.0f%% (100 = rested) · captures %d / misses %d\n" % [h.LABELS[int(s.stage)],s.activity,s.energy*100,s.captures,s.misses]
	if s.stage in [6,8]: text+="Meal captured at physical contact; school may move away.\n"
	elif not target.is_empty(): text+="Prey: %s · %.1f yd\n" % [target.label,h.position(actor).distance_to(h.prey_position(actor,int(s.kind),int(s.target),target))/.9144]
	else: text+="Prey: searching\n"
	text+="\nRecent: "+str(s.last_event)+"\n"
	if advanced:
		var count := 0
		for index in range(h.events.size()-1,-1,-1):
			var e: Dictionary=h.events[index]
			if e.actor==actor: text+="%.0f s ago: %s\n" % [p.elapsed-e.time,e.text];count+=1
			if count>=4: break
	return text
func find_hunt():
	if not available(): return
	var p=main.fish;var best := -1.0;var found := -1
	for i in range(p.ids.size()):
		if p.ecology.alive[i]==0: continue
		var s: Dictionary=p.hunting.states[i]
		var rank: float=HUNT_RANK.get(int(s.stage),-1)
		if rank<0: continue
		var score: float=rank+p.hunger[i]*.1
		if score>best: best=score;found=i
	if found<0:
		for index in range(p.hunting.events.size()-1,-1,-1):
			var e: Dictionary=p.hunting.events[index]
			if e.actor>=0 and p.elapsed-e.time<30 and "capture:" in e.text and p.ecology.alive[e.actor]==1: found=int(e.actor);break
	if found<0: status.text="No active pursuit or recent capture; keep simulating."
	if found>=0: select_entity(Entity.FISH,found);center_selected();main.camera.target_span=180
func select_at(geo: GeoPosition,mpp: float):
	if not available(): return
	var p=main.fish;var at := Vector2(geo.east,geo.south);var best := pow(maxf(12*mpp,3),2);var kind := Entity.NONE;var found := -1
	for code in candidates:
		var type := int(code)/FishSpatialIndex.STRIDE;var index := int(code)%FishSpatialIndex.STRIDE
		if type==2: continue
		if type==1 and p.ecology.alive[index]==0: continue
		if type==0 and not p.ecology.forage[index].get("active",true): continue
		var pos: Vector2=observed_position(0 if type==1 else 1,index);var d := at.distance_squared_to(pos)
		if d<best: best=d;kind=Entity.FISH if type==1 else Entity.BAIT;found=index
	for index in range(p.ecology.predators.size()):
		if not p.ecology.predators[index].active: continue
		var d := at.distance_squared_to(observed_position(2,index))
		if d<best: best=d;kind=Entity.PREDATOR;found=index
	if found>=0: select_entity(kind,found);return
	var area_size := INF
	for index in visible_areas:
		if not show_areas and mode!=4 and not (entity==Entity.AREA and entity_index==index): continue
		if p.food_web.contains(index,at) and p.food_web.areas[index].area_m2<area_size:
			area_size=p.food_web.areas[index].area_m2;found=index
	if found>=0: select_entity(Entity.AREA,found)
	elif not follow_lock: select_entity(Entity.NONE,-1)
func caption(at: Vector2,text: String,mpp: float,color: Color):
	draw_set_transform(at,0,Vector2.ONE*mpp);draw_string(ThemeDB.fallback_font,Vector2(10,-7),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color);draw_set_transform(Vector2.ZERO)
func path_line(path: PackedVector2Array,cursor: int,start: Vector2,mpp: float,color: Color):
	if cursor>=path.size(): return
	var line := PackedVector2Array([start]);var origin := Vector2(main.origin.east,main.origin.south)
	for i in range(cursor,path.size()): line.append(path[i]-origin)
	if line.size()>1: draw_polyline(line,color,1.5*mpp,true)
func _draw():
	if not enabled or not available(): return
	var p=main.fish;var eco=p.ecology;var mpp: float=main.camera.span/get_viewport_rect().size.y;var origin := Vector2(main.origin.east,main.origin.south)
	for code in candidates:
		var kind := int(code)/FishSpatialIndex.STRIDE;var index := int(code)%FishSpatialIndex.STRIDE
		if kind==1 and mode in [0,1]:
			if eco.alive[index]==0 or (main.camera.span>15000 and index%4!=0 and selected!=index): continue
			var pos: Vector2=observed_position(0,index)
			if view_bounds.has_point(pos): draw_circle(pos-origin,(3 if selected==index else 2)*mpp,COLORS[p.species[index]])
		elif kind==0 and mode in [0,2]:
			var a: Dictionary=eco.forage[index]
			if not a.get("active",true) or a.quantity<1: continue
			var pos: Vector2=observed_position(1,index)
			if not view_bounds.has_point(pos): continue
			draw_circle(pos-origin,p.hunting.school_radius(index),Color(.5,.85,1,.35),false,mpp)
			pos-=origin;var color: Color=BAIT_COLORS[int(a.kind)];var radius: float=clampf(4+sqrt(a.quantity)*.6,4,15)*mpp
			if a.kind in [4,5]: draw_rect(Rect2(pos-Vector2.ONE*radius,Vector2.ONE*radius*2),color,false,mpp)
			else: draw_circle(pos,radius,color,false,1.5*mpp)
			if a.get("fear",0)>.2: draw_circle(pos,radius*(1+a.fear*.8),Color(1,.4,.5,.6),false,mpp)
			var direction: Vector2=a.get("heading",Vector2.ZERO);draw_line(pos,pos+direction*(radius+8*mpp),color,1.5*mpp)
			if main.camera.span<3500 or (entity==Entity.BAIT and entity_index==index): caption(pos,"%s #%d ≈%.0f" % [eco.FORAGE_NAMES[int(a.kind)],a.id,a.quantity],mpp,color)
	if mode in [0,3]:
		for i in range(eco.predators.size()):
			var a: Dictionary=eco.predators[i];var at: Vector2=observed_position(2,i)
			if not a.active or not view_bounds.has_point(at): continue
			var pos := at-origin;var r := 7*mpp;draw_colored_polygon(PackedVector2Array([pos+Vector2(0,-r),pos+Vector2(r,r),pos+Vector2(-r,r)]),Color(.35,.9,1) if a.kind==3 else Color(1,.3,.2))
	if show_grid:
		for z in p.zones:
			var at := Vector2(z.x,z.y)
			if view_bounds.has_point(at): draw_rect(Rect2(at-origin-Vector2.ONE*375,Vector2.ONE*750),Color(.6,.8,.8,.18),false,mpp)
	for index in visible_areas:
		if not (show_areas or mode==4 or (entity==Entity.AREA and entity_index==index)): continue
		var a: Dictionary=p.food_web.areas[index];var color := Color(.95,.65,.2,.55) if a.inferred else Color(.3,1,.7,.7)
		if entity==Entity.AREA and entity_index==index: color=Color.WHITE
		for polygon in a.polygons:
			for ring in [polygon.outer]+polygon.holes:
				var line := PackedVector2Array()
				for point in ring: line.append(point-origin)
				if line.size()>1: draw_polyline(line,color,mpp,true)
	if entity!=Entity.NONE:
		var at := selected_position()-origin;draw_circle(at,13*mpp,Color.WHITE,false,2*mpp)
		if trail.size()>1:
			var line := PackedVector2Array()
			for point in trail: line.append(point-origin)
			draw_polyline(line,Color(.4,.9,1,.5),mpp,true)
		if show_paths: selected_paths(at,mpp)
	if entity in [Entity.FISH,Entity.PREDATOR]:
		var actor := entity_index if entity==Entity.FISH else -entity_index-1
		for event in p.hunting.events:
			if event.actor!=actor or p.elapsed-event.time>20 or not view_bounds.has_point(event.position): continue
			if not ("strike" in event.text or "capture:" in event.text or "escape" in event.text): continue
			var color := Color(.3,1,.3) if "capture:" in event.text else Color(1,.5,.3)
			draw_circle(event.position-origin,9*mpp,color,false,mpp);caption(event.position-origin,event.text,mpp,color)
	for event in p.food_web.events:
		var key: String="%s:%s:%s" % [event.time,event.id,event.kind];var age: float=real_time-float(event_seen.get(key,real_time-5))
		if age>3 or not view_bounds.has_point(event.position): continue
		var color := Color(.7,1,.7,1-age/3);draw_circle(event.position-origin,(12+age*9)*mpp,color,false,mpp)
		caption(event.position-origin,"%s #%d → #%d" % [event.kind,event.id,event.other],mpp,color)
func selected_paths(at: Vector2,mpp: float):
	if not available(): return
	var p=main.fish
	if entity in [Entity.FISH,Entity.PREDATOR]:
		var actor := entity_index if entity==Entity.FISH else -entity_index-1;var s: Dictionary=p.hunting.state(actor)
		if s.stage in [1,2,3,4,5]: path_line(s.path,int(s.cursor),at,mpp,Color(1,.5,.15))
		elif entity==Entity.FISH: path_line(p.movement.routes[entity_index],p.movement.cursors[entity_index],at,mpp,Color(1,.9,.3))
		var target: Dictionary=p.hunting.prey(int(s.kind),int(s.target))
		if not target.is_empty():
			var contact: Vector2=s.get("capture_position",p.hunting.position(actor)) if s.stage in [6,8] else p.hunting.prey_position(actor,int(s.kind),int(s.target),target)
			var pos: Vector2=contact-Vector2(main.origin.east,main.origin.south)
			draw_circle(pos,3*mpp,Color(1,.3,.2),false,mpp);draw_line(at,pos,Color(1,.4,.2,.7),mpp)
			caption(pos,"Captured meal" if s.stage in [6,8] else "Target prey member",mpp,Color(1,.6,.3))
	elif entity==Entity.BAIT:
		var a: Dictionary=p.ecology.forage[entity_index]
		if a.has("natural_path"): path_line(a.natural_path,int(a.path_cursor),at,mpp,BAIT_COLORS[int(a.kind)])
