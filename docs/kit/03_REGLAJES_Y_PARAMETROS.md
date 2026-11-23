# 03 · Parámetros del auto y sistema de reglaje manual

Tres capas, de abajo hacia arriba:

```
vehicles.json  (ficha base del auto: números físicos reales)
   + mejoras compradas (upg: motor, turbo, peso, frenos, suspensión, caja, diferencial, aero, stance)
   + reglaje manual del jugador (tune: sliders en %, grados, psi…)
   + ayudas (ABS / TC / estabilidad)
   + cubiertas (street, sport, slick, gravel, mud, drift)
        ↓  CarBuild.build_params(base, car_state, assists)
   Dictionary final  →  VehicleParams.from_dict(...)  →  VehiclePhysics
```

Todo el reglaje es **manual y declarativo**: `catalog.json` define qué sliders existen (`tune`), qué desbloquea cada mejora, y `car_build.gd` los aplica. Para tu juego podés dejar todos los sliders desbloqueados (ver §5).

## 1. `vehicles.json` — campo por campo

30 autos; ejemplo en `vehicles.json["hatch"]`. Cada campo es un campo de `VehicleParams` (`physics/vehicle_params.gd`; los que faltan toman el default de esa clase).

**Cuerpo**
| campo | unidad | qué hace / valores típicos |
|---|---|---|
| `mass` | kg | 1000 (hatch) … 2500 (pickup) … 9000 (camión) |
| `weightFront` | 0..1 | fracción de peso sobre el eje delantero (0,5 = 50/50) |
| `comHeight` | m | altura del centro de masa sobre el piso: 0,45 deportivo … 0,9 camión. Más alto = más transferencia de peso y balanceo |
| `Ixx Iyy Izz` | kg·m² | inercias de balanceo, cabeceo y guiñada. Si no las conocés: `Izz ≈ mass·(wheelBase²/12 + trackF²/12)` y `Iyy ≈ Izz·0,85`, `Ixx ≈ Izz·0,3` |
| `wheelBase` `trackF` `trackR` | m | distancia entre ejes y trochas |
| `wheelRadius` `rimRadius` `tireWidth` | m | radio de la goma, de la llanta y ancho (afecta marcas de frenada) |
| `wheelInertia` | kg·m² | inercia de cada rueda: 0,7·masa·R² aprox. |
| `rideOffset` `hardpointY` | m | ajustes de altura de la carrocería/anclaje de suspensión |

**Suspensión**
| campo | qué hace |
|---|---|
| `travel` | recorrido total (m). Rally 0,3–0,35; deportivo 0,1–0,15 |
| `freqF` `freqR` | frecuencia natural (Hz): 1,2 blando/confortable … 2,5 duro/pista. Define el resorte |
| `zetaBump` `zetaRebound` | amortiguación como fracción de la crítica (0,25–0,45 compresión, 0,5–0,7 extensión) |
| `arbF` `arbR` | barras estabilizadoras (N/m): más arbF = subviraje, más arbR = sobreviraje |
| `bumpStopK` `bumpStopC` | tope de fin de recorrido (rigidez/amortiguación) |
| `antiSquat` `antiDive` `rollCenter` | geometría anti-hundimiento, anti-cabeceo y altura del centro de balanceo (m) |

**Neumático**
| campo | qué hace |
|---|---|
| `mu` | agarre base (0,9 camión … 1,3 slick) |
| `gripFront` `gripRear` | multiplicadores por eje (los toca el reglaje «Grip») |
| `slipPeakLong` `slipPeakLat` | deslizamiento donde está el pico de agarre (0,10–0,20) |
| `tireFalloff` | cuánto cae el agarre pasado el pico (1,2 suave … 1,6 abrupto) |
| `rolling` | coeficiente de rodadura (≈ 0,015) |
| `surfGrip` | `{asphalt, dirt, shoulder, grass, outside, mud, snow}` → multiplicador por superficie (0..1,2). Una pista `ground_info` que devuelve el id 0..6 selecciona el valor. Falta `snow`: se calcula como `0,78·dirt` |

