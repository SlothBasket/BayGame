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
	throttle = clampf(throttle+dt*settings.get("throttle_response",0.65)*(Input.get_action_strength("throttle_up")-Input.get_action_strength("throttle_down")),-1,1)
	if Input.is_action_pressed("neutral"): throttle=0
	var steer := Input.get_axis("steer_left","steer_right")
	var thrust: float = throttle*settings.acceleration*(settings.reverse_factor if throttle<0 else 1.0)
	speed += (thrust-settings.linear_drag*speed-settings.quadratic_drag*speed*absf(speed))*dt
	speed=clampf(speed,-settings.get("max_reverse_mps",5.0),settings.get("max_forward_mps",22.352))
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

func mph() -> float: return absf(speed)*2.236936292
