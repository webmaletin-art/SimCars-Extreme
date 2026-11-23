extends RefCounted
## Panel de ajustes (gráficos, controles, sonido, piloto). Lo usan el menú principal y la pausa; cada cambio se guarda en el perfil y avisa con on_change(clave).

const UI := preload("res://game/ui/ui_kit.gd")
const Profile := preload("res://game/save/profile.gd")
const Gfx := preload("res://game/ui/gfx.gd")

## Niveles de simulación (ayudas): los 4 de Dream Rally. Al tocar una ayuda suelta el nivel pasa a PERSONALIZADO.
const SIM_PRESETS := {
	"arcade": {"abs": true, "tc": 80.0, "stab": 90.0, "line": 60.0, "wheel_real": 0},
	"mid": {"abs": true, "tc": 50.0, "stab": 30.0, "line": 25.0, "wheel_real": 0},
	"pro": {"abs": false, "tc": 0.0, "stab": 0.0, "line": 0.0, "wheel_real": 100}, # simulador total: volante real, ABS y control apagados
	"adv": {"abs": true, "tc": 30.0, "stab": 20.0, "line": 0.0, "wheel_real": 0},
}
const SIM_IDS := ["arcade", "mid", "pro", "adv", "custom"]
const PAGES := ["GRÁFICOS", "CONTROLES Y AYUDAS", "SONIDO Y PILOTO"]

static func apply_sim(S: Dictionary, id: String) -> void:
	S["sim"] = id
	if SIM_PRESETS.has(id):
		for k in SIM_PRESETS[id]:
			S[k] = SIM_PRESETS[id][k]

static func build(profile: Dictionary, on_change: Callable, in_game := false) -> Control:
	var S: Dictionary = profile["settings"]
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	root.add_child(holder)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.scroll_deadzone = 4
	scroll.custom_minimum_size = Vector2(900, 340)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(scroll)
	var vb := scroll.get_v_scroll_bar()
	vb.custom_minimum_size = Vector2(34, 0)
	# botones grandes ▲ ▼ (con el dedo sobre un deslizador no se puede arrastrar la lista)
	var arrows := VBoxContainer.new()
	arrows.add_theme_constant_override("separation", 10)
	holder.add_child(arrows)
	var up := UI.button("▲", Vector2(70, 150), 30)
	up.pressed.connect(func() -> void: scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - 220))
	arrows.add_child(up)
	var dn := UI.button("▼", Vector2(70, 150), 30)
	dn.pressed.connect(func() -> void: scroll.scroll_vertical += 220)
	arrows.add_child(dn)
	var page_i := [int(profile.get("opt_page", 0))]
	var fill := func() -> void: pass
	var set_s := func(k: String, v: Variant) -> void:
		S[k] = v
		if k in ["abs", "tc", "stab", "line", "wheel_real"] and S.get("sim", "custom") != "custom":
			S["sim"] = "custom"
		Profile.save_profile(profile)
		on_change.call(k)
	var draw := func() -> void:
		for c in scroll.get_children():
			if c is not VScrollBar and c is not HScrollBar:
				c.queue_free()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(box)
		var section := func(t: String) -> void:
			var l := UI.label(t, 26, UI.ACC)
			l.custom_minimum_size = Vector2(0, 42)
			box.add_child(l)
		match page_i[0]:
			0:
				_page_graphics(box, S, in_game, set_s, section)
			1:
				_page_controls(box, profile, S, set_s, section, on_change, fill)
			2:
				_page_sound(box, profile, S, set_s, section, on_change)
		scroll.scroll_vertical = 0
	fill = draw
	for i in PAGES.size():
		var b := UI.button(PAGES[i], Vector2(270, 46), 18, i == page_i[0])
		b.pressed.connect(func() -> void:
			page_i[0] = i
			profile["opt_page"] = i
			for k in tabs.get_child_count():
				(tabs.get_child(k) as Button).add_theme_stylebox_override("normal", UI.style(UI.ACC if k == i else Color(0.12, 0.17, 0.25, 0.95), 16, UI.ACC2 if k == i else Color(0.3, 0.4, 0.55, 0.8), 2))
			draw.call())
		tabs.add_child(b)
	draw.call()
	return root

