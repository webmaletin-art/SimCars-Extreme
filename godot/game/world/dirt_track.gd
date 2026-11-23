extends "res://game/world/lot_track.gd"
## Camino de tierra: circuito cerrado (curva suave por puntos de control), con zona de tierra, banquina, charcos de barro, lomos, ondas y un cerco de madera a cada
## lado que el auto no puede cruzar. La misma curva arma la malla del camino y los cercos (dirt_world.gd).
##
## Superficies: tierra (1) en el camino, banquina (2) entre el camino y el cerco, barro (5) en los charcos.

const ROAD_HALF := 4.4 # semiancho del camino (m)
const FENCE_HALF := 8.8 # distancia del eje al cerco (m): está ARRIBA del talud, a 1,2 m del borde de la meseta
const BANK_FROM := 4.2 # donde empieza a subir el talud (m desde el eje)
const BANK_LEN := 3.4 # largo en planta del talud (m)
const CELL := 24.0

## puntos de control del eje (x, z) en metros; la curva pasa por todos y se cierra
const CTRL := [Vector2(0, 0), Vector2(60, -6), Vector2(130, -6), Vector2(190, 16), Vector2(218, 62), Vector2(192, 108), Vector2(140, 122), Vector2(102, 96), Vector2(80, 60),
	Vector2(40, 50), Vector2(2, 76), Vector2(-44, 122), Vector2(-100, 128), Vector2(-146, 96), Vector2(-152, 42), Vector2(-112, 4), Vector2(-56, -16)]

var pts: PackedVector2Array = PackedVector2Array() # eje muestreado (~2 m)
var tans: PackedVector2Array = PackedVector2Array()
var cum: PackedFloat32Array = PackedFloat32Array()
var length := 0.0
var _grid := {}
var mud: Array = [] # {x, z, r}
var curv: PackedFloat32Array = PackedFloat32Array() # curvatura firmada por punto (1/m)
var hprof: PackedFloat32Array = PackedFloat32Array() # altura del eje por punto (lomas suaves: pendiente máxima ~7 %)
var bank: PackedFloat32Array = PackedFloat32Array() # altura del talud sobre el camino por punto: el camino va hundido entre dos taludes de tierra (0,3 a 1,45 m)
var holes: Array = [] # {x, z, r, depth, water}
var coarse: PackedVector3Array = PackedVector3Array() # (x, z, altura) cada ~10 m: para el terreno lejano
const CROWN := 0.045 # el camino es más alto en el medio (desagote)
const DITCH := 0.11 # profundidad de la zanja de la banquina

func _default_lot() -> void:
	pass # (el estacionamiento: acá no hay nada; el camino se arma en _init, cuando ya existen las variables de esta clase)

func _init() -> void:
	_sample()
	_setup()

## Hooks para los circuitos que heredan (asfalto): puntos de control, altura del eje, anchos y perfil transversal
func _ctrl() -> Array:
	return CTRL

func _elev(u: float) -> float:
	return 2.4 * sin(TAU * 2.0 * u + 0.5) + 1.5 * sin(TAU * 3.0 * u + 1.7) + 0.8 * sin(TAU * 5.0 * u + 0.3) + 0.45 * sin(TAU * 8.0 * u + 2.0)

func road_half() -> float:
	return ROAD_HALF

func fence_half() -> float:
	return FENCE_HALF

## desde qué distancia del eje crece el pasto suelto (la banquina)
func tuft_lo() -> float:
	return 4.6

func profile(lat: float) -> float:
	return cross_profile(lat)

## Perfil transversal del punto i (camino hundido con taludes)
func profile_at(i: int, lat: float) -> float:
	return bank_profile(lat, float(bank[i]))

## altura del talud (m) según el avance u (0..1): varía a lo largo del camino, a veces casi a nivel y a veces bien hundido
func _bank(u: float) -> float:
	return clampf(0.85 + 0.5 * sin(TAU * 3.0 * u + 0.7) + 0.22 * sin(TAU * 7.0 * u + 2.1), 0.3, 1.45)

