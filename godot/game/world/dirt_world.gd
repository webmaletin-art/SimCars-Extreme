extends "res://game/world/lot_world.gd"
## Camino de tierra: circuito cerrado sin rivales, con cerco de madera a cada lado (una sola cara visible: la del lado del camino; el auto no lo cruza), un bosque denso
## de árboles de todos los colores que tapa la vista (atrás no hay nada) y charcos de barro, lomos y ondas sobre el camino.
## Todo sale de la curva del eje (DirtTrack): la malla del camino, los cercos, los árboles y la física usan los mismos puntos.

const DirtTrack := preload("res://game/world/dirt_track.gd")
const ROAD := preload("res://game/world/road.gdshader")

## Bosque nativo (todo verde): árboles de copa baja [textura, alto (m), proporción ancho/alto, peso]
const SPECIES := [
	["arbol_bajo_a", 5.0, 1.0, 24], ["arbol_bajo_b", 5.0, 1.0, 18], ["arbol_bajo_c", 5.0, 0.75, 14], ["arbol_bajo_d", 5.0, 1.0, 16], ["arbol_bajo_e", 5.0, 1.0, 16],
	["arbol_cipres", 8.0, 0.5, 5], ["arbol_alamo", 8.0, 0.417, 4]]
var wall_set := ["bosque_lejos", "bosque_cerca", 7.5, 5.5] # texturas y alturas de la pared de fondo (el circuito urbano usa edificios)
const WALL_OFF := 34.0 # hasta dónde se aleja la pared de bosque del eje (m)

var dt: DirtTrack
var arc_nodes: Array = [] # {n, a0, a1}: pedazos de cerco/barrera que sólo se dibujan cuando su tramo del circuito está cerca del auto
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _win_clock := 0.0

func _init() -> void:
	dt = DirtTrack.new()
	track = dt

func _build_scene() -> void:
	_build_terrain()
	_build_features()
	_build_road()
	_build_puddles()
	_build_fences()
	_build_forest()
	_build_details()
	_build_props()
	cones = []

## Arco del circuito (m) de un punto
func _arc_of(p: Vector3) -> float:
	return float(dt.cum[int(dt.nearest(p.x, p.z)["i"])])

## Ventana de lo que se ve: el tramo del circuito cerca del auto (adelante según la velocidad, un poco atrás). Lo del otro lado de la vuelta no se dibuja:
## los árboles y el pasto lo descartan en el shader (track_window) y los cercos por pedazos acá.
func set_car_pos(p: Vector3) -> void:
	super.set_car_pos(p)
	var dtm := maxf(get_process_delta_time(), 0.001)
	var v := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length() / dtm
	_last_pos = p
	_speed = lerpf(_speed, minf(v, 90.0), 0.08)
	var arc := _arc_of(p)
	var ahead := clampf(120.0 + 1.6 * _speed, 120.0, 210.0) # (más corto: en las curvas se veían árboles del otro lado de la pista)
	RenderingServer.global_shader_parameter_set("track_window", Vector4(arc, ahead, 60.0, dt.length))
	_win_clock -= dtm
	if _win_clock <= 0.0:
		_win_clock = 0.2
		for e in arc_nodes:
			var mid: float = (float(e["a0"]) + float(e["a1"])) * 0.5
			var half: float = absf(float(e["a1"]) - float(e["a0"])) * 0.5
			var d := fposmod(mid - arc + dt.length * 0.5, dt.length) - dt.length * 0.5
			var ext: float = float(e.get("ext", 0.0)) # (la pared de bosque se ve un poco más lejos: es barata y así no se nota el corte)
			(e["n"] as Node3D).visible = d - half < ahead + ext and d + half > -60.0 - ext

