## Mide 0-100 km/h, 0-200, velocidad máxima y frenado 100-0 de cada auto (físico, sin dibujar).
## godot --headless --path godot --script res://tests/perf_test.gd
extends SceneTree

const VehicleParams := preload("res://game/physics/vehicle_params.gd")
const VehiclePhysics := preload("res://game/physics/vehicle_physics.gd")
const FlatTrack := preload("res://game/physics/flat_track.gd")
const CarBuild := preload("res://game/data/car_build.gd")

const TARGET := {"mclaren_f1": [3.4, 370], "mclaren_f1_gtr": [3.2, 330], "aventador_s": [2.9, 350], "ranger_limited": [9.5, 185], "rx3_savanna": [10.5, 190], "cls63_amg": [4.0, 250]}

func _init() -> void:
	var vs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/vehicles.json"))
	var fails := 0
	for id in vs:
		var st := {"upg": {}, "tune": {}, "tires": "street", "tiresOwned": ["street"]}
		var d: Dictionary = CarBuild.build_params(vs[id], st, {"abs": true, "tc": 50.0, "stab": 30.0})
		var P := VehicleParams.from_dict(d)
		var ph := VehiclePhysics.new(FlatTrack.new(), P)
		ph.reset(0.0, 0.0, 0.0)
		var t := 0.0
		var t100 := -1.0
		var t200 := -1.0
		var vmax := 0.0
		var dt := 1.0 / 120.0
		while t < 80.0:
			ph.step(dt, 1.0, 0.0, 0.0, false, false, 0)
			t += dt
			var kmh := sqrt(ph.vx * ph.vx + ph.vz * ph.vz) * 3.6
			vmax = maxf(vmax, kmh)
			if t100 < 0.0 and kmh >= 100.0:
				t100 = t
			if t200 < 0.0 and kmh >= 200.0:
				t200 = t
		# frenada desde 100
		ph.reset(0.0, 0.0, 0.0)
		ph.vz = 27.8
		ph.vx = 0.0
		var tb := 0.0
		var dist := 0.0
		while tb < 12.0 and ph.vz > 0.5:
			ph.step(dt, 0.0, 1.0, 0.0, false, false, 0)
			tb += dt
			dist += ph.vz * dt
		var tg: Array = TARGET[id]
		var ok := absf(t100 - float(tg[0])) < float(tg[0]) * 0.25 and absf(vmax - float(tg[1])) < float(tg[1]) * 0.12
		if not ok:
			fails += 1
		print("%-16s 0-100: %5.2f s (obj %.1f) · 0-200: %5.2f · vmax: %4.0f km/h (obj %d) · 100-0: %4.1f m · gear final %d %s" % [id, t100, tg[0], t200, vmax, tg[1], dist, ph.gear, "OK" if ok else "REVISAR"])
	quit(0 if fails == 0 else 1)
