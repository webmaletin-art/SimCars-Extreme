extends "res://game/world/dirt_world.gd"
## Circuito de asfalto: pista ancha con bombeo, líneas blancas, curbs rojos y blancos, zona de escape de grava y pasto, barrera a franjas, neumáticos en las curvas,
## recta de largada con pórtico y línea a cuadros, tribunas con gente de colores, edificio de boxes, carteles de curva y bosque de fondo.
## Todo sale de la curva del eje (AsphaltTrack): la malla, las barreras y la física usan los mismos puntos.

const AsphaltTrack := preload("res://game/world/asphalt_track.gd")

var at: AsphaltTrack

func _init() -> void:
	at = AsphaltTrack.new()
	dt = at # (el resto del juego —GPS, ayuda de trazada, volver a la pista— habla con world.dt)
	track = at

func _build_scene() -> void:
	_build_terrain_a()
	_build_track()
	_build_barrier()
	_build_tyres()
	_build_trees()
	_build_scenery()
	_build_start()
	_build_signs_a()
	cones = []

func gy(x: float, z: float) -> float:
	var nr := at.nearest(x, z)
	if float(nr["d"]) < AsphaltTrack.FH + 0.4:
		return at.axis_height(nr, x, z) + at.profile(float(nr["side"]))
	return at.terrain_height(x, z)

# ───────────────────────── texturas hechas en código ─────────────────────────
func _img_tex(w: int, h: int, fn: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, fn.call(x, y))
	return ImageTexture.create_from_image(img)

