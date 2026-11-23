extends SceneTree
## Cuenta lo que arma cada mapa (instancias por tipo) sin dibujar nada: sirve para ver qué pesa. Uso: godot --headless --script tests/world_count.gd -- dirt
func _init() -> void:
	var mp := "lot"
	for a in OS.get_cmdline_user_args():
		mp = a
	var W: Script
	match mp:
		"dirt": W = load("res://game/world/dirt_world.gd")
		"asphalt": W = load("res://game/world/asphalt_world.gd")
		_: W = load("res://game/world/lot_world.gd")
	var w: Node3D = W.new()
	root.add_child(w)
	w.build({"parked": 7, "grass": 1.0, "trees": 1.0, "shadows": false, "backdrop": true, "cones": true})
	var mm := {}
	var singles := 0
	var tri_mm := 0
	var tri_single := 0
	for n in w.find_children("*", "MultiMeshInstance3D", true, false):
		var m: MultiMesh = (n as MultiMeshInstance3D).multimesh
		var t := 0
		if m.mesh != null:
			t = m.mesh.get_faces().size() / 3
		var key := "%s x%d (vis_end %.0f)" % [(n.get_parent().name if false else str(m.mesh.get_class())), m.instance_count, (n as MultiMeshInstance3D).visibility_range_end]
		mm[key] = int(mm.get(key, 0)) + 1
		tri_mm += t * m.instance_count
	for n in w.find_children("*", "MeshInstance3D", true, false):
		singles += 1
		var me: Mesh = (n as MeshInstance3D).mesh
		if me != null:
			tri_single += me.get_faces().size() / 3
	print("MAPA ", mp, ": MultiMesh=", w.find_children("*", "MultiMeshInstance3D", true, false).size(), " triangulos(MM)=", tri_mm, " mallas sueltas=", singles, " triangulos(sueltas)=", tri_single)
	var inst := 0
	for n in w.find_children("*", "MultiMeshInstance3D", true, false):
		inst += (n as MultiMeshInstance3D).multimesh.instance_count
	print("  instancias totales en MultiMesh: ", inst)
	for n in w.find_children("*", "MultiMeshInstance3D", true, false):
		var m2: MultiMesh = (n as MultiMeshInstance3D).multimesh
		var mat: Material = (n as MultiMeshInstance3D).material_override
		var tx := ""
		if mat is ShaderMaterial:
			var t2: Variant = (mat as ShaderMaterial).get_shader_parameter("tex")
			tx = (t2 as Texture2D).resource_path.get_file() if t2 is Texture2D else "?"
		print("   ", tx, " n=", m2.instance_count, " vis_end=", (n as MultiMeshInstance3D).visibility_range_end)
	quit()
