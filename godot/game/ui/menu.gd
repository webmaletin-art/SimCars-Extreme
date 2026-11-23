extends Control
## Menú principal: sala de exhibición 3D de fondo + pantallas (inicio, garaje, piloto, ajustes). Todo se arma en código, con el estilo de UiKit.

signal play_pressed
signal quit_pressed

const UI := preload("res://game/ui/ui_kit.gd")
const Garage := preload("res://game/data/garage.gd")
const Profile := preload("res://game/save/profile.gd")
const OptionsPanel := preload("res://game/ui/options_panel.gd")
const Gfx := preload("res://game/ui/gfx.gd")

var profile: Dictionary
var showroom: Node3D
var _box: Control
var _cars: Array = []
var _car_i := 0
var _chars: Array = []
var _char_i := 0
const VERSION_TXT := "v0.1 · prueba"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cars = Garage.available()
	_chars = Garage.chars()
	_car_i = maxi(0, _cars.find(profile["car"]))
	_char_i = 0
	for i in _chars.size():
		if _chars[i]["id"] == profile["char"]:
			_char_i = i
	_main()

func _reset() -> void:
	if _box != null:
		_box.queue_free()
	_box = Control.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

func _title(parent: Control, big := true) -> void:
	var t := UI.label("SIMCARS", 50 if big else 34, Color.WHITE)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override("outline_size", 6)
	parent.add_child(t)
	var t2 := UI.label("EXTREME", 32 if big else 24, UI.ACC)
	t2.add_theme_constant_override("outline_size", 5)
	t2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	parent.add_child(t2)

func _back_button(to: Callable) -> Button:
	var b := UI.button("◀  VOLVER", Vector2(200, 56), 22)
	b.position = Vector2(24, 20)
	b.pressed.connect(to)
	return b

# ───────────────────────── inicio ─────────────────────────
func _main() -> void:
	_reset()
	var cid: String = String(profile["car"]) if profile["car"] in _cars else String(_cars[0])
	showroom.show_car(cid, Garage.paint_of(profile, cid))
	showroom.focus = Vector3(0.0, 0.65, 0.0)
	showroom.spin = true
	var left := VBoxContainer.new()
	left.position = Vector2(36, 16)
	left.add_theme_constant_override("separation", 6)
	_box.add_child(left)
	_title(left)
	var sub := UI.label("Simulador de conducción · estacionamiento de pruebas", 17, UI.DIM)
	left.add_child(sub)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	left.add_child(sp)
	var play := UI.button("JUGAR", Vector2(330, 66), 32, true)
	play.pressed.connect(func() -> void: play_pressed.emit())
	left.add_child(play)
	var g := UI.button("GARAJE", Vector2(330, 52), 24)
	g.pressed.connect(_garage)
	left.add_child(g)
	var p := UI.button("PILOTO", Vector2(330, 52), 24)
	p.pressed.connect(_char)
	left.add_child(p)
	var o := UI.button("AJUSTES", Vector2(330, 52), 24)
	o.pressed.connect(_options)
	left.add_child(o)
	var q := UI.button("SALIR", Vector2(330, 46), 20)
	q.pressed.connect(func() -> void: quit_pressed.emit())
	left.add_child(q)
	# abajo a la derecha: lo elegido
	var info: Dictionary = Garage.info(String(profile["car"])) if Garage.vehicles().has(profile["car"]) else {}
	var st: Dictionary = profile["stats"]
	var pn := ""
	for c in _chars:
		if c["id"] == profile["char"]:
			pn = c["name"]
	var card := UI.panel(Vector2(420, 0), UI.BG, 16, 16.0)
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.offset_left = -450
	card.offset_right = -24
	card.offset_top = -170
	card.offset_bottom = -24
	_box.add_child(card)
	var cv := VBoxContainer.new()
	card.add_child(cv)
	cv.add_child(UI.label(String(info.get("name", "")), 26, Color.WHITE))
	cv.add_child(UI.label("Piloto: %s" % pn, 20, UI.DIM))
	cv.add_child(UI.label("Recorrido: %.1f km · Velocidad máx.: %.0f km/h" % [float(st["km"]), float(st["top_kmh"])], 18, UI.DIM))
	cv.add_child(UI.label(VERSION_TXT, 16, Color(0.4, 0.5, 0.6)))

