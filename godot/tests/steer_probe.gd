extends SceneTree
## ¿Cada auto encuentra el nodo del volante? Uso: godot --headless --script tests/steer_probe.gd
const CarVisual := preload("res://game/car/car_visual.gd")
func _init() -> void:
	for id in ["cls63_amg", "aventador_s", "mclaren_f1", "mclaren_f1_gtr", "ranger_limited", "rx3_savanna"]:
		for lite in [true, false]:
			var v := CarVisual.new(id, lite)
			var names := []
			for c in v.model.get_children():
				if String(c.name).to_lower().contains("steer") or String(c.name).to_lower().contains("wheel"):
					names.append(String(c.name))
			print("%-16s %-5s steer_node=%s hijos=%s meta.steer_axis=%s" % [id, "lite" if lite else "full", str(v.steer_node.name if v.steer_node != null else "NULL"), str(names), str(v.meta.get("steer_axis"))])
			v.free()
	quit()
