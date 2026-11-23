extends Node3D
## Sala de exhibición del menú: plataforma giratoria con luces, el auto (o el piloto) de turno y una cámara que se arrastra con el dedo.

const CarVisual := preload("res://game/car/car_visual.gd")
const RigPilot := preload("res://game/car/rig_pilot.gd")

var cam: Camera3D
var holder: Node3D
var stage: MeshInstance3D
var spin := true
var yaw := 0.6
var elev := 0.16
var dist := 7.5
var focus := Vector3(0, 0.7, 0)
var _target_dist := 7.5
var _visual: Node3D
var _t := 0.0
var _drag := false
var _last := Vector2.ZERO

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.045, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.52, 0.62)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 35, 0)
	key.light_energy = 1.35
	key.shadow_enabled = false
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 215, 0)
	rim.light_energy = 0.8
	rim.light_color = Color(1.0, 0.6, 0.3)
	rim.shadow_enabled = false
	add_child(rim)
	# plataforma
	stage = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.6
	cm.bottom_radius = 3.7
	cm.height = 0.12
	cm.radial_segments = 48
	stage.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.11, 0.15)
	m.roughness = 0.35
	m.metallic = 0.4
	stage.material_override = m
	stage.position.y = -0.06
	add_child(stage)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.55
	tm.outer_radius = 3.7
	tm.rings = 48
	tm.ring_segments = 6
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1.0, 0.5, 0.12)
	rm.emission_enabled = true
	rm.emission = Color(1.0, 0.5, 0.12)
	rm.emission_energy_multiplier = 1.4
	ring.material_override = rm
	ring.position.y = 0.0
	add_child(ring)
	holder = Node3D.new()
	add_child(holder)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.far = 200.0
	add_child(cam)
	_place_cam()

func clear() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = null

func show_car(id: String, p_paint := "") -> void:
	clear()
	var v := CarVisual.new(id, false)
	if v.model == null:
		v.free()
		return
	holder.add_child(v)
	_visual = v
	if p_paint != "":
		v.set_paint(Color.html(p_paint))
	focus = Vector3(0, 0.62, 0)
	_target_dist = clampf(float(v.meta.get("length", 4.6)) * 1.5, 6.5, 10.0)
	dist = _target_dist
	holder.rotation.y = 0.0
	elev = 0.14

func show_character(id: String) -> void:
	clear()
	var path := "res://game/models/characters/%s.glb" % id
	if not ResourceLoader.exists(path):
		return
	var n: Node3D = (load(path) as PackedScene).instantiate()
	holder.add_child(n)
	_visual = n
	focus = Vector3(0, 0.95, 0)
	_target_dist = 3.4
	dist = _target_dist
	elev = 0.05

func _place_cam() -> void:
	var cp := focus + Vector3(sin(yaw) * cos(elev), sin(elev), cos(yaw) * cos(elev)) * dist
	cam.position = cp
	cam.look_at(focus)

func _process(dt: float) -> void:
	_t += dt
	if spin and not _drag:
		yaw += dt * 0.35
	dist += (_target_dist - dist) * (1.0 - exp(-dt * 4.0))
	_place_cam()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventMouseButton:
		var pressed: bool = e.pressed
		if e is InputEventMouseButton and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_target_dist = clampf(_target_dist * (0.92 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.08), 2.5, 14.0)
			return
		_drag = pressed
		_last = e.position
	elif (e is InputEventScreenDrag or e is InputEventMouseMotion) and _drag:
		var rel: Vector2 = e.relative
		yaw -= rel.x * 0.008
		elev = clampf(elev + rel.y * 0.004, -0.05, 0.9)
