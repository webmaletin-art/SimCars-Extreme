extends Node3D
## La partida en el estacionamiento de pruebas: mundo, auto (física propia a 120 Hz del kit de Dream Racing), modelo con piezas que se rompen, piloto con las
## manos en el volante, cámaras con ajuste, efectos, sonido, controles táctiles y menú de pausa.
##
## Teclado (para probar en PC): W/↑ gas · S/↓ freno · A D dirección · ESPACIO freno de mano · E/Q cambios (con caja manual) · C cámara · R volver al inicio · ESC pausa

signal exit_to_menu

const VehicleParams := preload("res://game/physics/vehicle_params.gd")
const Car := preload("res://game/car/car.gd")
const CameraRig := preload("res://game/car/camera_rig.gd")
const Effects := preload("res://game/fx/effects.gd")
const CarAudio := preload("res://game/audio/car_audio.gd")
const Controls := preload("res://game/ui/controls.gd")
const CarBuild := preload("res://game/data/car_build.gd")
const CarVisual := preload("res://game/car/car_visual.gd")
const Cockpit := preload("res://game/car/cockpit.gd")
const LotWorld := preload("res://game/world/lot_world.gd")
const Garage := preload("res://game/data/garage.gd")
const Profile := preload("res://game/save/profile.gd")
const OptionsPanel := preload("res://game/ui/options_panel.gd")
const UI := preload("res://game/ui/ui_kit.gd")
const Gfx := preload("res://game/ui/gfx.gd")
const PerfProbe := preload("res://game/diag/perf_probe.gd")

const STEP := 1.0 / 120.0 # la física SIEMPRE a 120 Hz (se interpola al dibujar)
const START := Vector3(0.0, 0.0, -25.5)

var profile: Dictionary
var world: LotWorld
var track
var car: Car
var visual: CarVisual
var cockpit: Cockpit
var cam: Camera3D
var rig: CameraRig
var fx: Effects
var audio: CarAudio
var controls: Controls
var hud: CanvasLayer
var ui: CanvasLayer
var lbl_info: Label
var lbl_fps: Label
var lbl_dmg: Label
var cam_panel: Control
var pause_panel: Control
var car_id := ""
var acc := 0.0
var sim_t := 0.0
var render_t := 0.0
var smooth_dt := 1.0 / 60.0
var paused := false
var last_pos := Vector3.ZERO
var save_t := 0.0
var autotest := false
var test_t := 0.0
var shot_path := ""
var shot_cam := -1
var shot_wait := 3.0
var drive := true
var dbg_cam := []
var crash := false
var opt_script := ""
var _vp_base: Viewport

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for a in OS.get_cmdline_user_args():
		if a == "--autotest":
			autotest = true
		elif a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--cam="):
			shot_cam = int(a.substr(6))
		elif a.begins_with("--wait="):
			shot_wait = float(a.substr(7))
		elif a.begins_with("--dbgcam="): # x,y,z,tx,ty,tz en el marco del auto (para mirar al piloto desde afuera en las capturas)
			for v in a.substr(9).split(","):
				dbg_cam.append(float(v))
		elif a == "--perf": # corre el diagnóstico solo y escribe el informe (pruebas)
			call_deferred("_auto_perf")
		elif a == "--crash":
			crash = true
		elif a == "--still":
			drive = false
	if profile == null or profile.is_empty():
		profile = Profile.load_profile()
	car_id = String(profile["car"])
	if not Garage.vehicles().has(car_id) or not CarVisual.has_model(car_id):
		car_id = Garage.available()[0]
	_build()

func _S(k: String) -> Variant:
	return (profile["settings"] as Dictionary)[k]

func _build() -> void:
	world = LotWorld.new()
	add_child(world)
	world.build({"parked": int(_S("parked")), "grass": float(_S("grass")), "trees": float(_S("trees")), "shadows": _S("shadows") != "off",
		"backdrop": bool(_S("backdrop")), "cones": bool(_S("cones"))})
	track = world.track
	fx = Effects.new()
	add_child(fx)
	fx.setup(track)
	fx.prepare(0)
	cam = Camera3D.new()
	cam.far = 650.0
	cam.near = 0.15
	add_child(cam)
	rig = CameraRig.new(cam, track)
	rig.adj = (profile["cam_adj"] as Dictionary).duplicate(true)
	_spawn_car()
	_build_hud()
	_apply_settings()
	rig.set_preset(shot_cam if shot_cam >= 0 else int(profile["cam"]))
	_update_camera_mode()

