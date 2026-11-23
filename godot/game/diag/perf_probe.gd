extends Node
## Diagnóstico de rendimiento (pausa → RENDIMIENTO). Dos partes:
##  1. MEDICIÓN REAL: apaga de a un sistema por vez (sombras, pasto y flores, árboles, edificios, autos estacionados, conos, partículas, piloto,
##     auto del jugador, carteles) y mide el tiempo de cuadro promedio con y sin él. Lo que más baja el tiempo es lo que más cuesta en ESE teléfono.
##  2. MATERIALES: recorre la escena y arma la lista de materiales con lo que cuesta dibujarlos (triángulos, cantidad de dibujos, transparencia,
##     tamaño de las texturas). Es una estimación (Godot no mide la GPU por material), pero ordena bien qué conviene simplificar primero.
## Todo termina en un texto que se copia con un botón (DisplayServer.clipboard_set) para pegárselo al desarrollador.

signal finished(report: String)

var game: Node # play.gd
var world: Node # lot_world.gd
var running := false
var _log := PackedStringArray()

const SETTLE := 0.6 # s que se espera después de cambiar algo
const MEASURE := 1.6 # s que se mide

func _frame_ms(seconds: float) -> Dictionary:
	var t := 0.0
	var n := 0
	var worst := 0.0
	var acc := 0.0
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		n += 1
		acc += dt
		worst = maxf(worst, dt)
	return {"avg": acc / maxf(1.0, float(n)) * 1000.0, "worst": worst * 1000.0,
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"tris": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objs": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}

func _systems() -> Array:
	var out := []
	var w = world
	out.append(["Sombras del sol", func(on: bool) -> void: w.sun.shadow_enabled = on and String(game.profile["settings"]["shadows"]) != "off"])
	out.append(["Pasto, flores y arbustos", func(on: bool) -> void: w.set_group_visible("grass", on)])
	out.append(["Árboles", func(on: bool) -> void: w.set_group_visible("trees", on)])
	out.append(["Edificios de fondo", func(on: bool) -> void: w.set_group_visible("backdrop", on)])
	out.append(["Autos estacionados", func(on: bool) -> void: w.set_group_visible("parked", on)])
	out.append(["Conos y piezas sueltas", func(on: bool) -> void: w.debris.visible = on])
	out.append(["Partículas (humo, polvo, marcas)", func(on: bool) -> void: game.fx.visible = on])
	out.append(["Piloto", func(on: bool) -> void: game.cockpit.set_visible(on)])
	out.append(["Auto del jugador", func(on: bool) -> void: game.visual.visible = on])
	out.append(["Lomadas, carteles, postes", func(on: bool) -> void: w.set_group_visible("misc", on)])
	out.append(["HUD (controles en pantalla)", func(on: bool) -> void: game.hud.visible = on])
	return out

func run() -> void:
	if running:
		return
	running = true
	_log = PackedStringArray()
	var S: Dictionary = game.profile["settings"]
	var vp := get_viewport()
	var sz := vp.get_visible_rect().size
	_log.append("=== SIMCARS EXTREME · DIAGNÓSTICO DE RENDIMIENTO ===")
	_log.append("Equipo: %s · %s · %s" % [OS.get_model_name(), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()])
	_log.append("API: %s · Godot %s" % [RenderingServer.get_video_adapter_api_version(), Engine.get_version_info()["string"]])
	_log.append("Pantalla: %s · lienzo %dx%d · resolución 3D %.0f %% · ajuste pantalla «%s»" % [str(DisplayServer.screen_get_size()), int(sz.x), int(sz.y), float(S["res_scale"]) * 100.0, str(S.get("screen_res", "NATIVA"))])
	_log.append("Ajustes: sombras %s · MSAA %s · FPS máx %s · distancia %s m · detalle a distancia ×%.1f · pasto ×%.1f · árboles ×%.1f · estacionados %s · auto %s" % [S["shadows"], S["msaa"], S["fps_cap"], S.get("view_dist", 650), float(S.get("detail_dist", 1.0)), float(S["grass"]), float(S["trees"]), S["parked"], "liviano" if S.get("player_lite", false) else "original"])
	_log.append("Auto: %s · piloto: %s" % [game.car_id, game.profile["char"]])
	_log.append("")
	var base: Dictionary = await _measure_base()
	_log.append("BASE (todo prendido): %.2f ms por cuadro (%.0f FPS) · peor %.1f ms · %d dibujos · %d triángulos · %d objetos" % [base["avg"], 1000.0 / maxf(0.01, base["avg"]), base["worst"], int(base["draws"]), int(base["tris"]), int(base["objs"])])
	_log.append("Memoria de video: %.0f MB (texturas %.0f MB, mallas %.0f MB)" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0])
	_log.append("")
	_log.append("— SISTEMAS (cuánto se gana apagando cada uno) —")
	var rows := []
	for s in _systems():
		var setter: Callable = s[1]
		setter.call(false)
		await get_tree().create_timer(SETTLE).timeout
		var m: Dictionary = await _frame_ms(MEASURE)
		setter.call(true)
		await get_tree().create_timer(0.2).timeout
		rows.append({"name": s[0], "gain": base["avg"] - m["avg"], "draws": base["draws"] - m["draws"], "tris": base["tris"] - m["tris"]})
	rows.sort_custom(func(a, b): return a["gain"] > b["gain"])
	for r in rows:
		_log.append("%-34s %+6.2f ms  · %+5d dibujos · %+8d triángulos" % [r["name"], -float(r["gain"]), -int(r["draws"]), -int(r["tris"])])
	_log.append("")
	_log.append("— MATERIALES MÁS PESADOS (estimado) —")
	for line in material_report(14):
		_log.append(line)
	_log.append("")
	_log.append("Pegale este texto al desarrollador para ajustar la optimización.")
	var rep := "\n".join(_log)
	running = false
	finished.emit(rep)

