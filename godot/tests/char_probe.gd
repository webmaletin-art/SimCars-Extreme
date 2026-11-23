extends SceneTree
func _init() -> void:
	for id in ["aiden", "kate", "mujer_adulta"]:
		var sc: PackedScene = load("res://game/models/characters/%s.glb" % id)
		var n: Node = sc.instantiate()
		root.add_child(n)
		var sk: Skeleton3D = _find(n)
		print(id, " bones ", sk.get_bone_count(), " skel scale ", sk.global_transform.basis.get_scale(), " parent ", sk.get_parent().name)
		var hi := sk.find_bone("EM3D_Base_Head")
		var ft := sk.find_bone("EM3D_Base_L_Foot")
		var tb := sk.find_bone("EM3D_Base_L_ToeBase")
		print("  head y ", sk.get_bone_global_rest(hi).origin, " foot ", sk.get_bone_global_rest(ft).origin, " toe ", sk.get_bone_global_rest(tb).origin)
		var lh := sk.find_bone("EM3D_Base_L_Hand"); var rh := sk.find_bone("EM3D_Base_R_Hand")
		print("  L hand ", sk.get_bone_global_rest(lh).origin, " R hand ", sk.get_bone_global_rest(rh).origin)
	quit()
func _find(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find(c)
		if r: return r
	return null
