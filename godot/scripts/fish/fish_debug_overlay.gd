class_name FishDebugOverlay
extends Node2D
var main
var selected := -1
var selected_zone := -1
var enabled := false
var timer := 0.0
var mode := 0
var show_grid := false
var follow_selected := false
var selected_feature := -1
var selected_area := -1
var trail := PackedVector2Array()
var trail_id := -1
var centroids := PackedVector2Array()
var selected_forage := -1
var selected_predator := -1
var tide_button: Button
var predator_button: Button
var drawn_origin := Vector2.ZERO
var canvas: CanvasLayer
var panel: PanelContainer
var info: Label
var legend: Label
var speed_button: Button
var counts := PackedInt32Array()
var species_counts: Array = []
const COLORS := [Color(.98,.48,.22),Color(.35,.83,.96),Color(.77,.54,.96),Color(.85,.85,.7),Color(.7,.9,1),Color(1,.9,.2),Color(.6,.45,.25)]
func setup(game):
	main=game;z_index=5
	canvas=CanvasLayer.new();canvas.layer=9;add_child(canvas)
	panel=PanelContainer.new();panel.position=Vector2(24,130);panel.custom_minimum_size=Vector2(520,880);panel.size=Vector2(520,880);canvas.add_child(panel);panel.hide()
	var style := StyleBoxFlat.new();style.bg_color=Color(.025,.05,.065,.94)
	for side in ["left","right","top","bottom"]: style.set("content_margin_"+side,12)
	panel.add_theme_stylebox_override("panel",style)
	var scroll := ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
	var body := VBoxContainer.new();body.custom_minimum_size.x=485;scroll.add_child(body)
	legend=Label.new();legend.custom_minimum_size.x=480;legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;legend.text="FISH LAB — click fish, forage or predator\nCircles: game fish · Rings: forage · Triangles: predators\nOrange redfish · Cyan trout · Purple snook\nCream sheepshead · Silver tarpon · Yellow jack · Brown flounder";body.add_child(legend)
	var mode_button := Button.new();mode_button.text="View: density / species";body.add_child(mode_button)
	mode_button.pressed.connect(func(): mode=(mode+1)%6;mode_button.text=["View: density / species","View: food availability","View: selected fish depth suitability","View: predator pressure","View: habitats / preferred spots","View: schools / prey"][mode];queue_redraw())
	speed_button=Button.new();speed_button.text="Simulation: 1×";body.add_child(speed_button)
	speed_button.pressed.connect(func(): main.fish.time_scale=10.0 if main.fish.time_scale==1 else (60.0 if main.fish.time_scale==10 else (300.0 if main.fish.time_scale==60 else 1.0));speed_button.text="Simulation: %d×" % main.fish.time_scale)
	var bait := Button.new();bait.text="Add food to selected zone";body.add_child(bait);bait.pressed.connect(func(): main.fish.boost_food(selected_zone);refresh())
	var grid_toggle := CheckButton.new();grid_toggle.text="Show internal population grid";body.add_child(grid_toggle)
	grid_toggle.toggled.connect(func(value: bool): show_grid=value;queue_redraw())
	var track_toggle := CheckButton.new();track_toggle.text="Follow selected fish / bait / predator";body.add_child(track_toggle)
	track_toggle.toggled.connect(func(value: bool):
		follow_selected=value
		if value: main.camera.follow=false;main.camera.anchor=null;main.camera.target_span=1500)
	var nearby := Button.new();nearby.text="Select fish in zone (next)";body.add_child(nearby);nearby.pressed.connect(select_next)
	var follow := Button.new();follow.text="Center map on selected fish";body.add_child(follow)
	follow.pressed.connect(func():
		if selected<0: return
		main.camera.follow=false;main.camera.anchor=null;main.camera.geo=GeoPosition.new(main.fish.east[selected],main.fish.south[selected]);main.camera.target_span=1500)
	tide_button=Button.new();body.add_child(tide_button)
	tide_button.pressed.connect(func():
		var eco=main.fish.ecology
		if eco==null: return
		eco.tide_level_m+=.5*.3048
		if eco.tide_level_m>5*.3048: eco.tide_level_m=-3*.3048
		refresh())
	predator_button=Button.new();body.add_child(predator_button)
	predator_button.pressed.connect(func():
		var eco=main.fish.ecology
		if eco==null: return
		eco.set_predator_ratio(0 if eco.predator_ratio>=.02 else eco.predator_ratio+.005);refresh())
	var scare := Button.new();scare.text="Temporary predator scare in selected zone";body.add_child(scare)
	scare.pressed.connect(func():
		if selected_zone>=0 and main.fish.ecology!=null: main.fish.ecology.pressure[selected_zone]=1.0)
	var demo := Button.new();demo.text="Observe selected fish feeding / return cycle (60×)";body.add_child(demo)
	demo.pressed.connect(func():
		if selected<0 or main.fish.ecology==null: return
		selected_zone=main.fish.ecology.feeding[selected];main.fish.boost_food(selected_zone);main.fish.time_scale=60
		main.camera.follow=false;main.camera.anchor=null;main.camera.geo=GeoPosition.new(main.fish.east[selected],main.fish.south[selected]);main.camera.target_span=2500;refresh())
	var observe := Button.new();observe.text="Find hungry hunter and follow (10×)";body.add_child(observe)
	observe.pressed.connect(observe_hunt)
	var find_id := LineEdit.new();find_id.placeholder_text="Find persistent game fish ID, then Enter";body.add_child(find_id)
	find_id.text_submitted.connect(func(value: String):
		var index: int=main.fish.ids.find(value.to_int())
		if index>=0: selected=index;selected_zone=main.fish.region[index];selected_forage=-1;selected_predator=-1;refresh())
	info=Label.new();info.custom_minimum_size.x=480;info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.add_theme_font_size_override("font_size",16);body.add_child(info)
