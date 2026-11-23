extends "res://game/physics/track_base.gd"
## Física del estacionamiento de pruebas: altura del piso (lomadas, ondas, rampas, cordón, montículo de tierra), superficie (asfalto / tierra / pasto) y
## obstáculos (límites, autos estacionados, postes, árboles, barreras) que el auto de Car._keep_out esquiva con push().
##
## Las lomadas se describen UNA sola vez (features) y de ahí salen tanto la altura que ve la física (ground_info) como la malla que ve el jugador
## (lot_world.gd las arma muestreando feat_height): lo que se ve es exactamente lo que se siente.
##
## Marco: +X a la derecha del mapa (este), +Z hacia el norte del dibujo (abajo en la textura de marcas). El lote va de X −50..50 y Z −35..35.

const HALF := Vector2(50.0, 35.0)
const SURF_ASPHALT := 0
const SURF_DIRT := 1
const SURF_SHOULDER := 2
const SURF_GRASS := 3
const SURF_OUT := 4

## tipos de rasgo: hump (lomada redonda) · wash (serie de ondas) · ramp (rampa-meseta-rampa) · curb (escalón) · twist (rampa diagonal que inclina el auto) · mound (montículo de tierra) · bank (peralte)
var features: Array = []
var dirt_rects: Array = [] # Rect2 de tierra
var grass_rects: Array = []
var circles: Array = [] # {x, z, r, id, breakable, owner}
var boxes: Array = [] # {cx, cz, hx, hz, yaw}
var breaks: Array = [] # postes rotos desde la última consulta: {id, x, z, vx, vz}
var car_vx := 0.0 # velocidad del auto (la escribe Car._keep_out antes de consultar)
var car_vz := 0.0
var last_hit := {} # {id, owner, nx, nz, x, z}: el último obstáculo contra el que se apoyó el auto

func _init() -> void:
	_default_lot()

func _default_lot() -> void:
	# ── franja de suspensión (este): 4 carriles que se recorren hacia +X, con la entrada en x = 12
	# carril 1 (z −29): tres lomadas de 10 cm
	for i in 3:
		features.append({"t": "hump", "cx": 20.0 + i * 9.0, "cz": -29.0, "l": 3.2, "w": 4.2, "h": 0.10, "yaw": 0.0})
	# carril 2 (z −22): serie de ondas («chapa de serrucho», 12 ondas de 5 cm cada 1,4 m)
	features.append({"t": "wash", "cx": 28.0, "cz": -22.0, "l": 16.8, "w": 4.2, "h": 0.055, "n": 12, "yaw": 0.0})
	# carril 3 (z −15): rampa de 45 cm: sube 6 m, meseta 3 m, baja 6 m
	features.append({"t": "ramp", "cx": 28.0, "cz": -15.0, "l": 15.0, "w": 4.2, "h": 0.45, "up": 6.0, "top": 3.0, "yaw": 0.0})
	# carril 4 (z −8): cordón de 14 cm en un sentido y una lomada alta de 18 cm
	features.append({"t": "curb", "cx": 18.0, "cz": -8.0, "l": 0.6, "w": 4.2, "h": 0.14, "yaw": 0.0})
	features.append({"t": "hump", "cx": 34.0, "cz": -8.0, "l": 3.6, "w": 4.2, "h": 0.18, "yaw": 0.0})
	# rampa en diagonal: sube de un solo lado, inclina el auto (prueba de la barra estabilizadora)
	features.append({"t": "twist", "cx": 43.0, "cz": -15.0, "l": 9.0, "w": 6.0, "h": 0.32, "yaw": 0.0})
	# lomadas sueltas en la plaza (como las de un estacionamiento real)
	features.append({"t": "hump", "cx": -20.0, "cz": 0.0, "l": 3.0, "w": 8.0, "h": 0.09, "yaw": 0.0})
	features.append({"t": "hump", "cx": -20.0, "cz": 3.8, "l": 3.0, "w": 8.0, "h": 0.09, "yaw": 0.0})
	# peralte de drift: una curva elevada en el sector oeste
	features.append({"t": "bank", "cx": -38.0, "cz": -22.0, "l": 14.0, "w": 14.0, "h": 0.55, "yaw": 0.0})
	# ── tierra (este-norte): terreno, montículo y pozos suaves
	dirt_rects.append(Rect2(12.0, 2.0, 36.0, 31.0))
	features.append({"t": "mound", "cx": 38.0, "cz": 22.0, "l": 7.0, "w": 7.0, "h": 0.9, "yaw": 0.0})
	features.append({"t": "mound", "cx": 27.0, "cz": 12.0, "l": 5.0, "w": 5.0, "h": 0.35, "yaw": 0.0})
	features.append({"t": "wash", "cx": 22.0, "cz": 24.0, "l": 12.0, "w": 6.0, "h": 0.12, "n": 6, "yaw": 0.0, "dirt": true})
	# pasto: franjas a los costados del lote
	grass_rects.append(Rect2(-50.0, 31.0, 100.0, 4.0))
	grass_rects.append(Rect2(-50.0, -35.0, 4.0, 70.0))