## Pared continua a lo largo del eje, partida en pedazos de ~100 m (cada uno se oculta solo cuando su tramo queda lejos del auto)
func _wall_chunks(side: float, lat: float, y_off: float, h: float, u_per_m: float, v_top: float, v_bot: float, mat: Material, one_sided: bool) -> void:
	var n := dt.pts.size()
	var CH := 50
	for c0 in range(0, n, CH):
		var c1 := mini(c0 + CH, n)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(c0, c1 + 1):
			var k := i % n
			var tg := dt.tans[k]
			var nl := Vector2(-tg.y, tg.x)
			var q: Vector2 = dt.pts[k] + nl * side * lat
			var c := float(dt.cum[k]) if i < n else dt.length
			var yb := float(dt.hprof[k]) + dt.profile_at(k, lat) + y_off
			st.set_uv(Vector2(c * u_per_m, v_bot))
			st.add_vertex(Vector3(q.x, yb, q.y))
			st.set_uv(Vector2(c * u_per_m, v_top))
			st.add_vertex(Vector3(q.x, yb + h, q.y))
		for i in c1 - c0:
			var v0 := i * 2
			if side < 0.0 or not one_sided:
				st.add_index(v0)
				st.add_index(v0 + 1)
				st.add_index(v0 + 2)
				st.add_index(v0 + 1)
				st.add_index(v0 + 3)
				st.add_index(v0 + 2)
			else:
				st.add_index(v0)
				st.add_index(v0 + 2)
				st.add_index(v0 + 1)
				st.add_index(v0 + 1)
				st.add_index(v0 + 2)
				st.add_index(v0 + 3)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(mi)
		_tag(mi, "misc", 260.0)
		arc_nodes.append({"n": mi, "a0": float(dt.cum[c0 % n]), "a1": float(dt.cum[c1 % n]) if c1 < n else dt.length})

## Altura del suelo en cualquier punto (camino y banquina: la física; más lejos: el terreno)
func gy(x: float, z: float) -> float:
	var nr := dt.nearest(x, z)
	if float(nr["d"]) < dt.fence_half() + 1.7:
		return dt.axis_height(nr, x, z) + dt.profile_at(int(nr["i"]), float(nr["side"]))
	return dt.terrain_height(x, z)

func _static_trimesh(mesh: Mesh) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	sb.add_child(cs)
	add_child(sb)

## Terreno con lomas: grilla de 6 m que sigue la altura del camino cerca y se vuelve loma propia lejos
func _build_terrain() -> void:
	var x0 := -240.0
	var z0 := -100.0
	var nx := 88
	var nz := 57
	var cell := 6.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nse := FastNoiseLite.new()
	nse.seed = 5
	nse.frequency = 0.03
	for i in nx + 1:
		for j in nz + 1:
			var x := x0 + float(i) * cell
			var z := z0 + float(j) * cell
			var h := dt.terrain_height(x, z)
			var nr := dt.nearest(x, z)
			var d: float = nr["d"]
			var dry := 1.0 - smoothstep(8.0, 26.0, d)
			var v := 0.82 + 0.3 * (nse.get_noise_2d(x, z) * 0.5 + 0.5)
			var col := Color(v, v, v).lerp(Color(0.95, 0.85, 0.62), dry * 0.5)
			st.set_color(col)
			st.set_uv(Vector2(x, z) / 4.0)
			st.add_vertex(Vector3(x, h, z))
	for i in nx:
		for j in nz:
			var a := i * (nz + 1) + j
			var b := a + 1
			var c := a + (nz + 1)
			var d2 := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d2)
			st.add_index(c)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := _mat_tex("pasto", Vector3(1, 1, 1), 0.95, Color(0.92, 0.98, 0.85))
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.add_child(mi)
	_static_trimesh(mesh)
	# más allá del terreno: un plano lejano a la altura del borde
	var far := _mat_tex("pasto", Vector3(300, 300, 1), 0.95, Color(0.55, 0.66, 0.46))
	_plane(Vector2(1400, 1400), -8.0, far, Vector3(30, 0, 60))

const ROAD_LAT := [-4.8, -4.4, -3.8, -3.1, -2.4, -1.7, -1.2, -0.95, -0.7, -0.35, 0.0, 0.35, 0.7, 0.95, 1.2, 1.7, 2.4, 3.1, 3.8, 4.4, 4.8]
const SLOPE_L := [4.7, 5.0, 5.3, 5.6, 5.9, 6.2, 6.5, 6.8, 7.1, 7.4, 7.8]
const TOP_L := [7.7, 8.8, 10.0, 11.8]

