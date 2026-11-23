extends "res://game/world/lot_world.gd"
## Camino de tierra: circuito cerrado sin rivales, con cerco de madera a cada lado (una sola cara visible: la del lado del camino; el auto no lo cruza), un bosque denso
## de árboles de todos los colores que tapa la vista (atrás no hay nada) y charcos de barro, lomos y ondas sobre el camino.
## Todo sale de la curva del eje (DirtTrack): la malla del camino, los cercos, los árboles y la física usan los mismos puntos.

const DirtTrack := preload("res://game/world/dirt_track.gd")
const ROAD := preload("res://game/world/road.gdshader")

## [textura, alto (m), proporción ancho/alto, peso]
const SPECIES := [
	["arbol_redondo", 8.0, 0.667, 26], ["arbol_cipres", 8.0, 0.5, 13], ["arbol_alamo", 8.0, 0.417, 9], ["arbol_otono", 7.0, 0.8, 8],
	["arbol_amarillo", 8.0, 0.667, 8], ["arbol_rojo", 8.0, 0.667, 8], ["arbol_rosa", 8.0, 0.667, 7], ["arbol_violeta", 7.0, 0.8, 7],
	["arbol_cipres_azul", 8.0, 0.5, 6], ["arbol_alamo_amarillo", 8.0, 0.417, 6]]

var dt: DirtTrack

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

## Altura del suelo en cualquier punto (camino y banquina: la física; más lejos: el terreno)
func gy(x: float, z: float) -> float:
	var nr := dt.nearest(x, z)
	if float(nr["d"]) < 6.9:
		return dt.axis_height(nr, x, z) + DirtTrack.cross_profile(float(nr["side"]))
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

const ROAD_LAT := [-5.1, -4.6, -4.0, -3.2, -2.4, -1.6, -1.15, -0.95, -0.7, -0.35, 0.0, 0.35, 0.7, 0.95, 1.15, 1.6, 2.4, 3.2, 4.0, 4.6, 5.1]
const SHOULDER_L := [4.9, 5.2, 5.5, 5.9, 6.3, 6.8]

## Cinta del camino + banquinas (con zanja). Cada vértice usa la altura real del eje y el perfil transversal: es la misma superficie que siente la física
func _build_road() -> void:
	var road := _ribbon(ROAD_LAT, 0.0, "tierra", 3.0, true, Color.WHITE, true)
	props.add_child(road)
	_static_trimesh(road.mesh)
	var left := _ribbon(SHOULDER_L, -0.004, "pasto", 3.0, false, Color(0.86, 0.8, 0.56), false)
	var neg: Array = []
	for v in SHOULDER_L:
		neg.append(-float(v))
	neg.reverse()
	var right := _ribbon(neg, -0.004, "pasto", 3.0, false, Color(0.86, 0.8, 0.56), false)
	props.add_child(left)
	props.add_child(right)
	_static_trimesh(left.mesh)
	_static_trimesh(right.mesh)

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
			st.add_vertex(Vector3(q.x, hk + DirtTrack.cross_profile(lat) + dy, q.y))
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
	wm.albedo_color = Color(0.2, 0.15, 0.1, 0.85)
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
	var mm := _mat_tex("tierra", Vector3(0.3, 0.3, 1), 0.3, Color(0.3, 0.2, 0.12))
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
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := dt.pts.size()
		for i in n + 1:
			var k := i % n
			var p := dt.pts[k]
			var tg := dt.tans[k]
			var nl := Vector2(-tg.y, tg.x)
			var q: Vector2 = p + nl * float(side) * DirtTrack.FENCE_HALF
			var c := float(dt.cum[k]) if i < n else dt.length
			var yb := float(dt.hprof[k]) + DirtTrack.cross_profile(DirtTrack.FENCE_HALF) - 0.05
			st.set_uv(Vector2(c / 3.0, 1.0))
			st.add_vertex(Vector3(q.x, yb, q.y))
			st.set_uv(Vector2(c / 3.0, 0.0))
			st.add_vertex(Vector3(q.x, yb + 1.25, q.y))
		for i in n:
			var v0 := i * 2
			if side < 0.0:
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
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(mi)
		_tag(mi, "misc", 260.0)

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

