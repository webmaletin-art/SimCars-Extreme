extends Node3D
## Auto en 3D: carrocería, 4 ruedas, volante y piezas que se dañan, se doblan y se caen (puertas, capó, baúl, paragolpes, parabrisas).
##
## El modelo lo prepara tools/blender/process_car.py y trae esta jerarquía (el auto mira a +Z, la izquierda es +X, el origen está en el piso bajo el centro de gravedad):
##   car/body            carrocería fija        car/wheel_fl|fr|rl|rr   ruedas (el origen de cada nodo es el centro de la rueda)
##   car/steer_wheel     volante (si el modelo lo trae)
##   car/part_<nombre>/ok|dam   piezas sanas / dañadas (el origen de la pieza es su centro)
## Todo el estado físico viene de CarSnapshot (sync_from). El daño es visual: lo calcula hit() a partir del choque que mide Car._keep_out.

const MODELS := "res://game/models/cars/"
const WHEEL_KEYS := ["fl", "fr", "rl", "rr"]
## fragilidad de cada pieza (1 = normal): los vidrios y paragolpes ceden antes que una puerta
const FRAGILITY := {"windscreen": 1.8, "bump_front": 1.2, "bump_rear": 1.2, "plate_rear": 2.0, "bonnet": 0.9, "boot": 0.9}
const MAX_DEBRIS := 28

static var _cache := {}

var id := ""
var meta := {}
var lite := false
var model: Node3D # raíz del GLB («car»)
var wheels: Array = [] # [{steer, spin, front, cx, cz, base_y}]
var parts := {} # nombre → {node, ok, dam, center (marco del auto), size, hp, state, rest: Transform3D, hinge, wob}
var steer_node: Node3D
var steer_axis := Vector3(0, 0.34, -0.94)
var steer_vis := 0.0
var debris_root: Node # donde caen las piezas (el mundo)
var damage_total := 0.0 # 0..100 daño acumulado de la carrocería (para el tablero)
var _meshes: Array = [] # [{mi, owner: parte o ""}]
var _dented := {} # MeshInstance3D → true (su malla ya es una copia propia)
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _phys: Object # VehicleParams (alturas de ruedas)
var shake := 0.0
var world_vel := Vector3.ZERO # velocidad del auto (m/s, mundo): las piezas que se caen salen con ella

static func meta_of(car_id: String) -> Dictionary:
	if not _cache.has(car_id):
		var p := MODELS + car_id + ".json"
		_cache[car_id] = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else {}
	return _cache[car_id]

static func has_model(car_id: String) -> bool:
	return ResourceLoader.exists(MODELS + car_id + ".glb")

func _init(car_id: String = "", p_lite := false) -> void:
	id = car_id
	lite = p_lite
	_rng.randomize()
	if id != "":
		load_model()

func load_model() -> bool:
	meta = meta_of(id)
	var path := MODELS + id + ("_lite" if lite else "") + ".glb"
	if not ResourceLoader.exists(path):
		path = MODELS + id + ".glb"
	if not ResourceLoader.exists(path):
		return false
	var ps: PackedScene = load(path)
	var inst: Node = ps.instantiate()
	model = inst.get_node_or_null("car") as Node3D
	if model == null:
		model = inst as Node3D
		add_child(model)
	else:
		inst.remove_child(model)
		model.owner = null
		for d in model.find_children("*", "", true, false):
			d.owner = null
		add_child(model)
		inst.free()
	for w in WHEEL_KEYS:
		var wn := model.get_node_or_null("wheel_" + w) as Node3D
		if wn == null:
			wheels.append(null)
			continue
		var c := wn.position
		var steer := Node3D.new()
		steer.name = "steer_" + w
		model.add_child(steer)
		steer.position = Vector3(c.x, 0.0, c.z)
		wn.reparent(steer, false)
		wn.position = Vector3.ZERO
		wheels.append({"steer": steer, "spin": wn, "front": w.begins_with("f"), "cx": c.x, "cz": c.z, "base_y": c.y})
	_fix_materials(model)
	steer_node = model.get_node_or_null("steer_wheel") as Node3D
	if meta.has("steer_axis"):
		var a: Array = meta["steer_axis"]
		steer_axis = Vector3(a[0], a[1], a[2]).normalized()
	for ch in model.get_children():
		if ch.name.begins_with("part_"):
			_register_part(ch as Node3D)
	_collect_meshes(model)
	return true

