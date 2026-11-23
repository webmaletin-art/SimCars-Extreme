extends SceneTree
## Compara dibujos (superficies visibles) y triángulos de cada auto con y sin la unión de mallas fijas. Uso: godot --headless --script tests/car_merge_test.gd
const CarVisual := preload("res://game/car/car_visual.gd")
func _count(v: Node3D) -> Array:
	var surf := 0
	var tris := 0
	for n in v.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var p: Node = mi.get_parent()
		var vis := true
		while p != null and p != v:
			if p is Node3D and not (p as Node3D).visible:
				vis = false
			p = p.get_parent()
		if not vis:
			continue
		surf += mi.mesh.get_surface_count()
		tris += mi.mesh.get_faces().size() / 3
	return [surf, tris]
func _init() -> void:
	var ids := ["cls63_amg", "aventador_s", "mclaren_f1", "mclaren_f1_gtr", "ranger_limited", "rx3_savanna"]
	for lite in [true, false]:
		for id in ids:
			CarVisual.merge_enabled = false
			var a := CarVisual.new(id, lite)
			var ca := _count(a)
			CarVisual.merge_enabled = true
			var b := CarVisual.new(id, lite)
			var cb := _count(b)
			print("%-16s %-5s dibujos %4d → %4d   triángulos %6d → %6d" % [id, "lite" if lite else "full", ca[0], cb[0], ca[1], cb[1]])
			a.free()
			b.free()
	quit()