**Motor y transmisión**
| campo | qué hace |
|---|---|
| `peakTorque` (N·m), `torqueCurve` | torque máximo y curva `[[rpm, factor 0..1], …]` |
| `idleRpm` `launchRpm` `maxRpm` | ralentí, régimen de largada y corte |
| `engineInertia` `engineBrake` | inercia del motor y freno motor (N·m) |
| `gears[]` `reverseRatio` `finalDrive` `efficiency` | relaciones, reversa, final y eficiencia (≈ 0,88) |
| `clutchTime` | tiempo de embrague al arrancar (s) |
| `shiftUpRpm` `shiftDownRpm` `shiftTime` | puntos de cambio automático y tiempo del cambio |
| `vGov` | limitador de velocidad (km/h; 0 = sin) |
| `driveType` `frontDriveRatio` `rearDriveRatio` `centerDiffBias` `lsd` | tracción y diferenciales |
| `nitroCap` `nitroBoost` | nitro (s de carga y +% de torque) |
| `firingOrder` | **sólo audio**: cilindros por vuelta (4 = 4 cilindros, 6, 8, 10, 12…) → frecuencia y carácter del motor |

**Frenos, dirección, aero y ayudas de fábrica**
`brakeTorque` (N·m en total), `brakeBiasFront` (0,55–0,70), `abs` + `absSlip` (0,14), `maxSteer` (rad, 0,45–0,6), `steerResponse` (7–12), `dragCoef`, `aeroF/aeroR`, `stabilityAssist`, `tractionControl` + `tcSlip`, `powerScale` (1 = sin mejoras).

**Metadatos (no físicos)**: `name`, `tagline`, `icon`, `visualType`, `class`. `visualType` elige el modelo 3D en Dream Racing; en tu juego es el nombre de tu escena de auto.

### Cómo crear un auto nuevo en 5 minutos

1. Copiá la ficha de un auto parecido y cambiá `mass, wheelBase, trackF/R, comHeight, weightFront`.
2. Elegí `gears` para que `vmax ≈ rpmMax/ (gears[última]·finalDrive)·radio·0,1047` coincida con la velocidad que querés (`CarBuild.perf_of` te la calcula).
3. Ajustá `peakTorque` hasta que el 0-100 sea el que buscás (también en `perf_of`).
4. Probalo con la demo (`--car=<id>`) y afiná `tireFalloff`, `freq*`, `arb*`, `maxSteer`.

## 2. Reglaje manual (sliders): `catalog.json["tune"]`

Cada grupo tiene `items` con `k` (clave), `n` (nombre), `min/max/step/def`, `u` (unidad), `req` (mejora que lo desbloquea, ver §3), `info/lo/hi` (textos de ayuda: qué pasa con el valor bajo y con el alto). La UI de Dream Racing los dibuja como sliders con esos textos. El estado del jugador guarda `car.tune = {clave: valor}`; lo que no esté usa `CarBuild.default_tune(base)`.

| grupo | clave | rango (def) | efecto | requiere |
|---|---|---|---|---|
| Neumáticos | `pressF` `pressR` | 22–40 psi (30) | presión: huella/agarre vs. precisión | — |
| Alineación | `camberF` `camberR` | −5…+1° (−1 / −0,5) | agarre en curva vs. frenado/tracción | camber |
| | `toeF` `toeR` | −1…+1° (0 / 0,1) | entrada en curva vs. estabilidad | toe |
| | `steer` | 70–130 % (100) | ángulo máximo de las ruedas | — |
| Suspensión | `height` | −60…+80 mm (0) | altura de la carrocería | height |
| | `springF` `springR` | 60–160 % (100) | rigidez de resortes (multiplica `freq²`) | springs |
| | `bump` `rebound` | 50–170 % (100) | amortiguador compresión/extensión | damp |
| | `arbF` `arbR` | 0–220 % (100) | barras estabilizadoras | arb |
| Frenos | `bias` | 40–78 % del. | reparto de frenado | — |
| | `bpress` | 70–125 % (100) | fuerza total de frenado | — |
| Transmisión | `split` | 0–100 % del. | reparto de tracción (0 = RWD, 100 = FWD) | split |
| | `lsd` | 0–250 % (100) | bloqueo del diferencial | lsd |
| | `final` | 75–130 % (100) | relación final | final |
| Aerodinámica | `aeroF` `aeroR` | 0–100 % (50 / 60) | carga delantera / alerón trasero | aero |
| Diversión | `stanceCamber` | 0–12° (0) | camber extremo estético (con costo de agarre) | stance |
| | `gripF` `gripR` | 70–110 / 60–110 % | agarre por eje (para derrapar) | — |

Para agregar un reglaje nuevo: (1) sumá el item en `catalog.json`; (2) leelo en `CarBuild.build_params` con `pct("clave")` y aplicalo al campo de `V`; (3) dibujá el slider (la UI de Dream Racing es `ui/garage_ui.gd`; el kit no la trae, pero la lista de grupos/items se recorre sola).

## 3. Mejoras (`catalog.json["upgrades"]`)