## Cinta del camino + taludes de tierra a los costados (el camino va hundido) + meseta de pasto donde está el cerco. Cada vértice usa la altura real del eje y el perfil
## de ese punto: es la misma superficie que siente la física
func _build_road() -> void:
	var road := _ribbon(ROAD_LAT, 0.0, "tierra_roja", 3.0, true, Color.WHITE, true)
	props.add_child(road)
	_static_trimesh(road.mesh)
	var neg_s: Array = []
	for v in SLOPE_L:
		neg_s.append(-float(v))
	neg_s.reverse()
	var neg_t: Array = []
	for v in TOP_L:
		neg_t.append(-float(v))
	neg_t.reverse()
	for e in [[SLOPE_L, "tierra_roja", Color(0.86, 0.76, 0.68)], [neg_s, "tierra_roja", Color(0.86, 0.76, 0.68)], [TOP_L, "pasto", Color(0.84, 0.78, 0.52)], [neg_t, "pasto", Color(0.84, 0.78, 0.52)]]:
		var r := _ribbon(e[0], -0.004, String(e[1]), 3.0, false, e[2], false)
		props.add_child(r)
		_static_trimesh(r.mesh)

func _ribbon(lats: Array, dy: float, tex: String, tile: float, shade: bool, tint := Color.WHITE, holes := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := dt.pts.size()
	var m := lats.size()
	for i in n + 1:
		var k := i % n
		var p := dt.pts[k]
		var tg := dt.tans[k]
		var nl := Vector2(-tg.y, tg.x)
		var c := float(dt.cum[k]) if i < n else dt.length
		var hk := float(dt.hprof[k])
		for e in lats:
			var lat := float(e)
			var q: Vector2 = p + nl * lat
			var col := Color(1, 1, 1)
			if shade:
				var a := absf(lat)
				col = Color(0.74, 0.7, 0.66) if (a > 0.6 and a < 1.3) else (Color(1, 1, 1) if a < 3.6 else Color(0.92, 0.9, 0.75))
			st.set_color(col)
			st.set_uv(Vector2(lat / tile, c / tile))
			st.add_vertex(Vector3(q.x, hk + dt.profile_at(k, lat) + dy, q.y))
	for i in n:
		for j in m - 1:
			var v0 := i * m + j
			var v1 := v0 + 1
			var v2 := v0 + m
			var v3 := v2 + 1
			st.add_index(v0)
			st.add_index(v1)
			st.add_index(v2)
			st.add_index(v1)
			st.add_index(v3)
			st.add_index(v2)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat: Material
	if holes:
		var sm := ShaderMaterial.new()
		sm.shader = ROAD
		sm.set_shader_parameter("tex", _tex(tex))
		sm.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		var arr := PackedVector4Array()
		for h in dt.holes:
			arr.append(Vector4(float(h["x"]), float(h["z"]), float(h["r"]) * 1.12, 0.0))
		while arr.size() < 40:
			arr.append(Vector4(0, 0, 0, 0))
		sm.set_shader_parameter("holes", arr)
		sm.set_shader_parameter("n_holes", mini(40, dt.holes.size()))
		mat = sm
	else:
		var sm2 := _mat_tex(tex, Vector3(1, 1, 1), 0.95, tint)
		sm2.vertex_color_use_as_albedo = true
		sm2.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat = sm2
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Agua en los charcos y en los baches llenos: disco oscuro y brillante a la altura del agua
func _build_puddles() -> void:
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.33, 0.16, 0.09, 0.72)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.04
	wm.metallic_specular = 1.0
	wm.metallic = 0.2
	var drawn := {}
	for h in dt.holes:
		var r := float(h["r"])
		var gx := float(h["x"])
		var gz := float(h["z"])
		if bool(h["water"]):
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = r * 0.98
			cm.bottom_radius = r * 0.98
			cm.height = 0.004
			cm.radial_segments = 20
			mi.mesh = cm
			mi.material_override = wm
			var base := gy(gx, gz) - float(h["depth"]) * 0.45
			mi.position = Vector3(gx, base, gz)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props.add_child(mi)
			drawn[Vector2i(int(gx), int(gz))] = true
	# charcos grandes del camino (los de barro)
	var mm := _mat_tex("tierra_roja", Vector3(0.3, 0.3, 1), 0.3, Color(0.3, 0.15, 0.09))
	for m in dt.mud:
		if drawn.has(Vector2i(int(float(m["x"])), int(float(m["z"])))) or float(m["r"]) < 3.0:
			continue
		var mi2 := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = float(m["r"])
		cm2.bottom_radius = float(m["r"])
		cm2.height = 0.006
		cm2.radial_segments = 24
		mi2.mesh = cm2
		mi2.material_override = mm
		mi2.position = Vector3(float(m["x"]), gy(float(m["x"]), float(m["z"])) + 0.012, float(m["z"]))
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(mi2)
		var wi := MeshInstance3D.new()
		var cw := CylinderMesh.new()
		cw.top_radius = float(m["r"]) * 0.8
		cw.bottom_radius = float(m["r"]) * 0.8
		cw.height = 0.004
		cw.radial_segments = 24
		wi.mesh = cw
		wi.material_override = wm
		wi.position = mi2.position + Vector3(0, 0.006, 0)
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(wi)