func _setup() -> void:
	# lomos y ondas sobre el camino (cada rasgo se alinea con el eje: yaw = ángulo de la tangente)
	_feature_at(0.17, "hump", 3.0, 0.07)
	_feature_at(0.33, "wash", 14.0, 0.05, 10)
	_feature_at(0.52, "hump", 3.4, 0.10)
	_feature_at(0.64, "wash", 12.0, 0.06, 9)
	_feature_at(0.80, "hump", 3.0, 0.08)
	_feature_at(0.92, "wash", 10.0, 0.05, 8)
	var hr := RandomNumberGenerator.new()
	hr.seed = 7717
	for k in 26:
		var i2 := hr.randi() % pts.size()
		var tg2 := tans[i2]
		var n2 := Vector2(-tg2.y, tg2.x)
		var off2 := hr.randf_range(-3.0, 3.0)
		var r2 := hr.randf_range(0.45, 1.0)
		var water := hr.randf() < 0.4
		var hx: float = pts[i2].x + n2.x * off2
		var hz: float = pts[i2].y + n2.y * off2
		holes.append({"x": hx, "z": hz, "r": r2, "depth": hr.randf_range(0.05, 0.13), "water": water})
		features.append({"t": "pothole", "cx": hx, "cz": hz, "l": r2 * 2.0, "w": r2 * 2.0, "h": float(holes[holes.size() - 1]["depth"]), "yaw": 0.0, "dirt": true})
		if water:
			mud.append({"x": hx, "z": hz, "r": r2 * 0.95})
	for t in [0.12, 0.27, 0.45, 0.58, 0.74, 0.88]:
		var i := int(t * pts.size())
		var off := (1.0 if int(t * 100) % 2 == 0 else -1.0) * 0.8
		var n := Vector2(-tans[i].y, tans[i].x)
		mud.append({"x": pts[i].x + n.x * off, "z": pts[i].y + n.y * off, "r": 3.2})

func _feature_at(t: float, kind: String, l: float, h: float, n := 0) -> void:
	var i := int(t * pts.size()) % pts.size()
	var tg := tans[i]
	var f := {"t": kind, "cx": pts[i].x, "cz": pts[i].y, "l": l, "w": ROAD_HALF * 2.0 + 0.4, "h": h, "yaw": atan2(tg.y, tg.x) * -1.0 + 0.0, "dirt": true}
	if n > 0:
		f["n"] = n
	# feat_height usa u = dx·cos + dz·sin (eje del rasgo a lo largo de yaw): yaw = ángulo de la tangente en el plano (x, z)
	f["yaw"] = atan2(tg.y, tg.x)
	features.append(f)

## Catmull-Rom cerrada, muestreada cada ~2 m
func _sample() -> void:
	var CT := _ctrl()
	var n := CT.size()
	var raw := PackedVector2Array()
	for i in n:
		var p0: Vector2 = CT[(i - 1 + n) % n]
		var p1: Vector2 = CT[i]
		var p2: Vector2 = CT[(i + 1) % n]
		var p3: Vector2 = CT[(i + 2) % n]
		for k in 24:
			var t := float(k) / 24.0
			var t2 := t * t
			var t3 := t2 * t
			raw.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	# remuestreo a paso constante
	pts = PackedVector2Array()
	var acc := 0.0
	pts.append(raw[0])
	for i in range(1, raw.size() + 1):
		var a: Vector2 = raw[i - 1]
		var b: Vector2 = raw[i % raw.size()]
		var seg := a.distance_to(b)
		acc += seg
		if acc >= 2.0:
			acc = 0.0
			pts.append(b)
	if pts[pts.size() - 1].distance_to(pts[0]) < 1.0:
		pts.remove_at(pts.size() - 1)
	var m := pts.size()
	tans = PackedVector2Array()
	cum = PackedFloat32Array()
	curv = PackedFloat32Array()
	var c := 0.0
	for i in m:
		tans.append((pts[(i + 1) % m] - pts[(i - 1 + m) % m]).normalized())
		cum.append(c)
		c += pts[i].distance_to(pts[(i + 1) % m])
	length = c
	for i in m:
		var a2 := atan2(tans[i].y, tans[i].x)
		var b2 := atan2(tans[(i + 3) % m].y, tans[(i + 3) % m].x)
		curv.append(wrapf(b2 - a2, -PI, PI) / maxf(0.1, pts[i].distance_to(pts[(i + 3) % m])))
	hprof = PackedFloat32Array()
	for i in m:
		var u := float(cum[i]) / length
		hprof.append(_elev(u))
	bank = PackedFloat32Array()
	for i in m:
		bank.append(_bank(float(cum[i]) / length))
	coarse = PackedVector3Array()
	for i in range(0, m, 5):
		coarse.append(Vector3(pts[i].x, pts[i].y, hprof[i]))
	_grid.clear()
	for i in m:
		var key := Vector2i(int(floor(pts[i].x / CELL)), int(floor(pts[i].y / CELL)))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)