func _nearest_mat(tex: Texture2D, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

# ───────────────────────── terreno ─────────────────────────
func _build_terrain_a() -> void:
	var x0 := -270.0
	var z0 := -380.0
	var cell := 8.0
	var nx := 94
	var nz := 55
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nse := FastNoiseLite.new()
	nse.seed = 11
	nse.frequency = 0.03
	for i in nx + 1:
		for j in nz + 1:
			var x := x0 + float(i) * cell
			var z := z0 + float(j) * cell
			var v := 0.84 + 0.28 * (nse.get_noise_2d(x, z) * 0.5 + 0.5)
			st.set_color(Color(v, v, v))
			st.set_uv(Vector2(x, z) / 4.0)
			st.add_vertex(Vector3(x, at.terrain_height(x, z), z))
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
	var mat := _mat_tex("pasto", Vector3(1, 1, 1), 0.95, Color(0.9, 1.0, 0.85))
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.add_child(mi)
	_static_trimesh(mesh)
	var far := _mat_tex("pasto", Vector3(300, 300, 1), 0.95, Color(0.55, 0.66, 0.46))
	_plane(Vector2(1800, 1800), -8.0, far, Vector3(150, 0, -120))

# ───────────────────────── cintas de la pista ─────────────────────────
## Cinta a lo largo del eje entre las distancias laterales dadas (con la altura real del eje + perfil + dy). uv = (lat / tile_u, avance / tile_v)
func _band(lats: Array, dy: float, tile_u: float, tile_v: float, mat: Material, collide := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := at.pts.size()
	var m := lats.size()
	for i in n + 1:
		var k := i % n
		var p := at.pts[k]
		var nl := Vector2(-at.tans[k].y, at.tans[k].x)
		var c := float(at.cum[k]) if i < n else at.length
		var hk := float(at.hprof[k])
		for e in lats:
			var lat := float(e)
			var q: Vector2 = p + nl * lat
			st.set_uv(Vector2(lat / tile_u, c / tile_v))
			st.add_vertex(Vector3(q.x, hk + at.profile(lat) + dy, q.y))
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
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.add_child(mi)
	if collide:
		_static_trimesh(mi.mesh)
	return mi

func _mirror(a: Array) -> Array:
	var r: Array = []
	for v in a:
		r.append(-float(v))
	r.reverse()
	return r

func _build_track() -> void:
	var RH := AsphaltTrack.RH
	var KB := AsphaltTrack.KERB
	# asfalto
	var lats: Array = []
	for k in 14:
		lats.append(-RH + (2.0 * RH) * float(k) / 13.0)
	var am := _mat_tex("asfalto", Vector3(1, 1, 1), 0.9, Color(0.78, 0.78, 0.8))
	am.cull_mode = BaseMaterial3D.CULL_DISABLED
	_band(lats, 0.0, 6.0, 6.0, am, true)
	# curbs rojos y blancos (franjas de 1,6 m)
	var kt := _img_tex(2, 2, func(_x, y): return Color(0.85, 0.1, 0.08) if y == 0 else Color(0.95, 0.95, 0.95))
	var km := _nearest_mat(kt)
	var kl := [RH, RH + KB * 0.5, RH + KB]
	_band(kl, 0.003, 1.0, 1.6, km, true)
	_band(_mirror(kl), 0.003, 1.0, 1.6, km, true)
	# líneas blancas de borde
	var white := _flat(Color(0.95, 0.95, 0.92), 0.8)
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	for s in [1.0, -1.0]:
		var e0 := (RH - 0.55) * float(s)
		var e1 := (RH - 0.33) * float(s)
		_band([e0, e1] if s > 0.0 else [e1, e0], 0.014, 1.0, 6.0, white, false)
	# zona de escape: grava y después pasto (la física usa los mismos límites en AsphaltTrack.surface_at)
	var g0 := RH + KB
	var g1 := RH + KB + AsphaltTrack.GRAVEL
	var f1 := AsphaltTrack.FH + 0.5
	var gl := [g0, g0 + 0.9, g0 + 1.8, g1]
	var grav := _mat_tex("tierra", Vector3(1, 1, 1), 0.95, Color(0.78, 0.76, 0.72))
	grav.cull_mode = BaseMaterial3D.CULL_DISABLED
	_band(gl, -0.004, 3.0, 3.0, grav, true)
	_band(_mirror(gl), -0.004, 3.0, 3.0, grav, true)
	var grass := _mat_tex("pasto", Vector3(1, 1, 1), 0.95, Color(0.9, 1.0, 0.82))
	grass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pl := [g1, g1 + 1.4, g1 + 2.8, f1]
	_band(pl, -0.004, 4.0, 4.0, grass, true)
	_band(_mirror(pl), -0.004, 4.0, 4.0, grass, true)

# ───────────────────────── barrera, neumáticos, arco de salida ─────────────────────────
func _build_barrier() -> void:
	var bt := _img_tex(8, 2, func(x, y): return (Color(0.85, 0.12, 0.1) if x < 4 else Color(0.94, 0.94, 0.94)) if y == 0 else Color(0.28, 0.28, 0.3))
	var bm := _nearest_mat(bt)
	for side in [1.0, -1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := at.pts.size()
		for i in n + 1:
			var k := i % n
			var p := at.pts[k]
			var nl := Vector2(-at.tans[k].y, at.tans[k].x)
			var q: Vector2 = p + nl * float(side) * AsphaltTrack.FH
			var c := float(at.cum[k]) if i < n else at.length
			var yb := float(at.hprof[k]) + at.profile(AsphaltTrack.FH) - 0.05
			st.set_uv(Vector2(c / 8.0, 0.99))
			st.add_vertex(Vector3(q.x, yb, q.y))
			st.set_uv(Vector2(c / 8.0, 0.01))
			st.add_vertex(Vector3(q.x, yb + 0.95, q.y))
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
		mi.material_override = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(mi)
		_tag(mi, "misc", 300.0)

## Pilas de neumáticos del lado de afuera de las curvas cerradas
func _build_tyres() -> void:
	var xf: Array = []
	var last := -100
	for i in at.pts.size():
		var cv: float = at.curv[i]
		if absf(cv) < 0.011 or i - last < 2:
			continue
		last = i
		var nl := Vector2(-at.tans[i].y, at.tans[i].x)
		var outer := -1.0 if cv > 0.0 else 1.0
		var q: Vector2 = at.pts[i] + nl * outer * (AsphaltTrack.FH - 0.7)
		var y0 := gy(q.x, q.y)
		for lv in 3:
			xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(q.x, y0 + 0.17 + 0.34 * float(lv), q.y)))
	if xf.is_empty():
		return
	var cm := CylinderMesh.new()
	cm.top_radius = 0.46
	cm.bottom_radius = 0.46
	cm.height = 0.34
	cm.radial_segments = 10
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _flat(Color(0.07, 0.07, 0.08), 0.95)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 200.0
	props.add_child(mi)

# ───────────────────────── bosque y pasto ─────────────────────────
func _build_trees() -> void:
	var tq: float = opts["trees"]
	var groups := {}
	for s in SPECIES:
		groups[s[0]] = []
	var n := at.pts.size()
	var step := maxi(1, int(round(5.0 / maxf(0.3, tq) / 2.0)))
	for i in range(0, n, step):
		var nl := Vector2(-at.tans[i].y, at.tans[i].x)
		for side in [1.0, -1.0]:
			var off := AsphaltTrack.FH + rng.randf_range(7.0, 11.0)
			var q: Vector2 = at.pts[i] + nl * float(side) * off
			var s := _pick_species()
			groups[s[0]].append(_xf(Vector3(q.x, gy(q.x, q.y) - 0.1, q.y), rng.randf_range(1.1, 1.7)))
	var sp := 13.0 / maxf(0.4, sqrt(tq))
	var x := -250.0
	while x < 600.0:
		var z := -360.0
		while z < 130.0:
			var px := x + rng.randf_range(-4.0, 4.0)
			var pz := z + rng.randf_range(-4.0, 4.0)
			var d: float = at.nearest(px, pz)["d"]
			if d > AsphaltTrack.FH + 16.0 and d < 170.0 and rng.randf() < 0.85:
				var s2 := _pick_species()
				groups[s2[0]].append(_xf(Vector3(px, at.terrain_height(px, pz) - 0.1, pz), rng.randf_range(1.0, 1.9)))
			z += sp
		x += sp
	for s in SPECIES:
		var arr: Array = groups[s[0]]
		if arr.size() > 0:
			_multi(s[0], float(s[1]) * float(s[2]), float(s[1]), arr, 0.06, Color(0.97, 0.98, 0.97), 240.0, true)
	# pasto corto en la zona de escape y mata alta / arbustos / flores detrás de la barrera
	var g := float(opts["grass"])
	var tuft := {"pasto_mata": [], "pasto_alto": [], "pasto_seco": []}
	var bush := {"arbusto_verde": [], "arbusto_flores_rosa": [], "arbusto_flores_amarillo": []}
	var flo := {"flor_blanca": [], "flor_amarilla": [], "flor_roja": [], "flor_violeta": []}
	var bt := ["arbusto_verde", "arbusto_flores_rosa", "arbusto_flores_amarillo"]
	var ft := ["flor_blanca", "flor_amarilla", "flor_roja", "flor_violeta"]
	for i in range(0, n, 2):
		var nl2 := Vector2(-at.tans[i].y, at.tans[i].x)
		for side in [1.0, -1.0]:
			for k in int(round(2.0 * g)):
				var off2 := rng.randf_range(AsphaltTrack.RH + AsphaltTrack.KERB + AsphaltTrack.GRAVEL + 0.4, AsphaltTrack.FH - 0.6) if rng.randf() < 0.5 else rng.randf_range(AsphaltTrack.FH + 0.6, AsphaltTrack.FH + 6.0)
				var q2: Vector2 = at.pts[i] + nl2 * float(side) * off2 + at.tans[i] * rng.randf_range(-1.0, 1.0)
				var tt: String = ["pasto_mata", "pasto_mata", "pasto_alto", "pasto_seco"][rng.randi() % 4]
				tuft[tt].append(_xf(Vector3(q2.x, gy(q2.x, q2.y) - 0.02, q2.y), rng.randf_range(0.7, 1.4)))
			if rng.randf() < 0.18 * g:
				var q3: Vector2 = at.pts[i] + nl2 * float(side) * (AsphaltTrack.FH + rng.randf_range(1.5, 5.0))
				bush[bt[rng.randi() % 3]].append(_xf(Vector3(q3.x, gy(q3.x, q3.y) - 0.02, q3.y), rng.randf_range(0.8, 1.5)))
			if rng.randf() < 0.3 * g:
				var q4: Vector2 = at.pts[i] + nl2 * float(side) * (AsphaltTrack.FH + rng.randf_range(0.8, 3.0))
				flo[ft[rng.randi() % 4]].append(_xf(Vector3(q4.x, gy(q4.x, q4.y) - 0.02, q4.y), rng.randf_range(1.0, 1.7)))
	for t in tuft:
		if tuft[t].size() > 0:
			_multi(t, 0.66 if t == "pasto_mata" else 0.7, 0.5 if t == "pasto_mata" else 0.8, tuft[t], 0.07, Color.WHITE, 75.0)
	for b in bush:
		if bush[b].size() > 0:
			_multi(b, 2.0, 1.5, bush[b], 0.03, Color.WHITE, 150.0)
	for f in flo:
		if flo[f].size() > 0:
			_multi(f, 0.23, 0.35, flo[f], 0.08, Color.WHITE, 50.0)

# ───────────────────────── tribunas y boxes ─────────────────────────
func _box(pos: Vector3, size: Vector3, mat: Material, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	props.add_child(mi)
	_tag(mi, "misc", 320.0)
	return mi

func _build_scenery() -> void:
	# a lo largo de la recta de largada: tribuna del lado izquierdo (+) y edificio de boxes del derecho (−)
	var conc := _mat_tex("hormigon", Vector3(1, 1, 1), 0.95, Color(0.78, 0.78, 0.8))
	var roof := _flat(Color(0.8, 0.12, 0.1), 0.7)
	var crowd_x: Array = []
	for z0 in 2: # dos tribunas: una frente a la largada y otra más adelante
		var i := (6 + z0 * 38) % at.pts.size()
		var p := at.pts[i]
		var tg := at.tans[i]
		var nl := Vector2(-tg.y, tg.x)
		var yaw := atan2(tg.x, tg.y)
		var base := AsphaltTrack.FH + 5.0
		var y0 := float(at.hprof[i])
		for tier in 4:
			var q: Vector2 = p + nl * (base + float(tier) * 1.1)
			var h := 0.9 + 0.9 * float(tier)
			_box(Vector3(q.x, y0 + h * 0.5, q.y), Vector3(1.1, h, 34.0), conc, yaw)
			# gente: filas de cubitos de colores sobre cada escalón
			for k in 26:
				if rng.randf() < 0.82:
					var along := -16.0 + float(k) * 1.25
					var qp: Vector2 = q + tg * along + nl * 0.0
					var col := Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.9), rng.randf_range(0.6, 1.0))
					crowd_x.append([Transform3D(Basis.IDENTITY, Vector3(qp.x, y0 + h + 0.28, qp.y)), col])
		# techo sobre postes
		var qr: Vector2 = p + nl * (base + 3.4)
		_box(Vector3(qr.x, y0 + 6.4, qr.y), Vector3(8.0, 0.25, 34.0), roof, yaw)
		for pz in [-16.0, 0.0, 16.0]:
			for pn in [0.5, 6.6]:
				var qq: Vector2 = p + nl * (base - 0.5 + float(pn)) + tg * float(pz)
				_box(Vector3(qq.x, y0 + 3.2, qq.y), Vector3(0.3, 6.4, 0.3), conc)
	if crowd_x.size() > 0:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.55, 0.4)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = bm
		mm.instance_count = crowd_x.size()
		for k in crowd_x.size():
			mm.set_instance_transform(k, crowd_x[k][0])
			mm.set_instance_color(k, crowd_x[k][1])
		var cmi := MultiMeshInstance3D.new()
		cmi.multimesh = mm
		var cmat := StandardMaterial3D.new()
		cmat.vertex_color_use_as_albedo = true
		cmat.roughness = 0.9
		cmat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		cmi.material_override = cmat
		cmi.visibility_range_end = 260.0
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(cmi)
	# edificio de boxes del lado derecho de la recta
	var i2 := 30
	var p2 := at.pts[i2]
	var tg2 := at.tans[i2]
	var nl2 := Vector2(-tg2.y, tg2.x)
	var q2: Vector2 = p2 - nl2 * (AsphaltTrack.FH + 8.0)
	var y2 := float(at.hprof[i2])
	var gar := _mat_tex("fachada_b", Vector3(6, 1, 1), 0.9, Color(0.95, 0.95, 0.95))
	var yaw2 := atan2(tg2.x, tg2.y)
	_box(Vector3(q2.x, y2 + 3.0, q2.y), Vector3(7.0, 6.0, 90.0), gar, yaw2)
	_box(Vector3(q2.x, y2 + 6.2, q2.y), Vector3(8.0, 0.4, 91.0), _flat(Color(0.15, 0.16, 0.2), 0.7), yaw2)