func toggle():
	enabled=not enabled;panel.visible=enabled;refresh();queue_redraw()
func tick(dt: float):
	if main.fish!=null:
		main.fish.observed_fish=selected if enabled and selected_forage<0 and selected_predator<0 else -1
		if main.fish.food_web!=null: main.fish.food_web.observed_bait=selected_forage if enabled else -1
	if not enabled or main.fish==null: return
	if follow_selected:
		var at := Vector2.ZERO;var found := false
		if selected_forage>=0:
			var a: Dictionary=main.fish.ecology.forage[selected_forage];at=Vector2(a.x,a.y);found=true
		elif selected_predator>=0:
			var a: Dictionary=main.fish.ecology.predators[selected_predator];at=Vector2(a.x,a.y);found=true
		elif selected>=0: at=Vector2(main.fish.east[selected],main.fish.south[selected]);found=true
		if found: main.camera.follow=false;main.camera.anchor=null;main.camera.geo=GeoPosition.new(at.x,at.y)
	var current_origin := Vector2(main.origin.east,main.origin.south)
	if current_origin!=drawn_origin: queue_redraw()
	timer+=dt
	if timer>=.2:
		timer=0;refresh();queue_redraw()
		if selected>=0:
			if trail_id!=selected: trail.clear();trail_id=selected
			var at := Vector2(main.fish.east[selected],main.fish.south[selected])
			if trail.is_empty() or trail[-1].distance_to(at)>1:
				trail.append(at)
				if trail.size()>120: trail.remove_at(0)
