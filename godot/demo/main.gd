## DEMO MÍNIMA del sistema de conducción de Dream Racing.
## Pista plana infinita + auto sin modelo (caja y 4 ruedas) con: física propia a 120 Hz, suspensión de 4 ruedas,
## cámaras de seguimiento con ajuste, marcas de frenada y humo/polvo, sonido de motor por capas y controles
## táctiles con volante / pedal único / palanca / freno de mano que se pueden vestir con PNG (demo/hud/*.png).
##
## Teclado: W/↑ gas · S/↓ freno · A D / ← → dirección · ESPACIO freno de mano · E/Q sube/baja marcha (con M manual)
##          C cámara siguiente · M caja manual/automática · P PNG sí/no · R reiniciar · 1-4 cambia de auto · ESC salir
## Línea de comandos (después de «--»):  --car=<id de vehicles.json> --autotest --shot=<ruta.png> --noaudio
extends Node3D

const VehicleParams := preload("res://game/physics/vehicle_params.gd")
const FlatTrack := preload("res://game/physics/flat_track.gd")
const Car := preload("res://game/car/car.gd")
const CameraRig := preload("res://game/car/camera_rig.gd")
const Effects := preload("res://game/fx/effects.gd")
const CarAudio := preload("res://game/audio/car_audio.gd")
const Controls := preload("res://game/ui/controls.gd")
const CarBuild := preload("res://game/data/car_build.gd")
const Graphics := preload("res://demo/graphics.gd")

const STEP := 1.0 / 120.0 # la física SIEMPRE a 120 Hz (se interpola al dibujar)
const CARS := ["hatch", "gt", "genesis", "pickup"] # teclas 1-4

var vehicles: Dictionary
var tune := {} # reglaje manual: --tune=springs:70,arb:60 (ver docs/03)
var track := FlatTrack.new()
var car: Car
var car_id := "hatch"
var body: Node3D # el «modelo» del auto (caja + ruedas): reemplazalo por tu .glb
var wheel_nodes: Array[Node3D] = []
var cam: Camera3D
var rig: CameraRig
var fx: Effects
var audio: CarAudio
var controls: Controls
var sun: DirectionalLight3D
var gfx := Graphics.new()
var label: Label

var acc := 0.0
var sim_t := 0.0
var render_t := 0.0
var smooth_dt := 1.0 / 60.0
var manual := false
var autotest := false
var shot_path := ""
var test_t := 0.0
var max_speed := 0.0
var marks_seen := false
var events_seen := 0
var shot_done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			car_id = a.substr(6)
		elif a.begins_with("--tune="):
			for kv in a.substr(7).split(","):
				var pr := kv.split(":")
				if pr.size() == 2:
					tune[pr[0]] = float(pr[1])
		elif a == "--autotest":
			autotest = true
		elif a.begins_with("--shot="):
			shot_path = a.substr(7)
	vehicles = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/vehicles.json"))
	_build_world()
	_spawn_car(car_id)
	_build_hud()
	gfx.apply(self, sun, get_viewport(), fx)
	if "--noaudio" in OS.get_cmdline_user_args():
		AudioServer.set_bus_mute(0, true)

# ───────────────────────── mundo ─────────────────────────
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	# piso: tablero de ajedrez para sentir la velocidad (la física lo ve como asfalto plano: ground_info(x,z) = (0, superficie 0))
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var c := ((x / 32) + (y / 32)) % 2
			img.set_pixel(x, y, Color(0.30, 0.31, 0.33) if c == 0 else Color(0.36, 0.37, 0.4))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_scale = Vector3(400, 400, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	plane.mesh = pm
	plane.material_override = mat
	add_child(plane)
	# conos de referencia
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.35
	cone.height = 0.7
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.45, 0.05)
	for i in 24:
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = cmat
		mi.position = Vector3(((i % 2) * 2 - 1) * 12.0, 0.35, 25.0 + float(i / 2) * 18.0)
		add_child(mi)
	cam = Camera3D.new()
	cam.far = 1500.0
	add_child(cam)
	fx = Effects.new()
	add_child(fx)
	fx.setup(track)
	fx.prepare(0)
	rig = CameraRig.new(cam, track)
	rig.set_preset(1)