# ───────────────────────── largada ─────────────────────────
func _build_start() -> void:
	var p0 := at.pts[0]
	var tg := at.tans[0]
	var nl := Vector2(-tg.y, tg.x)
	var yaw := atan2(tg.x, tg.y)
	var RH := AsphaltTrack.RH
	# línea a cuadros pegada al asfalto (tablero de 0,8 m)
	var ct := _img_tex(2, 2, func(x, y): return Color(0.05, 0.05, 0.05) if (x + y) % 2 == 0 else Color(0.97, 0.97, 0.97))
	var cm := _nearest_mat(ct)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := RH - 0.6
	var corners := [[-w, -0.8], [w, -0.8], [-w, 0.8], [w, 0.8]]
	for c in corners:
		var q: Vector2 = p0 + nl * float(c[0]) + tg * float(c[1])
		st.set_uv(Vector2(float(c[0]) / 0.8, float(c[1]) / 0.8))
		st.add_vertex(Vector3(q.x, float(at.hprof[0]) + at.profile(float(c[0])) + 0.016, q.y))
	st.add_index(0)
	st.add_index(2)
	st.add_index(1)
	st.add_index(1)
	st.add_index(2)
	st.add_index(3)
	st.generate_normals()
	var line := MeshInstance3D.new()
	line.mesh = st.commit()
	line.material_override = cm
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.add_child(line)
	# pórtico
	var metal := _flat(Color(0.2, 0.2, 0.24), 0.6)
	var hp := float(at.hprof[0])
	for s in [1.0, -1.0]:
		var q2: Vector2 = p0 + nl * float(s) * (RH + 1.6)
		_box(Vector3(q2.x, hp + 3.2, q2.y), Vector3(0.6, 6.4, 0.6), metal)
	var ban := _box(Vector3(p0.x, hp + 6.5, p0.y), Vector3((RH + 1.6) * 2.0 + 0.8, 1.6, 0.4), _flat(Color(0.08, 0.1, 0.14), 0.7), yaw)
	for sd in [1.0, -1.0]:
		var lb := Label3D.new()
		lb.text = "META · SIMCAR EXTREME"
		lb.font_size = 72
		lb.pixel_size = 0.014
		lb.modulate = Color(1, 0.85, 0.2)
		lb.shaded = false
		lb.double_sided = false
		lb.position = ban.position + Vector3(tg.x, 0, tg.y) * (0.22 * float(sd))
		lb.rotation.y = yaw + (0.0 if sd < 0.0 else PI)
		props.add_child(lb)

