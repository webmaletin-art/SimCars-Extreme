extends "res://game/world/lot_world.gd"
## Camino de tierra: circuito cerrado sin rivales, con cerco de madera a cada lado (una sola cara visible: la del lado del camino; el auto no lo cruza), un bosque denso
## de árboles de todos los colores que tapa la vista (atrás no hay nada) y charcos de barro, lomos y ondas sobre el camino.
## Todo sale de la curva del eje (DirtTrack): la malla del camino, los cercos, los árboles y la física usan los mismos puntos.

const DirtTrack := preload("res://game/world/dirt_track.gd")

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
	_build_fences()
	_build_forest()
	_build_props()
	cones = []

func _build_terrain() -> void:
	var far := _mat_tex("pasto", Vector3(300, 300, 1), 0.95, Color(0.62, 0.72, 0.5))
	_plane(Vector2(900, 900), -0.04, far, Vector3(30, 0, 60))
	_static_box(Vector3(30, -0.5, 60), Vector3(900, 1.0, 900))

## Cinta del camino (tierra) + banquina (pasto seco) + charcos de barro
func _build_road() -> void:
	var road := _ribbon(-DirtTrack.ROAD_HALF - 0.7, DirtTrack.ROAD_HALF + 0.7, 0.0, "tierra", 3.0, true)
	props.add_child(road)
	var sh_l := _ribbon(DirtTrack.ROAD_HALF + 0.6, DirtTrack.FENCE_HALF + 0.3, -0.005, "pasto", 3.0, false, Color(0.82, 0.76, 0.52))
	var sh_r := _ribbon(-DirtTrack.FENCE_HALF - 0.3, -DirtTrack.ROAD_HALF - 0.6, -0.005, "pasto", 3.0, false, Color(0.82, 0.76, 0.52))
	props.add_child(sh_l)
	props.add_child(sh_r)
	var mm := _mat_tex("tierra", Vector3(0.3, 0.3, 1), 0.35, Color(0.3, 0.2, 0.12))
	mm.metallic_specular = 0.9
	for m in dt.mud:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(m["r"])
		cm.bottom_radius = float(m["r"])
		cm.height = 0.01
		cm.radial_segments = 20
		mi.mesh = cm
		mi.material_override = mm
		mi.position = Vector3(float(m["x"]), 0.006, float(m["z"]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(mi)

## Cinta a lo largo del eje entre dos distancias laterales (positivo = izquierda del sentido de marcha). uv: x = lateral/tile · y = largo/tile
func _ribbon(a: float, b: float, y: float, tex: String, tile: float, shade: bool, tint := Color.WHITE) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := dt.pts.size()
	for i in n + 1:
		var k := i % n
		var p := dt.pts[k]
		var tg := dt.tans[k]
		var nl := Vector2(-tg.y, tg.x)
		var c := float(dt.cum[k]) if i < n else dt.length
		for e in [a, b]:
			var q: Vector2 = p + nl * float(e)
			var col := Color(1, 1, 1)
			if shade: # huellas más oscuras en el centro y borde claro (polvo)
				var lat := absf(float(e))
				col = Color(0.78, 0.74, 0.7) if lat < 1.6 else (Color(1.0, 1.0, 1.0) if lat < 3.6 else Color(0.9, 0.88, 0.7))
			st.set_color(col)
			st.set_uv(Vector2(float(e) / tile, c / tile))
			st.add_vertex(Vector3(q.x, y, q.y))
	for i in n:
		var v0 := i * 2
		st.add_index(v0)
		st.add_index(v0 + 1)
		st.add_index(v0 + 2)
		st.add_index(v0 + 1)
		st.add_index(v0 + 3)
		st.add_index(v0 + 2)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := _mat_tex(tex, Vector3(1, 1, 1), 0.95, tint)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

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
			st.set_uv(Vector2(c / 3.0, 1.0))
			st.add_vertex(Vector3(q.x, 0.0, q.y))
			st.set_uv(Vector2(c / 3.0, 0.0))
			st.add_vertex(Vector3(q.x, 1.2, q.y))
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

## Bosque: dos hileras altas y apretadas pegadas al cerco (tapan la vista) y relleno hasta 120 m del camino por todos lados, todo de árboles en cruz
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
				groups_x[s[0]].append(_xf(Vector3(q.x, 0, q.y), rng.randf_range(1.15, 1.75)))
	# relleno
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
				groups_x[s2[0]].append(_xf(Vector3(px, 0, pz), rng.randf_range(1.0, 1.9)))
			z += sp
		x += sp
	for s in SPECIES:
		var arr: Array = groups_x[s[0]]
		if arr.size() > 0:
			_multi(s[0], float(s[1]) * float(s[2]), float(s[1]), arr, 0.06, Color(0.97, 0.98, 0.97), 230.0, true)
	# sotobosque: matas de pasto y arbustos pegados al cerco por fuera, flores
	var g := float(opts["grass"])
	var grass_x := []
	var bush_x := {"arbusto_verde": [], "arbusto_flores_rosa": [], "arbusto_flores_amarillo": []}
	var flower_x := {"flor_blanca": [], "flor_amarilla": [], "flor_roja": [], "flor_violeta": []}
	var bt := ["arbusto_verde", "arbusto_flores_rosa", "arbusto_flores_amarillo"]
	var ft := ["flor_blanca", "flor_amarilla", "flor_roja", "flor_violeta"]
	for i in range(0, n, 1):
		var p2 := dt.pts[i]
		var tg2 := dt.tans[i]
		var nl2 := Vector2(-tg2.y, tg2.x)
		for side in [1.0, -1.0]:
			for k in int(round(2.4 * g)):
				var off2 := DirtTrack.FENCE_HALF + rng.randf_range(0.1, 2.6)
				var q2: Vector2 = p2 + nl2 * float(side) * off2 + tg2 * rng.randf_range(-1.0, 1.0)
				grass_x.append(_xf(Vector3(q2.x, -0.02, q2.y), rng.randf_range(0.7, 1.4)))
			if rng.randf() < 0.18 * g:
				var q3: Vector2 = p2 + nl2 * float(side) * (DirtTrack.FENCE_HALF + rng.randf_range(1.2, 4.0))
				bush_x[bt[rng.randi() % 3]].append(_xf(Vector3(q3.x, -0.02, q3.y), rng.randf_range(0.8, 1.5)))
			if rng.randf() < 0.3 * g:
				var q4: Vector2 = p2 + nl2 * float(side) * (DirtTrack.FENCE_HALF + rng.randf_range(0.2, 2.0))
				flower_x[ft[rng.randi() % 4]].append(_xf(Vector3(q4.x, -0.02, q4.y), rng.randf_range(1.0, 1.6)))
	if grass_x.size() > 0:
		_multi("pasto_mata", 0.66, 0.55, grass_x, 0.07, Color.WHITE, 70.0)
	for b in bush_x:
		if bush_x[b].size() > 0:
			_multi(b, 2.0, 1.5, bush_x[b], 0.03, Color.WHITE, 150.0)
	for f in flower_x:
		if flower_x[f].size() > 0:
			_multi(f, 0.23, 0.35, flower_x[f], 0.08, Color.WHITE, 50.0)

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
		post.position = Vector3(q.x, 2.5, q.y)
		props.add_child(post)
	var banner := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3((DirtTrack.ROAD_HALF + 1.0) * 2.0 + 0.4, 1.0, 0.2)
	banner.mesh = bb
	banner.material_override = _flat(Color(0.08, 0.1, 0.14), 0.7)
	banner.position = Vector3(p0.x, 5.2, p0.y)
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
		board.position = Vector3(q2.x, 1.6, q2.y)
		var face := atan2(-n2.x * outer, -n2.y * outer) # mira hacia el eje del camino
		board.rotation.y = face
		props.add_child(board)
		var lb2 := Label3D.new()
		lb2.text = "◀◀◀" if cv > 0.0 else "▶▶▶"
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
		post2.position = Vector3(q2.x, 0.65, q2.y)
		props.add_child(post2)
