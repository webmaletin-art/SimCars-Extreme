extends RefCounted
## Ajustes gráficos globales que valen en el menú y en la partida.

const SCREEN_RES := ["NATIVA", "1440p", "1080p", "900p", "720p", "576p", "480p", "360p"]
const BASE_H := 576.0 # alto lógico de la interfaz (project.godot)

## Resolución de pantalla: cuántos píxeles se dibujan de VERDAD (todo el cuadro, interfaz incluida). La interfaz no cambia de tamaño:
## el lienzo lógico sigue siendo de 576 de alto; sólo se calcula con menos (o más) píxeles y el teléfono lo estira.
static func apply_screen(tree: SceneTree, S: Dictionary) -> void:
	var root := tree.root
	var sr := String(S.get("screen_res", "NATIVA"))
	if sr == "NATIVA" or not sr.ends_with("p"):
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_size = Vector2i(1280, 576)
		root.content_scale_factor = 1.0
	else:
		var h := int(sr.trim_suffix("p"))
		var ws := Vector2(root.size)
		var asp := ws.x / maxf(1.0, ws.y)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(int(round(h * asp)), h)
		root.content_scale_factor = float(h) / BASE_H
	var vp := root.get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(float(S.get("res_scale", 1.0)), 0.25, 1.0)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(S.get("msaa", 0)), 0, 2)]
	Engine.max_fps = int(S.get("fps_cap", 60))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(S.get("vsync", true)) else DisplayServer.VSYNC_DISABLED)
