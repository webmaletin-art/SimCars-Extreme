extends Node3D
## El estacionamiento de pruebas, todo «papercraft»: suelo con texturas hechas en Blender, lomadas y rampas armadas desde la MISMA función que usa la física,
## autos estacionados, conos y postes que vuelan y se rompen (Jolt), tierra con piedras, límites, vegetación en cruz que se mece y, atrás, cajas de cartón con fachadas.
## Física del auto = LotTrack (propia). Física de las cosas sueltas (conos, postes caídos, piezas del auto) = el motor (RigidBody3D).
##
## Capas de colisión del motor:  1 suelo y paredes · 2 el auto del jugador (AnimatableBody3D) · 4 piezas del auto · 8 conos y cosas sueltas

const LotTrack := preload("res://game/world/lot_track.gd")
const CarVisual := preload("res://game/car/car_visual.gd")
const Garage := preload("res://game/data/garage.gd")
const TEX := "res://game/tex/"
const SWAY := preload("res://game/world/sway.gdshader")
const PARKED_IDS := ["mclaren_f1", "mclaren_f1_gtr", "aventador_s", "ranger_limited", "rx3_savanna", "cls63_amg"]

var track := LotTrack.new()
var sun: DirectionalLight3D
var debris: Node3D # piezas sueltas (CarVisual las deja acá)
var props: Node3D
var cones: Array = []
var poles := {} # id → {node, x, z}
var parked: Array = [] # [{vis, circles}]
var trees: Array = [] # {mm, idx, x, z, r, kick}
var car_body: AnimatableBody3D
var car_xf := Transform3D.IDENTITY
var opts := {"parked": 7, "grass": 1.0, "trees": 1.0, "shadows": true, "backdrop": true, "cones": true}
var rng := RandomNumberGenerator.new()
var _cone_mesh: ArrayMesh
var _mats := {}
var _mm_all: Array = []
## Grupos para el diagnóstico y la «distancia de detalle»: nombre → [[nodo, alcance base (m)]]
var groups := {"grass": [], "trees": [], "backdrop": [], "parked": [], "misc": []}
var detail_k := 1.0

func _tag(n: Node, g: String, rng: float) -> void:
	if g == "auto": # multimallas de vegetación: árboles por un lado, el resto (pasto, flores, arbustos) por otro
		var mi := n as GeometryInstance3D
		g = "trees" if mi.has_meta("tree") else "grass"
		rng = mi.visibility_range_end
	groups[g].append([n, rng])
	if n is GeometryInstance3D and rng > 0.0:
		(n as GeometryInstance3D).visibility_range_end = rng * detail_k

## Autos estacionados: sólo la carrocería hace sombra (las piezas, ruedas e interior no: cada malla con sombra se dibuja dos veces más)
func _cheap_shadows(v: Node3D) -> void:
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var p: Node = mi.get_parent()
		if p == null or p.name != "body":
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## «Distancia de detalle»: multiplica hasta dónde se dibuja la vegetación, los autos estacionados y lo chico (0,3 = muy cerca … 2 = lejos)
func set_detail_distance(k: float) -> void:
	detail_k = k
	for g in groups:
		for e in groups[g]:
			var n: Node = e[0]
			var r: float = e[1]
			if not is_instance_valid(n) or r <= 0.0:
				continue
			if n is GeometryInstance3D:
				(n as GeometryInstance3D).visibility_range_end = r * k
			elif n is Node3D: # autos estacionados: cada malla del modelo
				for c in n.find_children("*", "GeometryInstance3D", true, false):
					(c as GeometryInstance3D).visibility_range_end = r * k

## Distancia de dibujo: la niebla se cierra antes para tapar el corte; los edificios de fondo sólo si se llega a verlos
func set_view_distance(d: float) -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	for c in get_children():
		if c is WorldEnvironment:
			we = c
	if we != null:
		we.environment.fog_density = clampf(1.2 / d, 0.0015, 0.02)
	set_group_visible("backdrop", d >= 180.0 and bool(opts["backdrop"]))

func set_group_visible(g: String, on: bool) -> void:
	for e in groups.get(g, []):
		if is_instance_valid(e[0]):
			(e[0] as Node3D).visible = on
var wind := 0.6

func _tex(n: String) -> Texture2D:
	var p := TEX + n + ".png"
	if _mats.has(p):
		return _mats[p]
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_mats[p] = t
	return t

func _mat_tex(n: String, uv := Vector3(1, 1, 1), rough := 0.92, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var t := _tex(n)
	if t != null:
		m.albedo_texture = t
	m.albedo_color = tint
	m.uv1_scale = uv
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m

func _flat(col: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m

# ───────────────────────── armado ─────────────────────────
func build(p_opts := {}) -> void:
	for k in p_opts:
		opts[k] = p_opts[k]
	rng.seed = 20261123
	debris = Node3D.new()
	debris.name = "debris"
	add_child(debris)
	props = Node3D.new()
	props.name = "props"
	add_child(props)
	_build_environment()
	_build_ground()
	_build_features()
	_build_walls()
	_build_poles()
	if opts["cones"]:
		_build_cones()
	_build_barriers()
	_build_parked()
	_build_nature()
	_build_signs()
	if opts["backdrop"]:
		_build_backdrop()
	car_body = AnimatableBody3D.new()
	car_body.name = "car_body"
	car_body.collision_layer = 2
	car_body.collision_mask = 0
	car_body.sync_to_physics = true
	add_child(car_body)

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := PanoramaSkyMaterial.new()
	if _tex("cielo") != null:
		sm.panorama = _tex("cielo")
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.9)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.82, 0.92)
	env.fog_density = 0.0022
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = opts["shadows"]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_bias = 0.05
	add_child(sun)

