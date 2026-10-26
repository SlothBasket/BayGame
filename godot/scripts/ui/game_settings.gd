class_name GameSettings
extends RefCounted
const PATH = "user://settings.json"
var options := {"speed_unit":0,"visual_mode":0,"visual_revision":3,"aerial_opacity":0.85,"depth_opacity":0.55,"soundings_radius":3000.0,"soundings":false,"contours":false,"deadzone":0.2,"developer":false,"permissive_navigation":false}
var actions := {
"throttle_up":["Boat","Increase throttle"],"throttle_down":["Boat","Decrease throttle"],"steer_left":["Boat","Steer left"],"steer_right":["Boat","Steer right"],"neutral":["Boat","Neutral throttle"],
"zoom_in":["Camera","Zoom in"],"zoom_out":["Camera","Zoom out"],"pan_map":["Camera","Drag map"],"map_left":["Camera","Map / reticle left"],"map_right":["Camera","Map / reticle right"],"map_up":["Camera","Map / reticle up"],"map_down":["Camera","Map / reticle down"],"follow":["Camera","Toggle follow"],"recenter":["Camera","Recenter boat"],"overview":["Camera","World overview"],
"teleport_boat_to_cursor":["Navigation","Teleport to cursor / reticle"],"target_mode":["Navigation","Controller targeting mode"],"chart":["Navigation","Toggle chart"],"visual_mode":["Navigation","Switch visual mode"],
"local_soundings":["Navigation","Toggle local depth soundings"],"menu":["Interface","Open / close menu"],"ui_accept":["Interface","Confirm"],"ui_cancel":["Interface","Back / cancel"],
"debug_overlay":["Developer","Developer overlay"],"chunk_grid":["Developer","Chunk grid"],"benchmark":["Developer","Run benchmark"]}
func _init(load_saved := true):
	defaults()
	if load_saved: restore()
func bind(action: String, kind: String, code: int, value := 1.0):
	InputMap.action_add_event(action,decode({"kind":kind,"code":code,"value":value}))
func defaults():
	for a in actions:
		if not InputMap.has_action(a): InputMap.add_action(a,0.2)
		InputMap.action_erase_events(a)
	var keys := {"local_soundings":KEY_L,"throttle_up":KEY_W,"throttle_down":KEY_S,"steer_left":KEY_A,"steer_right":KEY_D,"neutral":KEY_SPACE,"follow":KEY_F,"recenter":KEY_HOME,"overview":KEY_O,"teleport_boat_to_cursor":KEY_T,"target_mode":KEY_R,"chart":KEY_TAB,"visual_mode":KEY_V,"menu":KEY_ESCAPE,"ui_accept":KEY_ENTER,"ui_cancel":KEY_BACKSPACE,"debug_overlay":KEY_F3,"chunk_grid":KEY_C,"benchmark":KEY_B}
	for a in keys: bind(a,"key",keys[a])
	bind("zoom_in","mouse",MOUSE_BUTTON_WHEEL_UP);bind("zoom_out","mouse",MOUSE_BUTTON_WHEEL_DOWN)
	bind("pan_map","mouse",MOUSE_BUTTON_RIGHT);bind("pan_map","mouse",MOUSE_BUTTON_MIDDLE)
	for entry in [["steer_left",JOY_AXIS_LEFT_X,-1],["steer_right",JOY_AXIS_LEFT_X,1],["throttle_up",JOY_AXIS_TRIGGER_RIGHT,1],["throttle_down",JOY_AXIS_TRIGGER_LEFT,1],["map_left",JOY_AXIS_RIGHT_X,-1],["map_right",JOY_AXIS_RIGHT_X,1],["map_up",JOY_AXIS_RIGHT_Y,-1],["map_down",JOY_AXIS_RIGHT_Y,1]]: bind(entry[0],"axis",entry[1],entry[2])
	for entry in [["local_soundings",JOY_BUTTON_BACK],["menu",JOY_BUTTON_START],["teleport_boat_to_cursor",JOY_BUTTON_A],["target_mode",JOY_BUTTON_Y],["neutral",JOY_BUTTON_B],["follow",JOY_BUTTON_X],["zoom_in",JOY_BUTTON_DPAD_UP],["zoom_out",JOY_BUTTON_DPAD_DOWN],["recenter",JOY_BUTTON_LEFT_SHOULDER],["overview",JOY_BUTTON_RIGHT_SHOULDER]]: bind(entry[0],"button",entry[1])
	# UI accept/cancel share face buttons only in menus; context prevents gameplay conflicts.
	bind("ui_accept","button",JOY_BUTTON_A);bind("ui_cancel","button",JOY_BUTTON_B)
func encode(e: InputEvent) -> Dictionary:
	if e is InputEventKey: return {"kind":"key","code":e.physical_keycode if e.physical_keycode else e.keycode,"ctrl":e.ctrl_pressed,"alt":e.alt_pressed,"shift":e.shift_pressed,"meta":e.meta_pressed}
	if e is InputEventMouseButton: return {"kind":"mouse","code":e.button_index}
	if e is InputEventJoypadButton: return {"kind":"button","code":e.button_index}
	if e is InputEventJoypadMotion: return {"kind":"axis","code":e.axis,"value":signf(e.axis_value)}
	return {}
func decode(d: Dictionary) -> InputEvent:
	var e: InputEvent
	match d.get("kind",""):
		"key":
			e=InputEventKey.new();e.physical_keycode=int(d.code);e.ctrl_pressed=d.get("ctrl",false);e.alt_pressed=d.get("alt",false);e.shift_pressed=d.get("shift",false);e.meta_pressed=d.get("meta",false)
		"mouse": e=InputEventMouseButton.new();e.button_index=int(d.code)
		"button": e=InputEventJoypadButton.new();e.button_index=int(d.code);e.device=-1
		"axis": e=InputEventJoypadMotion.new();e.axis=int(d.code);e.axis_value=float(d.value);e.device=-1
	return e
func conflicts(action: String,e: InputEvent) -> Array:
	var out := []
	for a in actions:
		if a==action: continue
		for old in InputMap.action_get_events(a):
			if encode(old)==encode(e): out.append(a);break
	return out
func save(path := PATH) -> Error:
	var bindings := {}
	for a in actions:
		bindings[a]=[]
		for e in InputMap.action_get_events(a): bindings[a].append(encode(e))
	var f := FileAccess.open(path,FileAccess.WRITE)
	if f==null: return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version":1,"options":options,"bindings":bindings},"\t"));return OK
func restore(path := PATH):
	if not FileAccess.file_exists(path): return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or d.get("version",0)!=1: return
	options.merge(d.get("options",{}),true)
	if int(d.get("options",{}).get("visual_revision",0))<3:
		options.visual_mode=0;options.visual_revision=3
	if not options.developer and int(options.visual_mode)==2: options.visual_mode=0
	for a in d.get("bindings",{}):
		if not actions.has(a): continue
		InputMap.action_erase_events(a)
		for record in d.bindings[a]:
			var e := decode(record)
			if e!=null: InputMap.action_add_event(a,e)
	apply_deadzone()
func apply_deadzone():
	options.deadzone=clampf(float(options.deadzone),0.05,0.65)
	for a in actions: InputMap.action_set_deadzone(a,options.deadzone)
func describe(action: String) -> String:
	var names := PackedStringArray()
	for e in InputMap.action_get_events(action): names.append(e.as_text())
	return "Unbound" if names.is_empty() else " / ".join(names)
