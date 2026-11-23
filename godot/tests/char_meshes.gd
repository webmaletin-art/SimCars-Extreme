extends SceneTree
func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var ps: PackedScene = load("res://game/models/characters/%s.glb" % a)
		var r: Node = ps.instantiate()
		root.add_child(r)
		for n in r.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var m := mi.mesh
			var mats := []
			for s in m.get_surface_count():
				var mt := mi.get_active_material(s)
				var tx := ""
				if mt is BaseMaterial3D and (mt as BaseMaterial3D).albedo_texture != null:
					var t: Texture2D = (mt as BaseMaterial3D).albedo_texture
					tx = "%dx%d" % [t.get_width(), t.get_height()]
				mats.append("%s[%s tr=%s]" % [mt.resource_name if mt != null else "-", tx, str((mt as BaseMaterial3D).transparency) if mt is BaseMaterial3D else "?"])
			print(a, " ", mi.name, " tris=", m.get_faces().size() / 3, " blend=", m.get_blend_shape_count(), " skin=", mi.skin != null, " ", mats)
	quit()