func _plane(size: Vector2, y: float, mat: Material, center := Vector3.ZERO, uv := Vector2(1, 1)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.position = center + Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props.add_child(mi)
	return mi

func _static_box(pos: Vector3, size: Vector3, yaw := 0.0, layer := 1) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = yaw
	add_child(sb)
	return sb

func _build_ground() -> void:
	var H := LotTrack.HALF
	# asfalto del lote (la textura se repite cada 3 m)
	_plane(Vector2(H.x * 2, H.y * 2), 0.0, _mat_tex("asfalto", Vector3(H.x * 2 / 3.0, H.y * 2 / 3.0, 1)))
	# tierra
	for r in track.dirt_rects:
		var rr: Rect2 = r
		_plane(rr.size, 0.008, _mat_tex("tierra", Vector3(rr.size.x / 3.0, rr.size.y / 3.0, 1)), Vector3(rr.get_center().x, 0, rr.get_center().y))
	for r in track.grass_rects:
		var rr: Rect2 = r
		_plane(rr.size, 0.004, _mat_tex("pasto", Vector3(rr.size.x / 3.0, rr.size.y / 3.0, 1)), Vector3(rr.get_center().x, 0, rr.get_center().y))
	# marcas viales (PNG con transparencia que se hizo en Blender: cubre todo el lote)
	if _tex("marcas") != null:
		var mm := _mat_tex("marcas", Vector3(1, 1, 1))
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		mm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		_plane(Vector2(H.x * 2, H.y * 2), 0.016, mm)
	# fuera del lote: pasto lejano hasta el horizonte
	var far := _mat_tex("pasto", Vector3(120, 120, 1), 0.95, Color(0.78, 0.86, 0.7))
	var fp := _plane(Vector2(400, 400), -0.02, far)
	# piso del motor de física (cosas sueltas): una caja enorme
	_static_box(Vector3(0, -0.5, 0), Vector3(600, 1.0, 600))

## Lomadas, ondas, rampas y montículos: la malla sale de track.feat_height (igual a la física)
func _build_features() -> void:
	for f in track.features:
		var mi := MeshInstance3D.new()
		var mesh := _feature_mesh(f)
		mi.mesh = mesh
		var dirt: bool = String(f["t"]) == "mound" or f.get("dirt", false)
		var mat: StandardMaterial3D
		if dirt:
			mat = _mat_tex("tierra", Vector3(1.0 / 3.0, 1.0 / 3.0, 1))
		else:
			mat = _mat_tex("asfalto", Vector3(1.0 / 3.0, 1.0 / 3.0, 1))
			mat.vertex_color_use_as_albedo = true
		mat.uv1_triplanar = false
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		props.add_child(mi)
		_tag(mi, "misc", 160.0)
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		sb.add_child(cs)
		add_child(sb)

func _feature_mesh(f: Dictionary) -> ArrayMesh:
	var l := float(f["l"])
	var w := float(f["w"])
	var step := 0.25 if String(f["t"]) in ["hump", "wash", "curb"] else 0.4
	var nu := maxi(2, int(ceil(l / step)))
	var nv := maxi(2, int(ceil(w / 0.5)))
	var yaw := float(f["yaw"])
	var c := cos(yaw)
	var s := sin(yaw)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kind := String(f["t"])
	var dirt: bool = kind == "mound" or f.get("dirt", false)
	for i in nu + 1:
		for j in nv + 1:
			var u := -l * 0.5 + l * float(i) / float(nu)
			var v := -w * 0.5 + w * float(j) / float(nv)
			var x := float(f["cx"]) + u * c - v * s
			var z := float(f["cz"]) + u * s + v * c
			var h := track.feat_height(f, x, z)
			var col := Color(1, 1, 1)
			if not dirt:
				if kind == "hump" or kind == "curb":
					# franjas amarillas y negras en diagonal (como las lomadas pintadas de verdad)
					var k := int(floor((u + absf(v) * 0.55) / 0.42))
					col = Color(0.95, 0.75, 0.08) if k % 2 == 0 else Color(0.12, 0.12, 0.12)
					col = col.lerp(Color(0.5, 0.5, 0.5), 0.15)
				elif kind == "ramp":
					var edge := absf(v) > w * 0.5 - 0.3
					col = Color(0.95, 0.35, 0.1) if edge else Color(0.55, 0.55, 0.55)
				elif kind == "twist":
					col = Color(0.8, 0.8, 0.8) if int(floor((u + v) / 0.8)) % 2 == 0 else Color(0.35, 0.35, 0.35)
				elif kind == "wash":
					col = Color(0.62, 0.62, 0.62)
				elif kind == "bank":
					col = Color(0.7, 0.7, 0.7)
			st.set_color(col)
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, h + 0.002, z))
	for i in nu:
		for j in nv:
			var a := i * (nv + 1) + j
			var b := a + 1
			var cc := a + (nv + 1)
			var d := cc + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(cc)
			st.add_index(b)
			st.add_index(d)
			st.add_index(cc)
	st.generate_normals()
	return st.commit()

