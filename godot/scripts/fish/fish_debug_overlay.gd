class_name FishDebugOverlay
extends Node2D
var main
var selected := -1
var selected_zone := -1
var enabled := false
var timer := 0.0
var mode := 0
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
	var nearby := Button.new();nearby.text="Select fish in zone (next)";body.add_child(nearby);nearby.pressed.connect(select_next)
	var follow := Button.new();follow.text="Center map on selected fish";body.add_child(follow)
	follow.pressed.connect(func():
		if selected<0: return
		main.camera.follow=false;main.camera.anchor=null;main.camera.geo=GeoPosition.new(main.fish.east[selected],main.fish.south[selected]);main.camera.target_span=1500)
	tide_button=Button.new();body.add_child(tide_button)
	tide_button.pressed.connect(func():
		var eco=main.fish.ecology
		if eco==null: return
		eco.tide_level_m+=.5
		if eco.tide_level_m>1.5: eco.tide_level_m=-1
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
	var find_id := LineEdit.new();find_id.placeholder_text="Find persistent game fish ID, then Enter";body.add_child(find_id)
	find_id.text_submitted.connect(func(value: String):
		var index: int=main.fish.ids.find(value.to_int())
		if index>=0: selected=index;selected_zone=main.fish.region[index];selected_forage=-1;selected_predator=-1;refresh())
	info=Label.new();info.custom_minimum_size.x=480;info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;info.add_theme_font_size_override("font_size",16);body.add_child(info)
func toggle():
	enabled=not enabled;panel.visible=enabled;refresh();queue_redraw()
func tick(dt: float):
	if not enabled or main.fish==null: return
	var current_origin := Vector2(main.origin.east,main.origin.south)
	if current_origin!=drawn_origin: queue_redraw()
	timer+=dt
	if timer>=.2: timer=0;refresh();queue_redraw()
func refresh():
	if main.fish==null or main.fish.zones.is_empty(): return
	var fish: FishPopulation=main.fish
	speed_button.text="Simulation: %d×" % fish.time_scale
	counts=fish.zone_counts;species_counts=fish.zone_species_counts
	var eco=fish.ecology
	if eco!=null:
		tide_button.text="Ecology tide: %+.1f m (click to cycle)" % eco.tide_level_m
		predator_button.text="Predators: %.1f per 100 game fish" % (eco.predator_ratio*100)
	info.text="%d fish · %d zones\n%.3f ms update · %d migrations\n" % [fish.ids.size(),fish.zones.size(),fish.update_ms,fish.migrations]
	if eco!=null:
		var living := 0
		for count in counts: living+=count
		info.text+="Alive %d · forage pods %d\nMeals: %.1f forage / %d game fish\nPredator meals %d · returns %d · jumps %d\n" % [living,eco.forage.size(),eco.forage_consumed,eco.game_fish_consumed,eco.predator_meals,eco.returns,eco.jumps]
	if selected_zone>=0:
		var z: Dictionary=fish.zones[selected_zone]
		info.text+="\nZone %s · %d fish\nFood %.0f%% · depth %.1f ft\nSpecies counts: %s\n" % [z.id,counts[selected_zone],fish.food[selected_zone]*100,float(z.depth_m)*3.280839895,str(species_counts[selected_zone])]
		if eco!=null:
			info.text+="Pressure %.0f%% · %s\nHabitat candidates: %s\n" % [eco.pressure[selected_zone]*100,forage_summary(selected_zone),", ".join(eco.habitats[selected_zone].tags)]
	if selected>=0:
		var d := fish.inspect_fish(selected)
		info.text+="\nFish #%d · %s · %.0f cm\nPrefers %.1f ft · Hunger %.0f%%\nE %.1f / S %.1f m\n%s → %s\n%s" % [d.id,d.species,d.size_cm,d.preferred_depth_m*3.280839895,d.hunger*100,d.east,d.south,d.zone,d.destination,d.state]
		if eco!=null:
			info.text+="\n"+eco.describe(selected)
			if eco.school[selected]>=0: info.text+="\nSchool member IDs: "+school_summary(eco.school[selected])
	if eco!=null and selected_forage>=0:
		var a: Dictionary=eco.forage[selected_forage]
		info.text+="\nPREY #%d · %s · %.1f remaining\nSize %.1f cm · zone %s\n%s" % [a.id,eco.FORAGE_NAMES[int(a.kind)],a.quantity,a.size_cm,fish.zones[int(a.zone)].id,"scattering" if a.scatter_until>fish.elapsed else ("jumping" if a.jump_until>fish.elapsed else "foraging / moving")]
	if eco!=null and selected_predator>=0:
		var a: Dictionary=eco.predators[selected_predator]
		info.text+="\nPREDATOR #%d · %s\nHunger %.0f%% · dolphin pod %s\nDestination %s" % [a.id,eco.PREDATOR_NAMES[int(a.kind)],a.hunger*100,str(a.pod),str(a.destination)]
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
	selected_forage=-1;selected_predator=-1
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
	if found>=0: selected=found;selected_zone=fish.region[found]
	else:
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
		if main.camera.span<20000:
			for neighbor in zone.neighbors:
				if neighbor<z: continue
				var q: Dictionary=fish.zones[neighbor]
				draw_line(p,Vector2(q.x-main.origin.east,q.y-main.origin.south),Color(.5,.9,.8,.25),mpp)
		var distribution: PackedInt32Array=species_counts[z];var dominant := 0
		for k in range(distribution.size()):
			if distribution[k]>distribution[dominant]: dominant=k
		var color: Color=COLORS[dominant]
		if mode==1: color=Color(.2,.22,.15).lerp(Color(.5,1,.25),fish.food[z])
		if mode==3 and fish.ecology!=null: color=Color(.1,.5,.4).lerp(Color(1,.1,.1),fish.ecology.pressure[z])
		if mode==2: color=Color(.8,.2,.2).lerp(Color(.2,.9,.7),fish.suitability(selected,z) if selected>=0 else .5)
		draw_circle(p,clampf(3+sqrt(float(counts[z])),3,12)*mpp,Color(color,.65))
		if z==selected_zone: draw_circle(p,15*mpp,Color.WHITE,false,mpp)
	if main.camera.span<7000:
		for i in range(fish.ids.size()):
			if fish.ecology!=null and fish.ecology.alive[i]==0: continue
			var absolute := Vector2(fish.east[i],fish.south[i])
			if not bounds.has_point(absolute): continue
			var p := absolute-Vector2(main.origin.east,main.origin.south)
			draw_circle(p,2.5*mpp,COLORS[fish.species[i]])
			if fish.destination[i]>=0:
				var z: Dictionary=fish.zones[fish.destination[i]];var direction := Vector2(z.x-fish.east[i],z.y-fish.south[i]).normalized()
				draw_line(p,p+direction*12*mpp,COLORS[fish.species[i]],mpp)
	if selected>=0:
		var p := Vector2(fish.east[selected]-main.origin.east,fish.south[selected]-main.origin.south)
		draw_circle(p,8*mpp,Color.WHITE,false,2*mpp)
		if fish.destination[selected]>=0:
			var z: Dictionary=fish.zones[fish.destination[selected]]
			draw_line(p,Vector2(z.x-main.origin.east,z.y-main.origin.south),Color(1,1,.4,.8),2*mpp)

	if fish.ecology!=null: draw_ecology(fish,mpp,bounds)
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
		for index in range(eco.predators.size()):
			var a: Dictionary=eco.predators[index];var absolute := Vector2(a.x,a.y)
			if not a.active or not bounds.has_point(absolute): continue
			var pos := absolute-origin;var r := 8*mpp;var color := Color(1,.25,.2) if a.kind!=3 else Color(.4,.95,1)
			draw_colored_polygon(PackedVector2Array([pos+Vector2(0,-r),pos+Vector2(r,r),pos+Vector2(-r,r)]),color)
			if index==selected_predator: draw_circle(pos,15*mpp,Color.WHITE,false,2*mpp)
		if selected_zone>=0 and mode==4:
			var z: Dictionary=fish.zones[selected_zone]
			for spot in eco.habitats[selected_zone].spots:
				var pos := Vector2(spot.x,spot.y)-origin
				draw_circle(pos,8*mpp,Color(.5,1,.4),false,mpp)
				draw_line(Vector2(z.x,z.y)-origin,pos,Color(.5,1,.4,.4),mpp)
	if selected>=0:
		for z in [eco.home[selected],eco.feeding[selected],eco.resting[selected]]:
			var zone: Dictionary=fish.zones[z];var pos := Vector2(zone.x,zone.y)-origin
			draw_rect(Rect2(pos-Vector2.ONE*14*mpp,Vector2.ONE*28*mpp),Color(1,.8,.2),false,2*mpp)
		if mode==5 and eco.school[selected]>=0:
			var p := Vector2(fish.east[selected],fish.south[selected])-origin
			for member in eco.schools.get(eco.school[selected],[]):
				if eco.alive[member]==0: continue
				var q := Vector2(fish.east[member],fish.south[member])-origin
				draw_line(p,q,Color(.8,.8,1,.35),mpp)