## Los materiales de GTA vienen en modo «mezcla» (transparente) aunque sean pintura, plástico o calcos con borde recortado: se dibujan mucho más caros
## y se ordenan mal. Todo lo que no es vidrio ni luz pasa a «recorte» (opaco, con el borde de la textura). Se hace una sola vez por material.
const GLASS_WORDS := ["glass", "vidrio", "window", "wind", "light", "lamp", "cristal", "transpar", "tint", "lente", "optica", "reflector", "farol", "steklo", "glow"]
static var _fixed := {}
static func _fix_materials(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as BaseMaterial3D
			if m == null or _fixed.has(m):
				continue
			_fixed[m] = true
			if m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var nm := m.resource_name.to_lower()
			var glass := false
			for w in GLASS_WORDS:
				if nm.contains(w):
					glass = true
					break
			if glass or m.albedo_color.a < 0.95:
				continue
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.4

func _register_part(n: Node3D) -> void:
	var pname := String(n.name).substr(5)
	var pm: Dictionary = (meta.get("parts", {}) as Dictionary).get(pname, {})
	var c := Vector3.ZERO
	var sz := Vector3(0.5, 0.5, 0.5)
	if pm.has("center"):
		var a: Array = pm["center"]
		c = Vector3(a[0], a[1], a[2])
		var s: Array = pm["size"]
		sz = Vector3(s[0], s[1], s[2])
	else:
		c = n.position
	var dam := n.get_node_or_null("dam") as Node3D
	if dam != null:
		dam.visible = false
	parts[pname] = {"node": n, "ok": n.get_node_or_null("ok"), "dam": dam, "center": c, "size": sz, "hp": 100.0, "state": 0, "rest": n.transform,
		"wob": _rng.randf() * TAU, "sign": 1.0 if pname.ends_with("_lf") or pname.ends_with("_lr") else -1.0}

func _collect_meshes(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var owner_part := ""
			var p: Node = c
			while p != null and p != model:
				if String(p.name).begins_with("part_"):
					owner_part = String(p.name).substr(5)
					break
				p = p.get_parent()
			_meshes.append({"mi": c, "part": owner_part})
		_collect_meshes(c)

## Pinta la carrocería: cambia el tinte de los materiales «remap» del modelo (el color de pintura de los autos de GTA). Cada material se duplica una sola vez.
var _paint_mats := {}
func set_paint(col: Color) -> void:
	var names: Array = meta.get("paint", [])
	if names.is_empty():
		return
	for e in _meshes:
		var mi: MeshInstance3D = e["mi"]
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m is BaseMaterial3D and names.has(m.resource_name):
				if not _paint_mats.has(m):
					var mm := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
					_paint_mats[m] = mm
				(_paint_mats[m] as BaseMaterial3D).albedo_color = col
				mi.set_surface_override_material(s, _paint_mats[m])

# ───────────────────────── movimiento ─────────────────────────
## Igual que el demo del kit: posición, orientación (YXZ), altura de cada rueda con la suspensión, dirección y rodado
func sync_from(p, dt: float, V) -> void:
	_t += dt
	basis = Basis.from_euler(Vector3(p.pitch, p.yaw, p.roll), EULER_ORDER_YXZ)
	# p.py es la altura del CENTRO DE GRAVEDAD; el origen del modelo está en el piso, comHeight más abajo en el marco del auto
	# (antes se dibujaba el piso del modelo a la altura del centro de gravedad: los autos flotaban ~0,5 m)
	position = Vector3(p.px, p.py, p.pz) - basis.y * V.comHeight
	var base: float = V.comHeight + V.hardpointY - V.rideOffset
	for i in 4:
		var w = wheels[i]
		if w == null:
			continue
		var st: Node3D = w["steer"]
		st.position.y = base - p.wheel_s[i]
		if w["front"]:
			st.rotation.y = p.steerAngle
		(w["spin"] as Node3D).rotation.x += p.wheel_omega[i] * dt
	if steer_node != null:
		steer_vis += (p.steerAngle * 7.5 - steer_vis) * (1.0 - exp(-dt * 25.0))
		steer_node.basis = Basis(steer_axis, -steer_vis)
	_animate_parts(dt, absf(p.vLong))

func _animate_parts(dt: float, speed: float) -> void:
	for pn in parts:
		var P: Dictionary = parts[pn]
		if int(P["state"]) != 2:
			continue
		var n: Node3D = P["node"]
		var sz: Vector3 = P["size"]
		var rest: Transform3D = P["rest"]
		var ang := float(P.get("ang", 0.0)) + 0.03 * sin(_t * 9.0 + float(P["wob"])) * clampf(speed / 20.0, 0.0, 1.0)
		var axis := Vector3.UP
		var hinge_off := Vector3.ZERO # bisagra respecto del centro de la pieza
		if pn.begins_with("door"):
			axis = Vector3.UP
			hinge_off = Vector3(0, 0, sz.z * 0.5)
			ang = -float(P["sign"]) * (0.42 + 0.06 * sin(_t * 6.0 + float(P["wob"])) * clampf(speed / 15.0, 0.0, 1.0))
		elif pn == "bonnet":
			axis = Vector3.RIGHT
			hinge_off = Vector3(0, 0, -sz.z * 0.5)
			ang = -(0.5 + clampf(speed / 40.0, 0.0, 0.5) * 0.4) # el aire lo levanta
		elif pn == "boot":
			axis = Vector3.RIGHT
			hinge_off = Vector3(0, 0, sz.z * 0.5)
			ang = 0.5
		else: # paragolpes colgando
			axis = Vector3.RIGHT
			hinge_off = Vector3(0, sz.y * 0.5, 0)
			ang = 0.35 * float(P["sign"])
		var R := Basis(axis, ang)
		var o: Vector3 = rest.origin + hinge_off - R * hinge_off
		n.transform = Transform3D(R * rest.basis, o)

# ───────────────────────── daño ─────────────────────────
## Choque: point = punto del golpe en el marco del auto, dir = hacia dónde empuja el golpe (hacia adentro del auto), speed = m/s contra el obstáculo
func hit(point: Vector3, dir: Vector3, speed: float) -> void:
	var base := clampf((speed - 1.5) / 14.0, 0.0, 1.8) * 100.0
	if base <= 0.0:
		return
	damage_total = minf(100.0, damage_total + base * 0.12)
	for pn in parts.keys():
		var P: Dictionary = parts[pn]
		if int(P["state"]) >= 3:
			continue
		var sz: Vector3 = P["size"]
		var d := point.distance_to(P["center"] as Vector3)
		var reach := 0.7 + maxf(sz.x, maxf(sz.y, sz.z)) * 0.55
		if d > reach:
			continue
		var dmg := base * (1.0 - d / reach) * float(FRAGILITY.get(pn, 1.0)) * _rng.randf_range(0.8, 1.2)
		P["hp"] = float(P["hp"]) - dmg
		var hp: float = P["hp"]
		if hp <= 0.0 or (hp < 25.0 and _rng.randf() < 0.55 and (pn.begins_with("bump") or pn == "windscreen" or pn == "plate_rear")):
			_detach(pn, point, dir, speed)
		elif hp < 55.0 and int(P["state"]) < 2 and (pn.begins_with("door") or pn == "bonnet" or pn == "boot" or pn.begins_with("bump")):
			P["state"] = 2
			_show_dam(P)
		elif hp < 80.0 and int(P["state"]) < 1:
			P["state"] = 1
			_show_dam(P)
	# abolladuras en la malla de cada pieza y de la carrocería cerca del golpe
	var depth := clampf(base * 0.0035, 0.01, 0.30)
	for e in _meshes:
		var mi: MeshInstance3D = e["mi"]
		if not is_instance_valid(mi) or not mi.visible or mi.mesh == null:
			continue
		if String(e["part"]) != "" and (parts.get(e["part"], {}) as Dictionary).get("state", 0) >= 3:
			continue
		if not _near(mi, point, 1.5):
			continue
		_dent(mi, point, dir, 0.55 + base * 0.004, depth)

func _show_dam(P: Dictionary) -> void:
	var dam: Node3D = P["dam"]
	if dam != null:
		dam.visible = true
		var ok: Node3D = P["ok"]
		if ok != null:
			ok.visible = false

func _near(mi: MeshInstance3D, point: Vector3, r: float) -> bool:
	var aabb := mi.get_aabb()
	var lp := mi.global_transform.affine_inverse() * (model.global_transform * point)
	var c := aabb.get_center()
	var e := aabb.size * 0.5
	var q := (lp - c).abs() - e
	var out := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0))
	return out.length() < r

