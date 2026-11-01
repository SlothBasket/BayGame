extends SceneTree
var game
func _initialize(): call_deferred("run")
func run():
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 if not game.fish.startup_ready: quit(1);return
 game.hud.menu.hide();game.fish_overlay.toggle();game.fish_overlay.advanced=true
 game.camera.follow=false;game.camera.span=180;game.camera.target_span=180;game.fish.time_scale=5
 var groups: Dictionary={};var snapper:=0;var largest:=0
 for i in range(game.fish.ids.size()):
  if game.fish.species[i]!=7: continue
  snapper+=1
  var group: int=game.fish.ecology.school[i]
  if group>=0: groups[group]=int(groups.get(group,0))+1;largest=maxi(largest,groups[group])
 if largest>8: push_error("Snapper school exceeds eight");quit(1);return
 var pod:=0
 for i in range(game.fish.ecology.forage.size()):
  if game.fish.ecology.forage[i].kind==1 and not game.fish.ecology.forage[i].individual: pod=i;break
 for pair in [[FishDebugOverlay.Entity.BAIT,pod],[FishDebugOverlay.Entity.FISH,0],[FishDebugOverlay.Entity.PREDATOR,0]]:
  game.fish_overlay.select_entity(pair[0],pair[1]);game.fish_overlay.center_selected();game.fish_overlay.following=true
  await create_timer(2).timeout
  print("INSPECT ",game.fish_overlay.heading.text," | ",game.fish_overlay.info.text.replace("\n"," | "))
 game.fish_overlay.following=false;game.fish.time_scale=0
 await create_timer(.3).timeout
 var paused: float=game.fish.completed_time()
 await create_timer(.3).timeout
 if game.fish.completed_time()!=paused: push_error("Pause advanced time");quit(1);return
 print("INSPECT_RESULT ",JSON.stringify({"snapper":snapper,"schools":groups.size(),"largest_school":largest,"worker":game.fish.native.stats}))
 game.set_process(false);game.fish_overlay.enabled=false;game.fish.dispose();quit()
