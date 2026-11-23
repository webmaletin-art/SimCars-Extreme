extends SceneTree
## Desglose del estacionamiento: triángulos y mallas por rama (para ver qué pesa)
func _init() -> void:
	var W: Script = load("res://game/world/lot_world.gd")
	var w: Node3D = W.new()
	root.add_child(w)
	w.build({"parked": 7, "grass": 1.0, "trees": 1.0, "shadows": false, "backdrop": true, "cones": true})
	var agg := {}
	for ch in w.get_children():
		_walk(ch, ch.name, agg)
	for k in agg:
		print("%-28s mallas=%4d tris=%7d superficies=%4d" % [k, agg[k][0], agg[k][1], agg[k][2]])
	quit()
func _walk(n: Node, key: String, agg: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m := (n as MeshInstance3D).mesh
		var k := key
		var p := n
		# agrupa por el nombre de la clase del padre directo de props o del primer ancestro con nombre significativo
		if not agg.has(k):
			agg[k] = [0, 0, 0]
		agg[k][0] += 1
		agg[k][1] += m.get_faces().size() / 3
		agg[k][2] += m.get_surface_count()
	for c in n.get_children():
		var kk := key
		if key == "props":
			kk = "props/" + c.get_class() + ":" + (c.name.rstrip("0123456789@") if not (c is MeshInstance3D) else (c as MeshInstance3D).mesh.get_class())
		_walk(c, kk, agg)