# ───────────────────────── auto ─────────────────────────
## Parámetros finales = vehicles.json + piezas/reglajes (CarBuild.build_params). Sin piezas ni reglaje: {}
func _params_for(id: String) -> VehicleParams:
	# El «estado del auto» es lo que guarda el jugador: mejoras compradas (upg), reglaje (tune, en %), cubiertas.
	# CarBuild.build_params los combina con la ficha base de vehicles.json y devuelve el Dictionary final de la física.
	var state := {"upg": {}, "tune": tune, "tires": "street", "tiresOwned": ["street"]}
	var d: Dictionary = CarBuild.build_params(vehicles[id], state, {"abs": true, "tc": 50.0, "stab": 30.0})
	return VehicleParams.from_dict(d)

func _spawn_car(id: String) -> void:
	car_id = id
	var params := _params_for(id)
	car = Car.new(track, params, true)
	car.phys.tc_free_spin = false
	car.phys.manual = manual
	car.place(0.0, 0.0, 0.0)
	car.restart_history(0.0)
	sim_t = 0.0
	acc = 0.0
	if body != null:
		body.queue_free()
	body = _make_body(params)
	add_child(body)
	car.visual = null # (si tu modelo tiene sync_from(snap, dt), asignalo acá)
	rig.visual = body
	rig.set_preset(rig.index)
	fx.reset()
	if audio != null:
		audio.queue_free()
	audio = CarAudio.new()
	audio.set_vehicle(id)
	add_child(audio)

func _make_body(V: VehicleParams) -> Node3D:
	var root := Node3D.new()
	var chassis := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(V.trackF + 0.2, 0.5, V.wheelBase + 1.0)
	chassis.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.12, 0.1)
	chassis.material_override = m
	chassis.position.y = 0.0
	root.add_child(chassis)
	var cab := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(V.trackF - 0.1, 0.45, V.wheelBase * 0.5)
	cab.mesh = cm
	cab.material_override = m
	cab.position = Vector3(0, 0.45, -0.1)
	root.add_child(cab)
	wheel_nodes.clear()
	var wm := CylinderMesh.new()
	wm.top_radius = V.wheelRadius
	wm.bottom_radius = V.wheelRadius
	wm.height = 0.25
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.05, 0.05, 0.06)
	for i in 4:
		var steer := Node3D.new() # gira con la dirección (sólo las delanteras)
		var spin := Node3D.new() # gira rodando
		var mi := MeshInstance3D.new()
		mi.mesh = wm
		mi.material_override = tm
		mi.rotation.z = PI * 0.5 # el cilindro de Godot es vertical: lo acostamos para que el eje sea X
		spin.add_child(mi)
		steer.add_child(spin)
		var w = car.phys.wheels[i]
		steer.position = Vector3(w.x, 0.0, w.z)
		root.add_child(steer)
		wheel_nodes.append(steer)
	return root

## Igual que CarVisual.sync_from de Dream Racing: posición, orientación (YXZ) y por rueda la altura de la suspensión, el giro de la dirección y el rodado.
func _sync_body(dt: float) -> void:
	var p := car.snap
	body.position = Vector3(p.px, p.py, p.pz)
	body.basis = Basis.from_euler(Vector3(p.pitch, p.yaw, p.roll), EULER_ORDER_YXZ)
	var V := car.phys.V
	var base := V.comHeight + V.hardpointY - V.rideOffset
	for i in 4:
		var steer := wheel_nodes[i]
		steer.position.y = base - p.wheel_s[i]
		if car.phys.wheels[i].front:
			steer.rotation.y = p.steerAngle
		var spin: Node3D = steer.get_child(0)
		spin.rotation.x += p.wheel_omega[i] * dt