# ───────────────────────── auto ─────────────────────────
func _params() -> VehicleParams:
	var d: Dictionary = CarBuild.build_params(Garage.vehicles()[car_id], {"upg": {}, "tune": {}, "tires": "street", "tiresOwned": ["street"]},
		{"abs": bool(_S("abs")), "tc": float(_S("tc")), "stab": float(_S("stab"))})
	return VehicleParams.from_dict(d)

func _spawn_car() -> void:
	var P := _params()
	car = Car.new(track, P, true)
	car.phys.tc_free_spin = false
	car.phys.manual = bool(_S("manual"))
	car.solid = true # el lote tiene obstáculos: Car._keep_out consulta track.push()
	car.place(START.x, START.z, 0.0)
	car.restart_history(0.0)
	sim_t = 0.0
	acc = 0.0
	visual = CarVisual.new(car_id, bool(_S("player_lite")))
	visual.debris_root = world.debris
	add_child(visual)
	var pc := Garage.paint_of(profile, car_id)
	if pc != "":
		visual.set_paint(Color.html(pc))
	_build_car_collider()
	cockpit = Cockpit.new(visual, String(profile["char"]), float(profile["pilot_height"]))
	_apply_pilot_adj()
	rig.visual = visual
	rig.cockpit = cockpit
	rig.mount = cockpit.mount
	rig.ground_off = 0.0
	if audio != null:
		audio.queue_free()
	audio = CarAudio.new()
	audio.set_vehicle(car_id)
	add_child(audio)
	last_pos = Vector3(START.x, 0, START.z)
	fx.reset()

func _build_car_collider() -> void:
	for c in world.car_body.get_children():
		c.queue_free()
	var m := visual.meta
	var w := float(m.get("width", 1.9)) * 0.9
	var l := float(m.get("length", 4.6)) * 0.86
	var b1 := CollisionShape3D.new()
	var s1 := BoxShape3D.new()
	s1.size = Vector3(w, 0.55, l)
	b1.shape = s1
	b1.position = Vector3(0, 0.5, 0)
	world.car_body.add_child(b1)
	var b2 := CollisionShape3D.new()
	var s2 := BoxShape3D.new()
	s2.size = Vector3(w * 0.8, 0.5, l * 0.45)
	b2.shape = s2
	b2.position = Vector3(0, 0.95, -0.2)
	world.car_body.add_child(b2)

func _apply_pilot_adj() -> void:
	var a: Dictionary = profile["pilot_adj"]
	cockpit.adj = {"x": float(a["x"]), "y": float(a["y"]), "z": float(a["z"])}

func respawn(repair := false) -> void:
	car.place(START.x, START.z, 0.0)
	car.restart_history(0.0)
	sim_t = 0.0
	acc = 0.0
	fx.reset()
	if repair:
		visual.repair()

# ───────────────────────── interfaz ─────────────────────────
func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	controls = Controls.new()
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(controls)
	controls.load_skin("res://game/ui/hud")
	controls.camera_pressed.connect(func() -> void:
		rig.next()
		profile["cam"] = rig.index
		_update_camera_mode()
		_refresh_cam_panel())
	controls.pause_pressed.connect(_toggle_pause)
	controls.cam_drag.connect(func(rel: Vector2) -> void: rig.drag(rel))
	controls.cam_zoom.connect(func(f: float) -> void: rig.zoom(f))
	lbl_info = UI.label("", 18, Color(1, 1, 1, 0.85))
	lbl_info.position = Vector2(14, 8)
	lbl_info.add_theme_constant_override("outline_size", 4)
	lbl_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hud.add_child(lbl_info)
	lbl_fps = UI.label("", 20, Color(0.7, 1.0, 0.7))
	lbl_fps.position = Vector2(14, 34)
	hud.add_child(lbl_fps)
	lbl_dmg = UI.label("", 20, UI.ACC2)
	lbl_dmg.position = Vector2(14, 60)
	lbl_dmg.add_theme_constant_override("outline_size", 4)
	lbl_dmg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hud.add_child(lbl_dmg)
	# botón de ajuste rápido de la cámara
	var cb := UI.button("⚙ CÁMARA", Vector2(170, 46), 18)
	cb.anchor_left = 1.0
	cb.anchor_right = 1.0
	cb.offset_left = -190
	cb.offset_right = -20
	cb.offset_top = 86
	cb.offset_bottom = 132
	cb.pressed.connect(func() -> void:
		cam_panel.visible = not cam_panel.visible
		_refresh_cam_panel())
	hud.add_child(cb)
	ui = CanvasLayer.new()
	ui.layer = 20
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	_build_cam_panel()
	_build_pause()

