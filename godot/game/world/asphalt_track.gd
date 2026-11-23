extends "res://game/world/dirt_track.gd"
## Circuito de asfalto: ~1,5 km cerrado, ancho (13 m, tres autos de frente), recta larga de largada, una horquilla, una S y una curva rápida.
## Hereda la curva, la búsqueda del punto más cercano y el empuje de DirtTrack, pero con su propio ancho, perfil (sin huellas ni baches), curbs, zona de escape y barrera.
##
## Superficies: asfalto (0) en la pista y los curbs, banquina (2) en la zona de escape de grava, pasto (3) más afuera.

const RH := 6.5 # semiancho de la pista (m)
const KERB := 0.9 # ancho del curb (m)
const GRAVEL := 3.7 # hasta acá (desde el borde de la pista) la zona de escape es de grava
const FH := 11.6 # distancia del eje a la barrera (m)

const CTRL_A := [Vector2(0, 0), Vector2(150, 0), Vector2(300, -5), Vector2(400, -47.5), Vector2(442.5, -122.5), Vector2(420, -207.5), Vector2(345, -247.5), Vector2(267.5, -220),
	Vector2(245, -155), Vector2(187.5, -115), Vector2(120, -145), Vector2(77.5, -215), Vector2(-7.5, -245), Vector2(-97.5, -215), Vector2(-125, -140), Vector2(-90, -65), Vector2(-50, -17.5)]

func _ctrl() -> Array:
	return CTRL_A

## subidas y bajadas suaves (pendiente máxima ~3 %)
func _elev(u: float) -> float:
	return 2.2 * sin(TAU * u + 0.4) + 1.2 * sin(TAU * 2.0 * u + 1.3) + 0.5 * sin(TAU * 4.0 * u + 2.0)

func _setup() -> void:
	pass # sin lomos, baches ni charcos: el asfalto es parejo

func road_half() -> float:
	return RH + KERB

func fence_half() -> float:
	return FH

## Perfil transversal: leve bombeo, curb apenas más alto y zona de escape que baja suave
func profile(lat: float) -> float:
	var a := absf(lat)
	var h := 0.02 * (1.0 - minf(1.0, (a / RH) * (a / RH)))
	h += 0.014 * smoothstep(RH - 0.1, RH + 0.15, a) * (1.0 - smoothstep(RH + KERB - 0.1, RH + KERB + 0.2, a))
	h -= 0.1 * smoothstep(RH + KERB, RH + 4.5, a)
	return h

func surface_at(x: float, z: float) -> int:
	var d: float = nearest(x, z)["d"]
	if d < RH + KERB:
		return SURF_ASPHALT
	if d < RH + KERB + GRAVEL:
		return SURF_SHOULDER
	return SURF_GRASS

func ground_info(x: float, z: float) -> Vector2:
	var nr := nearest(x, z)
	var d: float = nr["d"]
	var surf := SURF_GRASS
	if d < RH + KERB:
		surf = SURF_ASPHALT
	elif d < RH + KERB + GRAVEL:
		surf = SURF_SHOULDER
	return Vector2(axis_height(nr, x, z) + profile(float(nr["side"])), float(surf))

func base_height(x: float, z: float) -> float:
	var nr := nearest(x, z)
	return axis_height(nr, x, z) + profile(float(nr["side"]) if float(nr["d"]) < 14.0 else 14.0)

## Relieve del terreno (sólo visual): pegado al camino cerca, lomas suaves lejos
func terrain_height(x: float, z: float) -> float:
	var nr := nearest(x, z)
	var d: float = nr["d"]
	var ah := axis_height(nr, x, z)
	if d < FH + 0.5:
		return ah + profile(float(nr["side"])) - 0.03
	var num := 0.0
	var den := 0.0
	for c in coarse:
		var dd := maxf(3.0, sqrt((c.x - x) * (c.x - x) + (c.y - z) * (c.y - z)))
		var w := 1.0 / (dd * dd * dd)
		num += w * c.z
		den += w
	var hr := num / den
	var far := smoothstep(FH + 4.0, 90.0, d)
	var hills := 3.2 * sin(x * 0.011 + 1.3) * cos(z * 0.014 - 0.4) + 1.4 * sin(x * 0.027 + z * 0.019)
	# arranca donde termina el perfil del camino (altura del eje - 0,13) y se despega de a poco
	var base := lerpf(ah - 0.13, hr * 0.6 + hills, far)
	return base
