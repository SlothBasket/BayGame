extends SceneTree
class OpenWater extends DepthService:
	func _init(): pass
	func navigable(_p: GeoPosition,_radius:=2.8) -> bool: return true
var failures:=0
func check(ok: bool,message: String):
	if not ok: failures+=1;push_error(message)
func _initialize():
	var settings := GameSettings.new(false)
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://assets/generated/boat.json'))
	var water:=OpenWater.new()
	Input.action_press('steer_right')
	var slow:=BoatModel.new(config);slow.throttle=.15
	for i in range(120): slow.step(1.0/60,water)
	check(slow.heading>.8 and slow.geo.relative_to(GeoPosition.new()).length()<2,'near-pivot low-throttle turn')
	var fast:=BoatModel.new(config);fast.throttle=1;fast.speed=22.352
	for i in range(120): fast.step(1.0/60,water)
	check(fast.yaw<slow.yaw and fast.speed<=22.352,'fast turns widen and speed remains capped')
	var reverse:=BoatModel.new(config);reverse.throttle=-.2
	for i in range(120): reverse.step(1.0/60,water)
	check(reverse.heading<-.8,'reverse steering authority')
	Input.action_release('steer_right')
	var before:=slow.yaw;slow.step(1.0/60,water)
	check(slow.yaw>0 and slow.yaw<before,'yaw decays smoothly')
	check(not settings.options.soundings and settings.options.visual_mode==0,'clean stylized defaults')
	print('STEERING/VISUAL DEFAULTS: 5 checks, ',failures,' failures');quit(failures)