## Cercos de madera: una cara sola (la del camino). Pared invisible para el auto = DirtTrack.push()
func _build_fences() -> void:
	var m := StandardMaterial3D.new()
	var t := _tex("valla")
	if t != null:
		m.albedo_texture = t
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.albedo_color = Color(0.74, 0.68, 0.62)
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for side in [1.0, -1.0]:
		_wall_chunks(float(side), DirtTrack.FENCE_HALF, -0.05, 1.25, 1.0 / 3.0, 0.0, 1.0, m, true)

func _pick_species() -> Array:
	var tot := 0
	for s in SPECIES:
		tot += int(s[3])
	var r := rng.randi() % tot
	for s in SPECIES:
		r -= int(s[3])
		if r < 0:
			return s
	return SPECIES[0]

## Bosque: UNA hilera de árboles bajos pegada al cerco (de verdad, en cruz) + la pared de bosque opaca detrás (png sin vértices de hojas) que cierra el paisaje
func _build_forest() -> void:
	var tq: float = opts["trees"]
	var groups_x := {}
	for s in SPECIES:
		groups_x[s[0]] = []
	var n := dt.pts.size()
	var fh := dt.fence_half()
	var step := maxi(1, int(round(5.2 / maxf(0.3, tq) / 2.0)))
	for i in range(0, n, step):
		var p := dt.pts[i]
		var tg := dt.tans[i]
		var nl := Vector2(-tg.y, tg.x)
		for side in [1.0, -1.0]:
			var off := fh + 2.6 + rng.randf_range(-0.5, 1.1)
			var q: Vector2 = p + nl * float(side) * off + tg * rng.randf_range(-1.4, 1.4)
			var s := _pick_species()
			groups_x[s[0]].append(_xf(Vector3(q.x, gy(q.x, q.y) - 0.1, q.y), rng.randf_range(0.85, 1.3)))
	for s in SPECIES:
		var arr: Array = groups_x[s[0]]
		if arr.size() > 0:
			_multi(s[0], float(s[1]) * float(s[2]), float(s[1]), arr, 0.06, Color(0.97, 0.98, 0.97), 230.0, true)
	_build_forest_wall()
	_build_grass_bands()

