## Vuelca las marcas que hoy usa cada auto (calculadas + ajustes CABIN) como punto de partida de game/data/cabin_markers.json
## godot --headless --script res://tests/dump_markers.gd > ../tools/_markers.json
extends SceneTree
const CarVisual := preload("res://game/car/car_visual.gd")
const Cockpit := preload("res://game/car/cockpit.gd")
func _init() -> void:
	var out := {}
	for id in ["cls63_amg", "aventador_s", "mclaren_f1", "mclaren_f1_gtr", "ranger_limited", "rx3_savanna"]:
		var v := CarVisual.new(id, true)
		root.add_child(v)
		var c := Cockpit.new(v, "none", 1.8, {"__": {}})
		c.markers = {}
		out[id] = c.current_markers()
	print("MARCAS_JSON " + JSON.stringify(out))
	quit()
