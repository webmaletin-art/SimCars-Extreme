extends SceneTree
## Lista las mallas de un auto (nombre, padre, triángulos, caja) para decidir qué se puede esconder. Uso: godot --headless --script tests/car_tree.gd -- cls63_amg
func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var ps: PackedScene = load("res://game/models/cars/%s.glb" % a)
		var _unused := 0
		var r: Node = ps.instantiate()
		root.add_child(r)
		var tot := 0
		for n in r.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var t := mi.mesh.get_faces().size() / 3
			tot += t
			var mats := []
			for s in mi.mesh.get_surface_count():
				var mt := mi.get_active_material(s)
				mats.append(mt.resource_name if mt != null else "-")
			var bb := mi.mesh.get_aabb()
			print("%-34s par=%-16s tris=%6d  c=(%.2f,%.2f,%.2f) s=(%.2f,%.2f,%.2f) %s" % [mi.name, mi.get_parent().name, t, bb.get_center().x, bb.get_center().y, bb.get_center().z, bb.size.x, bb.size.y, bb.size.z, str(mats)])
		print("TOTAL ", tot)
	quit()