func _measure_base() -> Dictionary:
	await get_tree().create_timer(SETTLE).timeout
	return await _frame_ms(MEASURE * 1.5)

## Lista de materiales ordenada por costo estimado: triángulos × (1 + 1,5 si es transparente) + 0,6 × KB de textura + 1500 por dibujo
func material_report(top := 14) -> PackedStringArray:
	var mats := {}
	var stack: Array = [get_tree().current_scene if get_tree().current_scene != null else get_tree().root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is GeometryInstance3D) or not (n as Node3D).is_visible_in_tree():
			continue
		var gi := n as GeometryInstance3D
		var mesh: Mesh = null
		var count := 1
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
			count = (gi as MultiMeshInstance3D).multimesh.visible_instance_count
			if count < 0:
				count = (gi as MultiMeshInstance3D).multimesh.instance_count
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m: Material = gi.material_override
			if m == null and gi is MeshInstance3D:
				m = (gi as MeshInstance3D).get_active_material(s)
			if m == null:
				m = mesh.surface_get_material(s)
			var key := m.resource_name if m != null and m.resource_name != "" else ("(sin nombre) " + (m.get_class() if m != null else "—"))
			var tris := 0
			var arr := mesh.surface_get_arrays(s) if mesh is ArrayMesh else []
			if arr.size() > 0:
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				tris = idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var e: Dictionary = mats.get(key, {"tris": 0, "draws": 0, "alpha": false, "tex_kb": 0.0, "shader": false})
			e["tris"] = int(e["tris"]) + tris * count
			e["draws"] = int(e["draws"]) + 1
			if m is BaseMaterial3D:
				var bm := m as BaseMaterial3D
				e["alpha"] = bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
				if bm.albedo_texture != null:
					e["tex_kb"] = maxf(float(e["tex_kb"]), bm.albedo_texture.get_width() * bm.albedo_texture.get_height() * 4.0 / 1024.0)
			elif m is ShaderMaterial:
				e["shader"] = true
			mats[key] = e
	var rows := []
	for k in mats:
		var e: Dictionary = mats[k]
		var cost := float(e["tris"]) * (2.5 if e["alpha"] else 1.0) + 0.6 * float(e["tex_kb"]) + 1500.0 * float(e["draws"])
		rows.append([k, cost, e])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var out := PackedStringArray()
	for i in mini(top, rows.size()):
		var e: Dictionary = rows[i][2]
		out.append("%2d. %-30s %8d tri · %3d dibujos · textura %5.0f KB%s%s" % [i + 1, String(rows[i][0]).left(30), int(e["tris"]), int(e["draws"]), float(e["tex_kb"]), " · TRANSPARENTE" if e["alpha"] else "", " · shader" if e["shader"] else ""])
	out.append("(materiales distintos en pantalla: %d)" % rows.size())
	return out