func _build_walls() -> void:
	var H := LotTrack.HALF
	var wall_h := 1.15
	var mat := _mat_tex("hormigon", Vector3(8, 1, 1), 0.95)
	for side in [[Vector2(0, H.y + 0.25), Vector2(H.x * 2 + 1.0, 0.5)], [Vector2(0, -H.y - 0.25), Vector2(H.x * 2 + 1.0, 0.5)], [Vector2(H.x + 0.25, 0), Vector2(0.5, H.y * 2)], [Vector2(-H.x - 0.25, 0), Vector2(0.5, H.y * 2)]]:
		var c: Vector2 = side[0]
		var sz: Vector2 = side[1]
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(sz.x, wall_h, sz.y)
		mi.mesh = bm
		var m2 := mat.duplicate() as StandardMaterial3D
		m2.uv1_scale = Vector3(maxf(sz.x, sz.y) / 4.0, 0.3, 1)
		mi.material_override = m2
		mi.position = Vector3(c.x, wall_h * 0.5, c.y)
		props.add_child(mi)
		_static_box(mi.position, bm.size)
		# franja roja y blanca de aviso en lo alto del muro
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(sz.x + 0.02 if sz.x > sz.y else 0.52, 0.16, 0.52 if sz.x > sz.y else sz.y + 0.02)
		strip.mesh = sm
		strip.material_override = _flat(Color(0.8, 0.12, 0.1))
		strip.position = Vector3(c.x, wall_h + 0.02, c.y)
		props.add_child(strip)

func _build_barriers() -> void:
	# barreras New Jersey en la entrada de la tierra y alrededor de la zona de rampas; bloques de hormigón sueltos
	var mat := _mat_tex("hormigon", Vector3(1, 1, 1), 0.95)
	var spots := [[10.5, 4.0, 0.0], [10.5, 6.3, 0.0], [10.5, 8.6, 0.0], [10.5, 10.9, 0.0], [14.0, -33.8, 0.0], [20.0, -33.8, 0.0], [26.0, -33.8, 0.0], [32.0, -33.8, 0.0], [38.0, -33.8, 0.0], [44.0, -33.8, 0.0]]
	for sp in spots:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.2, 0.82, 0.55) if sp[2] == 0.0 else Vector3(0.55, 0.82, 2.2)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(sp[0], 0.41, sp[1])
		props.add_child(mi)
		_static_box(mi.position, bm.size)
		track.add_box(sp[0], sp[1], bm.size.x * 0.5, bm.size.z * 0.5, 0.0, "barrier")
	# pila de neumáticos
	var tire_m := _flat(Color(0.05, 0.05, 0.055), 0.95)
	for p in [Vector2(11.0, 14.0), Vector2(11.0, 15.0), Vector2(-48.0, 4.0), Vector2(-48.0, 5.1)]:
		for k in 3:
			var t := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.18
			tm.outer_radius = 0.38
			tm.rings = 12
			tm.ring_segments = 6
			t.mesh = tm
			t.material_override = tire_m
			t.position = Vector3(p.x, 0.19 + k * 0.28, p.y)
			props.add_child(t)
		track.add_circle(p.x, p.y, 0.45, "tires")
		_static_box(Vector3(p.x, 0.45, p.y), Vector3(0.8, 0.9, 0.8))

# ───────────────────────── postes de luz (se rompen) ─────────────────────────
func _build_poles() -> void:
	var spots := [Vector2(-40, 18), Vector2(-20, 18), Vector2(0, 18), Vector2(-30, -3), Vector2(-10, -3), Vector2(10, -3), Vector2(-40, -28), Vector2(-25, -28), Vector2(-8, -34 + 3.0)]
	var i := 0
	for p in spots:
		var id := "pole_%d" % i
		var n := _make_pole()
		n.position = Vector3(p.x, 0, p.y)
		n.rotation.y = rng.randf() * TAU
		props.add_child(n)
		_tag(n, "misc", 160.0)
		poles[id] = {"node": n, "x": p.x, "z": p.y}
		track.add_circle(p.x, p.y, 0.24, id, null, true)
		i += 1

func _make_pole() -> Node3D:
	var root := Node3D.new()
	var metal := _flat(Color(0.42, 0.45, 0.48), 0.6)
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.14
	cm.height = 6.2
	base.mesh = cm
	base.material_override = metal
	base.position.y = 3.1
	root.add_child(base)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.4, 0.06, 0.4)
	plate.mesh = pm
	plate.material_override = metal
	plate.position.y = 0.03
	root.add_child(plate)
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(1.4, 0.07, 0.07)
	arm.mesh = am
	arm.material_override = metal
	arm.position = Vector3(0.6, 6.1, 0)
	root.add_child(arm)
	var lamp := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.7, 0.12, 0.28)
	lamp.mesh = lm
	var lmat := _flat(Color(0.95, 0.93, 0.8), 0.4)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.95, 0.75)
	lmat.emission_energy_multiplier = 0.6
	lamp.material_override = lmat
	lamp.position = Vector3(1.2, 6.06, 0)
	root.add_child(lamp)
	return root

