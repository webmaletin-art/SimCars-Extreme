extends RefCounted
## Panel de ajustes (gráficos, controles, sonido, piloto). Lo usan el menú principal y la pausa; cada cambio se guarda en el perfil y avisa con on_change(clave).

const UI := preload("res://game/ui/ui_kit.gd")
const Profile := preload("res://game/save/profile.gd")
const Gfx := preload("res://game/ui/gfx.gd")

static func build(profile: Dictionary, on_change: Callable, in_game := false) -> Control:
	var S: Dictionary = profile["settings"]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(900, 360)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var set_s := func(k: String, v: Variant) -> void:
		S[k] = v
		Profile.save_profile(profile)
		on_change.call(k)
	var section := func(t: String) -> void:
		var l := UI.label(t, 28, UI.ACC)
		l.custom_minimum_size = Vector2(0, 46)
		box.add_child(l)
	section.call("GRÁFICOS · RESOLUCIÓN")
	var sres: Array = Gfx.SCREEN_RES
	box.add_child(UI.choice("Resolución de pantalla", sres, maxi(0, sres.find(String(S.get("screen_res", "NATIVA")))), func(i: int) -> void: set_s.call("screen_res", sres[i]), 92))
	var rs := [0.25, 0.33, 0.4, 0.5, 0.6, 0.7, 0.75, 0.85, 1.0]
	var rs_lbl := ["25%", "33%", "40%", "50%", "60%", "70%", "75%", "85%", "100%"]
	var cur_rs := 0
	for i in rs.size():
		if absf(float(rs[i]) - float(S["res_scale"])) < absf(float(rs[cur_rs]) - float(S["res_scale"])):
			cur_rs = i
	box.add_child(UI.choice("Resolución 3D (render)", rs_lbl, cur_rs, func(i: int) -> void: set_s.call("res_scale", rs[i]), 72))
	box.add_child(UI.choice("Suavizado (MSAA)", ["NO", "2x", "4x"], clampi(int(S["msaa"]), 0, 2), func(i: int) -> void: set_s.call("msaa", i)))
	var fps := [30, 45, 60, 90, 120, 0]
	box.add_child(UI.choice("Límite de FPS", ["30", "45", "60", "90", "120", "SIN TOPE"], maxi(0, fps.find(int(S["fps_cap"]))), func(i: int) -> void: set_s.call("fps_cap", fps[i]), 92))
	box.add_child(UI.toggle("Sincronía vertical (VSync)", bool(S.get("vsync", true)), func(b: bool) -> void: set_s.call("vsync", b)))
	section.call("GRÁFICOS · DISTANCIAS Y DETALLE")
	var vd := [80, 120, 200, 350, 650]
	box.add_child(UI.choice("Distancia de dibujo", ["80 m", "120 m", "200 m", "350 m", "650 m"], maxi(0, vd.find(int(S.get("view_dist", 650)))), func(i: int) -> void: set_s.call("view_dist", vd[i]), 92))
	box.add_child(UI.slider("Distancia de detalle", 0.3, 2.0, float(S.get("detail_dist", 1.0)), 0.1, func(v: float) -> void: set_s.call("detail_dist", v), "×%.1f"))
	var sh := ["off", "baja", "media", "alta"]
	box.add_child(UI.choice("Sombras", ["NO", "BAJAS", "MEDIAS", "ALTAS"], maxi(0, sh.find(S["shadows"])), func(i: int) -> void: set_s.call("shadows", sh[i])))
	box.add_child(UI.slider("Distancia de sombras", 15.0, 100.0, float(S.get("shadow_dist", 55.0)), 5.0, func(v: float) -> void: set_s.call("shadow_dist", v), "%.0f m"))
	box.add_child(UI.toggle("Partículas (humo, polvo, marcas)", bool(S.get("particles_on", true)), func(b: bool) -> void: set_s.call("particles_on", b)))
	box.add_child(UI.slider("Cantidad de partículas", 0.0, 1.0, float(S["particles"]), 0.1, func(v: float) -> void: set_s.call("particles", v), "%.1f"))
	box.add_child(UI.toggle("Piloto visible desde afuera", bool(S.get("pilot_outside", true)), func(b: bool) -> void: set_s.call("pilot_outside", b)))
	box.add_child(UI.toggle("Mostrar FPS", bool(S["show_fps"]), func(b: bool) -> void: set_s.call("show_fps", b)))
	box.add_child(UI.slider("Viento", 0.0, 2.0, float(S["wind"]), 0.1, func(v: float) -> void: set_s.call("wind", v), "%.1f"))
	section.call("GRÁFICOS · ESCENARIO" + ("  (se aplica al reiniciar el escenario)" if in_game else ""))
	box.add_child(UI.choice("Auto del jugador", ["ORIGINAL", "LIVIANO"], 1 if bool(S.get("player_lite", false)) else 0, func(i: int) -> void: set_s.call("player_lite", i == 1)))
	box.add_child(UI.slider("Autos estacionados", 0, 9, float(S["parked"]), 1, func(v: float) -> void: set_s.call("parked", int(v)), "%d"))
	box.add_child(UI.slider("Pasto y flores", 0.0, 1.5, float(S["grass"]), 0.1, func(v: float) -> void: set_s.call("grass", v), "%.1f"))
	box.add_child(UI.slider("Árboles", 0.0, 1.5, float(S["trees"]), 0.1, func(v: float) -> void: set_s.call("trees", v), "%.1f"))
	box.add_child(UI.toggle("Edificios de fondo", bool(S["backdrop"]), func(b: bool) -> void: set_s.call("backdrop", b)))
	box.add_child(UI.toggle("Conos", bool(S["cones"]), func(b: bool) -> void: set_s.call("cones", b)))
	section.call("CONTROLES")
	box.add_child(UI.choice("Dirección en pantalla", ["VOLANTE", "BARRA"], 0 if S["steer_mode"] == "wheel" else 1, func(i: int) -> void: set_s.call("steer_mode", "wheel" if i == 0 else "slider")))
	var wr := [0, 50, 100]
	box.add_child(UI.choice("Giro del volante", ["ARCADE", "REAL 50%", "REAL 100%"], maxi(0, wr.find(int(S["wheel_real"]))), func(i: int) -> void: set_s.call("wheel_real", wr[i])))
	box.add_child(UI.toggle("Inclinar el celular para girar", bool(S["gyro"]), func(b: bool) -> void: set_s.call("gyro", b)))
	box.add_child(UI.toggle("Caja manual", bool(S["manual"]), func(b: bool) -> void: set_s.call("manual", b)))
	box.add_child(UI.toggle("ABS", bool(S["abs"]), func(b: bool) -> void: set_s.call("abs", b)))
	box.add_child(UI.slider("Control de tracción", 0.0, 100.0, float(S["tc"]), 5.0, func(v: float) -> void: set_s.call("tc", v), "%.0f"))
	box.add_child(UI.slider("Ayuda de estabilidad", 0.0, 100.0, float(S["stab"]), 5.0, func(v: float) -> void: set_s.call("stab", v), "%.0f"))
	box.add_child(UI.toggle("Velocidad en mph", bool(S["units_mph"]), func(b: bool) -> void: set_s.call("units_mph", b)))
	section.call("SONIDO")
	box.add_child(UI.slider("Volumen", 0.0, 100.0, float(S["volume"]), 5.0, func(v: float) -> void: set_s.call("volume", v), "%.0f"))
	section.call("PILOTO")
	var pa: Dictionary = profile["pilot_adj"]
	box.add_child(UI.slider("Estatura del piloto (m)", 1.45, 2.0, float(profile["pilot_height"]), 0.01, func(v: float) -> void:
		profile["pilot_height"] = v
		Profile.save_profile(profile)
		on_change.call("pilot"), "%.2f"))
	for ax in [["x", "Piloto: izquierda / derecha"], ["y", "Piloto: arriba / abajo"], ["z", "Piloto: adelante / atrás"]]:
		var key: String = ax[0]
		box.add_child(UI.slider(ax[1], -0.3, 0.3, float(pa[key]), 0.01, func(v: float) -> void:
			pa[key] = v
			Profile.save_profile(profile)
			on_change.call("pilot_adj"), "%.2f"))
	return scroll