func _build_cam_panel() -> void:
	cam_panel = UI.panel(Vector2(560, 0), Color(0.03, 0.05, 0.08, 0.86), 16, 14.0)
	cam_panel.anchor_left = 1.0
	cam_panel.anchor_right = 1.0
	cam_panel.offset_left = -610
	cam_panel.offset_right = -20
	cam_panel.offset_top = 140
	cam_panel.visible = false
	cam_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.add_child(cam_panel)

func _refresh_cam_panel() -> void:
	if cam_panel == null or not cam_panel.visible:
		return
	for c in cam_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	cam_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var prev := UI.button("◀", Vector2(60, 46), 22)
	prev.pressed.connect(func() -> void:
		rig.next(-1)
		profile["cam"] = rig.index
		_update_camera_mode()
		_refresh_cam_panel())
	head.add_child(prev)
	var nm := UI.label(rig.cam_name(), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var nx := UI.button("▶", Vector2(60, 46), 22)
	nx.pressed.connect(func() -> void:
		rig.next(1)
		profile["cam"] = rig.index
		_update_camera_mode()
		_refresh_cam_panel())
	head.add_child(nx)
	var inside := rig.mode() in ["onboard", "rearcabin", "hood", "bumper"]
	var rng_d := Vector2(-0.6, 0.6) if inside else Vector2(-4.0, 10.0)
	var rng_h := Vector2(-0.4, 0.4) if inside else Vector2(-1.5, 4.0)
	var rng_s := Vector2(-0.5, 0.5) if inside else Vector2(-3.0, 3.0)
	var save := func() -> void:
		profile["cam_adj"] = rig.adj.duplicate(true)
		Profile.save_profile(profile)
	v.add_child(UI.slider("Altura", rng_h.x, rng_h.y, rig.adj_of("height"), 0.02, func(x: float) -> void:
		rig.set_adj("height", x)
		save.call(), "%.2f", 300.0))
	v.add_child(UI.slider("Distancia", rng_d.x, rng_d.y, rig.adj_of("dist"), 0.05, func(x: float) -> void:
		rig.set_adj("dist", x)
		save.call(), "%.2f", 300.0))
	v.add_child(UI.slider("Lateral", rng_s.x, rng_s.y, rig.adj_of("side"), 0.02, func(x: float) -> void:
		rig.set_adj("side", x)
		save.call(), "%.2f", 300.0))
	v.add_child(UI.slider("Ángulo (FOV)", -25.0, 35.0, rig.adj_of("fov"), 1.0, func(x: float) -> void:
		rig.set_adj("fov", x)
		save.call(), "%.0f", 300.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var rs := UI.button("RESTABLECER", Vector2(230, 46), 20)
	rs.pressed.connect(func() -> void:
		rig.adj.erase(str(rig.index))
		save.call()
		_refresh_cam_panel())
	row.add_child(rs)
	var cl := UI.button("CERRAR", Vector2(150, 46), 20, true)
	cl.pressed.connect(func() -> void: cam_panel.visible = false)
	row.add_child(cl)

func _build_pause() -> void:
	pause_panel = Control.new()
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.add_child(pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(dim)

func _show_pause_main() -> void:
	for c in pause_panel.get_children():
		if c is not ColorRect:
			c.queue_free()
	var box := VBoxContainer.new()
	box.position = Vector2(420, 70)
	box.add_theme_constant_override("separation", 12)
	pause_panel.add_child(box)
	box.add_child(UI.label("PAUSA", 44, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var items := [
		["CONTINUAR", true, _toggle_pause],
		["CÁMARA", false, func() -> void:
			_toggle_pause()
			cam_panel.visible = true
			_refresh_cam_panel()],
		["AJUSTES", false, _show_pause_options],
		["RENDIMIENTO (diagnóstico)", false, _show_perf],
		["REPARAR EL AUTO", false, func() -> void:
			visual.repair()
			_toggle_pause()],
		["VOLVER AL INICIO", false, func() -> void:
			respawn(false)
			_toggle_pause()],
		["REINICIAR ESCENARIO", false, func() -> void:
			_save_stats()
			get_tree().paused = false
			get_tree().reload_current_scene()],
		["MENÚ PRINCIPAL", false, func() -> void:
			_save_stats()
			get_tree().paused = false
			exit_to_menu.emit()],
	]
	for it in items:
		var b := UI.button(String(it[0]), Vector2(440, 58), 24, bool(it[1]))
		b.pressed.connect(it[2])
		box.add_child(b)

func _show_pause_options() -> void:
	for c in pause_panel.get_children():
		if c is not ColorRect:
			c.queue_free()
	var panel := UI.panel(Vector2(980, 0), UI.BG, 18, 18.0)
	panel.position = Vector2(150, 50)
	pause_panel.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var bk := UI.button("◀ VOLVER", Vector2(170, 50), 20)
	bk.pressed.connect(_show_pause_main)
	top.add_child(bk)
	top.add_child(UI.label("   AJUSTES", 30, Color.WHITE))
	v.add_child(OptionsPanel.build(profile, func(_k: String) -> void: _apply_settings(), true))

## Diagnóstico de rendimiento: se mide con el juego andando (sin pausa), mostrando sólo un cartel; al final se ve el informe y se copia
var _perf_text: TextEdit
func _show_perf() -> void:
	for c in pause_panel.get_children():
		if c is not ColorRect:
			c.queue_free()
	var panel := UI.panel(Vector2(1100, 0), UI.BG, 18, 14.0)
	panel.position = Vector2(90, 20)
	pause_panel.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var bk := UI.button("◀ VOLVER", Vector2(160, 48), 20)
	bk.pressed.connect(_show_pause_main)
	top.add_child(bk)
	var go := UI.button("MEDIR AHORA (≈25 s)", Vector2(300, 48), 20, true)
	top.add_child(go)
	var cp := UI.button("COPIAR INFORME", Vector2(240, 48), 20)
	top.add_child(cp)
	_perf_text = TextEdit.new()
	_perf_text.custom_minimum_size = Vector2(1060, 420)
	_perf_text.editable = false
	_perf_text.add_theme_font_size_override("font_size", 14)
	_perf_text.text = "Tocá MEDIR AHORA: el juego sigue andando y va apagando de a un sistema por vez para ver cuánto cuesta cada uno en tu teléfono.\nDejá el auto quieto mirando la parte del escenario donde anda más lento.\n\nMATERIALES EN PANTALLA (estimado):\n" + "\n".join(_probe().material_report(14))
	v.add_child(_perf_text)
	cp.pressed.connect(func() -> void: DisplayServer.clipboard_set(_perf_text.text))
	go.pressed.connect(func() -> void:
		_toggle_pause() # se mide jugando
		lbl_dmg.text = "MIDIENDO RENDIMIENTO… no toques nada (≈25 s)"
		var pr: Node = _probe()
		pr.run()
		var rep: String = await pr.finished
		profile["last_perf"] = rep
		Profile.save_profile(profile)
		if not paused:
			_toggle_pause()
		_show_perf()
		_perf_text.text = rep)

func _auto_perf() -> void:
	await get_tree().create_timer(2.0).timeout
	var pr: Node = _probe()
	pr.run()
	var rep: String = await pr.finished
	print(rep)
	get_tree().quit()

var _probe_node: Node
func _probe():
	if _probe_node == null:
		_probe_node = PerfProbe.new()
		_probe_node.game = self
		_probe_node.world = world
		_probe_node.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_probe_node)
	return _probe_node

func _toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	pause_panel.visible = paused
	cam_panel.visible = false
	if paused:
		_save_stats()
		_show_pause_main()

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				_toggle_pause()
			KEY_C:
				controls.camera_pressed.emit()
			KEY_R:
				respawn(false)

# ───────────────────────── ajustes ─────────────────────────
func _apply_settings() -> void:
	var S: Dictionary = profile["settings"]
	Gfx.apply_screen(get_tree(), S)
	var sh: String = String(S["shadows"])
	var sun: DirectionalLight3D = world.sun
	sun.shadow_enabled = sh != "off"
	if sh != "off":
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if sh == "baja" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = float(S.get("shadow_dist", 55.0))
		RenderingServer.directional_shadow_atlas_set_size({"baja": 1024, "media": 2048, "alta": 4096}[sh], true)
	# distancia de dibujo: lo que está más lejos no se calcula; la niebla tapa el corte
	var vd := float(S.get("view_dist", 650))
	cam.far = vd
	world.set_view_distance(vd)
	world.set_detail_distance(float(S.get("detail_dist", 1.0)))
	var parts_on := bool(S.get("particles_on", true))
	fx.visible = parts_on
	fx.intensity = clampf(float(S["particles"]), 0.0, 1.0) if parts_on else 0.0
	controls.steer_mode = String(S["steer_mode"])
	controls.wheel_real = int(S["wheel_real"])
	controls.gyro_on = bool(S["gyro"])
	controls.use_mph = bool(S["units_mph"])
	controls.manual = bool(S["manual"])
	if car != null:
		car.phys.manual = bool(S["manual"])
		var d: Dictionary = CarBuild.build_params(Garage.vehicles()[car_id], {"upg": {}, "tune": {}, "tires": "street", "tiresOwned": ["street"]},
			{"abs": bool(S["abs"]), "tc": float(S["tc"]), "stab": float(S["stab"])})
		car.phys.V = VehicleParams.from_dict(d)
		car.phys.setup()
	world.set_wind(float(S["wind"]))
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(S["volume"]) / 100.0, 0.0001, 1.0)))
	lbl_fps.visible = bool(S["show_fps"])
	if cockpit != null:
		cockpit.height = float(profile["pilot_height"])
		_apply_pilot_adj()
		_update_camera_mode()

func _update_camera_mode() -> void:
	if cockpit != null:
		cockpit.set_inside(rig.is_inside())
		# con las cámaras de afuera el piloto se puede ocultar (opción): no se calcula su pose ni se dibuja
		cockpit.set_visible(rig.is_inside() or bool(_S("pilot_outside")))

func _save_stats() -> void:
	Profile.save_profile(profile)

# ───────────────────────── bucle ─────────────────────────
func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	controls.update_inputs(dt)
	var thr := controls.gas
	var brk := controls.brake
	var st := controls.steer
	var hb := controls.handbrake
	if autotest and not drive:
		test_t += dt
	elif autotest:
		test_t += dt
		thr = 1.0 if test_t < 6.0 else 0.0
		brk = 0.0 if test_t < 6.0 else 1.0
		st = 0.0 if test_t < 2.0 else (0.8 if int(test_t * 0.8) % 2 == 0 else -0.8)
		hb = false
		if crash: # derecho a toda marcha: poste, y después el muro del fondo
			thr = 1.0
			brk = 0.0
			st = 0.0
	car.in_throttle = thr
	car.in_brake = brk
	car.in_steer = st
	car.in_handbrake = hb
	if controls.shift != 0:
		car.in_shift = controls.shift
	smooth_dt = lerpf(smooth_dt, dt, 0.02)
	acc = minf(acc + dt, 0.05)
	var n := int(acc / STEP)
	acc -= float(n) * STEP
	for i in n:
		sim_t += STEP
		car.step_and_record(STEP, sim_t)
	render_t = sim_t + acc - (smooth_dt * 1.3 + STEP)
	car.snap.sample(render_t)
	var p := car.snap
	var events := p.take_events()
	var impact := p.take_impact()
	visual.sync_from(p, dt, car.phys.V)
	world.set_car_transform(visual.global_transform)
	_handle_hits(car.take_impact(), p)
	world.process_breaks()
	cockpit.update(dt, p, car.in_handbrake)
	rig.aspect = get_viewport().get_visible_rect().size.aspect()
	rig.update(dt, p, false)
	if dbg_cam.size() == 6:
		var xf := visual.global_transform
		cam.global_position = xf * Vector3(dbg_cam[0], dbg_cam[1], dbg_cam[2])
		cam.look_at(xf * Vector3(dbg_cam[3], dbg_cam[4], dbg_cam[5]))
		cam.fov = 50.0
	fx.tick(cam.position)
	fx.emit_from(0, p, dt, car.phys.V.tireWidth * 0.5)
	audio.mix["eng"] = 1.0
	audio.update(p, car.phys.V, dt, events, impact)
	var spd := absf(p.vLong) * 3.6
	controls.speed_kmh = spd * (0.621371 if controls.use_mph else 1.0)
	controls.gear_text = "R" if p.gear < 0 else ("N" if p.gear == 0 else str(p.gear))
	controls.rpm_frac = p.rpm / car.phys.V.maxRpm
	visual.world_vel = Vector3(p.vx, p.vy, p.vz)
	# estadísticas
	var cur := Vector3(p.px, 0, p.pz)
	profile["stats"]["km"] = float(profile["stats"]["km"]) + cur.distance_to(last_pos) / 1000.0
	profile["stats"]["time"] = float(profile["stats"]["time"]) + dt
	profile["stats"]["top_kmh"] = maxf(float(profile["stats"]["top_kmh"]), spd)
	last_pos = cur
	_update_labels(spd, p)
	if autotest and shot_path != "" and not drive and test_t > shot_wait:
		_finish_autotest(spd)
	elif autotest and drive and test_t > 14.0:
		_finish_autotest(spd)

func _handle_hits(imp: Dictionary, p) -> void:
	if imp.is_empty():
		return
	var spd: float = imp["speed"]
	if spd < 1.2:
		return
	profile["stats"]["hits"] = int(profile["stats"]["hits"]) + 1
	var wpt := Vector3(float(imp["wx"]), p.py - car.phys.V.comHeight + 0.55, float(imp["wz"]))
	var ndir := Vector3(float(imp["nx"]), 0, float(imp["nz"]))
	var xf := visual.global_transform
	var lpt := xf.affine_inverse() * wpt
	var ldir := (xf.basis.inverse() * ndir).normalized()
	visual.hit(lpt, ldir, spd)
	var owner: Variant = imp.get("owner")
	if owner is CarVisual:
		var pv: CarVisual = owner
		pv.hit(pv.global_transform.affine_inverse() * wpt, (pv.global_transform.basis.inverse() * -ndir).normalized(), spd * 0.9)
	if String(imp.get("id", "")) == "tree":
		world.kick_tree(float(imp["wx"]), float(imp["wz"]), clampf(spd / 12.0, 0.2, 1.0))

var _lbl_t := 0.0
var _lbl_last := ["", "", ""]
func _update_labels(spd: float, p) -> void:
	_lbl_t -= get_process_delta_time()
	if _lbl_t > 0.0:
		return
	_lbl_t = 0.25 # (el texto se rearma 4 veces por segundo y sólo si cambió: la interfaz no gasta cuadro a cuadro)
	var stt := visual.status()
	var t0 := "%s  ·  cámara: %s" % [Garage.vehicles()[car_id]["name"], rig.cam_name()]
	var t1 := "%d FPS · %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())] if lbl_fps.visible else ""
	var t2 := ""
	if visual.damage_total > 0.5 or stt["gone"] > 0:
		t2 = "DAÑO %d%%  ·  piezas caídas: %d  ·  dañadas: %d" % [int(visual.damage_total), stt["gone"], stt["hurt"]]
	if t0 != _lbl_last[0]:
		lbl_info.text = t0
	if t1 != _lbl_last[1]:
		lbl_fps.text = t1
	if t2 != _lbl_last[2]:
		lbl_dmg.text = t2
	_lbl_last = [t0, t1, t2]

# ───────────────────────── pruebas automáticas / capturas ─────────────────────────

func _finish_autotest(spd: float) -> void:
	autotest = false
	print("PLAY AUTOTEST: pilot=%s auto=%s km=%.3f top=%.0f parts=%s dmg=%.0f cones=%d → OK" % [cockpit.ok, car_id, float(profile["stats"]["km"]), float(profile["stats"]["top_kmh"]), str(visual.status()), visual.damage_total, world.cones.size()])
	if cockpit.ok:
		var rp = cockpit.rig
		var hip_i: int = rp.B["Hips"]
		print("PILOTO: escala=%.3f raíz=%s hips(cabina)=%s cabeza=%s manoD=%s manoI=%s S=%s xD=%.2f eY=%.2f eZ=%.2f hip_y=%.2f" % [rp.s, str(rp.root.position), str(rp._fpos(hip_i)), str(rp._fpos(rp.B["Head"])), str(rp._fpos(rp.B["RightHand"])), str(rp._fpos(rp.B["LeftHand"])), str(cockpit.S), cockpit.xD, cockpit.eY, cockpit.eZ, cockpit.hip_y])
	if shot_path != "":
		get_viewport().get_texture().get_image().save_png(shot_path)
	get_tree().quit(0)
