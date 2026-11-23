extends RefCounted
## Catálogo del garaje: orden, nombres reales, descripción y rendimiento calculado con la misma física del juego (CarBuild.perf_of).

const CarBuild := preload("res://game/data/car_build.gd")
const CarVisual := preload("res://game/car/car_visual.gd")

const ORDER := ["cls63_amg", "aventador_s", "mclaren_f1", "mclaren_f1_gtr", "ranger_limited", "rx3_savanna"]
const BLURB := {
	"mclaren_f1": "Superdeportivo de 1993 con el asiento del piloto en el centro y un V12 atmosférico de 6,1 litros. Fue el auto de calle más rápido del mundo durante más de una década.",
	"mclaren_f1_gtr": "La versión de carreras que ganó Le Mans en 1995: V12 de 6,0 litros, caja secuencial, slicks y un alerón enorme. Mucho agarre y muy poco perdón.",
	"aventador_s": "El toro de Sant'Agata: V12 de 740 CV, tracción integral y puertas de tijera. Aceleración brutal y estabilidad a más de 300 km/h.",
	"ranger_limited": "Pick-up mediana de doble cabina con tracción 4x4 y motor diésel V6 turbo. Suspensión larga: la reina de la tierra y de las lomadas.",
	"rx3_savanna": "Cupé japonés de 1973 con motor rotativo que gira alto y suena como ningún otro. Liviano, trasero y perfecto para cruzarse de costado.",
	"cls63_amg": "Sedán de cuatro puertas con corazón de carrera: V8 biturbo de 5,5 litros, tracción total y 557 CV. Cómodo para el día a día, salvaje al pisar.",
}
static var _vehicles := {}

static func vehicles() -> Dictionary:
	if _vehicles.is_empty():
		_vehicles = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/vehicles.json"))
	return _vehicles

static func params(id: String, tune := {}) -> Dictionary:
	var st := {"upg": {}, "tune": tune, "tires": "street", "tiresOwned": ["street"]}
	return CarBuild.build_params(vehicles()[id], st, {"abs": true, "tc": 50.0, "stab": 30.0})

static func info(id: String) -> Dictionary:
	var v: Dictionary = vehicles().get(id, {})
	var meta := CarVisual.meta_of(id)
	var perf := CarBuild.perf_of(params(id))
	return {"id": id, "name": v.get("name", id), "maker": meta.get("maker", ""), "year": meta.get("year", 0), "tag": v.get("tagline", ""), "blurb": BLURB.get(id, ""),
		"perf": perf, "drive": v.get("driveType", "RWD"), "mass": v.get("mass", 0), "side": meta.get("drive_side", "L")}

static func available() -> Array:
	var out := []
	for id in ORDER:
		if CarVisual.has_model(id):
			out.append(id)
	return out

const CHARS := [
	{"id": "aiden", "name": "Aiden", "desc": "Piloto joven de pelo oscuro. Traje de primera piel azul marino con vivos celestes."},
	{"id": "kate", "name": "Kate", "desc": "Pilota de pelo castaño rojizo. El mismo traje de carrera con vivos que brillan."},
	{"id": "mujer_adulta", "name": "Mujer adulta", "desc": "Conductora experimentada de pelo castaño oscuro. Traje de carrera azul marino."},
]

static func chars() -> Array:
	var out := []
	for c in CHARS:
		if ResourceLoader.exists("res://game/models/characters/%s.glb" % c["id"]):
			out.append(c)
	return out

## Pinturas: se tiñen los materiales «remap» del modelo (ver CarVisual.set_paint). "" = la original del archivo
const PAINTS := [
	{"n": "ORIGINAL", "c": ""}, {"n": "ROJO", "c": "c8141c"}, {"n": "AZUL", "c": "1b4fd6"}, {"n": "NEGRO", "c": "14161a"}, {"n": "NARANJA", "c": "ff6a00"},
	{"n": "VERDE", "c": "1d8a3e"}, {"n": "AMARILLO", "c": "f2c200"}, {"n": "PLATA", "c": "b9bec6"}, {"n": "VIOLETA", "c": "6b2fb3"}]

static func paint_of(profile: Dictionary, id: String) -> String:
	return String((profile.get("paint", {}) as Dictionary).get(id, ""))
