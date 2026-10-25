class_name GeographyStore
extends RefCounted
var root := "res://assets/generated/"
var manifest: Dictionary
var cache: Dictionary = {}
var pending: Dictionary = {}
var wanted: Dictionary = {}
var clock := 0
var bytes_loaded := 0
var hits := 0
var misses := 0
var load_ms := 0.0
var budget_ms := 3.0
var max_bytes := 268435456
var last_error := ""
func _init():
	if "--synthetic" in OS.get_cmdline_user_args(): root = "res://assets/synthetic/"
	# Exported executable reuses the included geographic files beside it.
	if not FileAccess.file_exists(root + "manifest.json") and not OS.has_feature("editor"):
		var exe_dir := OS.get_executable_path().get_base_dir()
		root = exe_dir.path_join("godot/assets/generated/")
		# Git checkouts reuse canonical assets; portable builds carry their own copy.
		if not FileAccess.file_exists(root+"manifest.json"):
			root = exe_dir.path_join("../../godot/assets/generated/")
	manifest = JSON.parse_string(FileAccess.get_file_as_string(root + "manifest.json"))
	budget_ms = manifest.parameters.load_budget_ms
	max_bytes = int(manifest.parameters.cache_mb * 1048576)
	# Root regions are the only synchronous startup assets.
	for key in manifest.nodes:
		if int(manifest.nodes[key].level) == int(manifest.max_lod):
			_install(key, _read(key))
func _read(key: String) -> Dictionary:
	var begin := Time.get_ticks_usec()
	var data = JSON.parse_string(FileAccess.get_file_as_string(root + "chunks/" + key + ".json"))
	if not data is Dictionary: return {"error":key}
	data["samples"] = FileAccess.get_file_as_bytes(root + "chunks/" + key + ".f32").to_float32_array()
	data["read_ms"] = (Time.get_ticks_usec() - begin) / 1000.0
	return data
func _install(key: String, data: Dictionary):
	if data.has("error"):
		last_error = "Unreadable chunk: " + key
		return
	data["used"] = clock
	cache[key] = data
	bytes_loaded += int(manifest.nodes[key].bytes)*5
	load_ms = data.read_ms
func request(key: String):
	if not manifest.nodes.has(key): return
	wanted[key] = true
	if cache.has(key):
		cache[key].used = clock
		hits += 1
		return
	if pending.has(key): return
	# Bound in-flight jobs. Unserved requests are retried next frame.
	if pending.size() >= 8: return
	misses += 1
	var result: Array = []
	var task := WorkerThreadPool.add_task(func(): result.append(_read(key)))
	pending[key] = {"task":task,"result":result}
func begin_frame():
	clock += 1
	wanted.clear()
	var begin := Time.get_ticks_usec()
	for key in pending.keys():
		var job: Dictionary = pending[key]
		if WorkerThreadPool.is_task_completed(job.task):
			WorkerThreadPool.wait_for_task_completion(job.task)
			_install(key, job.result[0])
			pending.erase(key)
		if (Time.get_ticks_usec() - begin) / 1000.0 > budget_ms: break
func get_chunk(key: String) -> Dictionary:
	request(key)
	return cache.get(key, {})
func evict():
	if bytes_loaded <= max_bytes: return
	var keys := cache.keys()
	keys.sort_custom(func(a,b): return cache[a].used < cache[b].used)
	for key in keys:
		if wanted.has(key) or int(manifest.nodes[key].level)==int(manifest.max_lod): continue
		bytes_loaded -= int(manifest.nodes[key].bytes)*5
		cache.erase(key)
		if bytes_loaded <= max_bytes: break
func shutdown():
	for job in pending.values(): WorkerThreadPool.wait_for_task_completion(job.task)
	pending.clear()
