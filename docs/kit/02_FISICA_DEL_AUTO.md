# 02 · Física del auto (todo lo que hace `vehicle_physics.gd`)

Archivo: `proyecto_godot/game/physics/vehicle_physics.gd`. Un `step(dt, throttle, brake, steer, handbrake, nitro, shift)` = 2 sub-pasos `_sub(h = dt/2)`. Cada sub-paso: ① caja automática → ② dirección → ③ contacto y suspensión por rueda → ④ barras estabilizadoras → ⑤ motor/embrague/caja/diferenciales/frenos (`_engine`) → ⑥ fuerzas de neumático por rueda y momentos → ⑦ integración del cuerpo rígido.

Unidades SI: metros, kg, N, rad, segundos. Torque en N·m. `rpm` en rev/min.

## Estado público útil (lo que leen cámara, HUD, sonido)

`px py pz` posición del centro de masa · `yaw pitch roll` · `vx vy vz` (mundo) · `vLong vLat` (en ejes del auto) · `aLong aLat` (suavizadas) · `yawRate` · `steerAngle` (rad, ruedas) · `rpm gear` (−1 reversa, 0 neutro, 1…n) · `wheels[i]` (`omega, comp, s, Fz, kappa, alpha, slip, contact, surf, gy`) · `limiter` · `nitro` · `damage` · `events[]` (la física los acumula; `CarSnapshot.push` los pasa a `pending_events`).

## 1. Suspensión (por rueda, independiente)

- **Contacto**: se mide la distancia vertical del punto de anclaje a `ground_info(x,z).altura + radio`. Si `d >= sMax` la rueda está en el aire (`Fz = 0`).
- **Resorte**: `k = m_rueda · (2π·f)²` con `f = freqF/freqR` (Hz) y `m_rueda = carga estática / g`. Fuerza `F = k·compresión`.
- **Amortiguador asimétrico**: `c = 2·√(k·m)` (crítico) × `zetaBump` (al comprimirse, `cv > 0`) o `zetaRebound` (al extenderse). Los reglajes `bump`/`rebound` escalan esos zeta.
- **Tope de compresión**: pasado `sMin` (recorrido `travel` m) entra `bumpStopK·penetración + bumpStopC·velocidad`. Un golpe fuerte en el tope genera `impact` (suena el golpe y vibra el teléfono).
- **Barras estabilizadoras** (`arbF`, `arbR` en N/m): transfieren carga entre las dos ruedas del eje en proporción a la diferencia de compresión.
- **Anti-dive / anti-squat / rollCenter**: parte del momento de cabeceo/balanceo se manda por la geometría (rueda "levanta" el cuerpo) en vez de comprimir el resorte (`w.jack`).
- **Aire y aterrizaje**: sin contacto, el cabeceo/balanceo/guiñada se amortiguan (`exp(−h·0.4/0.2)`) y se cuenta `airTime`; al volver a tocar después de > 0,25 s se emite el evento `land` con la velocidad de impacto.
- **Piso virtual**: el cuerpo nunca baja de `ground_y + 0.3` (red de seguridad si la pista falla).

## 2. Neumático (la parte que define cómo "se siente")

Modelo Pacejka simplificado con **deslizamiento combinado**:

```
kappa = (omega·R − v_long_rueda) / max(|v_long_rueda|, 2.5)     # patinaje longitudinal
alpha = atan2(v_lateral_rueda, max(|v_long_rueda|, 2.5))         # ángulo de deriva
sx = kappa / slipPeakLong ;  sy = alpha / (slipPeakLat · pkLat)
s  = √(sx² + sy²)                                                 # círculo de fricción: ambos se suman
curva(s) = sin( tireFalloff · atan( B·s ) ) ,   B = tan(π / (2·tireFalloff))
F = mu_efectivo · sensibilidad_carga · Fz · curva(s)
Fx = F·sx/s·longMul ;  Fy = −F·sy/s·latMul                        # la fuerza se reparte por la dirección del deslizamiento
```

- La curva sube hasta **s = 1** (pico de agarre) y cae después. **`tireFalloff`** decide cuánto cae: ~1,2 = cae poco (fácil de controlar), ~1,6 = cae mucho (resbaladizo y "nervioso"). El neumático de **drift** usa `falloff = 0.82` (cae muy suave: desliza largo y controlable).
- **`mu_efectivo`** = `track.grip_mul · mu · surfGrip[superficie] · gripFront|gripRear · (1 − 0.0009·(presión − óptima)²)`. La presión óptima es 32 psi en asfalto y 26 en suelo suelto (por eso el reglaje de presión importa).
- **Sensibilidad a la carga**: `lsens = clamp(1 − 0.12·(Fz/Fz0 − 1), 0.74, 1.12)` → una rueda muy cargada agarra *proporcionalmente* menos (por eso las barras estabilizadoras mueven el sobre/subviraje).
- **Camber**: `latMul` sube hasta ~1,07 con −2,5° y baja si es positivo o excesivo (> 5°: −3,5 % por grado, piso 0,6); `longMul = 1 − 0.012·|camber|`.
- **Toe**: ángulo extra de la rueda (`toeF/toeR`, el lado izquierdo con signo opuesto).
- **Presión**: además de `mu`, `pkLat = clamp(1 − 0.006·(p − 30), 0.85, 1.15)` mueve el pico lateral.
- **Resistencia a la rodadura**: `rolling · Fz · clamp(vl/0.5, −1, 1)`.
- **Rueda como volante de inercia**: `omega` se integra implícitamente con `wheelInertia` (+ la inercia del motor reflejada si el embrague está cerrado). Frena con el torque de freno; si el freno la lleva a 0, queda bloqueada.

