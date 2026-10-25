class_name GameHud
extends CanvasLayer
var main
var settings: GameSettings
var readout: Label
var notice: Label
var menu: PanelContainer
var body: VBoxContainer
var capture := ""
var pending: InputEvent
var clashes: Array = []
var message_time := 0.0
var target_reticle: Label
func setup(game, config: GameSettings):
	main=game;settings=config;layer=10
	var panel := PanelContainer.new();panel.position=Vector2(24,20);add_child(panel)
	var style := StyleBoxFlat.new();style.bg_color=Color(.025,.055,.07,.88)
	style.content_margin_left=14;style.content_margin_right=14;style.content_margin_top=8;style.content_margin_bottom=8;panel.add_theme_stylebox_override("panel",style)
	var hud := HBoxContainer.new();panel.add_child(hud)
	readout=Label.new();readout.custom_minimum_size=Vector2(440,64);readout.add_theme_font_size_override("font_size",24);hud.add_child(readout)
	var button := Button.new();button.text="Settings";button.pressed.connect(toggle);hud.add_child(button)
	notice=Label.new();notice.position=Vector2(24,94);notice.add_theme_font_size_override("font_size",18);add_child(notice)
	target_reticle=Label.new();target_reticle.text="+";target_reticle.add_theme_font_size_override("font_size",32);target_reticle.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(target_reticle)
	menu=PanelContainer.new();menu.position=Vector2(240,120);menu.size=Vector2(1440,820);add_child(menu);menu.hide()
	var margin := MarginContainer.new();for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	menu.add_child(margin)
	var scroll := ScrollContainer.new();margin.add_child(scroll)
	body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
func tell(message: String): notice.text=message;message_time=5
func persist():
	if settings.save()!=OK: tell("Settings could not be saved.")
func tick(dt: float):
	var d: Dictionary = main.depth.get_depth_metadata(main.boat.geo)
	var units := ["MPH","kn","km/h"]
	var factors := [2.236936292,1.94384449,3.6]
	var unit := clampi(int(settings.options.speed_unit),0,2)
	readout.text="%.1f %s   |   %s\nThrottle %d%%" % [absf(main.boat.speed)*factors[unit],units[unit],("Depth: %.1f ft · NAVD88" % (d.depth*3.280839895)) if d.available else "Depth: Unknown",roundi(main.boat.throttle*100)]
	message_time-=dt
	if message_time<=0: notice.text=""
	target_reticle.visible=main.camera.targeting and not menu.visible
	target_reticle.position=main.camera.reticle-Vector2(10,20)
func toggle():
	menu.visible=not menu.visible;main.camera.drag=false;capture=""
	if menu.visible: home()
func clear():
	for child in body.get_children(): body.remove_child(child);child.queue_free()
func title(text: String):
	var l := Label.new();l.text=text;l.add_theme_font_size_override("font_size",24);body.add_child(l)
func button(text: String,fn: Callable):
	var b := Button.new();b.text=text;b.alignment=HORIZONTAL_ALIGNMENT_LEFT;b.pressed.connect(fn);body.add_child(b);return b
func home():
	clear();title("Tampa Bay — paused")
	button("Resume",toggle).grab_focus()
	button("Controls",controls)
	button("Video / Display",video)
	button("Gameplay",gameplay)
	button("Developer",developer)
func back(): button("Back",home)
func video():
	clear();title("Video / Display")
	var modes := OptionButton.new()
	for name in ["Stylized","Chart"]: modes.add_item(name)
	modes.select(int(settings.options.visual_mode) if int(settings.options.visual_mode)<2 else -1);body.add_child(modes)
	if int(settings.options.visual_mode)==2: modes.text="Reference (developer)"
	modes.item_selected.connect(func(i): settings.options.visual_mode=i;main.apply_visual_mode();persist())
	button("Toggle fullscreen",func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN))
	back()
func gameplay():
	clear();title("Gameplay")
	var unit := OptionButton.new()
	for name in ["MPH","Knots","km/h"]: unit.add_item(name)
	unit.select(int(settings.options.speed_unit));body.add_child(unit)
	unit.item_selected.connect(func(i): settings.options.speed_unit=i;persist())
	title("Depths: feet below NAVD88 zero; no tide correction.\nChart contours: 5 ft. Unknown depths remain unknown.")
	button("View lower Alafia",func(): main.view_alafia();toggle())
	button("Local soundings: "+str(settings.options.soundings),func(): settings.options.soundings=not settings.options.soundings;persist();gameplay())
	button("Allow mapped water with unknown depth: "+str(settings.options.permissive_navigation),func(): settings.options.permissive_navigation=not settings.options.permissive_navigation;main.apply_visual_mode();persist();gameplay())
	back()