func refresh():
	if main.fish==null or main.fish.zones.is_empty(): return
	var fish: FishPopulation=main.fish
	speed_button.text="Simulation: %d×" % fish.time_scale
	counts=fish.zone_counts;species_counts=fish.zone_species_counts
	centroids.resize(fish.zones.size())
	for z in range(fish.zones.size()):
		var center := Vector2.ZERO
		for i in fish.buckets[z]: center+=Vector2(fish.east[i],fish.south[i])
		centroids[z]=center/maxi(1,counts[z]) if counts[z]>0 else Vector2(fish.zones[z].x,fish.zones[z].y)
	var eco=fish.ecology
	if eco!=null:
		tide_button.text="Ecology tide: %+.1f ft (click to cycle)" % (eco.tide_level_m/.3048)
		predator_button.text="Predators: %.1f per 100 game fish" % (eco.predator_ratio*100)
	info.text="%d fish · %d zones\n%.3f ms update · %d migrations\n" % [fish.ids.size(),fish.zones.size(),fish.update_ms,fish.migrations]
	if eco!=null:
		var living := 0
		for count in counts: living+=count
		info.text+="Alive %d · forage pods %d\nMeals: %.1f forage / %d game fish\nPredator meals %d · returns %d · jumps %d\n" % [living,eco.forage.size(),eco.forage_consumed,eco.game_fish_consumed,eco.predator_meals,eco.returns,eco.jumps]
	if selected_zone>=0:
		var z: Dictionary=fish.zones[selected_zone]
		info.text+="\nZone %s · %d fish\nPrey availability %.0f%% · depth %.1f ft\nSpecies counts: %s\n" % [z.id,counts[selected_zone],(fish.food_web.productivity(selected_zone) if fish.food_web!=null else fish.food[selected_zone])*100,float(z.depth_m)*3.280839895,str(species_counts[selected_zone])]
		if eco!=null:
			info.text+="Pressure %.0f%% · %s\nHabitat candidates: %s\n" % [eco.pressure[selected_zone]*100,forage_summary(selected_zone),", ".join(eco.habitats[selected_zone].tags)]
	if selected>=0:
		var d := fish.inspect_fish(selected)
		info.text+="\nFish #%d · %s · %.1f in\nPrefers %.1f ft · Hunger %.0f%%\nE %.2f / S %.2f mi\n%s → %s\n%s" % [d.id,d.species,d.size_cm/2.54,d.preferred_depth_m*3.280839895,d.hunger*100,d.east/1609.344,d.south/1609.344,d.zone,d.destination,d.state]
		if eco!=null:
			info.text+="\n"+eco.describe(selected)
			if fish.movement!=null and fish.movement.ready:
				var move=fish.movement;var target: int=move.targets[selected]
				info.text+="\nPreferred habitats: %d / %d\nTarget feature: %d · route point %d\nCyan: traveled trail · Yellow: planned route" % [move.preferred_rest[selected],move.preferred_feed[selected],target,move.cursors[selected]]
			if eco.school[selected]>=0: info.text+="\nSchool member IDs: "+school_summary(eco.school[selected])
	if fish.hunting!=null and selected>=0 and selected_forage<0 and selected_predator<0: info.text+="\n"+hunt_summary(selected)
	if eco!=null and selected_forage>=0:
		var a: Dictionary=eco.forage[selected_forage]
		info.text+="\nPREY #%d · %s · %.1f remaining\nSize %.1f in · zone %s\n%s" % [a.id,eco.FORAGE_NAMES[int(a.kind)],a.quantity,a.size_cm/2.54,fish.zones[int(a.zone)].id,a.get("activity","moving")]
		info.text+="\nHunger %.0f%% · fear %.0f%%\nPreferred area: %s\n%s" % [float(a.get("hunger",0))*100,float(a.get("fear",0))*100,a.get("preferred_area","searching"),a.get("last_event","")]
	if eco!=null and selected_predator>=0:
		var a: Dictionary=eco.predators[selected_predator]
		info.text+="\nPREDATOR #%d · %s\nHunger %.0f%% · dolphin pod %s\nDestination %s" % [a.id,eco.PREDATOR_NAMES[int(a.kind)],a.hunger*100,str(a.pod),str(a.destination)]
		if fish.hunting!=null: info.text+="\n"+hunt_summary(-int(a.id))
	if fish.food_web!=null:
		info.text+="\nSchools split %d / merged %d" % [fish.food_web.split_count,fish.food_web.merge_count]
		if selected_area>=0:
			var a: Dictionary=fish.food_web.areas[selected_area];var quantity := 0.0
			for b in fish.food_web.bottom:
				if b.area==a.id: quantity+=float(b.quantity)
			info.text+="\nAREA: %s\nRoles: %s\nExtent %.0f × %.0f ft\nBottom forage %.0f / %.0f capacity\nNutrients %.0f%% · gradual recovery\nEvidence: %s\n%s" % [a.kind,", ".join(a.roles),(a.bounds[2]-a.bounds[0])/.3048,(a.bounds[3]-a.bounds[1])/.3048,quantity,a.bottom_capacity,fish.food_web.nutrients[selected_area]*100,", ".join(a.evidence),"Inferred habitat and extent" if a.inferred else "Mapped evidence; opportunity boundary inferred"]