## 3. Dirección

```
steer_scale(v) = clamp( (wheelBase·mu·9.81/(v²+4)·1.1 + slipPeakLat·0.35 + min(0.35,|deriva|)) / maxSteer , 0.12, 1 )
steerAngle += (−steer_in · maxSteer · steer_scale − steerAngle) · (1 − exp(−h · steerResponse))
```

A baja velocidad las ruedas giran hasta `maxSteer` (rad); a alta velocidad el ángulo máximo se reduce (dirección "sensible a la velocidad"; piso 12 %). `steerResponse` (1/s) es la rapidez con que las ruedas siguen al volante. El reglaje **«Ángulo de dirección» (70–130 %)** multiplica `maxSteer`.

## 4. Motor, embrague y caja (`_engine`)

- **Curva de torque**: `torqueCurve = [[rpm, factor], …]` interpolada linealmente; torque = `peakTorque · powerScale · factor(rpm)`. `powerScale` sube con las mejoras (motor, turbo) y con `damage`.
- **Embrague**: en neutro el motor gira libre. Al arrancar con gas, `engage` sube en `clutchTime` s y las rpm van de `launchRpm` (patinada de largada) al régimen de las ruedas; cuando las rpm del motor alcanzan a las de las ruedas, el embrague se "cierra" (`clutchLocked`) y motor y ruedas quedan unidos. Si las rpm de rueda caen < 0,8·ralentí con gas soltado o freno, se vuelve a abrir.
- **Freno motor**: soltando el gas con embrague cerrado resta `engineBrake · rpm/maxRpm`.
- **Limitador**: en `maxRpm` corta el torque (evento `limiter` → suena el corte).
- **Governor de fábrica** (`vGov`, km/h): recorta el torque cerca de esa velocidad (0 = sin límite).
- **Caja automática** (`manual = false`): sube cuando `rpm > shiftUpRpm` (con gas > 10 %, ≥ 2 ruedas apoyadas y **> 0,45 s** en la marcha actual, o si las ruedas llegan al 99 % de `maxRpm`); baja al frenar fuerte (> 25 % de freno, > 0,28 s en marcha) o si el motor se "ahoga" (rpm < `shiftDownRpm` con gas, > 0,2 s). `inGearT` es el cronómetro que evita rebotes entre marchas; cada cambio corta el torque `shiftTime` s (evento `shift`).
- **Caja manual** (`manual = true`): `in_shift = +1/−1` pide subir/bajar; no deja bajar si las rpm resultantes pasan de `maxRpm·1.03`. Los cambios también cortan torque.
- **Reversa automática**: parado (< 0,6 m/s), con freno > 0,5 y gas < 0,05 durante 0,35 s pasa a reversa y **se intercambian gas y freno**. **No entra con el freno de mano puesto** (bug real de Dream Racing: se iban marcha atrás solos en la largada; ver doc 10).
- **Nitro**: `nitroCap` segundos de carga, `nitroBoost` multiplica el torque; se recarga en 35 s. Hoy Dream Racing no lo vende, pero la física lo soporta.

## 5. Tracción y diferenciales

- `driveType`: `"RWD"` (todo atrás), `"FWD"`, `"AWD"` (usa `frontDriveRatio/rearDriveRatio`).
- **Diferencial central** (AWD): `couple = centerDiffBias · 600 · (ωdelantero − ωtrasero)`; reparte el torque entre ejes según la diferencia de giro.
- **Autoblocante (LSD)**: por eje, `lsd · Δω` limitado por `0,45·inercia/h`; transfiere torque a la rueda que gira más lento. 
- Mucho `lsd` = sale fuerte de la curva pero cuesta que gire; poco = la rueda de adentro patina.

## 6. Frenos y ABS

- Torque total `brakeTorque` repartido por `brakeBiasFront` (delante) / `1 − bias` (atrás), por rueda /2. El **freno de mano** agrega `0,55·brakeTorque` sólo atrás (bloquea las traseras → drift).
- **ABS**: si el patinaje de una rueda < `−absSlip` (frenando), reduce su factor `absF` (9/s hasta 0,25) y lo recupera (4/s). Sin ABS la rueda se bloquea y patina (humo y marcas).

## 7. Control de tracción (TC) y estabilidad