## Abolla la malla: los vértices a menos de rad del golpe se hunden hacia adentro, con algo de ruido para que no quede un cráter liso
func _dent(mi: MeshInstance3D, point: Vector3, dir: Vector3, rad: float, depth: float) -> void:
	if not _dented.has(mi):
		mi.mesh = mi.mesh.duplicate()
		_dented[mi] = true
	var am := mi.mesh as ArrayMesh
	if am == null:
		return
	var inv := mi.global_transform.affine_inverse()
	var gp := model.global_transform * point
	var lp := inv * gp
	var ld := (inv.basis * (model.global_transform.basis * dir)).normalized()
	var surfaces := []
	for s in am.get_surface_count():
		surfaces.append({"arrays": am.surface_get_arrays(s), "mat": am.surface_get_material(s), "prim": am.surface_get_primitive_type(s)})
	var changed := false
	var sc := 1.0 / maxf(0.0001, mi.global_transform.basis.get_scale().x)
	var r2 := rad * rad * sc * sc
	for sd in surfaces:
		var arr: Array = sd["arrays"]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if vs.size() > 45000:
			continue
		for k in vs.size():
			var v := vs[k]
			var d2 := v.distance_squared_to(lp)
			if d2 < r2:
				var f := 1.0 - sqrt(d2 / r2)
				var n := 0.65 + 0.35 * sin(v.x * 37.0 + v.y * 23.0 + v.z * 41.0)
				vs[k] = v + ld * (depth * sc * f * f * n)
				changed = true
		arr[Mesh.ARRAY_VERTEX] = vs
	if not changed:
		return
	am.clear_surfaces()
	for sd in surfaces:
		am.add_surface_from_arrays(sd["prim"], sd["arrays"])
		am.surface_set_material(am.get_surface_count() - 1, sd["mat"])