## Una lista de {id, x, z, vx, vz} que dejó el auto al pasarles por encima rápido: los postes caen como cuerpos rígidos
func process_breaks() -> void:
	for b in track.pop_breaks():
		var id := String(b["id"])
		if not poles.has(id):
			continue
		var P: Dictionary = poles[id]
		var n: Node3D = P["node"]
		var rb := RigidBody3D.new()
		rb.mass = 90.0
		rb.collision_layer = 8
		rb.collision_mask = 1 | 8
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.22, 6.2, 0.22)
		cs.shape = bs
		cs.position.y = 3.1
		rb.add_child(cs)
		debris.add_child(rb)
		rb.global_transform = n.global_transform
		n.reparent(rb, false)
		n.transform = Transform3D.IDENTITY
		var dir := Vector3(float(b["vx"]), 0, float(b["vz"])).normalized()
		rb.apply_impulse(dir * 90.0 * 2.0 + Vector3(0, 40, 0), Vector3(0, 4.5, 0))
		rb.angular_velocity = dir.cross(Vector3.UP) * 1.6
		poles.erase(id)

# ───────────────────────── conos ─────────────────────────
func _make_cone_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 10
	var rings := [[0.04, 0.165, 0], [0.26, 0.115, 0], [0.30, 0.108, 1], [0.42, 0.075, 1], [0.46, 0.070, 0], [0.70, 0.016, 0]] # [y, radio, banda blanca]
	var orange := Color(1.0, 0.38, 0.04)
	var white := Color(0.95, 0.95, 0.92)
	for r in rings.size() - 1:
		var a: Array = rings[r]
		var b: Array = rings[r + 1]
		var col := white if (int(a[2]) == 1 and int(b[2]) == 1) else orange
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var p00 := Vector3(cos(t0) * float(a[1]), float(a[0]), sin(t0) * float(a[1]))
			var p01 := Vector3(cos(t1) * float(a[1]), float(a[0]), sin(t1) * float(a[1]))
			var p10 := Vector3(cos(t0) * float(b[1]), float(b[0]), sin(t0) * float(b[1]))
			var p11 := Vector3(cos(t1) * float(b[1]), float(b[0]), sin(t1) * float(b[1]))
			for v in [p00, p10, p01, p01, p10, p11]:
				st.set_color(col)
				st.add_vertex(v)
	# base negra cuadrada
	var bk := Color(0.06, 0.06, 0.06)
	var hs := 0.21
	var y0 := 0.0
	var y1 := 0.045
	var c8 := [Vector3(-hs, y0, -hs), Vector3(hs, y0, -hs), Vector3(hs, y0, hs), Vector3(-hs, y0, hs), Vector3(-hs, y1, -hs), Vector3(hs, y1, -hs), Vector3(hs, y1, hs), Vector3(-hs, y1, hs)]
	for f in [[4, 7, 6, 5], [0, 1, 2, 3], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]:
		for v in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			st.set_color(bk)
			st.add_vertex(c8[v])
	st.generate_normals()
	return st.commit()

func make_cone(pos: Vector3, yaw := 0.0) -> RigidBody3D:
	if _cone_mesh == null:
		_cone_mesh = _make_cone_mesh()
	var rb := RigidBody3D.new()
	rb.mass = 1.6
	rb.collision_layer = 8
	rb.collision_mask = 1 | 2 | 4 | 8
	rb.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.35
	rb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for sx in [-0.21, 0.21]:
		for sz in [-0.21, 0.21]:
			pts.append(Vector3(sx, 0.0, sz))
			pts.append(Vector3(sx, 0.045, sz))
	for k in 8:
		var a := TAU * k / 8.0
		pts.append(Vector3(cos(a) * 0.12, 0.3, sin(a) * 0.12))
		pts.append(Vector3(cos(a) * 0.02, 0.7, sin(a) * 0.02))
	sh.points = pts
	cs.shape = sh
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _cone_mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	mi.material_override = m
	rb.add_child(mi)
	rb.position = pos
	rb.rotation.y = yaw
	debris.add_child(rb)
	cones.append(rb)
	return rb

func _build_cones() -> void:
	# slalom: 12 conos cada 6 m en el oeste
	for i in 12:
		make_cone(Vector3(-46.0 + i * 3.4, 0.02, -8.0 + (0.0 if i % 2 == 0 else 0.0)))
	# puertas de conos (pares separados 3 m) para pasar de costado
	for i in 5:
		make_cone(Vector3(-40.0 + i * 8.0, 0.02, -17.0 - 1.5))
		make_cone(Vector3(-40.0 + i * 8.0, 0.02, -17.0 + 1.5))
	# pirámide de bolos: 10 conos en triángulo (se desparraman al pegarles)
	for r in 4:
		for k in (4 - r):
			make_cone(Vector3(-24.0 + float(k) * 0.55 - float(4 - r) * 0.275, 0.02, -26.0 + r * 0.55))
	# línea larga para frenar: 6 conos
	for i in 6:
		make_cone(Vector3(-4.0 + i * 1.6, 0.02, 22.0))
	# cordón de conos en la entrada de la tierra
	for i in 8:
		make_cone(Vector3(11.4, 0.02, 14.0 + i * 2.1 - 7.0 + 8.0))

