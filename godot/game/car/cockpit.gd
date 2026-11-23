extends RefCounted
## Habitáculo vivo: el piloto (esqueleto de Character Creator, ver rig_pilot.gd) sentado en el auto, con las manos en el volante (mano sobre mano),
## la mano a la palanca en cada cambio, el pie en el pedal, el cuerpo y la cabeza que se mueven con las fuerzas G (crew_motion.gd) y las
## cámaras de adentro (casco y atrás de las butacas).
## Todo se mide del modelo del auto (models/cars/<id>.json: centro y eje del volante): no hay números a ojo por auto salvo los de CABIN (ajuste fino).
## Marco: el del auto (+z adelante, +x izquierda, y desde el piso).

const RigPilot := preload("res://game/car/rig_pilot.gd")
const CrewMotion := preload("res://game/car/crew_motion.gd")
const CarSnapshot := preload("res://game/car/car_snapshot.gd")
const CHARS := "res://game/models/characters/"

## Ajuste fino por auto (todo opcional): dz/dy/dx mueven al piloto (m), eye_dy sube/baja los ojos, hip_dy la cadera, wheel_r radio del aro
const CABIN := {
	"mclaren_f1": {"dy": -0.02, "wheel_r": 0.155, "rc": [-0.12, 0.30, -0.45], "ped": [0.98, 0.27]}, # asiento central: la cámara va del lado del acompañante
	"mclaren_f1_gtr": {"rc": [-0.16, 0.46], "ped": [0.95, 0.28]},
	"aventador_s": {"dy": -0.06, "dz": -0.05, "wheel_r": 0.165, "rc": [-0.2, 0.46], "ped": [0.98, 0.27]},
	"ranger_limited": {"dy": -0.04},
	"rx3_savanna": {},
	"cls63_amg": {"hip": [-0.04, 0.60], "ped": [0.74, 0.30]}, # medido sobre el modelo: butaca, piso y pedales
}

var car: Node3D # CarVisual
var meta: Dictionary
var rig: RefCounted # RigPilot
var crew: Node3D
var mo := CrewMotion.new()
var ok := false
var S := Vector3.ZERO # centro del volante
var n_wheel := Vector3(0, 0.34, -0.94) # normal del aro (hacia el piloto)
var wheel_r := 0.19
var xD := 0.0
var eY := 1.0
var eZ := 0.0
var hip_y := 0.6
var floor_y := 0.1
var hip_z := 0.0
var ped_z := 0.6
var ped_y := 0.3
var knob := Vector3.ZERO
var hb_pos := Vector3.ZERO
var sh_i := 0 # mano que cambia: 0 derecha · 1 izquierda (autos con el volante a la derecha)
var mount := {}
var look_yaw := 0.0
var _time := 0.0
var char_id := ""
var height := 1.76
var crew_visible := true
var adj := {"x": 0.0, "y": 0.0, "z": 0.0} # ajuste del jugador del lugar del piloto (m)
var markers := {} # marcas de la cabina de este auto (ver cabin_markers.json): asiento, pedales, volante, palanca
var fit := {} # ajuste calculado por la marioneta de Blender (tools/blender/puppet_fit.py) para este auto y este piloto
var fit_scale := 1.0
var lean0 := -0.10
var lean1 := 0.18
var hip_tilt := -0.18

const MARKERS_PATH := "res://game/data/cabin_markers.json"
const FIT_PATH := "res://game/data/cabin_fit.json"
static var _markers_all := {}
static var _fit_all := {}

static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

static func markers_of(car_id: String, override := {}) -> Dictionary:
	if _markers_all.is_empty():
		_markers_all = _load_json(MARKERS_PATH)
	if override.has(car_id) and (override[car_id] as Dictionary).size() > 0:
		return override[car_id]
	return _markers_all.get(car_id, {})

func _init(p_car: Node3D, p_char: String, p_height := 1.76, p_override := {}) -> void:
	car = p_car
	meta = p_car.meta
	char_id = p_char
	height = p_height
	if not meta.has("steer_center"):
		return
	_measure()
	markers = markers_of(String(meta.get("id", "")), p_override)
	if not markers.is_empty():
		apply_markers(markers)
	# las manos agarran el volante que de verdad se ve y gira: su nodo (el centro de giro) y, si se separó por geometría, su radio real
	var sn: Node3D = p_car.get("steer_node")
	if sn != null:
		S = sn.position
		var rr: float = float(p_car.get("steer_radius_real"))
		if rr > 0.05:
			wheel_r = rr
	if _fit_all.is_empty():
		_fit_all = _load_json(FIT_PATH)
	fit = ((_fit_all.get(String(meta.get("id", "")), {}) as Dictionary).get(char_id, {})) as Dictionary
	if not fit.is_empty() and not bool(fit.get("ok", true)):
		fit = {} # el solver no logró alcanzar las marcas (marcas incoherentes): se usa el ajuste de siempre
	if not fit.is_empty():
		fit_scale = float(fit.get("scale", 1.0))
		hip_z += float(fit.get("dz", 0.0))
		hip_y += float(fit.get("dy", 0.0))
		lean0 = float(fit.get("lean0", lean0))
		lean1 = float(fit.get("lean1", lean1))
		hip_tilt = float(fit.get("hip_tilt", hip_tilt))
		eZ = hip_z + 0.11
	_spawn()

