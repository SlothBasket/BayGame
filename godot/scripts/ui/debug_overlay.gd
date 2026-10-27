class_name DebugOverlay
extends CanvasLayer
var label: Label
var times: Array[float] = []
var elapsed := 0.0
var average := 0.0
var p95 := 0.0
func _init():
	var panel := PanelContainer.new();panel.position=Vector2(18,120)
	var style := StyleBoxFlat.new();style.bg_color=Color(0.025,0.055,0.07,0.9)
	style.content_margin_left=16;style.content_margin_right=16;style.content_margin_top=12;style.content_margin_bottom=12
	panel.add_theme_stylebox_override("panel",style);add_child(panel)
	label=Label.new();label.add_theme_font_size_override("font_size",16);panel.add_child(label)
func tick(dt: float,main):
	times.append(dt*1000)
	if times.size()>300: times.pop_front()
	elapsed+=dt
	if elapsed<0.25: return
	elapsed=0;average=0
	for v in times: average+=v
	average/=times.size()
	var sorted := times.duplicate();sorted.sort();p95=sorted[mini(sorted.size()-1,floori(sorted.size()*0.95))]
	var m: Dictionary = main.store.manifest
	var d: Dictionary = main.depth.get_depth_metadata(main.boat.geo)
	var reading: String = "Unknown ("+d.reason+")"
	if d.available: reading="%.2f ft below NAVD88 zero" % (d.depth*3.280839895)
	label.text="TAMPA BAY  /  GEOGRAPHIC PROTOTYPE\n%s\n\n%.1f FPS  |  mean %.2f ms  |  p95 %.2f ms\nSpan %.1f yd  |  %s\nBoat E %.3f  S %.3f mi\nCamera E %.3f  S %.3f mi\n%.1f MPH  |  throttle %.0f%%  |  %s\nDepth: %s\n%s  |  %s\nVisible %d  |  cached %d  |  queued %d\nLOD %d: %d regions (requested %d)\nEstimated geography %.1f MiB\nRead %.2f ms  |  render work %.2f ms\nCache hits %d / misses %d\n\nW/S throttle  A/D steer  Space neutral\nWheel zoom  Right/middle drag pan\nF follow/free  Home boat  O overview\nTab chart  C chunk grid  B benchmark\n1–7 landmark views (see README)\nChart depth is datum-relative; no tides.\n%s" % ["SYNTHETIC FIXTURE" if m.synthetic else m.shoreline,Engine.get_frames_per_second(),average,p95,main.camera.span/0.9144,"FOLLOW" if main.camera.follow else "FREE",main.boat.geo.east/1609.344,main.boat.geo.south/1609.344,main.camera.geo.east/1609.344,main.camera.geo.south/1609.344,absf(main.boat.speed)*2.236936292,main.boat.throttle*100,"BLOCKED: land / unknown / loading" if main.boat.blocked else "navigation ready",reading,d.source,d.quality,main.renderer.visible_count,main.store.cache.size(),main.store.pending.size(),main.renderer.active_lod,main.renderer.visible_count,main.renderer.requested_lod,(main.store.bytes_loaded+main.renderer.visual_bytes)/1048576.0,main.store.load_ms,main.renderer.render_build_ms,main.store.hits,main.store.misses,main.store.last_error]


	label.text+="\nClassification: "+str(d.get("classification","unavailable"))
	label.text+="\nNavigation: "+main.depth.navigation_reason

	label.text+="\nImagery: %d cached / %.1f MiB / %.2f ms upload / %s" % [main.imagery.cache.size(),main.imagery.bytes/1048576.0,main.imagery.upload_ms,main.imagery.last_error]

	if main.fish!=null: label.text+="\nFish: %d records / %.2f MiB packed / %.3f ms update" % [main.fish.ids.size(),main.fish.packed_bytes()/1048576.0,main.fish.update_ms]