## Carteles de curva (flecha y distancia) del lado de afuera, antes de cada curva cerrada
func _build_signs_a() -> void:
	var last := -100
	for i in at.pts.size():
		var cv: float = at.curv[i]
		if absf(cv) < 0.013 or i - last < 12:
			continue
		last = i
		var j := (i - 14 + at.pts.size()) % at.pts.size() # el cartel va 28 m antes del vértice de la curva
		var t2 := at.tans[j]
		var n2 := Vector2(-t2.y, t2.x)
		var outer := -1.0 if cv > 0.0 else 1.0
		var q2: Vector2 = at.pts[j] + n2 * outer * (AsphaltTrack.FH + 1.4)
		var h0 := float(at.hprof[j])
		var board := _box(Vector3(q2.x, h0 + 2.4, q2.y), Vector3(3.0, 1.5, 0.12), _flat(Color(0.95, 0.75, 0.05), 0.6))
		var face := atan2(-n2.x * outer, -n2.y * outer)
		board.rotation.y = face
		var lb2 := Label3D.new()
		lb2.text = "<<<" if cv > 0.0 else ">>>"
		lb2.font_size = 90
		lb2.pixel_size = 0.011
		lb2.modulate = Color(0.1, 0.1, 0.1)
		lb2.shaded = false
		lb2.double_sided = false
		lb2.position = board.position + Vector3(-n2.x * outer, 0, -n2.y * outer) * 0.08
		lb2.rotation.y = face
		props.add_child(lb2)
		_box(Vector3(q2.x, h0 + 0.9, q2.y), Vector3(0.12, 1.8, 0.12), _flat(Color(0.3, 0.3, 0.3)))
