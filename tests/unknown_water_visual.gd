extends SceneTree
func _initialize(): call_deferred('run')
func run():
	var viewport:=SubViewport.new();viewport.size=Vector2i(256,256);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var view:=RegionView.new()
	var samples:=PackedFloat32Array();samples.resize(67*67);samples.fill(NAN)
	view.setup({'x':0,'y':0,'size':256,'n':64,'samples':samples,'indices':[],'shore':[],'channels':[]})
	viewport.add_child(view);view.refresh(GeoPosition.new(),true,false,1)
	await process_frame
	await RenderingServer.frame_post_draw
	var color:=viewport.get_texture().get_image().get_pixel(128,128)
	var ok:=color.g>.3 and color.b>.3 and color.a>.99
	print('UNKNOWN WATER GPU CHECK: ',ok,' color=',color)
	viewport.queue_free();quit(0 if ok else 1)
