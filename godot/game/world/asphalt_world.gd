extends "res://game/world/dirt_world.gd"
## Circuito de asfalto: pista ancha con bombeo, líneas blancas, curbs rojos y blancos, zona de escape de grava y pasto, barrera a franjas, neumáticos en las curvas,
## recta de largada con pórtico y línea a cuadros, tribunas con gente de colores, edificio de boxes, carteles de curva y bosque de fondo.
## Todo sale de la curva del eje (AsphaltTrack): la malla, las barreras y la física usan los mismos puntos.

const AsphaltTrack := preload("res://game/world/asphalt_track.gd")

var at: AsphaltTrack
var city := false # circuito urbano: pared de edificios (png) y calle de concreto en vez de bosque y pasto

func _init() -> void:
	at = AsphaltTrack.new()
	dt = at # (el resto del juego —GPS, ayuda de trazada, volver a la pista— habla con world.dt)
	track = at

func _build_scene() -> void:
	_build_terrain_a()
	_build_track()
	_build_barrier()
	_build_tyres()
	if city:
		_build_city_boxes()
		_build_lamps()
	else:
		_build_forest() # (una hilera de árboles bajos + pared de bosque + bandas de pasto: heredado del camino de tierra)
		_build_details(false)
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
func _ground_mat() -> StandardMaterial3D:
	if city:
		return _mat_tex("hormigon", Vector3(1, 1, 1), 0.95, Color(0.74, 0.74, 0.77))
	return _mat_tex("pasto", Vector3(1, 1, 1), 0.95, Color(0.9, 1.0, 0.85))

const FACADE := preload("res://game/world/city_facade.gdshader")

## Edificios como los de Dream City: cajas de ~10 triángulos (pared de frente y costados + techo) y un shader (copiado de Dream Rally) que dibuja las ventanas, postigos,
## balcones, vidrieras y marquesinas a partir de las medidas de la pared y las funde en una pared lisa a lo lejos. Dos filas: una baja pegada y otra más alta detrás.
func _build_city_boxes() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = FACADE
	var gimg := Image.create(128, 128, false, Image.FORMAT_L8)
	var gr := RandomNumberGenerator.new()
	gr.seed = 4
	for y in 128:
		for x in 128:
			gimg.set_pixel(x, y, Color.from_hsv(0, 0, 0.5 + gr.randf_range(-0.12, 0.12)))
	mat.set_shader_parameter("grain", ImageTexture.create_from_image(gimg))
	var walls := [Color(0.84, 0.76, 0.62), Color(0.72, 0.74, 0.78), Color(0.78, 0.56, 0.44), Color(0.88, 0.85, 0.78), Color(0.62, 0.68, 0.72), Color(0.80, 0.66, 0.50), Color(0.70, 0.52, 0.46), Color(0.76, 0.78, 0.66)]
	var n := at.pts.size()
	var fh := AsphaltTrack.FH
	var CH := 17
	for side in [1.0, -1.0]:
		var offs := _wall_offsets(float(side))
		var m := offs.size()
		var sts := {}
		var arcs := {}
		for row in 2:
			var j := 0
			while j < m - 2:
				var w := rng.randf_range(9.0, 17.0)
				# avanza por la curva hasta cubrir el ancho
				var je := j
				var run := 0.0
				while je < m - 1 and run < w:
					var qa := _wall_pt(j, je, side, offs, row)
					run = _wall_pt(j, j, side, offs, row).distance_to(qa)
					je += 1
				if je >= m:
					break
				var p0 := _wall_pt(j, j, side, offs, row)
				var p1 := _wall_pt(j, je, side, offs, row)
				var wdt := p0.distance_to(p1)
				var depth := rng.randf_range(8.0, 12.0)
				var back_i := (j * 3) % n
				var nl := Vector2(-at.tans[back_i].y, at.tans[back_i].x)
				var nrm := nl * float(side)
				var far_pt := p0 + nrm * (depth + 2.0)
				var hgt := rng.randf_range(11.0, 19.0) if row == 0 else rng.randf_range(20.0, 36.0)
				if wdt > 4.0 and _clear_of_other_legs(far_pt, back_i, fh + 4.5) and _clear_of_other_legs(p0, back_i, fh + 4.0) and _clear_of_other_legs(p1, back_i, fh + 4.0):
					var ci := j / CH
					if not sts.has(ci):
						var st := SurfaceTool.new()
						st.begin(Mesh.PRIMITIVE_TRIANGLES)
						sts[ci] = st
						arcs[ci] = [float(at.cum[(j * 3) % n]), float(at.cum[((j + CH) * 3) % n]) if (j + CH) * 3 < n else at.length]
					_add_box(sts[ci], p0, p1, nrm * depth, hgt, walls[rng.randi() % walls.size()], rng.randf())
				j = je + (1 if rng.randf() < 0.5 else 2)
		for ci in sts:
			var st2: SurfaceTool = sts[ci]
			var mi := MeshInstance3D.new()
			mi.mesh = st2.commit()
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props.add_child(mi)
			_tag(mi, "misc", 320.0)
			arc_nodes.append({"n": mi, "ext": 70.0, "a0": float(arcs[ci][0]), "a1": float(arcs[ci][1])})