func _measure() -> void:
	var c: Array = meta["steer_center"]
	var o: Dictionary = CABIN.get(String(meta.get("id", "")), {})
	S = Vector3(c[0], c[1], c[2]) + Vector3(float(o.get("dx", 0.0)), float(o.get("dy", 0.0)), float(o.get("dz", 0.0)))
	var a: Array = meta.get("steer_axis", [0, 0.34, -0.94])
	n_wheel = Vector3(a[0], a[1], a[2]).normalized()
	wheel_r = float(o.get("wheel_r", clampf(float(meta.get("steer_radius", 0.19)), 0.15, 0.24)))
	xD = S.x
	# medidas de una butaca real respecto del volante: cadera ~0,52 m detrás del aro y ~0,36 m más abajo; ojos ~0,27 m arriba del centro del aro
	eZ = S.z - 0.42 + float(o.get("eye_dz", 0.0))
	eY = S.y + 0.27 + float(o.get("eye_dy", 0.0))
	hip_y = S.y - 0.36 + float(o.get("hip_dy", 0.0))
	floor_y = clampf(S.y - 0.74, 0.08, 0.6)
	# butaca y pedales: medidos en el modelo si el auto los tiene en CABIN («hip»: [z, y] de la cadera · «ped»: [z, y] de la almohadilla del pedal); si no, por la geometría típica
	var hp: Array = o.get("hip", [S.z - 0.53, S.y - 0.36])
	hip_z = float(hp[0])
	hip_y = float(hp[1]) if o.has("hip") else hip_y
	var pd: Array = o.get("ped", [S.z + 0.38, floor_y + 0.16])
	ped_z = float(pd[0])
	ped_y = float(pd[1])
	eZ = hip_z + 0.11
	var rhd := String(meta.get("drive_side", "L")) == "R"
	sh_i = 1 if rhd else 0
	var sgn := 1.0 if xD >= 0.0 else -1.0
	if absf(xD) < 0.1: # asiento central: la palanca queda a la derecha
		knob = Vector3(-0.30, S.y - 0.30, S.z - 0.15)
	else:
		knob = Vector3(xD - sgn * 0.44, S.y - 0.30, S.z - 0.15)
	hb_pos = knob + Vector3(0, -0.06, -0.30)
	# montajes de las cámaras de capó y paragolpes
	var bonnet: Dictionary = (meta.get("parts", {}) as Dictionary).get("bonnet", {})
	var front_z := float(meta.get("front_z", 2.3))
	if bonnet.has("center"):
		var bc: Array = bonnet["center"]
		var bs: Array = bonnet["size"]
		mount["hood"] = {"y": float(bc[1]) + float(bs[1]) * 0.5 + 0.07, "z": float(bc[2]) - float(bs[2]) * 0.1, "ly": -0.04}
	else:
		mount["hood"] = {"y": 0.95, "z": front_z - 1.2, "ly": -0.04}
	mount["bumper"] = {"y": 0.42, "z": front_z - 0.12, "ly": 0.0}

## Las marcas mandan sobre lo calculado: asiento (cadera), pedales, volante y palanca (todo en el marco del auto: +z adelante, +x izquierda, y desde el piso)
func apply_markers(m: Dictionary) -> void:
	markers = m
	if m.has("wheel"):
		var w: Dictionary = m["wheel"]
		var c: Array = w["center"]
		S = Vector3(c[0], c[1], c[2])
		if w.has("axis"):
			var a: Array = w["axis"]
			n_wheel = Vector3(a[0], a[1], a[2]).normalized()
		wheel_r = float(w.get("radius", wheel_r))
	if m.has("seat"):
		var h: Array = m["seat"]["hip"]
		xD = float(h[0])
		hip_y = float(h[1])
		hip_z = float(h[2])
		eZ = hip_z + 0.11
		eY = S.y + 0.27
		if m["seat"].has("eye_y"):
			eY = float(m["seat"]["eye_y"])
	if m.has("pedals"):
		var a2: Array = m["pedals"]["accel"]
		ped_z = float(a2[2])
		ped_y = float(a2[1])
	if m.has("shifter"):
		var k: Array = m["shifter"]
		knob = Vector3(k[0], k[1], k[2])
		hb_pos = knob + Vector3(0, -0.06, -0.30)
	if m.has("handbrake"):
		var hb: Array = m["handbrake"]
		hb_pos = Vector3(hb[0], hb[1], hb[2])
	if m.has("shift_hand"):
		sh_i = 1 if String(m["shift_hand"]) == "L" else 0