# ───────────────────────── altura ─────────────────────────
static func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## altura del rasgo f en (x, z) (0 si está fuera de su rectángulo)
func feat_height(f: Dictionary, x: float, z: float) -> float:
	var dx := x - float(f["cx"])
	var dz := z - float(f["cz"])
	var yaw := float(f["yaw"])
	var u := dx
	var v := dz
	if yaw != 0.0:
		var c := cos(yaw)
		var s := sin(yaw)
		u = dx * c + dz * s
		v = -dx * s + dz * c
	var l := float(f["l"])
	var w := float(f["w"])
	if absf(u) > l * 0.5 or absf(v) > w * 0.5:
		return 0.0
	var h := float(f["h"])
	# los costados se afinan 25 cm para que la rueda no «caiga» a un escalón recto
	var edge := _smooth((w * 0.5 - absf(v)) / 0.3)
	match String(f["t"]):
		"hump":
			var t := cos(u / l * PI)
			return h * t * t * edge
		"wash":
			var n := int(f["n"])
			var ph := (u + l * 0.5) / l * float(n)
			var k := 0.5 - 0.5 * cos(ph * TAU)
			return h * k * edge
		"ramp":
			var up := float(f["up"])
			var top := float(f["top"])
			var x0 := -l * 0.5
			var p := u - x0
			if p < up:
				return h * (p / up) * edge
			if p < up + top:
				return h * edge
			return h * (1.0 - (p - up - top) / (l - up - top)) * edge
		"curb":
			return h * _smooth((l * 0.5 - absf(u)) / 0.14) * edge
		"twist":
			# rampa inclinada: la altura sube con la distancia al borde sur (v) y a lo largo (u)
			var a := clampf((u / l + 0.5), 0.0, 1.0)
			var b := clampf((v / w + 0.5), 0.0, 1.0)
			return h * minf(a * 2.0, 1.0) * b * minf((1.0 - a) * 3.0, 1.0)
		"mound":
			var r := sqrt((u / (l * 0.5)) * (u / (l * 0.5)) + (v / (w * 0.5)) * (v / (w * 0.5)))
			return h * maxf(0.0, 1.0 - r) * maxf(0.0, 1.0 - r) * (3.0 - 2.0 * maxf(0.0, 1.0 - r)) if r < 1.0 else 0.0
		"bank":
			# peralte: la mitad exterior de una curva circular sube hasta h
			var r2 := sqrt(u * u + v * v)
			var rr := l * 0.5
			return h * _smooth((r2 - rr * 0.35) / (rr * 0.65)) * (1.0 if r2 < rr else 0.0)
	return 0.0

func ground_info(x: float, z: float) -> Vector2:
	var h := 0.0
	for f in features:
		var cx: float = f["cx"]
		var cz: float = f["cz"]
		var m: float = maxf(float(f["l"]), float(f["w"])) * 0.75
		if absf(x - cx) > m or absf(z - cz) > m:
			continue
		h += feat_height(f, x, z)
	return Vector2(h, float(surface_at(x, z)))

func surface_at(x: float, z: float) -> int:
	if absf(x) > HALF.x or absf(z) > HALF.y:
		return SURF_OUT
	var p := Vector2(x, z)
	for r in dirt_rects:
		if (r as Rect2).has_point(p):
			return SURF_DIRT
	for r in grass_rects:
		if (r as Rect2).has_point(p):
			return SURF_GRASS
	return SURF_ASPHALT