func hunt_summary(actor: int) -> String:
	var hunt=main.fish.hunting;var s: Dictionary=hunt.state(actor);var prey: Dictionary=hunt.prey(int(s.kind),int(s.target))
	var label: String=prey.get("label","none")
	var distance := ""
	if not prey.is_empty(): distance=" · %.1f yd" % (hunt.position(actor).distance_to(prey.position)/.9144)
	var result := "Hunt: %s\n%s\nTarget: %s%s\nEnergy %.0f%% · captures %d / misses %d\n" % [hunt.LABELS[int(s.stage)],s.activity,label,distance,s.energy*100,s.captures,s.misses]
	var count := 0
	for index in range(hunt.events.size()-1,-1,-1):
		var e: Dictionary=hunt.events[index]
		if e.actor==actor: result+="%.0f s ago: %s\n" % [main.fish.elapsed-e.time,e.text];count+=1
		if count>=3: break
	return result
func observe_hunt():
	var fish=main.fish
	if fish.hunting==null: return
	var best := -INF
	for i in range(fish.ids.size()):
		if fish.ecology.alive[i]==0 or fish.hunger[i]<.3: continue
		var s: Dictionary=fish.hunting.states[i];var score: float=fish.hunger[i]
		if s.stage in [1,2,3,4,5]: score+=10
		else:
			for index in fish.ecology.forage_zones.get(int(fish.region[i]),[]):
				var a: Dictionary=fish.ecology.forage[index]
				if a.quantity>=1: score+=maxf(0,1-Vector2(fish.east[i]-a.x,fish.south[i]-a.y).length()/150.0)
		if score>best: best=score;selected=i
	if selected<0: return
	selected_forage=-1;selected_predator=-1;follow_selected=true;fish.time_scale=10;selected_zone=fish.region[selected]
	main.camera.follow=false;main.camera.anchor=null;main.camera.target_span=180;refresh()
func forage_summary(z: int) -> String:
	var eco=main.fish.ecology;var totals: Dictionary={}
	for index in eco.forage_zones.get(z,[]):
		var a: Dictionary=eco.forage[index];var label: String=eco.FORAGE_NAMES[int(a.kind)]
		totals[label]=float(totals.get(label,0))+float(a.quantity)
	var parts := PackedStringArray()
	for label in totals: parts.append("%s %.0f" % [label,totals[label]])
	return ", ".join(parts)
func school_summary(key: int) -> String:
	var parts := PackedStringArray();var eco=main.fish.ecology
	for i in eco.schools.get(key,[]):
		if eco.alive[i]==1: parts.append(str(main.fish.ids[i]))
	return ", ".join(parts)
func select_next():
	if selected_zone<0: return
	var members: Array=main.fish.buckets[selected_zone]
	if members.is_empty(): return
	selected_forage=-1;selected_predator=-1;selected=members[(members.find(selected)+1)%members.size()];refresh();queue_redraw()
