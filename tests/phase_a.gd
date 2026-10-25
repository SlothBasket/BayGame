extends SceneTree
var failures := 0
var checks := 0
class OpenWater extends DepthService:
	func _init(): pass
	func navigable(_p: GeoPosition,_radius := 2.8) -> bool: return true
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1;push_error(label)
func _initialize(): call_deferred("run")
func run():
	var settings := GameSettings.new(false)
	var file := "res://../tests/settings-test.json"
	settings.bind("neutral","key",KEY_N)
	settings.bind("steer_left","axis",JOY_AXIS_LEFT_Y,-1)
	check(settings.save(file)==OK,"save remappings")
	settings.defaults();settings.restore(file)
	check(settings.describe("neutral").contains("N"),"keyboard persistence")
	var axis := settings.decode({"kind":"axis","code":JOY_AXIS_LEFT_Y,"value":-1})
	check(InputMap.action_has_event("steer_left",axis),"negative axis persistence")
	axis.axis_value=1
	check(not InputMap.action_has_event("steer_left",axis),"axis sign distinction")
	check(settings.conflicts("neutral",settings.decode({"kind":"key","code":KEY_W})).has("throttle_up"),"conflict detection")
	var motion := InputEventJoypadMotion.new();motion.device=0;motion.axis=JOY_AXIS_LEFT_X;motion.axis_value=-.8
	Input.parse_input_event(motion.duplicate());Input.flush_buffered_events()
	check(Input.get_action_strength("steer_left")>.5 and Input.get_action_strength("steer_right")==0,"simulated controller steering direction")
	motion.axis_value=0;Input.parse_input_event(motion.duplicate());Input.flush_buffered_events()
	motion.axis=JOY_AXIS_TRIGGER_RIGHT;motion.axis_value=.7;Input.parse_input_event(motion.duplicate());Input.flush_buffered_events()
	check(Input.get_action_strength("throttle_up")>0 and Input.get_action_strength("throttle_up")<1,"proportional simulated trigger")
	motion.axis_value=0;Input.parse_input_event(motion.duplicate());Input.flush_buffered_events()
	DirAccess.remove_absolute(file)
	var boat := BoatModel.new(JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/boat.json")))
	var water := OpenWater.new();boat.throttle=1
	for i in range(60*120): boat.step(1.0/60,water)
	check(absf(boat.mph()-50)<.2,"full throttle reaches 50 MPH")
	boat.throttle=0;var initial := boat.speed;boat.step(1.0/60,water)
	check(boat.speed>0 and boat.speed<initial,"neutral retains momentum")
	boat.speed=0;boat.throttle=-1
	for i in range(60*60): boat.step(1.0/60,water)
	check(boat.speed>=-5 and boat.speed< -4,"reverse cap")
	var game = load("res://scenes/main.tscn").instantiate();root.add_child(game)
	for i in range(60): await process_frame
	# Preload spawn collision leaves deterministically.
	for y in range(-1,2):
		for x in range(-1,2): game.store.request(GeoPosition.new(game.boat.geo.east+x*1024,game.boat.geo.south+y*1024).key(0,1024))
	for i in range(100): await process_frame
	var original: GeoPosition = game.boat.geo.copy();game.boat.speed=15;game.boat.yaw=.2;game.boat.throttle=1
	var zoom: float=game.camera.target_span
	check(game.teleport_to(original),"valid teleport")
	check(game.boat.speed==0 and game.boat.yaw==0 and game.boat.throttle==0,"teleport resets velocity")
	check(game.camera.target_span==zoom,"teleport preserves zoom")
	check(not game.teleport_to(GeoPosition.new(-100000,-100000)),"invalid teleport rejected")
	check(game.boat.geo.east==original.east,"invalid teleport does not move boat")
	check(not game.overlay.visible,"debug defaults hidden")
	game.hud.toggle();game.hud.controls();game.hud.video();game.hud.gameplay();game.hud.developer();game.hud.toggle()
	game.queue_free();await process_frame
	print("PHASE A: ",checks," checks, ",failures," failures")
	quit(failures)
