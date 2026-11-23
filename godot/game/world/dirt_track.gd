extends "res://game/world/lot_track.gd"
## Camino de tierra: circuito cerrado (curva suave por puntos de control), con zona de tierra, banquina, charcos de barro, lomos, ondas y un cerco de madera a cada
## lado que el auto no puede cruzar. La misma curva arma la malla del camino y los cercos (dirt_world.gd).
##
## Superficies: tierra (1) en el camino, banquina (2) entre el camino y el cerco, barro (5) en los charcos.

const ROAD_HALF := 4.4 # semiancho del camino (m)
const FENCE_HALF := 6.4 # distancia del eje al cerco (m)
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

func _default_lot() -> void:
	pass # (el estacionamiento: acá no hay nada; el camino se arma en _init, cuando ya existen las variables de esta clase)

func _init() -> void:
	_sample()
	# lomos y ondas sobre el camino (cada rasgo se alinea con el eje: yaw = ángulo de la tangente)
	_feature_at(0.17, "hump", 3.0, 0.07)
	_feature_at(0.33, "wash", 14.0, 0.05, 10)
	_feature_at(0.52, "hump", 3.4, 0.10)
	_feature_at(0.64, "wash", 12.0, 0.06, 9)
	_feature_at(0.80, "hump", 3.0, 0.08)
	_feature_at(0.92, "wash", 10.0, 0.05, 8)
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
	var n := CTRL.size()
	var raw := PackedVector2Array()
	for i in n:
		var p0: Vector2 = CTRL[(i - 1 + n) % n]
		var p1: Vector2 = CTRL[i]
		var p2: Vector2 = CTRL[(i + 1) % n]
		var p3: Vector2 = CTRL[(i + 2) % n]
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

func surface_at(x: float, z: float) -> int:
	for m in mud:
		if (x - float(m["x"])) * (x - float(m["x"])) + (z - float(m["z"])) * (z - float(m["z"])) < float(m["r"]) * float(m["r"]):
			return 5
	var nr := nearest(x, z)
	var d: float = nr["d"]
	if d < ROAD_HALF:
		return SURF_DIRT
	if d < FENCE_HALF + 0.5:
		return SURF_SHOULDER
	return SURF_GRASS

func ground_info(x: float, z: float) -> Vector2:
	var h := 0.0
	for f in features:
		var cx: float = f["cx"]
		var cz: float = f["cz"]
		var mm: float = maxf(float(f["l"]), float(f["w"])) * 0.75
		if absf(x - cx) > mm or absf(z - cz) > mm:
			continue
		h += feat_height(f, x, z)
	return Vector2(h, float(surface_at(x, z)))

## El cerco: una pared continua a FENCE_HALF del eje. Devuelve la normal que devuelve al auto hacia el camino
func push(x: float, z: float, r: float) -> Vector3:
	var best := Vector3(0, 0, 0)
	var nr := nearest(x, z)
	var d: float = nr["d"]
	var lim := FENCE_HALF - 0.15 - r
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