## Las marcas tal como están ahora (para copiarlas desde el juego)
func current_markers() -> Dictionary:
	return {
		"wheel": {"center": [snappedf(S.x, 0.001), snappedf(S.y, 0.001), snappedf(S.z, 0.001)], "axis": [snappedf(n_wheel.x, 0.001), snappedf(n_wheel.y, 0.001), snappedf(n_wheel.z, 0.001)], "radius": snappedf(wheel_r, 0.001)},
		"seat": {"hip": [snappedf(xD, 0.001), snappedf(hip_y, 0.001), snappedf(hip_z, 0.001)], "cushion_top": snappedf(hip_y - 0.14, 0.001), "back_z": snappedf(hip_z - 0.26, 0.001), "back_tilt_deg": 14, "eye_y": snappedf(eY, 0.001)},
		"pedals": {"accel": [snappedf(xD - 0.11, 0.001), snappedf(ped_y, 0.001), snappedf(ped_z, 0.001)], "brake": [snappedf(xD - 0.01, 0.001), snappedf(ped_y, 0.001), snappedf(ped_z, 0.001)], "rest": [snappedf(xD + 0.13, 0.001), snappedf(ped_y, 0.001), snappedf(ped_z - 0.02, 0.001)]},
		"shifter": [snappedf(knob.x, 0.001), snappedf(knob.y, 0.001), snappedf(knob.z, 0.001)],
		"handbrake": [snappedf(hb_pos.x, 0.001), snappedf(hb_pos.y, 0.001), snappedf(hb_pos.z, 0.001)],
		"shift_hand": "L" if sh_i == 1 else "R",
	}

func _spawn() -> void:
	var path := CHARS + char_id + ".glb"
	if not ResourceLoader.exists(path):
		return
	crew = Node3D.new()
	crew.name = "crew"
	car.model.add_child(crew)
	rig = RigPilot.new(crew, load(path), height * fit_scale)
	ok = rig.ok
	if not ok:
		crew.queue_free()

func dispose() -> void:
	if crew != null and is_instance_valid(crew):
		crew.queue_free()
	ok = false

func set_inside(v: bool) -> void:
	if ok:
		rig.hide_head(v)

func set_visible(v: bool) -> void:
	crew_visible = v
	if crew != null:
		crew.visible = v

func _jit_noise(t: float, a: float, b: float) -> float:
	return sin(t * a) * 0.6 + sin(t * b + 1.1) * 0.4