9 mejoras con 3–4 niveles cada una. Cada nivel: `n` (nombre), `cost`, `eff` (efecto numérico) y a veces `unlock` (reglajes que habilita):

| id | efectos (`eff`) | desbloquea |
|---|---|---|
| `engine` | `power` +7 % por nivel (acumulable) | — |
| `turbo` | `power` +10 %…; define `turboLvl` (sonido del turbo) | — |
| `weight` | `mass` −4 %… | — |
| `brakes` | `brake` +12 % | — |
| `suspension` | `freq`, `arb`, `damp` | springs, damp, arb |
| `gearbox` | `clutch`, `shift` (más rápido) | — |
| `diff` | `lsd` | lsd |
| `aero` | `aeroF`, `aeroR`, `drag` | aero |
| `stance` | — | stance |

`CarBuild.effects_of(upg)` suma los efectos, `unlocks_of(upg)` devuelve los reglajes habilitados. **Un slider sin su mejora no hace nada** (se ignora en `build_params`), por eso `--tune=springs:80` en la demo no cambia nada hasta que el auto tenga `suspension` ≥ 1. Para un juego sin tienda: pasá `"lab": {"all": true}` en el estado del auto (el «taller de prueba» de Dream Racing) y se desbloquean *todos* los reglajes. Con `lab.all` además podés pasar `power, mass, travel, grip, drag` (en %, 100 = normal) como multiplicadores globales para experimentar.

## 4. Cubiertas (`catalog.json["tires"]`)

`street, sport, slick, gravel, mud, drift`. Cada una trae `s` = multiplicador de agarre por superficie (se multiplica por `surfGrip`), y `drift` además `falloff: 0.82`. El auto guarda `tires` (la activa) y `tiresOwned`. Desgaste: `car/tire_wear.gd` (duración en km por tipo; ver doc 07).

## 5. `CarBuild.build_params` — el único punto de entrada

```gdscript
var state := {"upg": {"suspension": 2, "turbo": 1}, "tune": {"springF": 120, "arbR": 140},
              "tires": "sport", "tiresOwned": ["street", "sport"], "lab": {"all": true}}   # lab.all = todo desbloqueado
var assists := {"abs": true, "tc": 50.0, "stab": 30.0}
var final: Dictionary = CarBuild.build_params(vehicles["gt"], state, assists)
var V := VehicleParams.from_dict(final)
```

Qué hace por dentro: aplica potencia/peso/frenos, convierte los % en valores físicos (`freqF = freqF0 · (1 + mejora) · springF/100`; `zetaBump = zeta0 · (1+mejora) · bump/100`; `arbF = arb0 · (1+mejora) · arbF/100`; `finalDrive = finalDrive0 · final/100`; `maxSteer = maxSteer0 · steer/100`; `brakeTorque = brake0 · (1+mejora) · bpress/100`; etc.), alineación/presión, relación final (`gears`), reparto de tracción, aero (alerones), grip por eje, stance, cubiertas (surfGrip), asistentes. Tras cambiar el reglaje **no hace falta recrear el auto**: `phys.V = VehicleParams.from_dict(...)` y `phys.setup()` (conserva `omega/comp/s` de las ruedas: ver `if old.size() == 4` en `setup()`). Probado en el kit (§8).

## 6. Rendimiento y clasificación

`CarBuild.perf_of(V: Dictionary)` calcula con el diccionario FINAL: **PI** (índice de rendimiento), `hp`, `vmax`, `t100` (0-100 km/h), barras (aceleración/velocidad/manejo/frenos) y `class_of(pi)` devuelve la clase (D…S…) con color. Se usa para armar tarjetas de auto y para igualar categorías de carrera. Es una estimación analítica, no una simulación (la validación real es `tests/…` con la física).

## 7. «Reglaje de ayudas» e interacción con las clases de simulación

Ver doc 02 §12 (`SIM_PRESETS`). Importante: **ABS/TC/estabilidad no son sliders del taller**, sino un nivel de simulación que se elige antes de largar. El «Ángulo de dirección» sí es del taller y del nivel PERSONALIZADO.

## 8. Aplicar un reglaje en caliente (probado)

```gdscript
var st := {"upg": {}, "tune": {"pressF": 26.0, "pressR": 34.0, "bias": 70.0, "gripR": 80.0}, "tires": "sport", "tiresOwned": ["street", "sport"], "lab": {"all": true}}
var V2 := VehicleParams.from_dict(CarBuild.build_params(vehicles[id], st, {"abs": true, "tc": 30.0, "stab": 20.0}))
car.phys.V = V2
car.phys.setup()          # recalcula resortes/pesos por rueda y CONSERVA la velocidad angular de las ruedas
```
