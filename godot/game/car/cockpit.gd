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
	"mclaren_f1": {"dy": -0.02, "wheel_r": 0.155},
	"mclaren_f1_gtr": {},
	"aventador_s": {"dy": -0.06, "dz": -0.05, "wheel_r": 0.165},
	"ranger_limited": {"dy": -0.04},
	"rx3_savanna": {},
	"cls63_amg": {},
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

func _init(p_car: Node3D, p_char: String, p_height := 1.76) -> void:
	car = p_car
	meta = p_car.meta
	char_id = p_char
	height = p_height
	if not meta.has("steer_center"):
		return
	_measure()
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
	floor_y = clampf(S.y - 0.80, 0.08, 0.5)
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

func _spawn() -> void:
	var path := CHARS + char_id + ".glb"
	if not ResourceLoader.exists(path):
		return
	crew = Node3D.new()
	crew.name = "crew"
	car.model.add_child(crew)
	rig = RigPilot.new(crew, load(path), height)
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
	rig.pose({"hips": Vector3(x0 + b.x * 0.4 + jx * jit * 0.3, hy + b.y * 0.3 + jy * jit * 0.5 + 0.003 * sin(_time * 1.6), ez - 0.11 + b.z * 0.3),
		"head": Vector3(x0 + h.x, ey - 0.07 + h.y + brake_nod, ez - 0.09 + h.z), "roll": h.x * 1.2 - b.x * 0.5, "look": look, "look_y": -0.1 - brake_nod * 4.0,
		"hands": hands, "grip": 1.2 + 0.45 * maxf(sw, hw2),
		"feet": [{"side": "Left", "pos": Vector3(x0 + 0.13, floor_y + adj["y"] + 0.13, ez + 0.60)}, {"side": "Right", "pos": mo.right_foot(x0, floor_y + adj["y"], ez)}]})

## Para CameraRig._inside: posición / mirada en el marco del auto
func camera_local(m: String, p: CarSnapshot, time: float, rough: float) -> Dictionary:
	var eyep := Vector3(xD + adj["x"], eY + adj["y"], eZ + adj["z"])
	var cs: Vector3 = mo.cam_s
	var vib := 0.0009 * (0.4 + rough * 1.6) * minf(1.0, absf(p.vLong) / 20.0)
	if m == "rearcabin":
		var pos := Vector3(xD * 0.55 + adj["x"], eY + adj["y"] + 0.30, eZ + adj["z"] - 1.15) + cs * 0.4
		return {"pos": pos, "look": Vector3(xD * 0.5, eY - 0.10, eZ + 10.0), "roll": 0.0, "hfov": 100.0}
	var pos2 := eyep + Vector3(sin(time * 16.3) * vib, sin(time * 19.1 + 0.6) * vib, 0.0) + cs - Vector3(0, 0.07, 0.09)
	var yaw := look_yaw * 0.6
	var look := pos2 + Vector3(sin(yaw), -0.02, cos(yaw)) * 10.0
	return {"pos": pos2, "look": look, "roll": -cs.x * 0.6, "hfov": 100.0}
