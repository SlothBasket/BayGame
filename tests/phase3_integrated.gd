extends SceneTree
var main
var rows: Array = []
var previous := 0
var elapsed := 0.0
var frames := 0
func _initialize(): call_deferred("start")
func start():
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);main.view_alafia();main.settings.options.soundings=true;main.settings.options.soundings_radius=3000.0;main.boat.geo=GeoPosition.new(63682,37503)
	main.camera.follow=false;previous=Time.get_ticks_usec()
func _process(dt):
	if main==null: return false
	var now := Time.get_ticks_usec();var ms := (now-previous)/1000.0;previous=now;elapsed+=dt;frames+=1
	# Continuous LOD crossings, then overview; no camera state enters fish updates.
	if elapsed<8: main.camera.target_span=exp(lerpf(log(500.0),log(16000.0),(sin(elapsed*.8)+1)*.5))
	else: main.camera.target_span=main.camera.overview_span()
	if elapsed>2: rows.append(ms)
	if elapsed>=12:
		rows.sort();var sum := 0.0
		for v in rows: sum+=v
		var result := {"frames":frames,"seconds":elapsed,"mean_ms":sum/rows.size(),"p95_ms":rows[int(rows.size()*.95)],"max_ms":rows[-1],"fish_records":main.fish.ids.size() if main.fish!=null else 0,"fish_update_ms":main.fish.update_ms if main.fish!=null else 0,"imagery_mib":main.imagery.bytes/1048576.0,"adapter":RenderingServer.get_video_adapter_name(),"viewport":str(root.size),"note":"12 second Alafia zoom-to-overview with soundings and persistent fish; first 2 seconds excluded from frame statistics"}
		var f := FileAccess.open("res://../docs/phase3-integrated.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close();print(JSON.stringify(result));quit()
	return false
