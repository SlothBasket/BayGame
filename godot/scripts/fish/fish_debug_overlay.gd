class_name FishDebugOverlay
extends Node2D
var main
var selected := -1
var selected_zone := -1
var enabled := false
var timer := 0.0
var mode := 0
var drawn_origin := Vector2.ZERO
var canvas: CanvasLayer
var panel: PanelContainer
var info: Label
var legend: Label
var speed_button: Button
var counts := PackedInt32Array()
var species_counts: Array = []
const COLORS := [Color(.98,.48,.22),Color(.35,.83,.96),Color(.77,.54,.96)]
func setup(game):
	main=game;z_index=5
	canvas=CanvasLayer.new();canvas.layer=9;add_child(canvas)
	panel=PanelContainer.new();panel.position=Vector2(24,200);panel.custom_minimum_size=Vector2(460,0);canvas.add_child(panel);panel.hide()
	var style := StyleBoxFlat.new();style.bg_color=Color(.025,.05,.065,.94)
	for side in ["left","right","top","bottom"]: style.set("content_margin_"+side,12)
	panel.add_theme_stylebox_override("panel",style)
	var body := VBoxContainer.new();panel.add_child(body)
	legend=Label.new();legend.text="FISH LAB — click a zone or fish\nOrange: red drum · Cyan: trout · Purple: snook\nCircles: population · Lines: water connections";body.add_child(legend)
	var mode_button := Button.new();mode_button.text="View: density / species";body.add_child(mode_button)
	mode_button.pressed.connect(func(): mode=(mode+1)%3;mode_button.text=["View: density / species","View: food availability","View: selected fish depth suitability"][mode];queue_redraw())
	speed_button=Button.new();speed_button.text="Simulation: 1×";body.add_child(speed_button)
	speed_button.pressed.connect(func(): main.fish.time_scale=10.0 if main.fish.time_scale==1 else (60.0 if main.fish.time_scale==10 else 1.0);speed_button.text="Simulation: %d×" % main.fish.time_scale)
	var bait := Button.new();bait.text="Add food to selected zone";body.add_child(bait);bait.pressed.connect(func(): main.fish.boost_food(selected_zone);refresh())
	var nearby := Button.new();nearby.text="Select fish in zone (next)";body.add_child(nearby);nearby.pressed.connect(select_next)
	var follow := Button.new();follow.text="Center map on selected fish";body.add_child(follow)
	follow.pressed.connect(func():
		if selected<0: return
		main.camera.follow=false;main.camera.anchor=null;main.camera.geo=GeoPosition.new(main.fish.east[selected],main.fish.south[selected]);main.camera.target_span=1500)
	info=Label.new();info.add_theme_font_size_override("font_size",16);body.add_child(info)
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
	info.text="%d fish · %d zones\n%.3f ms update · %d migrations\n" % [fish.ids.size(),fish.zones.size(),fish.update_ms,fish.migrations]
	if selected_zone>=0:
		var z: Dictionary=fish.zones[selected_zone]
		info.text+="\nZone %s · %d fish\nFood %.0f%% · depth %.1f ft\nSpecies counts: %s\n" % [z.id,counts[selected_zone],fish.food[selected_zone]*100,float(z.depth_m)*3.280839895,str(species_counts[selected_zone])]
	if selected>=0:
		var d := fish.inspect_fish(selected)
		info.text+="\nFish #%d · %s · %.0f cm\nPrefers %.1f ft · Hunger %.0f%%\nE %.1f / S %.1f m\n%s → %s\n%s" % [d.id,d.species,d.size_cm,d.preferred_depth_m*3.280839895,d.hunger*100,d.east,d.south,d.zone,d.destination,d.state]
func select_next():
	if selected_zone<0: return
	var members: Array=main.fish.buckets[selected_zone]
	if members.is_empty(): return
	selected=members[(members.find(selected)+1)%members.size()];refresh();queue_redraw()
func select_at(p: GeoPosition,mpp: float):
	if main.fish==null: return
	var fish: FishPopulation=main.fish;var best := pow(maxf(12*mpp,12),2);var found := -1
	if main.camera.span<7000:
		for i in range(fish.ids.size()):
			var d := pow(fish.east[i]-p.east,2)+pow(fish.south[i]-p.south,2)
			if d<best: best=d;found=i
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
		var distribution: PackedInt32Array=species_counts[z];var dominant := distribution.find(maxi(distribution[0],maxi(distribution[1],distribution[2])));var color: Color=COLORS[dominant]
		if mode==1: color=Color(.2,.22,.15).lerp(Color(.5,1,.25),fish.food[z])
		if mode==2: color=Color(.8,.2,.2).lerp(Color(.2,.9,.7),fish.suitability(selected,z) if selected>=0 else .5)
		draw_circle(p,clampf(3+sqrt(float(counts[z])),3,12)*mpp,Color(color,.65))
		if z==selected_zone: draw_circle(p,15*mpp,Color.WHITE,false,mpp)
	if main.camera.span<7000:
		for i in range(fish.ids.size()):
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