func developer():
	clear();title("Developer")
	button("Enable developer controls: "+str(settings.options.developer),func(): settings.options.developer=not settings.options.developer;main.apply_visual_mode();persist();developer())
	button("Show / hide diagnostic overlay",func(): main.overlay.visible=not main.overlay.visible)
	if settings.options.developer:
		button("Reference overlay (faded aerial imagery)",func(): settings.options.visual_mode=2;main.apply_visual_mode();persist();toggle())
		button("Run 56-second benchmark",func(): main.bench=true;main.bench_time=0;main.bench_rows.clear();toggle())
	back()
func controls():
	set_process_input(true);clear();capture="";title("Controls — select Add, then press an input")
	var deadzone := HSlider.new();deadzone.min_value=.05;deadzone.max_value=.65;deadzone.step=.05;deadzone.value=settings.options.deadzone;deadzone.custom_minimum_size=Vector2(300,30)
	title("Controller deadzone: %.2f" % settings.options.deadzone);body.add_child(deadzone)
	deadzone.drag_ended.connect(func(_changed): settings.options.deadzone=deadzone.value;settings.apply_deadzone();persist();controls())
	var group := ""
	for action in settings.actions:
		if group!=settings.actions[action][0]: group=settings.actions[action][0];title(group)
		var row := HBoxContainer.new();body.add_child(row)
		var l := Label.new();l.text=settings.actions[action][1]+"\n"+settings.describe(action);l.custom_minimum_size.x=980;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.add_child(l)
		var add := Button.new();add.text="Add";row.add_child(add);add.pressed.connect(begin_capture.bind(action))
		var remove := Button.new();remove.text="Clear";row.add_child(remove);remove.pressed.connect(func(): InputMap.action_erase_events(action);persist();controls())
	button("Restore default bindings",func(): settings.defaults();settings.apply_deadzone();persist();controls())
	back()
func begin_capture(action: String):
	clear();capture=action;title(settings.actions[action][1]);title("Press a key, mouse button, or controller input...\nMove an axis beyond 65%. Back/cancel cancels capture.")
	button("Cancel capture",controls)
func _input(e: InputEvent):
	if not menu.visible: return
	if capture.is_empty():
		if e.is_action_pressed("menu",false,true) or e.is_action_pressed("ui_cancel",false,true): toggle();get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("ui_cancel",false,true): controls();get_viewport().set_input_as_handled();return
	# Keep the visible cancel button operable rather than binding its click.
	if e is InputEventMouseButton and e.pressed and get_viewport().gui_get_hovered_control() is Button: return
	var valid: bool = (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventMouseButton and e.pressed) or (e is InputEventJoypadButton and e.pressed) or (e is InputEventJoypadMotion and absf(e.axis_value)>=.65)
	if not valid: return
	get_viewport().set_input_as_handled()
	pending=settings.decode(settings.encode(e));clashes=settings.conflicts(capture,pending)
	if clashes.is_empty(): commit_binding();return
	clear();title("Input already assigned to: "+", ".join(clashes))
	title("Replace removes this input from those actions. Other bindings remain.")
	button("Replace conflicting input",commit_binding).grab_focus()
	if clashes.size()==1 and not InputMap.action_get_events(capture).is_empty():
		button("Swap with first binding of this action",swap_binding)
	button("Cancel",controls)
	# Ignore further capture events while conflict choices are visible.
	set_process_input(false)
func commit_binding():
	for a in clashes:
		for old in InputMap.action_get_events(a):
			if settings.encode(old)==settings.encode(pending): InputMap.action_erase_event(a,old)
	InputMap.action_add_event(capture,pending);set_process_input(true);persist();controls()

func swap_binding():
	var old: InputEvent=InputMap.action_get_events(capture)[0]
	var destination: String=clashes[0]
	InputMap.action_erase_event(capture,old)
	commit_binding()
	InputMap.action_add_event(destination,old);persist();controls()
