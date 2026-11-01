extends SceneTree
var game
func _initialize(): call_deferred("run")
func run():
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 if not game.fish.startup_ready: print(game.fish.startup_error);quit(1);return
 game.hud.menu.hide();game.camera.follow=false;game.camera.geo=game.boat.geo.copy();game.camera.span=1000;game.camera.target_span=1000;game.fish_overlay.toggle()
 var pods:=0;var solitary:=0;var detached:=0;var quantity:=0
 for a in game.fish.ecology.forage:
  if a.get("temporary",false): detached+=1
  elif a.get("individual",false): solitary+=1
  else: pods+=1
  quantity+=int(a.quantity)
 print("INITIAL ",JSON.stringify({"pods":pods,"solitary":solitary,"detached":detached,"prey_quantity":quantity,"fish":game.fish.ids.size(),"predators":game.fish.ecology.predators.size()}))
 var meter=ClassDB.instantiate("BaySimulation")
 game.fish.diagnostics.detailed=true
 await create_timer(4).timeout
 for speed in [1,5,10]:
  game.fish.time_scale=speed
  await create_timer(2).timeout
  var start:=Time.get_ticks_usec();var last:=start;var frame_times:Array[float]=[];var initial:float=game.fish.completed_time();var debt:float=game.fish.time_debt
  game.fish.diagnostics.begin_session()
  while Time.get_ticks_usec()-start<12000000:
   await process_frame
   var now:=Time.get_ticks_usec();frame_times.append((now-last)/1000.0);last=now
  var wall:float=(Time.get_ticks_usec()-start)/1000000.0;frame_times.sort()
  var result:Dictionary={"native":game.fish.native!=null,"speed":speed,"fps":frame_times.size()/wall,"p50":frame_times[frame_times.size()/2],"p95":frame_times[int(frame_times.size()*.95)],"max":frame_times[-1],"achieved":(game.fish.completed_time()-initial)/wall,"debt_delta":game.fish.time_debt-debt,"memory":meter.process_memory()}
  if game.fish.native!=null: result.worker=game.fish.native.stats
  print("PROFILE ",JSON.stringify(result));print(game.fish.diagnostics.report(game.fish))
 game.set_process(false);game.fish_overlay.enabled=false;game.fish.dispose();quit()