# ───────────────────────── obstáculos ─────────────────────────
func add_circle(x: float, z: float, r: float, id := "", owner: Object = null, breakable := false) -> Dictionary:
	var c := {"x": x, "z": z, "r": r, "id": id, "owner": owner, "breakable": breakable, "on": true}
	circles.append(c)
	return c

func add_box(cx: float, cz: float, hx: float, hz: float, yaw := 0.0, id := "") -> void:
	boxes.append({"cx": cx, "cz": cz, "hx": hx, "hz": hz, "yaw": yaw, "id": id})

## Un auto (círculo x, z, radio r) contra el lote: devuelve Vector3(nx, nz, penetración) con la normal que lo saca del obstáculo; z ≤ 0 si no choca
func push(x: float, z: float, r: float) -> Vector3:
	var best := Vector3(0, 0, 0)
	# límites del lote
	var m := 0.6
	if x > HALF.x - m - r:
		best = _worse(best, Vector3(-1, 0, x - (HALF.x - m - r)), "wall", null)
	if x < -HALF.x + m + r:
		best = _worse(best, Vector3(1, 0, (-HALF.x + m + r) - x), "wall", null)
	if z > HALF.y - m - r:
		best = _worse(best, Vector3(0, -1, z - (HALF.y - m - r)), "wall", null)
	if z < -HALF.y + m + r:
		best = _worse(best, Vector3(0, 1, (-HALF.y + m + r) - z), "wall", null)
	for c in circles:
		if not c["on"]:
			continue
		var dx: float = x - float(c["x"])
		var dz: float = z - float(c["z"])
		var rr: float = r + float(c["r"])
		var d2 := dx * dx + dz * dz
		if d2 >= rr * rr:
			continue
		var spd := sqrt(car_vx * car_vx + car_vz * car_vz)
		if c["breakable"] and spd > 5.5:
			c["on"] = false # el poste se rompe: el auto sigue de largo (con un poco menos de velocidad: ver Car._keep_out → take_breaks)
			breaks.append({"id": c["id"], "x": c["x"], "z": c["z"], "vx": car_vx, "vz": car_vz})
			continue
		var d := sqrt(d2)
		var n := Vector2(dx, dz) / d if d > 0.0001 else Vector2(1, 0)
		best = _worse(best, Vector3(n.x, n.y, rr - d), String(c["id"]), c["owner"])
		last_hit["x"] = c["x"]
		last_hit["z"] = c["z"]
	for b in boxes:
		var hit := _push_box(b, x, z, r)
		if hit.z > 0.0:
			best = _worse(best, hit, String(b["id"]), null)
	return best

func _worse(cur: Vector3, nw: Vector3, id: String, owner: Object) -> Vector3:
	if nw.z > cur.z:
		last_hit = {"id": id, "owner": owner, "nx": nw.x, "nz": nw.y}
		return nw
	return cur

func _push_box(b: Dictionary, x: float, z: float, r: float) -> Vector3:
	var yaw := float(b["yaw"])
	var dx := x - float(b["cx"])
	var dz := z - float(b["cz"])
	var c := cos(yaw)
	var s := sin(yaw)
	var u := dx * c + dz * s
	var v := -dx * s + dz * c
	var hx := float(b["hx"])
	var hz := float(b["hz"])
	var qx := clampf(u, -hx, hx)
	var qz := clampf(v, -hz, hz)
	var ex := u - qx
	var ez := v - qz
	var d2 := ex * ex + ez * ez
	if d2 >= r * r:
		return Vector3(0, 0, 0)
	var nu := 0.0
	var nv := 0.0
	var pen := 0.0
	if d2 > 0.000001:
		var d := sqrt(d2)
		nu = ex / d
		nv = ez / d
		pen = r - d
	else: # el centro está dentro de la caja: sale por el lado más cercano
		var ox := hx - absf(u)
		var oz := hz - absf(v)
		if ox < oz:
			nu = 1.0 if u >= 0.0 else -1.0
			pen = ox + r
		else:
			nv = 1.0 if v >= 0.0 else -1.0
			pen = oz + r
	# de local a mundo
	return Vector3(nu * c - nv * s, nu * s + nv * c, pen)

func take_breaks() -> int:
	return 0 # (la cuenta de postes la lleva el mundo con pop_breaks; el auto no pierde velocidad por contarlos dos veces)

func pop_breaks() -> Array:
	var b := breaks
	breaks = []
	return b