## Distancia de la pared al eje en cada muestra (cada 3 puntos = 6 m): hasta WALL_OFF, pero sin pasar sobre otros tramos del circuito
## ni plegarse del lado de adentro de las curvas cerradas (ahí la pared se acerca y cierra la curva).
func _wall_offsets(side: float) -> PackedFloat32Array:
	var n := dt.pts.size()
	var m := int(ceil(float(n) / 3.0))
	var fh := dt.fence_half()
	var off := PackedFloat32Array()
	off.resize(m)
	for j in m:
		var i := (j * 3) % n
		var nl := Vector2(-dt.tans[i].y, dt.tans[i].x)
		var chosen := fh + 3.5
		for cand in [WALL_OFF, 28.0, 22.0, 17.0]:
			var q: Vector2 = dt.pts[i] + nl * side * float(cand)
			if _clear_of_other_legs(q, i, fh + 4.5):
				chosen = float(cand)
				break
		var cv: float = dt.curv[i]
		if side * cv > 0.0004: # la curva gira hacia este lado: la pared no puede pasar del radio
			chosen = minf(chosen, maxf(fh + 3.5, 0.8 / absf(cv)))
		off[j] = chosen
	for _k in 2: # suaviza (la pared no puede saltar más de 3 m cada 6 m)
		for j in range(1, m):
			off[j] = minf(off[j], off[j - 1] + 3.0)
		for j in range(m - 2, -1, -1):
			off[j] = minf(off[j], off[j + 1] + 3.0)
		off[0] = minf(off[0], off[m - 1] + 3.0)
	return off

## ¿el punto q queda a más de `margin` de todos los tramos del circuito que están a más de 70 m de recorrido de la muestra i?
func _clear_of_other_legs(q: Vector2, i: int, margin: float) -> bool:
	var cx := int(floor(q.x / 24.0))
	var cz := int(floor(q.y / 24.0))
	var n := dt.pts.size()
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var lst: Array = dt._grid.get(Vector2i(cx + dx, cz + dz), [])
			for k in lst:
				var da := absf(float(dt.cum[k]) - float(dt.cum[i]))
				da = minf(da, dt.length - da)
				if da > 70.0 and q.distance_to(dt.pts[k]) < margin:
					return false
	return true

## Pared de bosque en dos capas (la de atrás más alta y oscura): cinta opaca (sólo se recorta la silueta de arriba) que sigue el circuito
func _build_forest_wall() -> void:
	for layer in 2:
		var far := layer == 0
		var tex := _tex(String(wall_set[0] if far else wall_set[1]))
		if tex == null:
			continue
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.albedo_color = Color(0.86, 0.9, 0.86) if far else Color(1, 1, 1)
		var hgt := float(wall_set[2] if far else wall_set[3])
		for side in [1.0, -1.0]:
			var offs := _wall_offsets(float(side))
			var back := 0.0 if far else -(6.0 + 2.0 * float(layer))
			_wall_ribbon(float(side), offs, 0.0 if far else -7.0, hgt, 40.0, m)

## Cinta vertical por las muestras de offs (cada una = 3 puntos del eje), partida en pedazos de ~100 m que se ocultan solos con la ventana del circuito.
func _wall_ribbon(side: float, offs: PackedFloat32Array, pull: float, h: float, tile: float, mat: Material) -> void:
	var n := dt.pts.size()
	var m := offs.size()
	var fh := dt.fence_half()
	var CH := 17
	var run := 0.0
	var acc := PackedFloat32Array() # largo recorrido por la pared hasta cada muestra (para que la textura no se estire)
	var prev := Vector2.ZERO
	var qs := PackedVector2Array()
	for j in m + 1:
		var i := (j * 3) % n
		var nl := Vector2(-dt.tans[i].y, dt.tans[i].x)
		var o := maxf(fh + 3.0, float(offs[j % m]) + pull)
		var q: Vector2 = dt.pts[i] + nl * side * o
		if j > 0:
			run += q.distance_to(prev)
		acc.append(run)
		qs.append(q)
		prev = q
	for c0 in range(0, m, CH):
		var c1 := mini(c0 + CH, m)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(c0, c1 + 1):
			var q: Vector2 = qs[j]
			var yb := gy(q.x, q.y) - 0.7
			st.set_uv(Vector2(float(acc[j]) / tile, 1.0))
			st.add_vertex(Vector3(q.x, yb, q.y))
			st.set_uv(Vector2(float(acc[j]) / tile, 0.0))
			st.add_vertex(Vector3(q.x, yb + h + 0.7, q.y))
		for k in c1 - c0:
			var v0 := k * 2
			st.add_index(v0)
			st.add_index(v0 + 1)
			st.add_index(v0 + 2)
			st.add_index(v0 + 1)
			st.add_index(v0 + 3)
			st.add_index(v0 + 2)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(mi)
		_tag(mi, "misc", 320.0)
		arc_nodes.append({"n": mi, "ext": 25.0, "a0": float(dt.cum[(c0 * 3) % n]), "a1": float(dt.cum[(c1 * 3) % n]) if c1 * 3 < n else dt.length})