func select_at(p: GeoPosition,mpp: float):
	if main.fish==null: return
	var fish: FishPopulation=main.fish;var best := pow(maxf(12*mpp,12),2);var found := -1
	if main.camera.span<7000:
		for i in range(fish.ids.size()):
			if fish.ecology!=null and fish.ecology.alive[i]==0: continue
			var d := pow(fish.east[i]-p.east,2)+pow(fish.south[i]-p.south,2)
			if d<best: best=d;found=i
	selected_feature=-1;selected_forage=-1;selected_predator=-1
	if fish.ecology!=null and main.camera.span<7000:
		for index in range(fish.ecology.forage.size()):
			var a: Dictionary=fish.ecology.forage[index];var d: float=Vector2(a.x-p.east,a.y-p.south).length_squared()
			if d<best: best=d;selected_forage=index;found=-1;selected_zone=a.zone
		for index in range(fish.ecology.predators.size()):
			var a: Dictionary=fish.ecology.predators[index]
			if not a.active: continue
			var d: float=Vector2(a.x-p.east,a.y-p.south).length_squared()
			if d<best: best=d;selected_predator=index;selected_forage=-1;found=-1;selected_zone=a.zone
	if selected_forage>=0 or selected_predator>=0: refresh();queue_redraw();return
	selected_area=-1
	if found<0 and fish.food_web!=null:
		for index in range(fish.food_web.areas.size()):
			if fish.food_web.contains(index,Vector2(p.east,p.south)):
				selected_area=index;selected_zone=int(fish.food_web.areas[index].zone);refresh();queue_redraw();return
	if found>=0: selected=found;selected_zone=fish.region[found]
	else:
		if fish.movement!=null and fish.movement.ready:
			var feature: int=fish.movement.nav.nearest(Vector2(p.east,p.south))
			if feature>=0 and fish.movement.nav.point(feature).distance_to(Vector2(p.east,p.south))<maxf(14*mpp,40):
				selected_feature=feature;selected_zone=fish.movement.nav.nodes[feature].zone;refresh();queue_redraw();return
		best=pow(maxf(20*mpp,450),2)
		for z in range(fish.zones.size()):
			var d := pow(float(fish.zones[z].x)-p.east,2)+pow(float(fish.zones[z].y)-p.south,2)
			if d<best: best=d;selected_zone=z
	refresh();queue_redraw()
func _draw():
	if not enabled or main.fish==null or counts.is_empty(): return
	drawn_origin=Vector2(main.origin.east,main.origin.south)
	var fish: FishPopulation=main.fish;var mpp: float=main.camera.span/get_viewport_rect().size.y
	var half := get_viewport_rect().size*mpp*.5
	var bounds := Rect2(main.camera.geo.east-half.x,main.camera.geo.south-half.y,half.x*2,half.y*2).grow(800)
	for z in range(fish.zones.size()):
		var zone: Dictionary=fish.zones[z];var absolute := Vector2(zone.x,zone.y)
		if not bounds.has_point(absolute): continue
		var p := absolute-Vector2(main.origin.east,main.origin.south)
		if show_grid and main.camera.span<20000:
			draw_rect(Rect2(p-Vector2.ONE*375,Vector2.ONE*750),Color(.5,.9,.8,.2),false,mpp)
			for neighbor in zone.neighbors:
				if neighbor<z: continue
				var q: Dictionary=fish.zones[neighbor]
				draw_line(p,Vector2(q.x-main.origin.east,q.y-main.origin.south),Color(.5,.9,.8,.25),mpp)
		var distribution: PackedInt32Array=species_counts[z];var dominant := 0
		for k in range(distribution.size()):
			if distribution[k]>distribution[dominant]: dominant=k
		var color: Color=COLORS[dominant]
		if mode==1: color=Color(.2,.22,.15).lerp(Color(.5,1,.25),fish.food_web.productivity(z) if fish.food_web!=null else fish.food[z])
		if mode==3 and fish.ecology!=null: color=Color(.1,.5,.4).lerp(Color(1,.1,.1),fish.ecology.pressure[z])
		if mode==2: color=Color(.8,.2,.2).lerp(Color(.2,.9,.7),fish.suitability(selected,z) if selected>=0 else .5)
		if counts[z]>0 and (main.camera.span>=7000 or mode in [1,2,3]):
			var actual_center := centroids[z]-Vector2(main.origin.east,main.origin.south)
			draw_circle(actual_center,clampf(3+sqrt(float(counts[z])),3,12)*mpp,Color(color,.65))
	if main.camera.span<7000:
		for i in range(fish.ids.size()):
			if fish.ecology!=null and fish.ecology.alive[i]==0: continue
			var absolute := Vector2(fish.east[i],fish.south[i])
			if not bounds.has_point(absolute): continue
			var p := absolute-Vector2(main.origin.east,main.origin.south)
			draw_circle(p,2.5*mpp,COLORS[fish.species[i]])
			if fish.destination[i]>=0:
				var direction: Vector2=fish.movement.headings[i] if fish.movement!=null and fish.movement.ready else Vector2.ZERO
				draw_line(p,p+direction*12*mpp,COLORS[fish.species[i]],mpp)
	if selected>=0:
		var p := Vector2(fish.east[selected]-main.origin.east,fish.south[selected]-main.origin.south)
		draw_circle(p,8*mpp,Color.WHITE,false,2*mpp)
		if fish.movement!=null and fish.movement.ready:
			if fish.hunting!=null and fish.hunting.states[selected].stage in [1,2,3,4,5]:
				var s: Dictionary=fish.hunting.states[selected];draw_route(s.path,int(s.cursor),p,Color(1,.5,.2),mpp)
			else: draw_route(fish.movement.routes[selected],fish.movement.cursors[selected],p,Color(1,1,.4,.8),mpp)
		if trail.size()>1:
			var local := PackedVector2Array()
			for at in trail: local.append(at-Vector2(main.origin.east,main.origin.south))
			draw_polyline(local,Color(.2,1,1,.7),mpp,true)

	if fish.ecology!=null: draw_ecology(fish,mpp,bounds)
	if fish.hunting!=null: draw_hunts(fish,mpp,bounds)
