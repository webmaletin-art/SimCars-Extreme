extends RefCounted
## Reglaje manual del auto (los deslizadores de catalog.json «tune»): presiones, alineación, suspensión, frenos, transmisión, aerodinámica.
## Se guarda por auto en profile["tune"][id] y se aplica en el momento (CarBuild.build_params con «lab: todo desbloqueado»).

const UI := preload("res://game/ui/ui_kit.gd")
const Profile := preload("res://game/save/profile.gd")
const CarBuild := preload("res://game/data/car_build.gd")
const Garage := preload("res://game/data/garage.gd")

static func state_for(profile: Dictionary, car_id: String) -> Dictionary:
	return {"upg": {}, "tune": (profile["tune"] as Dictionary).get(car_id, {}), "tires": "street", "tiresOwned": ["street"], "lab": {"all": true}}

static func build(profile: Dictionary, car_id: String, on_change: Callable) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var cat: Dictionary = CarBuild.catalog()
	var defs: Dictionary = CarBuild.default_tune(Garage.vehicles()[car_id])
	var tune: Dictionary = profile["tune"].get(car_id, {})
	profile["tune"][car_id] = tune
	var holder := HBoxContainer.new()
	root.add_child(holder)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.custom_minimum_size = Vector2(900, 330)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(scroll)
	scroll.get_v_scroll_bar().custom_minimum_size = Vector2(34, 0)
	var arrows := VBoxContainer.new()
	arrows.add_theme_constant_override("separation", 10)
	holder.add_child(arrows)
	var up := UI.button("SUBIR", Vector2(96, 150), 22)
	up.pressed.connect(func() -> void: scroll.scroll_vertical = maxi(0, scroll.scroll_vertical - 220))
	arrows.add_child(up)
	var dn := UI.button("BAJAR", Vector2(96, 150), 22)
	dn.pressed.connect(func() -> void: scroll.scroll_vertical += 220)
	arrows.add_child(dn)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	for g in cat["tune"]:
		var l := UI.label(String(g["g"]).to_upper(), 24, UI.ACC)
		l.custom_minimum_size = Vector2(0, 40)
		box.add_child(l)
		for it in g["items"]:
			var k: String = it["k"]
			var d: float = float(defs.get(k, it["def"]))
			var cur: float = float(tune.get(k, d))
			var fmt := "%.2f" if float(it["step"]) < 0.1 else ("%.1f" if float(it["step"]) < 1.0 else "%.0f")
			var row := UI.slider(String(it["n"]), float(it["min"]), float(it["max"]), cur, float(it["step"]), func(v: float) -> void:
				tune[k] = v
				Profile.save_profile(profile)
				on_change.call(), fmt + " " + String(it["u"]), 380.0)
			box.add_child(row)
			var info := UI.label(String(it["info"]), 14, UI.DIM)
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.custom_minimum_size = Vector2(760, 0)
			box.add_child(info)
	return root