# ───────────────────────── HUD ─────────────────────────
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	controls = Controls.new()
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(controls)
	var n := controls.load_skin("res://demo/hud")
	print("HUD: %d PNG cargados de res://demo/hud" % n)
	controls.manual = manual
	label = Label.new()
	label.position = Vector2(8, 4)
	label.add_theme_font_size_override("font_size", 14)
	layer.add_child(label)

# ───────────────────────── bucle ─────────────────────────
func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match e.keycode:
		KEY_C:
			# en el juego hay 9 cámaras; sin habitáculo ni anclajes sólo sirven las de seguimiento y la libre (índices 1-5)
			var n := rig.index + 1
			rig.set_preset(1 if n > 5 else n)
		KEY_M:
			manual = not manual
			controls.manual = manual # muestra los botones SUBIR / BAJAR
			car.phys.manual = manual # la caja de la física pasa a manual (en el juego lo hace race.gd según la opción «Caja de cambios»)
		KEY_P:
			if controls.skin.is_empty():
				controls.load_skin("res://demo/hud")
			else:
				controls.skin.clear()
				controls.queue_redraw()
		KEY_R:
			car.place(0.0, 0.0, 0.0)
			fx.reset()
		KEY_1, KEY_2, KEY_3, KEY_4:
			_spawn_car(CARS[e.keycode - KEY_1])
		KEY_ESCAPE:
			get_tree().quit()

func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	controls.update_inputs(dt)
	var thr := controls.gas
	var brk := controls.brake
	var st := controls.steer
	var hb := controls.handbrake
	if autotest:
		test_t += dt
		thr = 1.0
		brk = 0.0
		st = 0.0 if test_t < 4.0 else (0.7 if int(test_t) % 2 == 0 else -0.7) # recto, y después zigzag para dejar marcas
		hb = test_t > 9.0 and test_t < 9.6
	car.in_throttle = thr
	car.in_brake = brk
	car.in_steer = st
	car.in_handbrake = hb
	if controls.shift != 0:
		car.in_shift = controls.shift
	# acumulador a 120 Hz; el auto se dibuja un poco ATRASADO (render_t) entre dos pasos ya calculados
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
	events_seen += events.size()
	_sync_body(dt)
	rig.aspect = get_viewport().get_visible_rect().size.aspect()
	rig.update(dt, p, false)
	fx.tick(cam.position)
	fx.emit_from(0, p, dt, 0.325)
	audio.mix["eng"] = 1.0
	audio.update(p, car.phys.V, dt, events, impact)
	var spd := absf(p.vLong) * 3.6
	controls.speed_kmh = spd
	controls.gear_text = "R" if p.gear < 0 else ("N" if p.gear == 0 else str(p.gear))
	controls.rpm_frac = p.rpm / car.phys.V.maxRpm
	max_speed = maxf(max_speed, spd)
	label.text = "%s · %.0f km/h · marcha %s · %.0f rpm · cam: %s · %.0f FPS · %s" % [car_id, spd, controls.gear_text, p.rpm, rig.cam_name(), Engine.get_frames_per_second(), "MANUAL" if manual else "AUTO"]
	if autotest and shot_path != "" and test_t > 8.5 and not shot_done:
		shot_done = true # captura en pleno zigzag (se ven las marcas y el humo)
		get_viewport().get_texture().get_image().save_png(shot_path)
	if autotest and test_t > 12.0:
		_finish_autotest()

func _finish_autotest() -> void:
	autotest = false
	var marks := 0
	for i in Effects.MARKS: # cuántas tiras de marca de frenada hay dibujadas (las ocultas están en y = -999)
		if fx._marks.get_instance_transform(i).origin.y > -900.0:
			marks += 1
	print("marcas de frenada dibujadas: %d de %d" % [marks, Effects.MARKS])
	var ok := max_speed > 80.0 and events_seen > 0 and marks > 0
	print("AUTOTEST: auto=%s vmax=%.0f km/h eventos_de_fisica=%d skin_png=%d → %s" % [car_id, max_speed, events_seen, controls.skin.size(), "OK" if ok else "FALLA"])
	get_tree().quit(0 if ok else 1)