# ───────────────────────── garaje ─────────────────────────
func _garage() -> void:
	_reset()
	showroom.spin = true
	_box.add_child(_back_button(_main))
	var panel := UI.panel(Vector2(560, 0), UI.BG, 16, 14.0)
	panel.position = Vector2(24, 78)
	_box.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	var id: String = _cars[_car_i]
	var inf := Garage.info(id)
	showroom.show_car(id, Garage.paint_of(profile, id))
	v.add_child(UI.label("%d / %d" % [_car_i + 1, _cars.size()], 15, UI.DIM))
	v.add_child(UI.label(String(inf["name"]), 30, Color.WHITE))
	v.add_child(UI.label("%s · %d · %s" % [inf["maker"], int(inf["year"]), inf["tag"]], 15, UI.ACC2))
	var bl := UI.label(String(inf["blurb"]), 15, UI.DIM)
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.custom_minimum_size = Vector2(520, 0)
	v.add_child(bl)
	var pf: Dictionary = inf["perf"]
	var bars: Dictionary = pf["bars"]
	var gr := GridContainer.new()
	gr.columns = 2
	gr.add_theme_constant_override("h_separation", 16)
	gr.add_theme_constant_override("v_separation", 2)
	v.add_child(gr)
	gr.add_child(UI.bar("Velocidad", float(bars["speed"])))
	gr.add_child(UI.bar("Aceleración", float(bars["accel"])))
	gr.add_child(UI.bar("Agarre", float(bars["handling"])))
	gr.add_child(UI.bar("Frenos", float(bars["braking"])))
	gr.add_child(UI.bar("Todoterreno", float(bars["offroad"]), UI.GOOD))
	var dn := {"RWD": "Tracción trasera", "FWD": "Tracción delantera", "AWD": "Tracción integral"}
	v.add_child(UI.label("%d CV · %d kg · %s\n0-100 km/h: %.1f s · máx. %d km/h" % [int(pf["hp"]), int(pf["kg"]), dn.get(inf["drive"], inf["drive"]), float(pf["t100"]), int(pf["vmax"])], 17, UI.TXT))
	# colores
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 8)
	v.add_child(sw)
	sw.add_child(UI.label("Pintura", 20, UI.DIM))
	var cur_c := Garage.paint_of(profile, id)
	for pdef in Garage.PAINTS:
		var hexc: String = pdef["c"]
		var b := Button.new()
		b.custom_minimum_size = Vector2(42, 42)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = String(pdef["n"])
		var col := Color.html(hexc) if hexc != "" else Color(0.85, 0.85, 0.88)
		b.add_theme_stylebox_override("normal", UI.style(col, 21, Color.WHITE if hexc == cur_c else Color(0, 0, 0, 0.5), 3 if hexc == cur_c else 1))
		b.add_theme_stylebox_override("hover", UI.style(col.lightened(0.15), 21, UI.ACC2, 3))
		b.add_theme_stylebox_override("pressed", UI.style(col, 21, Color.WHITE, 3))
		if hexc == "":
			b.text = "◌"
		b.pressed.connect(func() -> void:
			(profile["paint"] as Dictionary)[id] = hexc
			Profile.save_profile(profile)
			_garage())
		sw.add_child(b)
	var pick := UI.button("ELEGIR ESTE AUTO", Vector2(300, 52), 22, true)
	pick.pressed.connect(func() -> void:
		profile["car"] = id
		Profile.save_profile(profile)
		_main())
	v.add_child(pick)
	var prev := UI.button("◀", Vector2(84, 84), 40)
	prev.anchor_left = 1.0
	prev.anchor_right = 1.0
	prev.anchor_top = 1.0
	prev.anchor_bottom = 1.0
	prev.offset_left = -204
	prev.offset_top = -110
	prev.offset_right = -120
	prev.offset_bottom = -26
	prev.pressed.connect(func() -> void:
		_car_i = (_car_i + _cars.size() - 1) % _cars.size()
		_garage())
	_box.add_child(prev)
	var nxt := UI.button("▶", Vector2(84, 84), 40)
	nxt.anchor_left = 1.0
	nxt.anchor_right = 1.0
	nxt.anchor_top = 0.5
	nxt.anchor_bottom = 0.5
	nxt.anchor_top = 1.0
	nxt.anchor_bottom = 1.0
	nxt.offset_left = -108
	nxt.offset_top = -110
	nxt.offset_right = -24
	nxt.offset_bottom = -26
	nxt.pressed.connect(func() -> void:
		_car_i = (_car_i + 1) % _cars.size()
		_garage())
	_box.add_child(nxt)

# ───────────────────────── piloto ─────────────────────────
func _char() -> void:
	_reset()
	showroom.spin = true
	_box.add_child(_back_button(_main))
	if _chars.is_empty():
		return
	var c: Dictionary = _chars[_char_i]
	showroom.show_character(String(c["id"]))
	var panel := UI.panel(Vector2(480, 0), UI.BG, 18, 18.0)
	panel.position = Vector2(24, 90)
	_box.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(UI.label("PILOTO  %d / %d" % [_char_i + 1, _chars.size()], 18, UI.DIM))
	v.add_child(UI.label(String(c["name"]), 38, Color.WHITE))
	var d := UI.label(String(c["desc"]), 20, UI.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(440, 0)
	v.add_child(d)
	v.add_child(UI.label("Sólo un piloto por auto (el acompañante llega más adelante).", 17, Color(0.5, 0.6, 0.7)))
	var pick := UI.button("ELEGIR ESTE PILOTO", Vector2(300, 60), 24, true)
	pick.pressed.connect(func() -> void:
		profile["char"] = c["id"]
		Profile.save_profile(profile)
		_main())
	v.add_child(pick)
	for dd in [[-1, "◀", -204.0, 1], [1, "▶", -108.0, 1]]:
		var b := UI.button(String(dd[1]), Vector2(84, 84), 40)
		b.anchor_left = float(dd[3])
		b.anchor_right = float(dd[3])
		b.anchor_top = 1.0
		b.anchor_bottom = 1.0
		b.offset_left = float(dd[2])
		b.offset_right = float(dd[2]) + 84
		b.offset_top = -110
		b.offset_bottom = -26
		var dir: int = dd[0]
		b.pressed.connect(func() -> void:
			_char_i = (_char_i + dir + _chars.size()) % _chars.size()
			_char())
		_box.add_child(b)

# ───────────────────────── ajustes ─────────────────────────
func _options() -> void:
	_reset()
	_box.add_child(_back_button(_main))
	var panel := UI.panel(Vector2(980, 0), UI.BG, 18, 18.0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(150, 90)
	_box.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(UI.label("AJUSTES", 34, Color.WHITE))
	v.add_child(OptionsPanel.build(profile, func(_k: String) -> void: Gfx.apply_screen(get_tree(), profile["settings"]), false))