## Punto más cercano del eje: devuelve {i, d (distancia), side (+ izquierda del sentido de marcha), t}
func nearest(x: float, z: float) -> Dictionary:
	var best := 1e18
	var bi := 0
	var cx := int(floor(x / CELL))
	var cz := int(floor(z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var lst: Array = _grid.get(Vector2i(cx + dx, cz + dz), [])
			for i in lst:
				var q: Vector2 = pts[i]
				var d2 := (q.x - x) * (q.x - x) + (q.y - z) * (q.y - z)
				if d2 < best:
					best = d2
					bi = i
	if best > 1e17: # lejos de todo (fuera de la grilla): búsqueda completa
		for i in pts.size():
			var q2: Vector2 = pts[i]
			var d3 := (q2.x - x) * (q2.x - x) + (q2.y - z) * (q2.y - z)
			if d3 < best:
				best = d3
				bi = i
	var tg := tans[bi]
	var rel := Vector2(x, z) - pts[bi]
	var side := rel.x * -tg.y + rel.y * tg.x
	return {"i": bi, "d": sqrt(best), "side": side, "tan": tg}

## Altura del eje interpolada entre los dos puntos vecinos (sin escalones cada 2 m)
func axis_height(nr: Dictionary, x: float, z: float) -> float:
	var i: int = nr["i"]
	var m := pts.size()
	var tg: Vector2 = nr["tan"]
	var tproj := ((x - pts[i].x) * tg.x + (z - pts[i].y) * tg.y) / 2.0
	if tproj >= 0.0:
		return lerpf(hprof[i], hprof[(i + 1) % m], minf(tproj, 1.0))
	return lerpf(hprof[i], hprof[(i - 1 + m) % m], minf(-tproj, 1.0))

## Perfil de camino rural hundido: corona leve, dos huellas de rueda y un lomo en el medio, y a los costados talud de tierra (rampa suave) que sube hasta la meseta del cerco
static func bank_profile(lat: float, B: float) -> float:
	var a := absf(lat)
	var h := 0.0
	if a < 4.8:
		h += CROWN * (1.0 - minf(1.0, (a / 4.4) * (a / 4.4)))
		h -= 0.042 * exp(-pow((a - 0.92) / 0.32, 2.0)) # huellas de las ruedas
		h += 0.02 * exp(-pow(a / 0.35, 2.0)) # lomo central
	var t := clampf((a - BANK_FROM) / BANK_LEN, 0.0, 1.0)
	h += B * t * t * (3.0 - 2.0 * t)
	return h

## (perfil viejo con zanja: lo usa el estacionamiento de pruebas del kit y el asfalto no)
static func cross_profile(lat: float) -> float:
	var a := absf(lat)
	var h := 0.0
	if a < 4.6:
		h += CROWN * (1.0 - (a / 4.4) * (a / 4.4))
		h -= 0.032 * exp(-pow((a - 0.92) / 0.3, 2.0)) # surcos de las ruedas
		h += 0.018 * exp(-pow(a / 0.35, 2.0)) # lomo central
	if a > 4.2:
		h -= DITCH * exp(-pow((a - 5.3) / 0.55, 2.0)) # zanja
		h += 0.05 * exp(-pow((a - 6.2) / 0.3, 2.0)) # montículo al pie del cerco
	return h

func base_height(x: float, z: float) -> float:
	var nr := nearest(x, z)
	var d: float = nr["d"]
	return axis_height(nr, x, z) + profile_at(int(nr["i"]), float(nr["side"]) if d < fence_half() + 2.0 else fence_half() + 2.0)

## Relieve del terreno lejano (sólo visual): bajo la cinta del camino y los taludes queda más hondo (la grilla de 6 m no puede asomar), después sigue la meseta y se va
## mezclando con lomas propias lejos
func terrain_height(x: float, z: float) -> float:
	var nr := nearest(x, z)
	var d: float = nr["d"]
	var i: int = nr["i"]
	var ah := axis_height(nr, x, z)
	var fh := fence_half()
	if d < fh + 1.7:
		return ah + profile_at(i, float(nr["side"])) - (0.6 if d < fh - 0.4 else 0.05)
	var num := 0.0
	var den := 0.0
	for c in coarse:
		var dd := maxf(3.0, sqrt((c.x - x) * (c.x - x) + (c.y - z) * (c.y - z)))
		var w := 1.0 / (dd * dd * dd)
		num += w * c.z
		den += w
	var hr := num / den
	var far := smoothstep(14.0, 70.0, d)
	var hills := 5.5 * sin(x * 0.011 + 1.3) * cos(z * 0.014 - 0.4) + 2.4 * sin(x * 0.027 + z * 0.019) + 1.1 * sin(z * 0.05 - x * 0.03)
	var edge := 1.0 - smoothstep(190.0, 260.0, d)
	return hr * (1.0 - far) + (hr * 0.4 + hills) * far * edge + float(bank[i]) * (1.0 - smoothstep(fh + 1.7, fh + 30.0, d))

func surface_at(x: float, z: float) -> int:
	for m in mud:
		if (x - float(m["x"])) * (x - float(m["x"])) + (z - float(m["z"])) * (z - float(m["z"])) < float(m["r"]) * float(m["r"]):
			return 5
	var nr := nearest(x, z)
	var d: float = nr["d"]
	if d < road_half():
		return SURF_DIRT
	if d < fence_half() + 0.5:
		return SURF_SHOULDER
	return SURF_GRASS

func ground_info(x: float, z: float) -> Vector2:
	var nr := nearest(x, z) # (una sola búsqueda por consulta: altura y superficie salen de la misma)
	var h := axis_height(nr, x, z) + profile_at(int(nr["i"]), float(nr["side"]))
	for f in features:
		var cx: float = f["cx"]
		var cz: float = f["cz"]
		var mm: float = maxf(float(f["l"]), float(f["w"])) * 0.75
		if absf(x - cx) > mm or absf(z - cz) > mm:
			continue
		h += feat_height(f, x, z)
	var d: float = nr["d"]
	var surf := SURF_GRASS
	if d < road_half():
		surf = SURF_DIRT
	elif d < fence_half() + 0.5:
		surf = SURF_SHOULDER
	for m in mud:
		var dx: float = x - float(m["x"])
		var dz: float = z - float(m["z"])
		if dx * dx + dz * dz < float(m["r"]) * float(m["r"]):
			surf = 5
			break
	return Vector2(h, float(surf))

## El cerco: una pared continua a FENCE_HALF del eje. Devuelve la normal que devuelve al auto hacia el camino
func push(x: float, z: float, r: float) -> Vector3:
	var best := Vector3(0, 0, 0)
	var nr := nearest(x, z)
	var d: float = nr["d"]
	var lim := fence_half() - 0.15 - r
	if d > lim:
		var q: Vector2 = pts[nr["i"]]
		var dir := (q - Vector2(x, z))
		var dl := dir.length()
		if dl > 0.001:
			dir /= dl
			best = Vector3(dir.x, dir.y, d - lim)
			last_hit = {"id": "fence", "owner": null, "nx": dir.x, "nz": dir.y}
	return best

## Punto del eje a una distancia s (m) adelante del índice i
func ahead(i: int, s: float) -> Vector2:
	var n := int(round(s / 2.0))
	return pts[(i + n) % pts.size()]

func start_pose() -> Vector3: # x, z, yaw
	var tg := tans[0]
	return Vector3(pts[0].x, pts[0].y, atan2(tg.x, tg.y))