func draw_ecology(fish: FishPopulation,mpp: float,bounds: Rect2):
	var eco=fish.ecology;var origin := Vector2(main.origin.east,main.origin.south)
	if main.camera.span<12000:
		for index in range(eco.forage.size()):
			var a: Dictionary=eco.forage[index];var absolute := Vector2(a.x,a.y)
			if not bounds.has_point(absolute) or a.quantity<=0: continue
			var color := Color(1,.9,.4,.8)
			if a.scatter_until>fish.elapsed: color=Color(1,.5,.7)
			var radius := 4.0+sqrt(float(a.quantity))*.3
			if a.jump_until>fish.elapsed: radius+=8
			draw_circle(absolute-origin,radius*mpp,color,false,mpp)
			if index==selected_forage: draw_circle(absolute-origin,15*mpp,Color.WHITE,false,2*mpp)
			if index==selected_forage or (mode==5 and main.camera.span<3000): draw_caption(absolute-origin,"%s %.0f" % [eco.FORAGE_NAMES[int(a.kind)],a.quantity],mpp,color)
		for index in range(eco.predators.size()):
			var a: Dictionary=eco.predators[index];var absolute := Vector2(a.x,a.y)
			if not a.active or not bounds.has_point(absolute): continue
			var pos := absolute-origin;var r := 8*mpp;var color := Color(1,.25,.2) if a.kind!=3 else Color(.4,.95,1)
			draw_colored_polygon(PackedVector2Array([pos+Vector2(0,-r),pos+Vector2(r,r),pos+Vector2(-r,r)]),color)
			if index==selected_predator: draw_circle(pos,15*mpp,Color.WHITE,false,2*mpp)
		if mode in [1,4] and fish.food_web!=null:
			var web=fish.food_web
			for index in range(web.areas.size()):
				var a: Dictionary=web.areas[index];var rect := Rect2(a.bounds[0],a.bounds[1],a.bounds[2]-a.bounds[0],a.bounds[3]-a.bounds[1])
				if not bounds.intersects(rect): continue
				var color := Color(.95,.65,.25,.6) if a.inferred else Color(.3,1,.7,.7)
				if mode==1:
					if a.bottom_capacity<=0: continue
					var stock := 0.0
					for b in web.bottom:
						if b.area==a.id: stock+=b.quantity
					color=Color(1,.2,.1).lerp(Color(.3,1,.3),stock/maxf(1,a.bottom_capacity))
				if index==selected_area: color=Color.WHITE
				for polygon in a.polygons:
					for ring in [polygon.outer]+polygon.holes:
						var local := PackedVector2Array()
						for point in ring: local.append(point-origin)
						if local.size()>1: draw_polyline(local,color,mpp,true)
	if selected>=0:
		if fish.movement!=null and fish.movement.ready:
			for feature in [fish.movement.preferred_feed[selected],fish.movement.preferred_rest[selected]]:
				var pos: Vector2=fish.movement.nav.point(feature)-origin
				draw_rect(Rect2(pos-Vector2.ONE*10*mpp,Vector2.ONE*20*mpp),Color(1,.8,.2),false,2*mpp)
		if mode==5 and eco.school[selected]>=0:
			var p := Vector2(fish.east[selected],fish.south[selected])-origin
			for member in eco.schools.get(eco.school[selected],[]):
				if eco.alive[member]==0: continue
				var q := Vector2(fish.east[member],fish.south[member])-origin
				draw_line(p,q,Color(.8,.8,1,.35),mpp)

	if selected_forage>=0:
		var a: Dictionary=eco.forage[selected_forage]
		if a.has("natural_path"): draw_route(a.natural_path,int(a.path_cursor),Vector2(a.x,a.y)-origin,Color(1,.8,.3),mpp)
	if selected_predator>=0:
		var a: Dictionary=eco.predators[selected_predator]
		if a.has("natural_path"): draw_route(a.natural_path,int(a.path_cursor),Vector2(a.x,a.y)-origin,Color(1,.3,.3),mpp)
