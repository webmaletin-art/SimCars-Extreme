extends SceneTree
func _init() -> void:
	await process_frame
	var r := root
	print("antes: visible=", r.get_visible_rect().size, " size=", r.size)
	r.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	r.content_scale_size = Vector2i(640, 288)
	r.content_scale_factor = 0.5
	await process_frame
	await process_frame
	print("viewport 640x288 f=0.5: visible=", r.get_visible_rect().size, " size=", r.size, " stretch=", r.get_stretch_transform())
	r.content_scale_factor = 1.0
	await process_frame
	print("viewport 640x288 f=1: visible=", r.get_visible_rect().size, " stretch=", r.get_stretch_transform())
	var img := r.get_texture().get_image()
	print("textura del cuadro: ", img.get_size())
	quit()