## p: CarSnapshot interpolado
func update(dt: float, p: CarSnapshot, hb: bool) -> void:
	_time += dt
	mo.step_forces(dt, p)
	mo.step_limbs(dt, p)
	mo.step_gear(dt, p.gear)
	if not ok or not crew_visible:
		return
	var x0: float = xD + float(adj["x"])
	var hy: float = hip_y + float(adj["y"])
	var ez: float = eZ + float(adj["z"])
	var ey: float = eY + float(adj["y"])
	var hz: float = hip_z + float(adj["z"])
	var pz: float = ped_z + float(adj["z"])
	var py: float = ped_y + float(adj["y"])
	var sp := clampf(absf(p.vLong) / 30.0, 0.0, 1.0)
	var jit := 0.0016 * sp
	var jy := _jit_noise(_time, 43.0, 27.0)
	var jx := _jit_noise(_time, 37.0, 21.0)
	mo.steer_vis += (p.steerAngle * 7.5 - mo.steer_vis) * (1.0 - exp(-dt * 25.0))
	var shift_busy := CrewMotion.shift_w(mo.shift_t) > 0.45 or mo.hbW > 0.45
	var busy := [false, false]
	busy[sh_i] = shift_busy
	mo.step_grip(dt, mo.steer_vis, busy)
	# manos en el aro
	var n := n_wheel
	var wX := Vector3.UP.cross(n).normalized()
	var wY := n.cross(wX)
	var hands := []
	for i in 2:
		var ph: float = mo.phi[i]
		var gp := S + Vector3(adj["x"], adj["y"], adj["z"]) + wX * (cos(ph) * wheel_r) + wY * (sin(ph) * wheel_r) + n * float(mo.lift[i])
		var rr := (gp - S - Vector3(adj["x"], adj["y"], adj["z"])).normalized()
		hands.append({"side": "Right" if i == 0 else "Left", "wrist": gp + n * 0.075 + rr * 0.05, "fdir": (rr * -0.15 + n * -0.85).normalized(), "back": (rr * 0.9 + n * 0.25).normalized(), "pole": Vector3(0.55, -0.55, -0.30)})
	var sw := CrewMotion.shift_w(mo.shift_t)
	var hr: Dictionary = hands[sh_i]
	var mirror := -1.0 if sh_i == 1 else 1.0
	if sw > 0.0:
		var kp := knob + Vector3(adj["x"], adj["y"], adj["z"])
		kp.z += -0.05 if mo.shift_up else 0.05
		hr["wrist"] = (hr["wrist"] as Vector3).lerp(kp + Vector3(0.05 * mirror, 0.075, -0.075), sw)
		hr["fdir"] = (hr["fdir"] as Vector3).lerp(Vector3(-0.2 * mirror, -0.75, 0.6).normalized(), sw).normalized()
		hr["back"] = (hr["back"] as Vector3).lerp(Vector3(-0.5 * mirror, 0.8, -0.2).normalized(), sw).normalized()
		hr["pole"] = (hr["pole"] as Vector3).lerp(Vector3(0.45, -0.25, -0.6), sw)
	var hw2: float = mo.hbW * (1.0 - sw)
	if hw2 > 0.01:
		var gp2 := hb_pos + Vector3(adj["x"], adj["y"], adj["z"])
		hr["wrist"] = (hr["wrist"] as Vector3).lerp(gp2 + Vector3(0.05 * mirror, 0.06, -0.05), hw2)
		hr["fdir"] = (hr["fdir"] as Vector3).lerp(Vector3(-0.1 * mirror, -0.6, 0.8).normalized(), hw2).normalized()
		hr["back"] = (hr["back"] as Vector3).lerp(Vector3(-0.9 * mirror, 0.3, 0).normalized(), hw2).normalized()
		hr["pole"] = (hr["pole"] as Vector3).lerp(Vector3(0.35, -0.2, -0.8), hw2)
	var b: Vector3 = mo.body
	var h: Vector3 = mo.head
	var look := clampf(p.steerAngle * 0.45 + p.yawRate * 0.06, -0.35, 0.35) * (1.0 - maxf(sw, hw2) * 0.3)
	look_yaw = look
	var brake_nod := clampf(-p.aLong * 0.004, -0.02, 0.05)
	rig.pose({"hips": Vector3(x0 + b.x * 0.4 + jx * jit * 0.3, hy + b.y * 0.3 + jy * jit * 0.5 + 0.003 * sin(_time * 1.6), hz + b.z * 0.3),
		"head": Vector3(x0 + h.x, ey - 0.07 + h.y + brake_nod, ez - 0.09 + h.z), "roll": h.x * 1.2 - b.x * 0.5, "lean0": lean0, "lean1": lean1, "hip_tilt": hip_tilt, "look": look, "look_y": -0.1 - brake_nod * 4.0,
		"hands": hands, "grip": 1.2 + 0.45 * maxf(sw, hw2),
		"feet": [{"side": "Left", "pos": Vector3(x0 + 0.13, py, pz - 0.02)}, {"side": "Right", "pos": mo.right_foot(x0, py - 0.13, pz - 0.62)}]})

## Para CameraRig._inside: posición / mirada en el marco del auto
func camera_local(m: String, p: CarSnapshot, time: float, rough: float) -> Dictionary:
	var eyep := Vector3(xD + adj["x"], eY + adj["y"], eZ + adj["z"])
	var cs: Vector3 = mo.cam_s
	var vib := 0.0009 * (0.4 + rough * 1.6) * minf(1.0, absf(p.vLong) / 20.0)
	if m == "rearcabin":
		# tercera persona adentro: centrada, detrás y por encima de las dos butacas (se ven los dos asientos, el piloto y el tablero)
		# (biplazas: detrás de las butacas está el motor; la cámara se arrima a la mampara — CABIN «rc»: [subir, adelantar])
		var rc: Array = (CABIN.get(String(meta.get("id", "")), {}) as Dictionary).get("rc", [0.0, 0.0])
		var pos := Vector3(float(rc[2]) if rc.size() > 2 else 0.0, eY + 0.16 + float(rc[0]), eZ - 0.80 + float(rc[1])) + cs * 0.4
		return {"pos": pos, "look": Vector3(0.0, eY - 0.25, eZ + 6.0), "roll": 0.0, "hfov": 105.0}
	var pos2 := eyep + Vector3(sin(time * 16.3) * vib, sin(time * 19.1 + 0.6) * vib, 0.0) + cs - Vector3(0, 0.07, 0.09)
	var yaw := look_yaw * 0.6
	var look := pos2 + Vector3(sin(yaw), -0.02, cos(yaw)) * 10.0
	return {"pos": pos2, "look": look, "roll": -cs.x * 0.6, "hfov": 100.0}