func draw_route(path: PackedVector2Array,cursor: int,start: Vector2,color: Color,mpp: float):
	if cursor>=path.size(): return
	var local := PackedVector2Array([start]);var origin := Vector2(main.origin.east,main.origin.south)
	for index in range(cursor,path.size()): local.append(path[index]-origin)
	if local.size()>1: draw_polyline(local,color,1.5*mpp,true)
	draw_circle(local[-1],6*mpp,color,false,mpp)

func draw_caption(at: Vector2,text: String,mpp: float,color: Color):
	draw_set_transform(at,0,Vector2.ONE*mpp)
	draw_string(ThemeDB.fallback_font,Vector2(10,-6),text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
	draw_set_transform(Vector2.ZERO)
func draw_hunts(fish: FishPopulation,mpp: float,bounds: Rect2):
	var hunt=fish.hunting;var origin := Vector2(main.origin.east,main.origin.south)
	var actor := selected if selected_predator<0 else -selected_predator-1
	if selected_forage<0 and (selected>=0 or selected_predator>=0):
		var s: Dictionary=hunt.state(actor);var at: Vector2=hunt.position(actor)-origin
		draw_caption(at,str(s.activity),mpp,Color(1,.85,.4))
		var prey: Dictionary=hunt.prey(int(s.kind),int(s.target))
		if not prey.is_empty():
			var target: Vector2=hunt.prey_position(actor,int(s.kind),int(s.target),prey)-origin
			draw_circle(target,5*mpp,Color(1,.2,.25),false,2*mpp);draw_line(at,target,Color(1,.25,.2,.4),mpp)
		if selected_predator>=0: draw_route(s.path,int(s.cursor),at,Color(1,.5,.1),mpp)
	for e in hunt.events:
		if fish.elapsed-e.time>30 or not bounds.has_point(e.position): continue
		if not ("strike" in e.text or "capture:" in e.text or "escape" in e.text): continue
		var color := Color(.3,1,.3) if "capture:" in e.text else (Color(.8,.8,.8) if "escape" in e.text else Color(1,.3,.15))
		draw_circle(e.position-origin,10*mpp,color,false,2*mpp)
		draw_caption(e.position-origin,e.text,mpp,color)