# ───────────────────────── autos estacionados ─────────────────────────
func _build_parked() -> void:
	var n := int(opts["parked"])
	if n <= 0:
		return
	var bays: Array = []
	for i in 12:
		bays.append(Vector3(-42.0 + i * 2.7 + 1.35, 26.6, 0.0))
	bays.shuffle()
	for i in mini(n, bays.size()):
		var cid: String = PARKED_IDS[rng.randi() % PARKED_IDS.size()]
		var v := CarVisual.new(cid, true)
		if v.model == null:
			continue
		var b: Vector3 = bays[i]
		var yaw := PI if rng.randf() < 0.6 else 0.0
		yaw += rng.randf_range(-0.04, 0.04)
		v.position = Vector3(b.x, 0, b.y)
		v.rotation.y = yaw
		v.debris_root = debris
		props.add_child(v)
		_tag(v, "parked", 140.0)
		_cheap_shadows(v)
		var pcol: Dictionary = Garage.PAINTS[1 + rng.randi() % (Garage.PAINTS.size() - 1)]
		v.set_paint(Color.html(pcol["c"]))
		# la física de los autos estacionados: tres círculos a lo largo
		var m: Dictionary = v.meta
		var L: float = minf(float(m.get("length", 4.6)) * 0.9, 5.0)
		var r := clampf(float(m.get("width", 1.9)) * 0.5 * 0.82, 0.7, 1.0)
		var circles := []
		for off in [-(L * 0.5 - r), 0.0, (L * 0.5 - r)]:
			var cx := b.x + sin(yaw) * float(off)
			var cz := b.y + cos(yaw) * float(off)
			circles.append(track.add_circle(cx, cz, r, "parked_%d" % i, v))
		parked.append({"vis": v, "circles": circles})
	# dos más, en diagonal (sur)
	for k in 2:
		var cid2: String = PARKED_IDS[rng.randi() % PARKED_IDS.size()]
		var v2 := CarVisual.new(cid2, true)
		if v2.model == null:
			continue
		var bx := -34.0 + k * 9.0
		var bz := -15.5
		var yaw2 := 0.78 + (PI if k == 1 else 0.0)
		v2.position = Vector3(bx, 0, bz)
		v2.rotation.y = yaw2
		v2.debris_root = debris
		props.add_child(v2)
		_tag(v2, "parked", 140.0)
		_cheap_shadows(v2)
		v2.set_paint(Color.html((Garage.PAINTS[1 + rng.randi() % (Garage.PAINTS.size() - 1)] as Dictionary)["c"]))
		var m2: Dictionary = v2.meta
		var L2: float = minf(float(m2.get("length", 4.6)) * 0.9, 5.0)
		var r2 := clampf(float(m2.get("width", 1.9)) * 0.5 * 0.82, 0.7, 1.0)
		var cl := []
		for off in [-(L2 * 0.5 - r2), 0.0, (L2 * 0.5 - r2)]:
			cl.append(track.add_circle(bx + sin(yaw2) * float(off), bz + cos(yaw2) * float(off), r2, "parked_s%d" % k, v2))
		parked.append({"vis": v2, "circles": cl})

