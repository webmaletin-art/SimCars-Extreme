extends SceneTree
## Recorre el eje (y una línea a 2 m) de cada circuito cada 0,5 m y busca saltos de altura: pendiente máxima y mayor cambio de pendiente. Uso: godot --headless --script tests/ground_roughness.gd
func _init() -> void:
	for pair in [["dirt", "res://game/world/dirt_track.gd"], ["asphalt", "res://game/world/asphalt_track.gd"]]:
		var t: RefCounted = load(pair[1]).new()
		for lat in [0.0, 2.0, -2.0, 3.5]:
			var prev := 0.0
			var prev_s := 0.0
			var maxs := 0.0
			var maxd := 0.0
			var worst := 0.0
			var n: int = t.pts.size()
			var s := 0.0
			var first := true
			while s < t.length - 1.0:
				var i := 0
				while i < n - 1 and float(t.cum[i + 1]) <= s:
					i += 1
				var tg: Vector2 = t.tans[i]
				var q: Vector2 = t.pts[i] + Vector2(-tg.y, tg.x) * lat + tg * (s - float(t.cum[i]))
				var h: float = t.ground_info(q.x, q.y).x
				if not first and s > 4.0:
					var sl := (h - prev) / 0.5
					if absf(sl) > 0.09 and lat == 0.0:
						print("   ", pair[0], " s=", s, " pendiente ", snappedf(sl, 0.001), " h=", snappedf(h, 0.01))
					maxs = maxf(maxs, absf(sl))
					maxd = maxf(maxd, absf(sl - prev_s))
					if absf(sl - prev_s) > worst - 0.0001 and absf(sl - prev_s) >= maxd:
						worst = s
					prev_s = sl
				prev = h
				first = false
				s += 0.5
			print("%-8s lat %4.1f  pendiente máx %.3f  mayor cambio de pendiente %.3f (en s=%.0f)" % [pair[0], lat, maxs, maxd, worst])
	quit()