## punto del frente de los edificios (fila 0 pegada, fila 1 más atrás) en la muestra je
func _wall_pt(_j: int, je: int, side: float, offs: PackedFloat32Array, row: int) -> Vector2:
	var n := at.pts.size()
	var i := (je * 3) % n
	var nl := Vector2(-at.tans[i].y, at.tans[i].x)
	var o := float(offs[je % offs.size()]) - 6.0 + (22.0 if row == 1 else 0.0)
	return at.pts[i] + nl * side * maxf(AsphaltTrack.FH + 3.5, o)

## una caja: frente p0→p1 (el lado que mira al circuito), profundidad d (vector hacia atrás), alto h. UV en metros, UV2 = (ancho, alto), COLOR = pared + semilla
func _add_box(st: SurfaceTool, p0: Vector2, p1: Vector2, d: Vector2, h: float, col: Color, seed: float) -> void:
	var y0 := minf(gy(p0.x, p0.y), gy(p1.x, p1.y)) - 0.6
	var y1 := y0 + h + 0.6
	var c := Color(col.r, col.g, col.b, snappedf(seed, 1.0 / 255.0))
	var w := p0.distance_to(p1)
	var dl := d.length()
	var corners := [p0, p1, p1 + d, p0 + d]
	# paredes: frente (0→1), costado en 1, fondo y costado en 0
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var wl := a.distance_to(b)
		var nrm3 := Vector3(b.y - a.y, 0, -(b.x - a.x)).normalized()
		if k == 0 or k == 2:
			pass
		var verts := [Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)]
		var uvs := [Vector2(0, -0.6), Vector2(wl, -0.6), Vector2(wl, h), Vector2(0, h)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(c)
			st.set_normal(nrm3)
			st.set_uv(uvs[idx])
			st.set_uv2(Vector2(wl, h))
			st.add_vertex(verts[idx])
	# techo
	var rv := [Vector3(p0.x, y1, p0.y), Vector3(p1.x, y1, p1.y), Vector3((p1 + d).x, y1, (p1 + d).y), Vector3((p0 + d).x, y1, (p0 + d).y)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(col.r * 0.92, col.g * 0.92, col.b * 0.92, c.a))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, 0))
		st.set_uv2(Vector2(w, 0.0))
		st.add_vertex(rv[idx])
	dl = dl

## Postes de luz cada 36 m a los dos lados (dos multimallas: poste y farol)
func _build_lamps() -> void:
	var poles: Array = []
	var heads: Array = []
	for i in range(4, at.pts.size(), 18):
		var nl := Vector2(-at.tans[i].y, at.tans[i].x)
		for side in [1.0, -1.0]:
			var q: Vector2 = at.pts[i] + nl * float(side) * (AsphaltTrack.FH + 1.6)
			var y0 := gy(q.x, q.y)
			poles.append(Transform3D(Basis.IDENTITY, Vector3(q.x, y0 + 3.6, q.y)))
			var to_track := Vector3(-nl.x * float(side), 0, -nl.y * float(side))
			var yaw := atan2(to_track.x, to_track.z)
			var hp := Vector3(q.x, y0 + 7.1, q.y) + to_track * 0.7
			heads.append(Transform3D(Basis(Vector3.UP, yaw), hp))
	for e in [[poles, Vector3(0.14, 7.2, 0.14), Color(0.25, 0.26, 0.3)], [heads, Vector3(0.45, 0.14, 1.6), Color(0.96, 0.95, 0.85)]]:
		var xf: Array = e[0]
		var bm := BoxMesh.new()
		bm.size = e[1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bm
		mm.instance_count = xf.size()
		for k in xf.size():
			mm.set_instance_transform(k, xf[k])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var fm := _flat(e[2], 0.8)
		if e[2].r > 0.9:
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = fm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 220.0
		props.add_child(mi)

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
	var mat := _ground_mat()
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.add_child(mi)
	_static_trimesh(mesh)
	var far := _mat_tex("hormigon" if city else "pasto", Vector3(300, 300, 1), 0.95, Color(0.55, 0.55, 0.57) if city else Color(0.55, 0.66, 0.46))
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
	var grass := _ground_mat()
	grass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pl := [g1, g1 + 1.4, g1 + 2.8, f1]
	_band(pl, -0.004, 4.0, 4.0, grass, true)
	_band(_mirror(pl), -0.004, 4.0, 4.0, grass, true)

# ───────────────────────── barrera, neumáticos, arco de salida ─────────────────────────
func _build_barrier() -> void:
	var bt := _img_tex(8, 2, func(x, y): return (Color(0.85, 0.12, 0.1) if x < 4 else Color(0.94, 0.94, 0.94)) if y == 0 else Color(0.28, 0.28, 0.3))
	var bm := _nearest_mat(bt)
	for side in [1.0, -1.0]:
		_wall_chunks(float(side), AsphaltTrack.FH, at.profile(AsphaltTrack.FH) - 0.05, 0.95, 1.0 / 8.0, 0.01, 0.99, bm, false)

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