# ───────────────────────── vegetación ─────────────────────────
func _quad_cross(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ang in [0.0, PI * 0.5]:
		var c := cos(ang)
		var s := sin(ang)
		var pts := [Vector3(-w / 2 * c, 0, w / 2 * s), Vector3(w / 2 * c, 0, -w / 2 * s), Vector3(w / 2 * c, h, -w / 2 * s), Vector3(-w / 2 * c, h, w / 2 * s)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[idx])
			st.add_vertex(pts[idx])
	return st.commit()

func _sway_mat(tex: String, amp := 0.05, tint := Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SWAY
	if _tex(tex) != null:
		m.set_shader_parameter("albedo_tex", _tex(tex))
	m.set_shader_parameter("amp", amp)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("wind", wind)
	return m

func _multi(tex: String, w: float, h: float, xforms: Array, amp := 0.05, tint := Color.WHITE, vis_end := 0.0, is_tree := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _quad_cross(w, h)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _sway_mat(tex, amp, tint)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
	if is_tree:
		mi.set_meta("tree", true)
	mi.extra_cull_margin = 4.0
	props.add_child(mi)
	_tag(mi, "auto", 0.0)
	_mm_all.append(mi)
	return mi

func _xf(pos: Vector3, sc: float, yaw := -1.0) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU if yaw < 0.0 else yaw).scaled(Vector3.ONE * sc)
	return Transform3D(b, pos)

func _build_nature() -> void:
	var H := LotTrack.HALF
	var tq: float = opts["trees"]
	# árboles de afuera: dos anillos alrededor del lote (sólo se ven; el muro los separa)
	var species := [["arbol_redondo", 8.0, 512.0 / 768.0], ["arbol_cipres", 8.0, 384.0 / 768.0], ["arbol_alamo", 8.0, 320.0 / 768.0], ["arbol_otono", 7.0, 512.0 / 640.0]]
	var groups := {}
	for s in species:
		groups[s[0]] = []
	var count := int(70.0 * tq)
	for i in count:
		var side := rng.randi() % 4
		var t := rng.randf()
		var off := rng.randf_range(3.0, 22.0)
		var x := 0.0
		var z := 0.0
		match side:
			0: x = lerpf(-H.x - 20.0, H.x + 20.0, t); z = H.y + off
			1: x = lerpf(-H.x - 20.0, H.x + 20.0, t); z = -H.y - off
			2: x = H.x + off; z = lerpf(-H.y - 10.0, H.y + 10.0, t)
			3: x = -H.x - off; z = lerpf(-H.y - 10.0, H.y + 10.0, t)
		var sp: Array = species[rng.randi() % species.size()]
		groups[sp[0]].append(_xf(Vector3(x, 0, z), rng.randf_range(0.8, 1.5)))
	# árboles de adentro: canteros con árbol, pasto, flores y arbustos
	var planters := [Vector2(-46.5, -31.0), Vector2(-46.5, 26.5), Vector2(6.0, 28.0), Vector2(-4.0, 12.5), Vector2(-33.0, 12.5), Vector2(8.0, -31.5), Vector2(-14.0, -31.5)]
	var inner_trees := []
	for p in planters:
		var sp2: Array = species[rng.randi() % 3 if p.x < 0 else 0]
		var sc := rng.randf_range(0.7, 0.95)
		var xf := _xf(Vector3(p.x, 0, p.y), sc)
		groups[sp2[0]].append(xf)
		inner_trees.append({"x": p.x, "z": p.y, "sp": sp2[0], "idx": groups[sp2[0]].size() - 1})
		# cantero de hormigón
		var mi := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(3.6, 0.22, 3.6)
		mi.mesh = cm
		mi.material_override = _mat_tex("hormigon", Vector3(2, 1, 1), 0.95)
		mi.position = Vector3(p.x, 0.11, p.y)
		props.add_child(mi)
		var top := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(3.3, 0.04, 3.3)
		top.mesh = tm
		top.material_override = _mat_tex("pasto", Vector3(1.1, 1.1, 1), 0.95)
		top.position = Vector3(p.x, 0.225, p.y)
		props.add_child(top)
		_static_box(Vector3(p.x, 0.15, p.y), Vector3(3.6, 0.3, 3.6))
		track.add_box(p.x, p.y, 1.8, 1.8, 0.0, "planter")
		track.add_circle(p.x, p.y, 0.38, "tree", null)
	var idx_base := {}
	for s in species:
		var arr: Array = groups[s[0]]
		if arr.is_empty():
			continue
		var mmi := _multi(s[0], float(s[1]) * float(s[2]), float(s[1]), arr, 0.06, Color(0.96, 0.98, 0.96), 190.0, true)
		idx_base[s[0]] = mmi
	for it in inner_trees:
		var mm_i: MultiMeshInstance3D = idx_base.get(it["sp"])
		if mm_i != null:
			trees.append({"mm": mm_i.multimesh, "idx": it["idx"], "x": it["x"], "z": it["z"], "kick": 0.0})
	# arbustos con flores en los canteros y a lo largo del muro
	var bush_t := ["arbusto_verde", "arbusto_flores_rosa", "arbusto_flores_amarillo"]
	var bush_x := {"arbusto_verde": [], "arbusto_flores_rosa": [], "arbusto_flores_amarillo": []}
	for p in planters:
		for k in 3:
			var bt: String = bush_t[rng.randi() % 3]
			bush_x[bt].append(_xf(Vector3(p.x + rng.randf_range(-1.2, 1.2), 0.2, p.y + rng.randf_range(-1.2, 1.2)), rng.randf_range(0.5, 0.8)))
	for i in int(36.0 * tq):
		var bt2: String = bush_t[rng.randi() % 3]
		var xx := rng.randf_range(-H.x, H.x)
		bush_x[bt2].append(_xf(Vector3(xx, 0, H.y + rng.randf_range(0.9, 6.0) * (1.0 if rng.randf() < 0.5 else -1.0) * (1.0 if rng.randf() < 0.5 else 1.0)), rng.randf_range(0.8, 1.4)))
	for bt3 in bush_t:
		if bush_x[bt3].size() > 0:
			_multi(bt3, 2.7 * 0.0 + 2.0, 1.5, bush_x[bt3], 0.03, Color.WHITE, 140.0)
	# pasto y flores
	var g := float(opts["grass"])
	var grass_x := []
	var flower_x := {"flor_blanca": [], "flor_amarilla": [], "flor_roja": [], "flor_violeta": []}
	var area_pts := []
	for r in track.grass_rects:
		area_pts.append(r)
	area_pts.append(Rect2(11.0, 33.0, 39.0, 2.0))
	for r in area_pts:
		var rr: Rect2 = r
		var n := int(rr.get_area() * 0.9 * g)
		for i in n:
			grass_x.append(_xf(Vector3(rr.position.x + rng.randf() * rr.size.x, 0, rr.position.y + rng.randf() * rr.size.y), rng.randf_range(0.6, 1.3)))
		var nf := int(rr.get_area() * 0.12 * g)
		for i in nf:
			var ft: String = ["flor_blanca", "flor_amarilla", "flor_roja", "flor_violeta"][rng.randi() % 4]
			flower_x[ft].append(_xf(Vector3(rr.position.x + rng.randf() * rr.size.x, 0, rr.position.y + rng.randf() * rr.size.y), rng.randf_range(0.9, 1.5)))
	# matas sueltas alrededor de los canteros y cerca de la tierra
	for p in planters:
		for k in int(40.0 * g):
			grass_x.append(_xf(Vector3(p.x + rng.randf_range(-1.6, 1.6), 0.22, p.y + rng.randf_range(-1.6, 1.6)), rng.randf_range(0.5, 1.0)))
	for k in int(260.0 * g):
		grass_x.append(_xf(Vector3(rng.randf_range(12.0, 48.0), 0.0, rng.randf_range(2.5, 33.0)), rng.randf_range(0.5, 0.9)))
	if grass_x.size() > 0:
		_multi("pasto_mata", 0.55 * 1.2, 0.55, grass_x, 0.07, Color.WHITE, 60.0)
	for ft2 in flower_x:
		if flower_x[ft2].size() > 0:
			_multi(ft2, 0.23, 0.35, flower_x[ft2], 0.08, Color.WHITE, 45.0)
	# piedras sobre la tierra: rocas bajas (malla de ruido) y algunas grandes con choque
	var rock_m := _build_rock_mesh()
	var rmat := _mat_tex("tierra", Vector3(0.25, 0.25, 1), 0.95, Color(0.62, 0.6, 0.58))
	var rmm := MultiMesh.new()
	rmm.transform_format = MultiMesh.TRANSFORM_3D
	rmm.mesh = rock_m
	var rocks := int(90.0 * g) + 10
	rmm.instance_count = rocks
	for i in rocks:
		var sc2 := rng.randf_range(0.08, 0.32)
		var b2 := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)) * Basis.from_scale(Vector3(sc2 * rng.randf_range(1.0, 1.7), sc2 * rng.randf_range(0.5, 0.9), sc2 * rng.randf_range(1.0, 1.5)))
		var px := rng.randf_range(12.5, 48.0)
		var pz := rng.randf_range(2.5, 33.0)
		rmm.set_instance_transform(i, Transform3D(b2, Vector3(px, track.ground_info(px, pz).x + 0.02, pz)))
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = rmm
	rmi.material_override = rmat
	props.add_child(rmi)
	for p3 in [Vector2(14.5, 31.0), Vector2(46.0, 31.5), Vector2(47.0, 4.0), Vector2(22.0, 5.5), Vector2(44.0, 12.0)]:
		var sc3 := rng.randf_range(0.9, 1.3)
		var mi := MeshInstance3D.new()
		mi.mesh = rock_m
		mi.material_override = rmat
		mi.scale = Vector3(sc3 * 1.2, sc3 * 0.8, sc3)
		mi.position = Vector3(p3.x, 0.35 * sc3, p3.y)
		mi.rotation.y = rng.randf() * TAU
		props.add_child(mi)
		_tag(mi, "grass", 80.0)
		track.add_circle(p3.x, p3.y, 0.75 * sc3, "rock")
		_static_box(mi.position, Vector3(1.3, 0.8, 1.2) * sc3)

