extends RefCounted
## Panel de ajustes (gráficos, controles, sonido, piloto). Lo usan el menú principal y la pausa; cada cambio se guarda en el perfil y avisa con on_change(clave).

const UI := preload("res://game/ui/ui_kit.gd")
const Profile := preload("res://game/save/profile.gd")

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
	section.call("GRÁFICOS")
	var sh := ["off", "baja", "media", "alta"]
	box.add_child(UI.choice("Sombras", ["NO", "BAJAS", "MEDIAS", "ALTAS"], maxi(0, sh.find(S["shadows"])), func(i: int) -> void: set_s.call("shadows", sh[i])))
	box.add_child(UI.slider("Resolución 3D", 0.4, 1.0, float(S["res_scale"]), 0.05, func(v: float) -> void: set_s.call("res_scale", v), "%.2f"))
	var fps := [30, 60, 0]
	box.add_child(UI.choice("Límite de FPS", ["30", "60", "SIN TOPE"], maxi(0, fps.find(int(S["fps_cap"]))), func(i: int) -> void: set_s.call("fps_cap", fps[i])))
	box.add_child(UI.toggle("Mostrar FPS", bool(S["show_fps"]), func(b: bool) -> void: set_s.call("show_fps", b)))
	box.add_child(UI.slider("Partículas", 0.0, 1.0, float(S["particles"]), 0.1, func(v: float) -> void: set_s.call("particles", v), "%.1f"))
	if not in_game:
		box.add_child(UI.slider("Autos estacionados", 0, 9, float(S["parked"]), 1, func(v: float) -> void: set_s.call("parked", int(v)), "%d"))
		box.add_child(UI.slider("Pasto y flores", 0.0, 1.5, float(S["grass"]), 0.1, func(v: float) -> void: set_s.call("grass", v), "%.1f"))
		box.add_child(UI.slider("Árboles", 0.0, 1.5, float(S["trees"]), 0.1, func(v: float) -> void: set_s.call("trees", v), "%.1f"))
		box.add_child(UI.toggle("Edificios de fondo", bool(S["backdrop"]), func(b: bool) -> void: set_s.call("backdrop", b)))
		box.add_child(UI.toggle("Conos", bool(S["cones"]), func(b: bool) -> void: set_s.call("cones", b)))
	box.add_child(UI.slider("Viento", 0.0, 2.0, float(S["wind"]), 0.1, func(v: float) -> void: set_s.call("wind", v), "%.1f"))
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