static func _page_graphics(box: VBoxContainer, S: Dictionary, in_game: bool, set_s: Callable, section: Callable) -> void:
	section.call("RESOLUCIÓN")
	var sres: Array = Gfx.SCREEN_RES
	box.add_child(UI.choice("Resolución de pantalla", sres, maxi(0, sres.find(String(S.get("screen_res", "NATIVA")))), func(i: int) -> void: set_s.call("screen_res", sres[i]), 84))
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
	section.call("DISTANCIAS Y DETALLE")
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
	section.call("ESCENARIO" + ("  (se aplica al reiniciar el escenario)" if in_game else ""))
	box.add_child(UI.choice("Auto del jugador", ["ORIGINAL", "LIVIANO"], 1 if bool(S.get("player_lite", false)) else 0, func(i: int) -> void: set_s.call("player_lite", i == 1)))
	box.add_child(UI.slider("Autos estacionados", 0, 9, float(S["parked"]), 1, func(v: float) -> void: set_s.call("parked", int(v)), "%d"))
	box.add_child(UI.slider("Pasto y flores", 0.0, 1.5, float(S["grass"]), 0.1, func(v: float) -> void: set_s.call("grass", v), "%.1f"))
	box.add_child(UI.slider("Árboles", 0.0, 1.5, float(S["trees"]), 0.1, func(v: float) -> void: set_s.call("trees", v), "%.1f"))
	box.add_child(UI.toggle("Edificios de fondo", bool(S["backdrop"]), func(b: bool) -> void: set_s.call("backdrop", b)))
	box.add_child(UI.toggle("Conos", bool(S["cones"]), func(b: bool) -> void: set_s.call("cones", b)))

static func _page_controls(box: VBoxContainer, profile: Dictionary, S: Dictionary, set_s: Callable, section: Callable, on_change: Callable, redraw: Callable) -> void:
	section.call("NIVEL DE SIMULACIÓN")
	var sim := String(S.get("sim", "mid"))
	box.add_child(UI.choice("Nivel", ["ARCADE", "MEDIO", "PRO", "AVANZADO", "PERSONAL."], maxi(0, SIM_IDS.find(sim)), func(i: int) -> void:
		apply_sim(S, SIM_IDS[i])
		Profile.save_profile(profile)
		on_change.call("sim")
		redraw.call(), 130))
	var info := {"arcade": "Muchas ayudas: el auto se agarra solo, el volante gira ¾ de vuelta.", "mid": "Ayudas medias: lo normal para empezar.",
		"pro": "Simulador total: sin ABS ni control de tracción ni estabilidad, y el volante da las 3 vueltas reales.", "adv": "Casi simulación con un poquito de ayuda.", "custom": "Lo que elijas abajo."}
	var il := UI.label(String(info.get(sim, "")), 18, UI.DIM)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.custom_minimum_size = Vector2(760, 0)
	box.add_child(il)
	box.add_child(UI.toggle("ABS", bool(S["abs"]), func(b: bool) -> void: set_s.call("abs", b)))
	box.add_child(UI.slider("Control de tracción", 0.0, 100.0, float(S["tc"]), 5.0, func(v: float) -> void: set_s.call("tc", v), "%.0f"))
	box.add_child(UI.slider("Ayuda de estabilidad", 0.0, 100.0, float(S["stab"]), 5.0, func(v: float) -> void: set_s.call("stab", v), "%.0f"))
	box.add_child(UI.slider("Ayuda de trazada (camino)", 0.0, 100.0, float(S.get("line", 25.0)), 5.0, func(v: float) -> void: set_s.call("line", v), "%.0f"))
	section.call("VOLANTE Y CAJA")
	box.add_child(UI.choice("Dirección en pantalla", ["VOLANTE", "BARRA"], 0 if S["steer_mode"] == "wheel" else 1, func(i: int) -> void: set_s.call("steer_mode", "wheel" if i == 0 else "slider")))
	var wr := [0, 50, 100]
	box.add_child(UI.choice("Giro del volante", ["ARCADE ¾", "REAL 1½", "REAL 3 vueltas"], maxi(0, wr.find(int(S["wheel_real"]))), func(i: int) -> void: set_s.call("wheel_real", wr[i]), 150))
	box.add_child(UI.toggle("Inclinar el celular para girar", bool(S["gyro"]), func(b: bool) -> void: set_s.call("gyro", b)))
	box.add_child(UI.toggle("Caja manual", bool(S["manual"]), func(b: bool) -> void: set_s.call("manual", b)))
	box.add_child(UI.toggle("Velocidad en mph", bool(S["units_mph"]), func(b: bool) -> void: set_s.call("units_mph", b)))

static func _page_sound(box: VBoxContainer, profile: Dictionary, S: Dictionary, set_s: Callable, section: Callable, on_change: Callable) -> void:
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
