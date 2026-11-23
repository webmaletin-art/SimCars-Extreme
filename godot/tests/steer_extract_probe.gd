extends SceneTree
## ¿Se puede sacar el volante de la malla del interior por geometría? (autos sin pieza de volante). Uso: godot --headless --script tests/steer_extract_probe.gd
const CarVisual := preload("res://game/car/car_visual.gd")
func _rel(mi: Node3D, par: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = mi
	while n != par and n != null:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
func _init() -> void:
	for id in ["aventador_s", "mclaren_f1"]:
		var v := CarVisual.new(id, true)
		var m: Dictionary = v.meta
		var c := Vector3(m["steer_center"][0], m["steer_center"][1], m["steer_center"][2])
		var ax := Vector3(m["steer_axis"][0], m["steer_axis"][1], m["steer_axis"][2]).normalized()
		var r := float(m["steer_radius"])
		print("== ", id, " centro ", c, " eje ", ax, " radio ", r)
		for n in v.model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var T := _rel(mi, v.model)
			for si in mi.mesh.get_surface_count():
				var a: Array = mi.mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var cnt := 0
				var lo := 9.0
				var hi := -9.0
				var rmax := 0.0
				for k in range(0, idx.size() - 2, 3):
					var ok := true
					var cen := Vector3.ZERO
					for q in 3:
						var p := T * vs[idx[k + q]]
						var d := p - c
						var axial := d.dot(ax)
						var rad := (d - ax * axial).length()
						if rad > r * 1.2 or absf(axial) > 0.07:
							ok = false
						cen += p / 3.0
					if ok:
						cnt += 1
						var d2 := cen - c
						lo = minf(lo, d2.dot(ax))
						hi = maxf(hi, d2.dot(ax))
						rmax = maxf(rmax, (d2 - ax * d2.dot(ax)).length())
				if cnt > 0:
					var mt := mi.mesh.surface_get_material(si)
					print("  ", mi.name, " sup ", si, " mat=", mt.resource_name if mt != null else "-", " tris=", cnt, " axial[", snappedf(lo, 0.001), ",", snappedf(hi, 0.001), "] radio máx ", snappedf(rmax, 0.001))
		v.free()
	quit()