## La pieza se desprende y sale rodando como un cuerpo rígido del motor de física (Jolt)
func _detach(pn: String, point: Vector3, dir: Vector3, speed: float) -> void:
	var P: Dictionary = parts[pn]
	if int(P["state"]) >= 3 or debris_root == null:
		P["state"] = 3
		(P["node"] as Node3D).visible = false
		return
	P["state"] = 3
	var n: Node3D = P["node"]
	var gx := n.global_transform
	var sz: Vector3 = P["size"]
	var rb := RigidBody3D.new()
	rb.mass = clampf(sz.x * sz.y * sz.z * 120.0, 4.0, 45.0)
	rb.continuous_cd = true
	var mat := PhysicsMaterial.new()
	mat.friction = 0.7
	mat.bounce = 0.25
	rb.physics_material_override = mat
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(sz.x, 0.08), maxf(sz.y, 0.06), maxf(sz.z, 0.08))
	cs.shape = bs
	rb.add_child(cs)
	debris_root.add_child(rb)
	rb.global_transform = gx
	n.reparent(rb, false)
	n.transform = Transform3D.IDENTITY
	if P["dam"] != null and (P["dam"] as Node3D).visible:
		pass
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 # suelo y cuerpos del escenario; no choca con el auto (la física del auto es propia)
	var vel := (model.global_transform.basis * dir) * speed * 0.5 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(1.5, 4.0), _rng.randf_range(-1, 1))
	rb.linear_velocity = vel * 0.6 + world_vel
	rb.angular_velocity = Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4), _rng.randf_range(-4, 4))
	_trim_debris()

func _trim_debris() -> void:
	var kids := debris_root.get_children().filter(func(c): return c is RigidBody3D)
	while kids.size() > MAX_DEBRIS:
		kids.pop_front().queue_free()

## Deja el auto como nuevo (reiniciar)
func repair() -> void:
	damage_total = 0.0
	for pn in parts:
		var P: Dictionary = parts[pn]
		var n: Node3D = P["node"]
		if n.get_parent() != model:
			n.reparent(model, false)
		n.transform = P["rest"]
		n.visible = true
		P["hp"] = 100.0
		P["state"] = 0
		var ok: Node3D = P["ok"]
		if ok != null:
			ok.visible = true
		var dam: Node3D = P["dam"]
		if dam != null:
			dam.visible = false
	# mallas abolladas: se descartan las copias (se vuelve a leer del modelo)
	for mi in _dented.keys():
		pass
	if not _dented.is_empty():
		_reload_meshes()

func _reload_meshes() -> void:
	var path := MODELS + id + ("_lite" if lite else "") + ".glb"
	if not ResourceLoader.exists(path):
		path = MODELS + id + ".glb"
	var fresh: Node = (load(path) as PackedScene).instantiate()
	var idx := {}
	_index(fresh, fresh, idx)
	for mi in _dented.keys():
		if not is_instance_valid(mi):
			continue
		var rel := str(model.get_path_to(mi))
		if idx.has(rel):
			mi.mesh = (idx[rel] as MeshInstance3D).mesh
	_dented.clear()
	fresh.free()

func _index(n: Node, base: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out[str(base.get_path_to(c))] = c
		_index(c, base, out)

func part_names() -> Array:
	return parts.keys()

## cuántas piezas siguen en su lugar / dañadas (para el tablero)
func status() -> Dictionary:
	var gone := 0
	var hurt := 0
	for pn in parts:
		var s: int = parts[pn]["state"]
		if s >= 3:
			gone += 1
		elif s >= 1:
			hurt += 1
	return {"gone": gone, "hurt": hurt, "total": parts.size()}
