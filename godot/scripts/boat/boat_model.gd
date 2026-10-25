class_name BoatModel
extends RefCounted
var geo := GeoPosition.new()
var heading := 0.0
var speed := 0.0
var throttle := 0.0
var yaw := 0.0
var blocked := false
var settings: Dictionary
func _init(config: Dictionary): settings=config
func step(dt: float, depth: DepthService):
	if Input.is_physical_key_pressed(KEY_W): throttle = minf(1,throttle+dt*0.65)
	if Input.is_physical_key_pressed(KEY_S): throttle = maxf(-1,throttle-dt*0.65)
	if Input.is_physical_key_pressed(KEY_SPACE): throttle=0
	var steer := float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
	var thrust: float = throttle*settings.acceleration*(settings.reverse_factor if throttle<0 else 1.0)
	speed += (thrust-settings.linear_drag*speed-settings.quadratic_drag*speed*absf(speed))*dt
	var target: float = steer*settings.max_yaw_rate*(speed/(absf(speed)+3.0))
	yaw = lerpf(yaw,target,1.0-exp(-settings.yaw_response*dt))
	heading += yaw*dt
	var distance := speed*dt
	var steps := maxi(1,ceili(absf(distance)/settings.collision_step_m))
	blocked=false
	for i in range(steps):
		var next := GeoPosition.new(geo.east+sin(heading)*distance/steps,geo.south-cos(heading)*distance/steps)
		if not depth.navigable(next,settings.length_m*0.5+0.2):
			speed=0;blocked=true;break
		geo=next
func knots() -> float: return speed*1.94384449