- **TC**: si el patinaje de las ruedas motrices supera `tcSlip`, el factor `tc` baja (hasta 0,2) y se lo recupera (hasta 1). Recorta el torque. **Se suelta** (el gas manda siempre) en un trompo (muy de costado) o yendo marcha atrás, si `tc_free_spin = true` (el valor por defecto); la prueba contra la versión HTML lo apaga.
- **Asistente de estabilidad** (`stabilityAssist`): aplica un momento de guiñada que lleva `yawRate` hacia la guiñada cinemática ideal `v·tan(steerAngle)/wheelBase` cuando el auto gira más que eso (contravuelta automática). Sólo actúa si hay contacto y a partir de ~8 m/s. A < 3 m/s hay además un amortiguador que empareja la guiñada con la cinemática (el auto parado no gira solo).

## 8. Aerodinámica y resistencia

- Resistencia: `F = −dragCoef · v · vector_velocidad` (lineal en v, parametrizada para que la velocidad máxima salga bien con el torque disponible).
- Carga aerodinámica: `0,6·v²·aeroF/aeroR` en N hacia abajo, aplicada adelante y atrás (mueve el balance de cabeceo). Los reglajes `aeroF/aeroR` (0–100 %) y las mejoras de aerodinámica la controlan.
- Pendiente: `FzSum·(sen pendiente longitudinal/lateral)` empuja al auto cuesta abajo (la pendiente sale de las alturas de las 4 ruedas).

## 9. Cuerpo rígido

Fuerzas longitudinal/lateral sumadas en ejes del auto → aceleración en ejes del mundo; momentos `Mz` (guiñada), `tauP` (cabeceo), `tauR` (balanceo) con inercias `Izz, Iyy, Ixx`. Cabeceo y balanceo se limitan a ±0,6 rad. Si el auto casi parado (< 0,25 m/s, sin gas, 4 ruedas apoyadas) se aplica un amortiguador (×0,8) para que quede quieto sin "temblar".

**Red de seguridad**: si algún valor no es finito (NaN), `step()` hace `reset()` a la última posición buena (se guarda 1 vez por segundo). Sin esto, un NaN rompe todo el juego.

## 10. Entradas (contrato con el HUD)

`Car.in_throttle` 0..1 · `in_brake` 0..1 · `in_steer` −1..+1 (**+ = derecha**) · `in_handbrake` bool · `in_nitro` bool · `in_shift` −1/0/+1 (se consume en el primer sub-paso). El HUD táctil ya entrega justamente esos valores (`Controls.gas/brake/steer/handbrake/shift`).

## 11. Daño y desgaste

- `damage` (0..1) resta hasta 35 % de potencia (`Te *= 1 − 0.35·damage`) y `powerMul` es un multiplicador externo (p. ej. nafta/efectos).
- Desgaste de cubiertas: `car/tire_wear.gd` (km → agarre). Ver doc 07.

## 12. Presets de «nivel de simulación» (ayudas) — `race.gd → SIM_PRESETS`

Las ayudas se eligen **una vez por carrera** y no las pisa ningún otro menú:

| nivel | ABS | TC % | Estabilidad % | Ayuda de trazada % | Volante real % |
|---|---|---|---|---|---|
| arcade | sí | 80 | 90 | 60 | 0 (¾ de vuelta) |
| medio | sí | 50 | 30 | 25 | 0 |
| pro | no | 0 | 0 | 0 | 100 (3 vueltas) |
| avanzado | sí | 30 | 20 | 0 | 0 |
| personalizado | lo que eligió el jugador (`abs, tc, stab, lineAssist, steerAngle, wheelReal`) |

`CarBuild.build_params(base, car_state, assists)` recibe `{"abs": bool, "tc": 0..100, "stab": 0..100}` y los convierte en `tractionControl/tcSlip/stabilityAssist/abs` del auto. La **ayuda de trazada** no es física: suma un volante virtual hacia la línea de carrera (`_line_steer` en `race.gd`); en el kit no existe, la reemplaza tu IA/línea.

## 13. Cómo usar la física sin el resto (una pista de prueba en 10 líneas)

```gdscript
const VehiclePhysics := preload("res://game/physics/vehicle_physics.gd")
const VehicleParams  := preload("res://game/physics/vehicle_params.gd")
const FlatTrack      := preload("res://game/physics/flat_track.gd")
var vehicles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/vehicles.json"))
var ph := VehiclePhysics.new(FlatTrack.new(), VehicleParams.from_dict(vehicles["gt"]))
ph.tc_free_spin = false
for i in 600:                       # 5 s a 120 Hz, gas a fondo
    ph.step(1.0 / 120.0, 1.0, 0.0, 0.0, false)
print(ph.vLong * 3.6, " km/h  marcha ", ph.gear, "  rpm ", ph.rpm)
```

(Atención: `vehicles.json` crudo no trae `camberF/toeF/pressF`: usan los defaults de `VehicleParams` (−1°, 0°, 30 psi). La demo pasa por `CarBuild.build_params`, que es la forma correcta.)