func _build_rock_mesh() -> ArrayMesh:
	var sph := SphereMesh.new()
	sph.radial_segments = 9
	sph.rings = 5
	sph.radius = 1.0
	sph.height = 2.0
	var arr := sph.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in vs.size():
		vs[i] = vs[i] * (0.82 + 0.3 * r.randf())
	arr[Mesh.ARRAY_VERTEX] = vs
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	return st.commit()

# ───────────────────────── carteles ─────────────────────────
func _build_signs() -> void:
	var items := [
		["ESTACIONAMIENTO DE PRUEBAS", Vector3(-22, 3.3, -33.2), 0.0, 40],
		["SUSPENSIÓN →", Vector3(14.0, 2.1, -4.5), PI / 2.0, 36],
		["TIERRA", Vector3(11.0, 2.0, 24.0), PI / 2.0, 40],
		["SLALOM", Vector3(-46.0, 2.0, -10.5), 0.0, 36],
		["PIRÁMIDE DE CONOS", Vector3(-24.0, 2.0, -29.0), 0.0, 30],
		["DRIFT", Vector3(-38.0, 2.2, -29.0), 0.0, 40],
	]
	for it in items:
		var pos: Vector3 = it[1]
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.04
		cm.height = pos.y
		post.mesh = cm
		post.material_override = _flat(Color(0.3, 0.3, 0.32))
		post.position = Vector3(pos.x, pos.y * 0.5, pos.z)
		props.add_child(post)
		_tag(post, "misc", 120.0)
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.62, 3.6) if float(it[2]) != 0.0 else Vector3(3.6, 0.62, 0.05)
		board.mesh = bm
		board.material_override = _flat(Color(0.09, 0.32, 0.55))
		board.position = Vector3(pos.x, pos.y + 0.2, pos.z)
		props.add_child(board)
		_tag(board, "misc", 120.0)
		for side in [1.0, -1.0]:
			var lb := Label3D.new()
			lb.text = String(it[0])
			lb.font_size = int(it[3])
			lb.pixel_size = 0.0062
			lb.modulate = Color(1, 1, 1)
			lb.outline_size = 0
			lb.shaded = false
			lb.double_sided = false
			lb.position = board.position + (Vector3(0.04 * side, 0, 0) if float(it[2]) != 0.0 else Vector3(0, 0, 0.04 * side))
			lb.rotation.y = (PI / 2.0 if side > 0 else -PI / 2.0) if float(it[2]) != 0.0 else (0.0 if side > 0 else PI)
			props.add_child(lb)
			_tag(lb, "misc", 120.0)

