extends RefCounted
## Piezas de interfaz con el mismo estilo en el menú y en la pausa (fondo azul noche, acento naranja, esquinas redondeadas, todo grande para tocar con el dedo).

const ACC := Color(1.0, 0.5, 0.12)
const ACC2 := Color(1.0, 0.72, 0.25)
const BG := Color(0.035, 0.05, 0.08, 0.94)
const BG2 := Color(0.07, 0.10, 0.15, 0.96)
const TXT := Color(0.94, 0.96, 1.0)
const DIM := Color(0.62, 0.70, 0.8)
const GOOD := Color(0.35, 0.85, 0.5)
const BAD := Color(1.0, 0.32, 0.28)

static func style(col: Color, radius := 14, border := Color(0, 0, 0, 0), bw := 0, pad := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	if pad > 0.0:
		s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s

static func button(text: String, min_size := Vector2(240, 62), font := 26, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.1) if primary else Color.WHITE)
	var base := ACC if primary else Color(0.12, 0.17, 0.25, 0.95)
	b.add_theme_stylebox_override("normal", style(base, 16, ACC2 if primary else Color(0.3, 0.4, 0.55, 0.8), 2))
	b.add_theme_stylebox_override("hover", style(base.lightened(0.12), 16, ACC2, 2))
	b.add_theme_stylebox_override("pressed", style(ACC2 if primary else ACC.darkened(0.2), 16, Color.WHITE, 2))
	b.add_theme_stylebox_override("disabled", style(Color(0.1, 0.12, 0.16, 0.7), 16))
	return b

static func label(text: String, size := 22, col := TXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	return l

static func panel(min_size := Vector2.ZERO, col := BG, radius := 18, pad := 18.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	p.add_theme_stylebox_override("panel", style(col, radius, Color(0.25, 0.35, 0.5, 0.5), 1, pad))
	return p

## Fila «nombre · deslizador · valor». on_change(v: float) se llama al mover.
static func slider(title: String, lo: float, hi: float, val: float, step: float, on_change: Callable, fmt := "%.2f", width := 520.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := label(title, 22, TXT)
	l.custom_minimum_size = Vector2(190, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(width, 44)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.add_theme_stylebox_override("slider", style(Color(0.18, 0.25, 0.36), 6, Color(0, 0, 0, 0), 0, 0))
	s.add_theme_stylebox_override("grabber_area", style(ACC, 6))
	s.add_theme_stylebox_override("grabber_area_highlight", style(ACC2, 6))
	var sb := (s.get_theme_stylebox("slider") as StyleBoxFlat)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	row.add_child(s)
	var v := label(fmt % val, 22, ACC2, HORIZONTAL_ALIGNMENT_RIGHT)
	v.custom_minimum_size = Vector2(76, 0)
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % x
		on_change.call(x))
	return row

static func toggle(title: String, on: bool, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := label(title, 22, TXT)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var b := button("SÍ" if on else "NO", Vector2(110, 48), 22, on)
	b.set_meta("on", on)
	b.pressed.connect(func() -> void:
		var n := not bool(b.get_meta("on"))
		b.set_meta("on", n)
		b.text = "SÍ" if n else "NO"
		b.add_theme_stylebox_override("normal", style(ACC if n else Color(0.12, 0.17, 0.25, 0.95), 16, ACC2 if n else Color(0.3, 0.4, 0.55, 0.8), 2))
		on_change.call(n))
	if on:
		pass
	row.add_child(b)
	return row

## Selector de opciones en fila: [A] [B] [C] con la elegida resaltada
static func choice(title: String, options: Array, cur: int, on_change: Callable, bw := 120) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6 if bw < 110 else 10)
	var l := label(title, 20, TXT)
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)
	var btns: Array = []
	for i in options.size():
		var b := button(str(options[i]), Vector2(bw, 46), 18 if bw < 110 else 20, i == cur)
		btns.append(b)
		b.pressed.connect(func() -> void:
			for k in btns.size():
				var on := k == i
				(btns[k] as Button).add_theme_stylebox_override("normal", style(ACC if on else Color(0.12, 0.17, 0.25, 0.95), 16, ACC2 if on else Color(0.3, 0.4, 0.55, 0.8), 2))
			on_change.call(i))
		row.add_child(b)
	return row

static func bar(title: String, frac: float, col := ACC) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := label(title, 16, DIM)
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = clampf(frac, 0.0, 1.0)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(150, 14)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_theme_stylebox_override("background", style(Color(0.15, 0.2, 0.3), 9))
	pb.add_theme_stylebox_override("fill", style(col, 9))
	row.add_child(pb)
	return row
