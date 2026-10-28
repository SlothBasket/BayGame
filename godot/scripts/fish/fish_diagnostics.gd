extends RefCounted
# Fixed-size per-frame rings; no per-animal samples or log output. Nested timers overlap.
const WINDOW := 180
const TIERS := ["Detailed","Intermediate","Background"]
const THRESHOLDS := [50,100,250,500]
var samples: Dictionary = {}
var current: Dictionary = {}
var peaks: Dictionary = {}
var calls: Dictionary = {}
var cursor := 0
var frames := 0
var spikes := PackedInt64Array([0,0,0,0])
var ecology_disabled := false
var hunting_disabled := false
var publishing_disabled := false
var last_frame := 0
var real_seconds := 0.0
var last_completed := 0.0
var achieved := 0.0
var rate_at := 0.0
var rate_completed := 0.0
var step_started := 0
var step_cpu := 0.0
func add(key: String,usec: float):
	if not samples.has(key):
		var ring := PackedFloat64Array();ring.resize(WINDOW);ring.fill(0);samples[key]=ring;current[key]=0.0;peaks[key]=0.0;calls[key]=0
	current[key]+=usec/1000.0;peaks[key]=maxf(peaks[key],usec/1000.0);calls[key]+=1
func frame(completed: float):
	var now := Time.get_ticks_usec()
	if last_frame>0:
		var delta := (now-last_frame)/1000000.0
		add("Frame wall",delta*1000000);real_seconds+=delta
		for i in range(4):
			if delta*1000>THRESHOLDS[i]: spikes[i]+=1
	for key in samples:
		samples[key][cursor]=current[key];current[key]=0.0
	cursor=(cursor+1)%WINDOW;frames+=1;last_frame=now;last_completed=completed
	if real_seconds-rate_at>=1:
		achieved=(completed-rate_completed)/(real_seconds-rate_at);rate_completed=completed;rate_at=real_seconds
func stats(key: String) -> String:
	var values: PackedFloat64Array=samples[key].slice(0,mini(frames,WINDOW));values.sort()
	if values.is_empty(): return "pending"
	return "p50 %.2f p95 %.2f max %.2f / call-max %.2f ms (%d calls)" % [values[values.size()/2],values[mini(values.size()-1,int(values.size()*.95))],values[-1],peaks[key],calls[key]]
func report(p) -> String:
	var levels := PackedInt32Array([0,0,0]);var bait := 0;var escapees := 0
	for i in range(p.ids.size()):
		if p.ecology.alive[i]!=0: levels[p.simulation_detail.fish_levels[i]]+=1
	for a in p.ecology.forage:
		if not a.get("active",true): continue
		bait+=1;levels[int(a.get("detail",2))]+=1
		if a.get("temporary",false): escapees+=1
	for a in p.ecology.predators:
		if a.active: levels[int(a.get("detail",2))]+=1
	var costly := "none";var cost := 0.0
	for key in samples:
		if key in ["Frame wall","Main process","Simulation","World step wall","World step CPU","Navigation worker"]: continue
		var peak := 0.0
		for value in samples[key]: peak=maxf(peak,value)
		if peak>cost: cost=peak;costly=key
	var text := "BayGame diagnostics | FPS %.1f | requested %.0fx achieved %.2fx\nQueued %.2f s + in-flight %.2f s | phase %d cursor %d\nD/I/B animals %d / %d / %d (last assigned) | bait records %d escapees %d\nRoutes pending %d | largest recent subsystem %s %.2f ms\nFrames >50/100/250/500ms: %s (session, overlapping)\nDisabled: ecology=%s hunting=%s publishing=%s distance=%s\n" % [Engine.get_frames_per_second(),p.time_scale,achieved,p.time_debt,p.WORLD_STEP if p.sim_phase>=0 else 0.0,p.sim_phase,p.sim_cursor,levels[0],levels[1],levels[2],bait,escapees,p.movement.nav.queued_routes.size(),costly,cost,str(spikes),ecology_disabled,hunting_disabled,publishing_disabled,not p.simulation_detail.enabled]
	text+="Recent %d frames; timings ms/frame, nested (do not sum); call maxima/counts session. Worker time is off-thread.\n" % mini(frames,WINDOW)
	for key in samples: text+=key+": "+stats(key)+"\n"
	return text

func begin_session():
	samples.clear();current.clear();peaks.clear();calls.clear();cursor=0;frames=0
	spikes.fill(0);last_frame=0;real_seconds=0;rate_at=0;rate_completed=0