## Bosque: dos hileras altas y apretadas pegadas al cerco (tapan la vista) y relleno hasta 160 m del camino, todo de árboles en cruz posados sobre el terreno
func _build_forest() -> void:
	var tq: float = opts["trees"]
	var groups_x := {}
	for s in SPECIES:
		groups_x[s[0]] = []
	var n := dt.pts.size()
	var step := maxi(1, int(round(3.4 / maxf(0.3, tq) / 2.0)))
	for i in range(0, n, step):
		var p := dt.pts[i]
		var tg := dt.tans[i]
		var nl := Vector2(-tg.y, tg.x)
		for side in [1.0, -1.0]:
			for row in [3.0, 7.5]:
				var off := DirtTrack.FENCE_HALF + float(row) + rng.randf_range(-0.8, 1.2)
				var q: Vector2 = p + nl * float(side) * off + tg * rng.randf_range(-1.2, 1.2)
				var s := _pick_species()
				groups_x[s[0]].append(_xf(Vector3(q.x, gy(q.x, q.y) - 0.1, q.y), rng.randf_range(1.15, 1.75)))
	var sp := 8.0 / maxf(0.4, sqrt(tq))
	var x := -230.0
	while x < 280.0:
		var z := -90.0
		while z < 230.0:
			var px := x + rng.randf_range(-3.2, 3.2)
			var pz := z + rng.randf_range(-3.2, 3.2)
			var nr := dt.nearest(px, pz)
			var d: float = nr["d"]
			if d > DirtTrack.FENCE_HALF + 11.0 and d < 160.0 and rng.randf() < 0.92:
				var s2 := _pick_species()
				groups_x[s2[0]].append(_xf(Vector3(px, dt.terrain_height(px, pz) - 0.1, pz), rng.randf_range(1.0, 1.9)))
			z += sp
		x += sp
	for s in SPECIES:
		var arr: Array = groups_x[s[0]]
		if arr.size() > 0:
			_multi(s[0], float(s[1]) * float(s[2]), float(s[1]), arr, 0.06, Color(0.97, 0.98, 0.97), 230.0, true)

## Sotobosque y detalles: pasto verde, alto y seco, juncos en los charcos, matas, flores de campo, arbustos, rocas en la zanja, troncos caídos, tocones y fardos de heno
func _build_details() -> void:
	var g := float(opts["grass"])
	var n := dt.pts.size()
	var tuft := {"pasto_mata": [], "pasto_alto": [], "pasto_seco": []}
	var tuft_t := ["pasto_mata", "pasto_mata", "pasto_alto", "pasto_seco"]
	var bush_x := {"arbusto_verde": [], "arbusto_flores_rosa": [], "arbusto_flores_amarillo": []}
	var flower_x := {"flor_blanca": [], "flor_amarilla": [], "flor_roja": [], "flor_violeta": []}
	var bt := ["arbusto_verde", "arbusto_flores_rosa", "arbusto_flores_amarillo"]
	var ft := ["flor_blanca", "flor_amarilla", "flor_roja", "flor_violeta"]
	var rock_xf := []
	for i in range(0, n, 1):
		var p2 := dt.pts[i]
		var tg2 := dt.tans[i]
		var nl2 := Vector2(-tg2.y, tg2.x)
		for side in [1.0, -1.0]:
			# pasto en la banquina, la zanja y detrás del cerco
			for k in int(round(3.2 * g)):
				var off2: float = [rng.randf_range(4.6, 6.3), rng.randf_range(6.5, 9.0)][rng.randi() % 2]
				var q2: Vector2 = p2 + nl2 * float(side) * off2 + tg2 * rng.randf_range(-1.0, 1.0)
				tuft[tuft_t[rng.randi() % 4]].append(_xf(Vector3(q2.x, gy(q2.x, q2.y) - 0.02, q2.y), rng.randf_range(0.7, 1.5)))
			# matas altas al borde mismo del camino (poco)
			if rng.randf() < 0.35 * g:
				var q5: Vector2 = p2 + nl2 * float(side) * rng.randf_range(4.3, 4.9)
				tuft["pasto_seco"].append(_xf(Vector3(q5.x, gy(q5.x, q5.y) - 0.02, q5.y), rng.randf_range(0.5, 0.9)))
			if rng.randf() < 0.2 * g:
				var q3: Vector2 = p2 + nl2 * float(side) * (DirtTrack.FENCE_HALF + rng.randf_range(1.2, 4.0))
				bush_x[bt[rng.randi() % 3]].append(_xf(Vector3(q3.x, gy(q3.x, q3.y) - 0.02, q3.y), rng.randf_range(0.8, 1.5)))
			if rng.randf() < 0.32 * g:
				var q4: Vector2 = p2 + nl2 * float(side) * (DirtTrack.FENCE_HALF + rng.randf_range(0.2, 2.2))
				flower_x[ft[rng.randi() % 4]].append(_xf(Vector3(q4.x, gy(q4.x, q4.y) - 0.02, q4.y), rng.randf_range(1.0, 1.7)))
			# piedras de la zanja y del borde
			if rng.randf() < 0.45:
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
	for k in int(26.0 * g) + 4:
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
		board.position = Vector3(q2.x, float(dt.hprof[i]) + 1.6, q2.y)
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
		post2.position = Vector3(q2.x, float(dt.hprof[i]) + 0.65, q2.y)
		props.add_child(post2)