## Bandas de pasto y de matorral (png repetible) pegadas al cerco: la hilera real de matas va adelante y esto rellena el resto sin un solo pasto suelto
func _build_grass_bands() -> void:
	var fh := dt.fence_half()
	for spec in [["pasto_banda", 1.3, 1.2, 6.0, 1.2], ["matorral_banda", 5.0, 2.2, 6.0, 2.2]]:
		var tex := _tex(String(spec[0]))
		if tex == null:
			continue
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		for side in [1.0, -1.0]:
			_wall_chunks(float(side), fh + float(spec[1]), -0.25, float(spec[2]) + 0.25, 1.0 / float(spec[3]), 0.0, 1.0, m, false)

## Sotobosque y detalles: pasto verde, alto y seco, juncos en los charcos, matas, flores de campo, arbustos, rocas en la zanja, troncos caídos, tocones y fardos de heno
func _build_details(dirt_props := true) -> void:
	var g := float(opts["grass"])
	var n := dt.pts.size()
	var fh := dt.fence_half()
	var tuft := {"pasto_mata": [], "pasto_alto": [], "pasto_seco": []}
	var tuft_t := ["pasto_mata", "pasto_mata", "pasto_alto", "pasto_seco"]
	var bush_x := {"arbusto_verde": [], "arbusto_flores_rosa": [], "arbusto_flores_amarillo": []}
	var flower_x := {"flor_blanca": [], "flor_amarilla": [], "flor_roja": [], "flor_violeta": []}
	var bt := ["arbusto_verde", "arbusto_flores_rosa", "arbusto_flores_amarillo"]
	var ft := ["flor_blanca", "flor_amarilla", "flor_roja", "flor_violeta"]
	var rock_xf := []
	var lo := dt.tuft_lo()
	# Una hilera real de matas, arbustos y flores pegada al camino y al cerco; el resto del pasto es la banda png (_build_grass_bands)
	for i in range(0, n, 2):
		var p2 := dt.pts[i]
		var tg2 := dt.tans[i]
		var nl2 := Vector2(-tg2.y, tg2.x)
		for side in [1.0, -1.0]:
			for k in int(round(1.6 * g)):
				var off2: float = rng.randf_range(lo, fh + 1.0)
				var q2: Vector2 = p2 + nl2 * float(side) * off2 + tg2 * rng.randf_range(-1.0, 1.0)
				tuft[tuft_t[rng.randi() % 4]].append(_xf(Vector3(q2.x, gy(q2.x, q2.y) - 0.02, q2.y), rng.randf_range(0.7, 1.5)))
			if dirt_props and rng.randf() < 0.35 * g: # matas altas al borde mismo del camino
				var q5: Vector2 = p2 + nl2 * float(side) * rng.randf_range(4.3, 4.9)
				tuft["pasto_seco"].append(_xf(Vector3(q5.x, gy(q5.x, q5.y) - 0.02, q5.y), rng.randf_range(0.5, 0.9)))
			if rng.randf() < 0.1 * g:
				var q3: Vector2 = p2 + nl2 * float(side) * (fh + rng.randf_range(1.2, 4.0))
				bush_x[bt[rng.randi() % 3]].append(_xf(Vector3(q3.x, gy(q3.x, q3.y) - 0.02, q3.y), rng.randf_range(0.8, 1.5)))
			if rng.randf() < 0.14 * g:
				var q4: Vector2 = p2 + nl2 * float(side) * (fh + rng.randf_range(0.2, 2.2))
				flower_x[ft[rng.randi() % 4]].append(_xf(Vector3(q4.x, gy(q4.x, q4.y) - 0.02, q4.y), rng.randf_range(1.0, 1.7)))
			if false: # (piedras 3D de la zanja: sacadas a pedido del dueño, molestaban)
				var q6: Vector2 = p2 + nl2 * float(side) * rng.randf_range(4.2, 6.2)
				var sc := rng.randf_range(0.06, 0.30)
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sc * rng.randf_range(1.0, 1.6), sc * rng.randf_range(0.5, 0.9), sc * rng.randf_range(1.0, 1.4)))
				rock_xf.append(Transform3D(b, Vector3(q6.x, gy(q6.x, q6.y) + sc * 0.2, q6.y)))
	for t in tuft:
		if tuft[t].size() > 0:
			var w := 0.66 if t == "pasto_mata" else (0.7 if t == "pasto_alto" else 0.62)
			var h := 0.55 if t == "pasto_mata" else (0.9 if t == "pasto_alto" else 0.6)
			_multi(t, w, h, tuft[t], 0.07, Color.WHITE, 75.0)
	for b in bush_x:
		if bush_x[b].size() > 0:
			_multi(b, 2.0, 1.5, bush_x[b], 0.03, Color.WHITE, 150.0)
	for f in flower_x:
		if flower_x[f].size() > 0:
			_multi(f, 0.23, 0.35, flower_x[f], 0.08, Color.WHITE, 50.0)
	if not dirt_props:
		return
	# juncos alrededor de los baches con agua y de los charcos
	var reeds := []
	for h in dt.holes:
		if bool(h["water"]):
			for k in 7:
				var a := rng.randf() * TAU
				var rr := float(h["r"]) * rng.randf_range(1.0, 1.6)
				var qx := float(h["x"]) + cos(a) * rr
				var qz := float(h["z"]) + sin(a) * rr
				tuft["pasto_alto"].append(_xf(Vector3(qx, gy(qx, qz) - 0.02, qz), rng.randf_range(0.6, 1.0)))
	# rocas
	if rock_xf.size() > 0:
		var rock_m := _build_rock_mesh()
		var rmm := MultiMesh.new()
		rmm.transform_format = MultiMesh.TRANSFORM_3D
		rmm.mesh = rock_m
		rmm.instance_count = rock_xf.size()
		for i in rock_xf.size():
			rmm.set_instance_transform(i, rock_xf[i])
		var rmi := MultiMeshInstance3D.new()
		rmi.multimesh = rmm
		rmi.material_override = _mat_tex("tierra", Vector3(0.25, 0.25, 1), 0.95, Color(0.6, 0.58, 0.55))
		rmi.visibility_range_end = 120.0
		props.add_child(rmi)
		_tag(rmi, "grass", 120.0)
	# troncos caídos, tocones y fardos de heno fuera del cerco
	var bark := _mat_tex("hormigon", Vector3(1, 1, 1), 0.95, Color(0.42, 0.28, 0.17))
	var hay := _flat(Color(0.82, 0.68, 0.3), 0.95)
	for k in int(10.0 * g) + 3:
		var i3 := rng.randi() % n
		var p3 := dt.pts[i3]
		var tg3 := dt.tans[i3]
		var nl3 := Vector2(-tg3.y, tg3.x)
		var side3 := 1.0 if rng.randf() < 0.5 else -1.0
		var q7: Vector2 = p3 + nl3 * side3 * (DirtTrack.FENCE_HALF + rng.randf_range(1.5, 8.0))
		var gyv := gy(q7.x, q7.y)
		var kind := rng.randi() % 3
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		mi.material_override = bark
		if kind == 0: # tronco caído
			cm.top_radius = rng.randf_range(0.14, 0.26)
			cm.bottom_radius = cm.top_radius * 1.1
			cm.height = rng.randf_range(2.6, 5.0)
			mi.mesh = cm
			mi.position = Vector3(q7.x, gyv + cm.top_radius * 0.8, q7.y)
			mi.rotation = Vector3(0.0, rng.randf() * TAU, PI * 0.5)
		elif kind == 1: # tocón
			cm.top_radius = rng.randf_range(0.2, 0.34)
			cm.bottom_radius = cm.top_radius * 1.25
			cm.height = rng.randf_range(0.35, 0.7)
			mi.mesh = cm
			mi.position = Vector3(q7.x, gyv + cm.height * 0.4, q7.y)
		else: # fardo de heno
			cm.top_radius = 0.65
			cm.bottom_radius = 0.65
			cm.height = 0.9
			mi.mesh = cm
			mi.material_override = hay
			mi.position = Vector3(q7.x, gyv + 0.65, q7.y)
			mi.rotation = Vector3(0.0, rng.randf() * TAU, PI * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(mi)
		_tag(mi, "misc", 130.0)

## Arco de salida, carteles de curva cerrada y pilas de neumáticos en las horquillas
func _build_props() -> void:
	var p0 := dt.pts[0]
	var tg := dt.tans[0]
	var nl := Vector2(-tg.y, tg.x)
	var yaw := atan2(tg.x, tg.y)
	var metal := _flat(Color(0.75, 0.15, 0.12), 0.6)
	for side in [1.0, -1.0]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 5.0, 0.35)
		post.mesh = bm
		post.material_override = metal
		var q: Vector2 = p0 + nl * float(side) * (DirtTrack.ROAD_HALF + 1.0)
		post.position = Vector3(q.x, float(dt.hprof[0]) + 2.5, q.y)
		props.add_child(post)
	var banner := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3((DirtTrack.ROAD_HALF + 1.0) * 2.0 + 0.4, 1.0, 0.2)
	banner.mesh = bb
	banner.material_override = _flat(Color(0.08, 0.1, 0.14), 0.7)
	banner.position = Vector3(p0.x, float(dt.hprof[0]) + 5.2, p0.y)
	banner.rotation.y = yaw
	props.add_child(banner)
	for sd in [1.0, -1.0]:
		var lb := Label3D.new()
		lb.text = "SALIDA · META"
		lb.font_size = 64
		lb.pixel_size = 0.012
		lb.modulate = Color(1, 0.8, 0.2)
		lb.shaded = false
		lb.double_sided = false
		lb.position = banner.position + Vector3(tg.x, 0, tg.y) * (0.12 * float(sd))
		lb.rotation.y = yaw + (0.0 if sd < 0.0 else PI)
		props.add_child(lb)
	# carteles de curva: sólo donde la curva es cerrada, del lado de afuera, mirando al camino
	var last_i := -100
	for i in dt.pts.size():
		var cv: float = dt.curv[i]
		if absf(cv) < 0.026 or i - last_i < 7:
			continue
		last_i = i
		var p := dt.pts[i]
		var t2 := dt.tans[i]
		var n2 := Vector2(-t2.y, t2.x)
		var outer := -1.0 if cv > 0.0 else 1.0 # la curva gira hacia la izquierda (cv > 0) → el cartel va en el lado derecho
		var q2: Vector2 = p + n2 * outer * (DirtTrack.FENCE_HALF + 0.9)
		var board := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(2.4, 1.2, 0.1)
		board.mesh = bm2
		board.material_override = _flat(Color(0.95, 0.75, 0.05), 0.6)
		board.position = Vector3(q2.x, gy(q2.x, q2.y) + 1.6, q2.y)
		var face := atan2(-n2.x * outer, -n2.y * outer) # mira hacia el eje del camino
		board.rotation.y = face
		props.add_child(board)
		var lb2 := Label3D.new()
		lb2.text = "<<<" if cv > 0.0 else ">>>"
		lb2.font_size = 80
		lb2.pixel_size = 0.010
		lb2.modulate = Color(0.1, 0.1, 0.1)
		lb2.shaded = false
		lb2.double_sided = false
		lb2.position = board.position + Vector3(-n2.x * outer, 0, -n2.y * outer) * 0.07
		lb2.rotation.y = face
		props.add_child(lb2)
		var post2 := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 1.3
		post2.mesh = cm
		post2.material_override = _flat(Color(0.3, 0.3, 0.3))
		post2.position = Vector3(q2.x, gy(q2.x, q2.y) + 0.65, q2.y)
		props.add_child(post2)
