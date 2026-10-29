class_name FishDebugOverlay
extends Node2D
# Observation-only UI. Selection, follow and rendering never schedule simulation work.
enum Entity { NONE, FISH, BAIT, PREDATOR, AREA }
class ColumnIndicator extends Control:
	var bed_m := 1.0
	var animal_m := 0.0
	var prey_m := -1.0
	var holding_m := 0.0
	var target_m := 0.0
	func _draw():
		var scale := 78.0/maxf(.05,bed_m)
		draw_rect(Rect2(12,12,64,78),Color(.08,.24,.34))
		draw_line(Vector2(12,12),Vector2(76,12),Color(.5,.8,1),2)
		draw_line(Vector2(12,90),Vector2(76,90),Color(.7,.6,.35),2)
		draw_line(Vector2(12,12+holding_m*scale),Vector2(76,12+holding_m*scale),Color(.4,1,.5),1)
		draw_circle(Vector2(32,12+clampf(animal_m,0,bed_m)*scale),4,Color.WHITE)
		draw_circle(Vector2(52,12+clampf(target_m,0,bed_m)*scale),3,Color(1,.8,.25),false,1)
		if prey_m>=0: draw_circle(Vector2(65,12+clampf(prey_m,0,bed_m)*scale),4,Color(1,.4,.3))
		draw_string(ThemeDB.fallback_font,Vector2(90,23),"Surface",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(.5,.8,1))
		draw_string(ThemeDB.fallback_font,Vector2(90,44),"White: selected   Red: prey",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
		draw_string(ThemeDB.fallback_font,Vector2(90,65),"Green: holding   Gold: target",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
		draw_string(ThemeDB.fallback_font,Vector2(90,89),"Bottom %.1f ft" % (bed_m/.3048),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(.7,.6,.35))
var column_indicator: ColumnIndicator
var bait_menu: PopupMenu
var bait_spawn_at := Vector2.ZERO
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
var show_detail := false
var detail_controls: Array[Control] = []
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
var speed_buttons: Array[Button] = []
var refresh_clock := 0.0
var real_time := 0.0
var rate_clock := 0.0
var prior_sim := 0.0
var actual_rate := 0.0
var candidates: Array = []
var overview_points: Array[PackedVector2Array] = []
var overview_build: Array[PackedVector2Array] = []
var overview_candidates: Array = []
var overview_cursor := 0
var overview_origin := Vector2.ZERO

var visible_areas: Array[int] = []
var view_bounds := Rect2()
var cached_revision := -1
var view_refresh_at := 0.0
var cached_span := 0.0
var cached_center := Vector2.INF
var trail := PackedVector2Array()
var event_seen: Dictionary = {}
const SPEEDS := [0.0,1.0,5.0,10.0,20.0]
const HUNT_RANK := {5:10,6:9,8:8,3:7,2:6,1:4}
const COLORS := [Color(.98,.48,.22),Color(.35,.83,.96),Color(.77,.54,.96),Color(.85,.85,.7),Color(.7,.9,1),Color(1,.9,.2),Color(.6,.45,.25),Color(.95,.35,.48)]
const BAIT_COLORS := [Color(.8,1,.9),Color(.35,.7,1),Color(1,.7,.4),Color(1,.9,.25),Color(1,.5,.7),Color(.8,.5,.3),Color(.55,1,.6),Color(.25,.8,.45)]
var performance_label: Label
var performance_box: VBoxContainer
var diagnostic_clock := 0.0
var diagnostic_report := ""
var school_report := ""
var school_report_at := -1000
var school_report_index := -1
var diagnostic_mode: OptionButton
var saved_detail_enabled := true
var diagnostic_mode_index := 0
var diagnostic_shown := ""
func available() -> bool:
	var reason := "population not initialized" if main==null or main.fish==null else str(main.fish.initialization_problem())
	if reason.is_empty():
		diagnostic_shown=""
		return true
	candidates.clear();visible_areas.clear();trail.clear();entity=Entity.NONE;entity_index=-1;selected_zone=-1;following=false
	if info!=null and reason!=diagnostic_shown:
		diagnostic_shown=reason;heading.text="Fish Lab unavailable";info.text=reason+".\n\nSimulation unavailable for this session.";status.text="Ecology initialization incomplete"
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
	p.time_scale=SPEEDS[value]
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
	main=game
	bait_menu=PopupMenu.new();add_child(bait_menu)
	# Native popup uses screen pixels, independent of the world's canvas/zoom transform.
	bait_menu.force_native=true;bait_menu.content_scale_factor=1.0;bait_menu.content_scale_size=Vector2i.ZERO
	bait_menu.add_theme_font_size_override("font_size",16)
	bait_menu.close_requested.connect(bait_menu.hide)
	bait_menu.window_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			bait_menu.hide();bait_menu.set_input_as_handled()
		elif event.is_action_pressed("fish_debug",false,true):
			toggle();bait_menu.set_input_as_handled())
	for kind in range(FishEcology.FORAGE_NAMES.size()): bait_menu.add_item("Spawn one "+FishEcology.FORAGE_NAMES[kind],kind)
	bait_menu.id_pressed.connect(func(kind):
		bait_menu.hide()
		if not enabled or not available(): return
		var index: int=main.fish.food_web.spawn_single(kind,bait_spawn_at)
		main.hud.tell("Placed one "+FishEcology.FORAGE_NAMES[kind] if index>=0 else "Bait requires navigable water and an available record slot.")
		cache_view();queue_redraw())
	z_index=5;canvas=CanvasLayer.new();canvas.layer=9;add_child(canvas)
	toolbar=PanelContainer.new();toolbar.position=Vector2(16,110);toolbar.add_theme_stylebox_override("panel",style());canvas.add_child(toolbar)
	var controls := VBoxContainer.new();toolbar.add_child(controls)
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",10);controls.add_child(row)
	var title := Label.new();title.text="FISH LAB";title.add_theme_font_size_override("font_size",20);row.add_child(title)
	var modes := OptionButton.new()
	for text in ["All life","Game fish","Bait schools","Predators","Habitat / food"]: modes.add_item(text)
	row.add_child(modes);modes.item_selected.connect(func(value): mode=value;cache_view();queue_redraw())
	var speed_group := ButtonGroup.new()
	for i in range(SPEEDS.size()):
		var speed_button := Button.new();speed_button.text="Pause" if i==0 else "%d×" % SPEEDS[i];speed_button.toggle_mode=true;speed_button.button_group=speed_group
		speed_button.pressed.connect(set_speed.bind(i));row.add_child(speed_button);speed_buttons.append(speed_button)
	toggle_button(row,"Paths",true,func(v): show_paths=v)
	toggle_button(row,"Areas",false,func(v): show_areas=v;cache_view())
	toggle_button(row,"Grid",false,func(v): show_grid=v)
	toggle_button(row,"Advanced",false,func(v): advanced=v;main.fish.diagnostics.detailed=v;refresh())
	var distance_toggle := toggle_button(row,"Distance detail",true,func(v):
		if available(): main.fish.simulation_detail.enabled=v)
	if main.fish!=null and main.fish.simulation_detail!=null: distance_toggle.set_pressed_no_signal(main.fish.simulation_detail.enabled)
	detail_controls.append(distance_toggle)
	detail_controls.append(toggle_button(row,"Ranges",false,func(v): show_detail=v;queue_redraw()))
	for control in detail_controls: control.hide()
	button(row,"Inspector",func(): inspector_open=not inspector_open;panel.visible=enabled and inspector_open)
	performance_box=VBoxContainer.new();controls.add_child(performance_box)
	var diagnostic_row := HBoxContainer.new();performance_box.add_child(diagnostic_row)
	diagnostic_mode=OptionButton.new()
	for label in ["Diagnostics: Normal simulation","Diagnostics: Ecology disabled (time queues)","Diagnostics: Detailed hunting disabled","Diagnostics: Visual publishing disabled","Diagnostics: Distance optimization disabled"]: diagnostic_mode.add_item(label)
	diagnostic_row.add_child(diagnostic_mode);diagnostic_mode.item_selected.connect(set_diagnostic_mode)
	button(diagnostic_row,"Copy Diagnostics",func():
		if available(): DisplayServer.clipboard_set(main.fish.diagnostics.report(main.fish)+school_diagnostics()))
	performance_label=Label.new();performance_label.add_theme_font_size_override("font_size",13);performance_box.add_child(performance_label)
	status=Label.new();status.custom_minimum_size.x=330;status.add_theme_font_size_override("font_size",16);row.add_child(status)
	panel=PanelContainer.new();panel.position=Vector2(16,390);panel.custom_minimum_size=Vector2(390,660);panel.size=Vector2(390,660);panel.add_theme_stylebox_override("panel",style());canvas.add_child(panel)
	var column := VBoxContainer.new();column.add_theme_constant_override("separation",10);panel.add_child(column)
	heading=Label.new();heading.add_theme_font_size_override("font_size",22);heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;heading.custom_minimum_size.x=365;column.add_child(heading)
	column_indicator=ColumnIndicator.new();column_indicator.custom_minimum_size=Vector2(360,102);column.add_child(column_indicator);column_indicator.hide()
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
	bait_menu.hide()
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
	if main.fish.simulation_detail!=null:
		main.fish.observed_fish=entity_index if entity==Entity.FISH else -1
		main.fish.food_web.observed_bait=entity_index if entity==Entity.BAIT else -1
		main.fish.simulation_detail.selected_predator=entity_index if entity==Entity.PREDATOR else -1
	if entity==Entity.NONE:
		following=false
		if follow_toggle!=null: follow_toggle.set_pressed_no_signal(false)
	if scroll!=null: scroll.scroll_vertical=0
	if panel!=null and entity!=Entity.NONE: inspector_open=true;panel.visible=enabled
	refresh();queue_redraw()
func observed_position(kind: int,index: int) -> Vector2:
	return main.fish.displayed(kind,index)
func observed_prey(actor: int,s: Dictionary,data: Dictionary) -> Vector2:
	var h=main.fish.hunting
	var contact: Vector2=h.prey_position(actor,int(s.kind),int(s.target),data)
	if s.kind==0: return observed_position(1,int(s.target))+contact-Vector2(data.position)
	if s.kind==1: return observed_position(0,int(s.target))
	return contact
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
	if main==null or main.fish==null: return
	var diagnostic_begin := Time.get_ticks_usec()
	_measured_tick(dt)
	main.fish.diagnostics.add("Fish Lab UI",Time.get_ticks_usec()-diagnostic_begin)
func _measured_tick(dt: float):
	real_time+=dt
	if bait_menu.visible and (not enabled or main.hud.menu.visible): bait_menu.hide()
	if main.fish!=null: main.fish.presentation.view_active=enabled;main.fish.presentation.view_bounds=view_bounds
	if not enabled or not available(): return
	if following and entity!=Entity.NONE:
		var at := selected_position();var t := 1-exp(-10*minf(dt,.05))
		main.camera.follow=false;main.camera.anchor=null;main.camera.geo.east=lerpf(main.camera.geo.east,at.x,t);main.camera.geo.south=lerpf(main.camera.geo.south,at.y,t)
	diagnostic_clock+=dt
	if diagnostic_clock>=1:
		diagnostic_clock=0;diagnostic_report=main.fish.diagnostics.report(main.fish,false)
		var lines: PackedStringArray=diagnostic_report.split("\n")
		performance_label.text="\n".join(lines.slice(0,4))
		for key in ["Frame wall","Simulation"]:
			if main.fish.diagnostics.samples.has(key): performance_label.text+="\n"+key+": "+main.fish.diagnostics.stats(key)
	var center := Vector2(main.camera.geo.east,main.camera.geo.south)
	if cached_span<=0 or main.camera.span<cached_span*.8 or main.camera.span>cached_span*1.25 or center.distance_squared_to(cached_center)>pow(main.camera.span*.1,2):
		cache_view()
	refresh_clock+=dt;rate_clock+=dt
	if rate_clock>=1:
		actual_rate=maxf(0,(main.fish.completed_time()-prior_sim)/rate_clock);prior_sim=main.fish.completed_time();rate_clock=0
	if refresh_clock>=.25:
		refresh_clock=0
		if real_time>=view_refresh_at and cached_revision!=main.fish.hunting.spatial.revision: cache_view()
		refresh()
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
	if main.camera.span>3500: build_overview()
	queue_redraw()
func cache_view():
	if not available(): return
	var size := get_viewport_rect().size;var half: Vector2=Vector2(size.x/size.y,1)*main.camera.span*.5
	cached_span=main.camera.span;cached_center=Vector2(main.camera.geo.east,main.camera.geo.south)
	view_bounds=Rect2(cached_center-half,half*2).grow(250)
	candidates=main.fish.hunting.spatial.rectangle(view_bounds)
	cached_revision=main.fish.hunting.spatial.revision;view_refresh_at=real_time+1
	main.fish.presentation.view_bounds=view_bounds
	visible_areas.clear()
	for site in main.fish.food_web.site_areas: visible_areas.append(site)
	if show_areas or mode==4 or entity==Entity.AREA:
		for index in range(main.fish.food_web.areas.size()):
			var b: Array=main.fish.food_web.areas[index].bounds
			if view_bounds.intersects(Rect2(b[0],b[1],b[2]-b[0],b[3]-b[1])): visible_areas.append(index)
func refresh():
	if info==null or not available(): return
	var p=main.fish;var eco=p.ecology;var web=p.food_web
	for control in detail_controls: control.visible=advanced
	var slow: bool=p.time_scale>0 and real_time>2 and actual_rate<p.time_scale*.9 and p.time_debt>maxf(1,p.time_scale*.5)
	status.text="Paused" if p.time_scale<=0 else "%d×%s" % [p.time_scale," — running slower; CPU limit" if slow else ""]
	if advanced: status.text+="\nActual %.2f× · queued %.1f s\nSimulated %.2f h · %.1f ms/frame" % [actual_rate,p.time_debt,p.completed_time()/3600,p.update_ms]
	var speed_index := SPEEDS.find(p.time_scale)
	for i in range(speed_buttons.size()): speed_buttons[i].set_pressed_no_signal(i==speed_index)
	if entity==Entity.NONE:
		column_indicator.hide()
		heading.text="Explore the ecosystem";info.text="Click a fish, bait school, predator or habitat.\n\nOne entity is inspected at a time. Empty clicks clear selection unless locked.\n\nFollowing and zooming never change simulation behavior.";return
	var at := selected_position();var text := "Location E %.2f / S %.2f mi\n" % [at.x/1609.344,at.y/1609.344]
	if entity==Entity.FISH:
		var i := entity_index;heading.text="%s #%d" % [p.SPECIES[p.species[i]],p.ids[i]]
		text+="%.1f in · hunger %.0f%% (100 = starving)\nPreferred habitat bottom %.1f ft\n" % [p.size_cm[i]/2.54,p.hunger[i]*100,p.preferred_depth[i]/.3048]
		if eco.alive[i]==0: text+="Consumed — identity retained\n"
		else: text+=hunt_text(i)
		text+="\nSize cohort: "+p.size_cohort(i)+"\n"
		text+="\nPreferred areas\nRest: %s\nFeed: %s\nSchool: %s\n" % [web.area_for_feature(p.movement.preferred_rest[i],"resting"),web.area_for_feature(p.movement.preferred_feed[i],"feeding"),str(eco.school[i]) if eco.school[i]>=0 else "solo"]
		if advanced: text+="\n"+eco.describe(i)+"\nNavigation target: "+str(p.movement.targets[i])
	elif entity==Entity.BAIT:
		var a: Dictionary=eco.forage[entity_index];heading.text="%s %s #%d" % [eco.FORAGE_NAMES[int(a.kind)],"individual" if a.get("individual",false) else "school",a.id]
		text+="%.0f prey · %.1f in\n%s\nHunger %.0f%% · danger %.0f%%\nTarget habitat: %s\n\nRecent: %s\n" % [a.quantity,a.size_cm/2.54,a.get("activity","moving"),a.get("hunger",0)*100,a.get("fear",0)*100,a.get("preferred_area","searching"),a.get("last_event","")]
		text+=school_diagnostics()
		if not a.get("active",true): text+="Retired: "+str(a.activity)+"\n"
		if a.get("temporary",false):
			text+="\nEscapee #%d · parent school #%d\n%s\n" % [a.id,a.parent_id,a.activity]
			text+="Hunters: "+escapee_hunters(entity_index)+"\n"
		if advanced: text+="\nParent #%d · capacity %.0f\nDestination region %s" % [a.get("parent_id",-1),a.capacity,str(a.destination)]
	elif entity==Entity.PREDATOR:
		var a: Dictionary=eco.predators[entity_index];heading.text="%s #%d" % [eco.PREDATOR_NAMES[int(a.kind)],a.id]
		text+="%.1f in · hunger %.0f%% (100 = starving)\n" % [a.size_cm/2.54,a.hunger*100];text+=hunt_text(-int(a.id))
		if a.pod>=0: text+="\nDolphin pod %d" % a.pod
	else:
		var a: Dictionary=web.areas[entity_index];heading.text=a.get("label",str(a.kind).replace("_"," "))
		var stock := 0.0
		for b in web.bottom:
			if b.area==a.id: stock+=b.quantity
		text="%s\n\nFunctions: %s\nExtent %.0f × %.0f ft\nBottom prey %.0f / %.0f capacity\nNutrients %.0f%%; replenishes gradually\n" % ["Authored gameplay site (not a surveyed feature)" if a.get("authored",false) else ("Inferred habitat" if a.inferred else "Mapped evidence; inferred opportunity boundary"),", ".join(a.roles),(a.bounds[2]-a.bounds[0])/.3048,(a.bounds[3]-a.bounds[1])/.3048,stock,a.bottom_capacity,web.nutrients[entity_index]*100]
		if advanced: text+="\nEvidence: "+", ".join(a.evidence)+"\n"+a.id
	if p.simulation_detail!=null:
		var tier: int=p.simulation_detail.actor_level(entity_index) if entity==Entity.FISH else (p.simulation_detail.bait_level(entity_index) if entity==Entity.BAIT else (p.simulation_detail.actor_level(-entity_index-1) if entity==Entity.PREDATOR else -1))
		if tier>=0: text+="\nSimulation: "+p.simulation_detail.NAMES[tier]+"\n"
	text+=depth_text()
	info.text=text
func escapee_hunters(index: int) -> String:
	var p=main.fish;var a: Dictionary=p.ecology.forage[index];var names := PackedStringArray()
	for code in p.hunting.spatial.query(Vector2(a.x,a.y),250):
		if int(code)/FishSpatialIndex.STRIDE!=1: continue
		var fish_index := int(code)%FishSpatialIndex.STRIDE;var state: Dictionary=p.hunting.states[fish_index]
		if state.kind==0 and state.target==index and int(state.get("target_id",-1))==int(a.id): names.append("fish #"+str(p.ids[fish_index]))
		if names.size()>=8: break
	for predator in p.ecology.predators:
		var state: Dictionary=predator.hunt
		if state.kind==0 and state.target==index and int(state.get("target_id",-1))==int(a.id): names.append("predator #"+str(predator.id))
	return ", ".join(names) if not names.is_empty() else "none nearby"
func depth_text() -> String:
	var p=main.fish;var water=p.water_column
	if water==null or not entity in [Entity.FISH,Entity.BAIT,Entity.PREDATOR]: column_indicator.hide();return ""
	var depth := 0.0;var hold := 0.0;var target_depth := 0.0;var bed := 0.0;var prey_depth := -1.0
	if entity==Entity.FISH:
		depth=water.current[entity_index];hold=water.holding[entity_index];target_depth=water.target[entity_index];bed=water.bottom[entity_index]
	else:
		var a: Dictionary=p.ecology.forage[entity_index] if entity==Entity.BAIT else p.ecology.predators[entity_index]
		depth=a.swim_depth;hold=a.holding_depth;target_depth=a.target_depth;bed=a.bottom_depth
	var text := "\nWater column\nCurrent %.1f ft below surface\nPreferred holding %.1f ft · target %.1f ft\nBottom %.1f ft · height above bottom %.1f ft\n" % [depth/.3048,hold/.3048,target_depth/.3048,bed/.3048,maxf(0,bed-depth)/.3048]
	if entity in [Entity.FISH,Entity.PREDATOR]:
		var actor := entity_index if entity==Entity.FISH else -entity_index-1;var state: Dictionary=p.hunting.state(actor)
		var prey: Dictionary=p.hunting.tracked_prey(state)
		if not prey.is_empty() and state.stage in [1,2,3,4,5]:
			prey_depth=water.prey_depth(actor,int(state.kind),int(state.target),prey)
			text+="Prey %.1f ft · vertical gap %.1f ft\n" % [prey_depth/.3048,absf(depth-prey_depth)/.3048]
	elif entity==Entity.BAIT: text+="School vertical spread ±%.1f ft\n" % (float(p.ecology.forage[entity_index].vertical_spread)/.3048)
	column_indicator.bed_m=bed;column_indicator.animal_m=depth;column_indicator.holding_m=hold;column_indicator.target_m=target_depth;column_indicator.prey_m=prey_depth;column_indicator.show();column_indicator.queue_redraw()
	return text
func hunt_text(actor: int) -> String:
	if not available(): return "Hunting unavailable"
	var p=main.fish;var h=p.hunting;var s: Dictionary=h.state(actor);var target: Dictionary=h.tracked_prey(s)
	var text := "%s\n%s\nEnergy %.0f%% (100 = rested) · captures %d / misses %d\n" % [h.LABELS[int(s.stage)],s.activity,s.energy*100,s.captures,s.misses]
	if s.stage in [6,8]: text+="Meal captured at physical contact; school may move away.\n"
	elif not target.is_empty(): text+="Prey: %s · %.1f yd\n" % [target.label,p.water_column.distance_to_prey(actor,int(s.kind),int(s.target),target)/.9144]
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
		if not show_areas and mode!=4 and not p.food_web.areas[index].get("authored",false) and not (entity==Entity.AREA and entity_index==index): continue
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
	if main==null or main.fish==null: return
	var diagnostic_begin := Time.get_ticks_usec()
	_measured_draw()
	main.fish.diagnostics.add("Fish Lab draw",Time.get_ticks_usec()-diagnostic_begin)
func _measured_draw():
	if not enabled or not available(): return
	var p=main.fish;var eco=p.ecology;var mpp: float=main.camera.span/get_viewport_rect().size.y;var origin := Vector2(main.origin.east,main.origin.south)
	if show_detail and p.simulation_detail!=null:
		for focus in [p.simulation_detail.boat,p.simulation_detail.camera]:
			draw_circle(focus-origin,p.simulation_detail.detailed_m,Color(.4,1,.5,.4),false,mpp)
			draw_circle(focus-origin,p.simulation_detail.intermediate_m,Color(1,.8,.4,.3),false,mpp)
	var overview: bool=main.camera.span>3500
	var dots: Array[PackedVector2Array]=overview_points
	for code in ([] if overview else candidates):
		var kind := int(code)/FishSpatialIndex.STRIDE;var index := int(code)%FishSpatialIndex.STRIDE
		if kind==1 and mode in [0,1]:
			if eco.alive[index]==0 or (main.camera.span>15000 and index%4!=0 and selected!=index): continue
			var pos: Vector2=observed_position(0,index)
			if view_bounds.has_point(pos):
				draw_circle(pos-origin,(3 if selected==index else 2)*mpp,COLORS[p.species[index]])
				var hunt: Dictionary=p.hunting.states[index]
				if entity==Entity.BAIT and hunt.kind==0 and hunt.target==entity_index and int(hunt.get("target_id",-1))==int(eco.forage[entity_index].id): draw_line(pos-origin,observed_position(1,entity_index)-origin,Color(1,.4,.2,.65),mpp)
		elif kind==0 and mode in [0,2]:
			var a: Dictionary=eco.forage[index]
			if not a.get("active",true) or a.quantity<1: continue
			var pos: Vector2=observed_position(1,index)
			if not view_bounds.has_point(pos): continue
			if not a.get("individual",false) and (main.camera.span<1200 or (entity==Entity.BAIT and entity_index==index)):
				var footprint := PackedVector2Array()
				for n in range(17): footprint.append(pos-origin+p.food_web.member_offset(a,int(n*6283/16),p.hunting.school_radius(index)))
				draw_polyline(footprint,Color(.5,.85,1,.35),mpp,true)
				if main.camera.span<1200:
					for n in range(mini(8,int(a.quantity))):
						var member: Vector2=p.food_web.member_offset(a,int(a.id)*137+n*613,p.hunting.school_radius(index))
						if p.movement.nav.clear(Vector2(a.x,a.y),Vector2(a.x,a.y)+member): draw_circle(pos-origin+member,1.5*mpp,BAIT_COLORS[int(a.kind)])
			pos-=origin;var color: Color=Color(1,.35,.85) if a.get("temporary",false) else BAIT_COLORS[int(a.kind)];var radius: float=(2.5 if a.get("individual",false) else clampf(4+sqrt(a.quantity)*.6,4,15))*mpp
			if a.kind in [4,5]: draw_rect(Rect2(pos-Vector2.ONE*radius,Vector2.ONE*radius*2),color,false,mpp)
			else: draw_circle(pos,radius,color,false,1.5*mpp)
			if a.get("fear",0)>.2: draw_circle(pos,radius*(1+a.fear*.8),Color(1,.4,.5,.6),false,mpp)
			var direction: Vector2=a.get("heading",Vector2.ZERO);draw_line(pos,pos+direction*(radius+8*mpp),color,1.5*mpp)
			if main.camera.span<3500 or (entity==Entity.BAIT and entity_index==index): caption(pos,"%s #%d ≈%.0f" % [eco.FORAGE_NAMES[int(a.kind)],a.id,a.quantity],mpp,color)
	if overview:
		for n in range(dots.size()):
			if not dots[n].is_empty(): draw_set_transform(overview_origin-origin);draw_multiline(dots[n],COLORS[n] if n<COLORS.size() else (BAIT_COLORS[n-COLORS.size()] if n<COLORS.size()+8 else Color(1,.35,.85)),2*mpp);draw_set_transform(Vector2.ZERO)
	if mode in [0,3]:
		for i in range(eco.predators.size()):
			var a: Dictionary=eco.predators[i];var at: Vector2=observed_position(2,i)
			if not a.active or not view_bounds.has_point(at): continue
			if entity==Entity.BAIT:
				var hunt: Dictionary=p.hunting.state(-i-1)
				if hunt.kind==0 and hunt.target==entity_index and int(hunt.get("target_id",-1))==int(eco.forage[entity_index].id): draw_line(at-origin,observed_position(1,entity_index)-origin,Color(1,.4,.2,.65),mpp)
			var pos := at-origin;var r := 7*mpp;draw_colored_polygon(PackedVector2Array([pos+Vector2(0,-r),pos+Vector2(r,r),pos+Vector2(-r,r)]),Color(.35,.9,1) if a.kind==3 else Color(1,.3,.2))
	for site in p.food_web.site_areas:
		var area: Dictionary=p.food_web.areas[site];var at: Vector2=p.movement.nav.point(int(area.nodes[0]))
		if not view_bounds.has_point(at): continue
		var color := Color(.85,.7,.35) if area.kind=="oyster_bar_candidate" else Color(.65,.65,.75)
		draw_rect(Rect2(at-origin-Vector2.ONE*5*mpp,Vector2.ONE*10*mpp),color,false,mpp)
		if main.camera.span<3500: caption(at-origin,area.label,mpp,color)
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
		var target: Dictionary=p.hunting.tracked_prey(s)
		if not target.is_empty():
			var contact: Vector2=s.get("capture_position",p.hunting.position(actor)) if s.stage in [6,8] else observed_prey(actor,s,target)
			var pos: Vector2=contact-Vector2(main.origin.east,main.origin.south)
			draw_circle(pos,3*mpp,Color(1,.3,.2),false,mpp);draw_line(at,pos,Color(1,.4,.2,.7),mpp)
			caption(pos,"Captured meal" if s.stage in [6,8] else "Target prey member",mpp,Color(1,.6,.3))
	elif entity==Entity.BAIT:
		var a: Dictionary=p.ecology.forage[entity_index]
		if a.has("natural_path"): path_line(a.natural_path,int(a.path_cursor),at,mpp,BAIT_COLORS[int(a.kind)])

func set_diagnostic_mode(value: int):
	if not available(): return
	var p=main.fish
	if diagnostic_mode_index==4: p.simulation_detail.enabled=saved_detail_enabled
	diagnostic_mode_index=value
	p.diagnostics.ecology_disabled=value==1;p.diagnostics.hunting_disabled=value==2;p.diagnostics.publishing_disabled=value==3
	if value==4:
		saved_detail_enabled=p.simulation_detail.enabled;p.simulation_detail.enabled=false
func school_diagnostics() -> String:
	if entity!=Entity.BAIT or not valid_entity(entity,entity_index): return ""
	var now := Time.get_ticks_msec()
	if school_report_index==entity_index and now-school_report_at<2000: return school_report
	school_report_at=now;school_report_index=entity_index
	var p=main.fish;var a: Dictionary=p.ecology.forage[entity_index]
	var parent_id: int=int(a.get("parent_id",-1)) if a.get("temporary",false) else int(a.id)
	var school_index: int=p.food_web.bait_slots.get(parent_id,-1)
	if school_index<0: return "Parent school unavailable\n"
	var school: Dictionary=p.ecology.forage[school_index]
	var school_targets := 0;var escapee_targets := 0
	for state in p.hunting.states:
		var target_kind := school_target_kind(state,parent_id,school_index)
		if target_kind==1: school_targets+=1
		elif target_kind==2: escapee_targets+=1
	for predator in p.ecology.predators:
		if not predator.active: continue
		var target_kind := school_target_kind(predator.get("hunt",{}),parent_id,school_index)
		if target_kind==1: school_targets+=1
		elif target_kind==2: escapee_targets+=1
	school_report="\nSchool #%d: %.0f prey; detached %d\nFear %.2f; fleeing %s\nHunters targeting school %d / escapees %d\n" % [parent_id,school.quantity,school.get("escapees",0),school.fear,school.fear>.3,school_targets,escapee_targets]
	return school_report
func school_target_kind(state: Dictionary,parent_id: int,school_index: int) -> int:
	if int(state.get("kind",-1))!=0 or int(state.get("stage",0)) not in [1,2,3,4,5]: return 0
	var index: int=state.get("target",-1);var forage: Array=main.fish.ecology.forage
	if index<0 or index>=forage.size(): return 0
	var a: Dictionary=forage[index]
	if not a.active or int(state.get("target_id",-1))!=int(a.id): return 0
	if index==school_index: return 1
	return 2 if a.get("temporary",false) and int(a.get("parent_id",-1))==parent_id else 0


func build_overview():
	# Bay-wide movement is subpixel. Build a complete marker buffer incrementally,
	# while the previous buffer remains visible; close views still interpolate every frame.
	if overview_build.is_empty():
		for n in range(COLORS.size()+9): overview_build.append(PackedVector2Array())
		overview_candidates=candidates.duplicate();overview_cursor=0
	var begin := Time.get_ticks_usec()
	var p=main.fish;var mpp: float=main.camera.span/get_viewport_rect().size.y
	while overview_cursor<overview_candidates.size() and Time.get_ticks_usec()-begin<1000:
		var code: int=overview_candidates[overview_cursor];overview_cursor+=1
		var kind := code/FishSpatialIndex.STRIDE;var index := code%FishSpatialIndex.STRIDE
		var group := -1;var at := Vector2.ZERO
		if kind==1 and mode in [0,1] and p.ecology.alive[index]!=0:
			group=p.species[index];at=observed_position(0,index)
		elif kind==0 and mode in [0,2]:
			var a: Dictionary=p.ecology.forage[index]
			if not a.get("active",true) or a.quantity<1: continue
			group=COLORS.size()+8 if a.get("temporary",false) else COLORS.size()+int(a.kind);at=observed_position(1,index)
		if group>=0:
			overview_build[group].append(at-Vector2(mpp,0));overview_build[group].append(at+Vector2(mpp,0))
	if overview_cursor>=overview_candidates.size():
		overview_points=overview_build;overview_build=[];overview_origin=Vector2.ZERO
	p.diagnostics.add("Overview buffer",Time.get_ticks_usec()-begin)

func open_bait_menu(screen: Vector2) -> bool:
	if not enabled or entity!=Entity.NONE or not available(): return false
	var geo: GeoPosition=main.camera.world_at(screen);bait_spawn_at=Vector2(geo.east,geo.south)
	var window := get_window()
	var bounds := Rect2i(DisplayServer.window_get_position(window.get_window_id()),DisplayServer.window_get_size(window.get_window_id()))
	bounds=bounds.intersection(DisplayServer.screen_get_usable_rect(window.current_screen))
	var extent := Vector2i(mini(300,bounds.size.x),mini(290,bounds.size.y))
	var at := Vector2i(get_viewport().get_screen_transform()*screen)
	at.x=clampi(at.x,bounds.position.x,bounds.end.x-extent.x);at.y=clampi(at.y,bounds.position.y,bounds.end.y-extent.y)
	bait_menu.size=extent;bait_menu.popup(Rect2i(at,extent))
	return true
