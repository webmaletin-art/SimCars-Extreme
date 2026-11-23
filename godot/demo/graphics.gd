## Gráficos 100 % MANUALES (sin calibración automática). Cada valor es una perilla que ponés vos.
## En Dream Racing estas mismas perillas viven en Opciones → Gráficos (ui/options_ui.gd) y se aplican en race.gd
## (_apply_quality_settings, _setup_viewport). Acá están reducidas a lo esencial y comentadas.
extends RefCounted

## Perfil por defecto = «medio». Cambiá lo que quieras; nada se mide ni se corrige solo.
var cfg := {
	"res_scale": 1.0,     # escala del render 3D (0.5–1.0). Baja los píxeles que calcula la GPU; el HUD sigue nítido (en el juego es un SubViewport)
	"shadows": "media",   # "off" | "baja" | "media" | "alta"  (sombras del sol; 2 cascadas, distancia máx. 45 m)
	"particles": 1.0,     # 0 = sin partículas … 1 = todas
	"particles_q": "media", # "baja" (x0,5) | "media" | "alta" (x1,5): cantidad por emisor
	"msaa": 0,            # 0 sin · 1 2x · 2 4x (en celulares de gama media dejalo en 0)
	"fps_cap": 60,        # 0 = sin tope
	"show_fps": true,
}

func apply(root: Node3D, sun: DirectionalLight3D, vp: Viewport, fx) -> void:
	var sh: String = cfg["shadows"]
	sun.shadow_enabled = sh != "off"
	if sh != "off":
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if sh == "baja" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = {"baja": 25.0, "media": 45.0, "alta": 70.0}[sh]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(float(cfg["res_scale"]), 0.25, 1.0)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(cfg["msaa"]), 0, 2)]
	Engine.max_fps = int(cfg["fps_cap"])
	if fx != null:
		fx.intensity = clampf(float(cfg["particles"]), 0.0, 1.0)
		fx.set_quality(str(cfg["particles_q"]))
