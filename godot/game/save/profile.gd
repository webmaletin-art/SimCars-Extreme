extends RefCounted
## Perfil del jugador (user://profile.json): auto y piloto elegidos, ajustes, cámaras, estadísticas.
## Se guarda en el teléfono; mientras el APK se firme siempre con la misma llave, actualizar NO borra nada (ver docs/FIRMA_Y_ACTUALIZACIONES.md).

const PATH := "user://profile.json"
const VERSION := 1

static func defaults() -> Dictionary:
	return {
		"version": VERSION,
		"car": "cls63_amg",
		"char": "aiden",
		"paint": {},
		"pilot_height": 1.76,
		"pilot_adj": {"x": 0.0, "y": 0.0, "z": 0.0},
		"cam": 1, # índice de CameraRig.CAMERAS
		"cam_adj": {}, # por cámara: {dist, height, side, fov}
		"settings": {
			"shadows": "media", "res_scale": 1.0, "fps_cap": 60, "show_fps": false, "msaa": 0,
			"parked": 7, "grass": 1.0, "trees": 1.0, "particles": 1.0, "wind": 0.6,
			"steer_mode": "wheel", "wheel_real": 0, "gyro": false, "manual": false, "abs": true, "tc": 50.0, "stab": 30.0,
			"volume": 80.0, "units_mph": false, "backdrop": true, "cones": true,
			"screen_res": "NATIVA", "vsync": true, "particles_on": true, "view_dist": 650, "detail_dist": 1.0, "shadow_dist": 55.0,
			"player_lite": false, "pilot_outside": true, "hud_fps": false,
		},
		"stats": {"km": 0.0, "time": 0.0, "top_kmh": 0.0, "hits": 0, "parts_lost": 0},
	}

static func load_profile() -> Dictionary:
	var d := defaults()
	if FileAccess.file_exists(PATH):
		var t: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if t is Dictionary:
			_merge(d, t)
	return d

static func _merge(base: Dictionary, over: Dictionary) -> void:
	for k in over:
		if base.has(k) and base[k] is Dictionary and over[k] is Dictionary:
			_merge(base[k], over[k])
		else:
			base[k] = over[k]

static func save_profile(d: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()
