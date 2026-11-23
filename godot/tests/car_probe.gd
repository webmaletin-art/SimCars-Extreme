extends SceneTree
const CarVisual := preload("res://game/car/car_visual.gd")
func _init() -> void:
	var v := CarVisual.new("cls63_amg", true)
	root.add_child(v)
	print("model: ", v.model.name, " children: ", v.model.get_children().map(func(c): return c.name))
	print("parts: ", v.parts.keys(), " wheels: ", v.wheels.size(), " steer: ", v.steer_node)
	quit()