# ───────────────────────── fondo de cartón ─────────────────────────
func _building_mesh(w: float, h: float, d: float, tile_w: float, tile_h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := w * 0.5
	var hd := d * 0.5
	var sides := [[Vector3(-hw, 0, hd), Vector3(hw, 0, hd), w], [Vector3(hw, 0, hd), Vector3(hw, 0, -hd), d], [Vector3(hw, 0, -hd), Vector3(-hw, 0, -hd), w], [Vector3(-hw, 0, -hd), Vector3(-hw, 0, hd), d]]
	for s in sides:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var len := float(s[2])
		var tu := len / tile_w
		var tv := h / tile_h
		var pts := [a, b, b + Vector3(0, h, 0), a + Vector3(0, h, 0)]
		var uvs := [Vector2(0, tv), Vector2(tu, tv), Vector2(tu, 0), Vector2(0, 0)]
		for idx in [0, 2, 1, 0, 3, 2]: # (orden de los vértices: la cara pintada mira hacia AFUERA de la caja, hacia el jugador)
			st.set_uv(uvs[idx])
			st.add_vertex(pts[idx])
	st.generate_normals()
	return st.commit()

func _build_backdrop() -> void:
	var facs := ["fachada_a", "fachada_b", "fachada_c", "fachada_d"]
	var cardboard := Color(0.93, 0.88, 0.8)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 4242
	var ring := [[105.0, 22], [150.0, 30]]
	for rg in ring:
		var rad: float = rg[0]
		var n: int = rg[1]
		for i in n:
			var ang := TAU * (float(i) + r2.randf_range(-0.25, 0.25)) / n
			var w := r2.randf_range(14.0, 26.0)
			var h := r2.randf_range(16.0, 46.0)
			var d := r2.randf_range(12.0, 22.0)
			var f: String = facs[r2.randi() % 4]
			var mi := MeshInstance3D.new()
			mi.mesh = _building_mesh(w, h, d, 6.0, 9.0)
			mi.material_override = _mat_tex(f, Vector3(1, 1, 1), 0.95, cardboard)
			mi.position = Vector3(cos(ang) * rad * 1.35, 0, sin(ang) * rad)
			mi.rotation.y = -ang + PI / 2.0 + r2.randf_range(-0.15, 0.15)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props.add_child(mi)
			_tag(mi, "backdrop", 0.0)
			# techo plano de cartón
			var roof := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(w + 0.6, 0.5, d + 0.6)
			roof.mesh = rm
			roof.material_override = _mat_tex("carton", Vector3(2, 2, 1), 0.95, Color(0.75, 0.68, 0.58))
			roof.position = Vector3(0, h + 0.25, 0)
			mi.add_child(roof)

# ───────────────────────── actualización ─────────────────────────
func set_wind(v: float) -> void:
	wind = v
	for mi in _mm_all:
		((mi as MultiMeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("wind", v)

func set_car_transform(t: Transform3D) -> void:
	car_xf = t

func _physics_process(_dt: float) -> void:
	if car_body != null:
		car_body.global_transform = car_xf

## Un golpe del auto contra un árbol: el árbol se sacude
func kick_tree(x: float, z: float, amount: float) -> void:
	for t in trees:
		if absf(float(t["x"]) - x) < 1.0 and absf(float(t["z"]) - z) < 1.0:
			t["kick"] = minf(1.0, float(t["kick"]) + amount)

func _process(dt: float) -> void:
	for t in trees:
		var k: float = t["kick"]
		if k > 0.0:
			k = maxf(0.0, k - dt * 0.35)
			t["kick"] = k
			(t["mm"] as MultiMesh).set_instance_custom_data(int(t["idx"]), Color(k, 0, 0, 0))

## Para repetir el escenario: conos de pie, postes y piezas fuera
func reset_props() -> void:
	for c in cones:
		if is_instance_valid(c):
			c.queue_free()
	cones.clear()
	for c in debris.get_children():
		c.queue_free()
	if opts["cones"]:
		_build_cones()
