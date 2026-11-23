# 01 · Arquitectura del sistema de conducción

## Idea central

El auto **no usa la física de Godot**. Es una clase propia (`VehiclePhysics`, ~680 líneas) que integra el cuerpo rígido, 4 suspensiones independientes, 4 neumáticos, el motor y la caja a mano. Eso da control total del manejo (y es determinista), pero obliga a respetar un contrato:

1. La física corre a **120 Hz fijos** (`dt = 1/120`, con 2 sub-pasos de 1/240 dentro de cada paso), desacoplada de los FPS.
2. Cada paso deja su estado en un **historial circular** (`CarSnapshot`, 24 estados).
3. El dibujo pide el estado a una hora un poco **atrasada** (`render_t`) e **interpola** entre los dos pasos que la rodean. Así el auto no salta cuando un cuadro avanza 2 pasos y el siguiente 3.
4. Cámara, sonido, humo, HUD y modelo leen el **snapshot interpolado**, nunca la física directa.

## Piezas (en `proyecto_godot/game/`)

| Archivo | Rol |
|---|---|
| `physics/vehicle_params.gd` | Todos los parámetros del auto como campos tipados (`VehicleParams.from_dict`) |
| `physics/vehicle_physics.gd` | La simulación (`step`, `_sub`, `_engine`) |
| `physics/track_base.gd` | **Interfaz de pista**: `ground_info(x, z) → Vector2(altura, id_superficie)` y `grip_mul` |
| `physics/flat_track.gd` | Pista plana de asfalto (la de la demo y las pruebas) |
| `car/car.gd` | Un auto = física + entradas del jugador + historial (`snap`) + paredes opcionales |
| `car/car_snapshot.gd` | Historial circular + interpolación + eventos (cambio de marcha, limitador, aterrizaje) |
| `car/camera_rig.gd` | 9 cámaras con ajustes |
| `car/crew_motion.gd`, `tire_wear.gd` | Movimiento de la tripulación por fuerzas G; desgaste de cubiertas |
| `audio/car_audio.gd`, `wav_loop.gd` | Sonido del auto por capas; bucles sin riesgo de cierre |
| `fx/effects.gd` + `fx/tex/*.png` | Humo, polvo, rocío, piedritas y **marcas de frenada** |
| `ui/controls.gd` | Volante, pedal, barra, palanca, freno de mano, giroscopio, editor de layout, **skin PNG** |
| `data/vehicles.json` | 30 autos con todos sus parámetros físicos |
| `data/catalog.json` | Reglajes (sliders), mejoras, cubiertas |
| `data/car_build.gd` | `build_params` (ficha + mejoras + reglaje + ayudas → parámetros finales), `perf_of` (PI/CV/vmax/0-100), `class_of` |
| `i18n/tr.gd` | **Stub** de traducción (devuelve el texto): reemplazalo por el tuyo |

## El bucle (copiado de la demo, `demo/main.gd` → `_process`)

```gdscript
const STEP := 1.0 / 120.0
# 1) entradas → el auto
car.in_throttle = controls.gas; car.in_brake = controls.brake; car.in_steer = controls.steer
car.in_handbrake = controls.handbrake; if controls.shift != 0: car.in_shift = controls.shift
# 2) acumulador
smooth_dt = lerpf(smooth_dt, dt, 0.02)
acc = minf(acc + dt, 0.05)                 # tope: si el teléfono se traba no se simula una avalancha
var n := int(acc / STEP); acc -= n * STEP
for i in n:
    sim_t += STEP
    car.step_and_record(STEP, sim_t)       # física + push al historial con su hora
# 3) dibujo ATRASADO e interpolado
render_t = sim_t + acc - (smooth_dt * 1.3 + STEP)
car.snap.sample(render_t)
var p := car.snap
# 4) todo lo demás lee `p`
_sync_body(dt); rig.update(dt, p, false); fx.emit_from(0, p, dt, 0.325); audio.update(p, V, dt, p.take_events(), p.take_impact())
```

### Versión con hilos (la que usa Dream Racing)

`race.gd → _step_physics` reparte los pasos de cada auto en `WorkerThreadPool` (una tarea por auto) para que la física no coma tiempo del hilo de render. Si tenés **un solo auto**, no hace falta: la demo lo hace en el hilo principal y alcanza. Si tenés rivales, ver `docs/10` (§ Hilos): hay reglas estrictas (los hilos sólo ESCRIBEN el historial, el principal sólo LEE, y nunca a la vez; antes de mover un auto desde afuera hay que esperar a los hilos: `Car.set_sync_hook`).

## Pistas: qué le tiene que dar tu mundo a la física

Heredá de `track_base.gd` e implementá:

```gdscript
func ground_info(x: float, z: float) -> Vector2:
    return Vector2(altura_del_piso_en(x, z), id_de_superficie)   # 0 asfalto · 1 tierra · 2 banquina · 3 pasto · 4 afuera · 5 barro · 6 nieve
```

- La física lo llama **por cada rueda y por cada sub-paso** (≈ 960 llamadas/s por auto): tiene que ser barato (sin asignar memoria, sin búsquedas lineales; usá grillas o tramos precalculados).
- `grip_mul` (1.0 normal; < 1 lluvia/hielo) multiplica el agarre de toda la pista.
- Opcionales que el kit sabe usar si existen: `nearest(x,z)` + `r_lat/r_idx/r_t/laterals/tangents/wall_l/wall_r/n` (paredes de camino para `Car.wall`), `push(x,z,r)` y `take_breaks()` (obstáculos para `Car.solid`), `camera_clear(from, to)` (la cámara no se mete en edificios).

## Coordenadas y convenciones

- Y arriba. El auto mira hacia `+Z` cuando `yaw = 0`; adelante = `(sin yaw, 0, cos yaw)`; izquierda = `(cos yaw, 0, -sin yaw)`.
- Orientación del modelo: `Basis.from_euler(Vector3(pitch, yaw, roll), EULER_ORDER_YXZ)`.
- Ruedas: `wheels[0..3]` = delantera izq., delantera der., trasera izq., trasera der. (`front`, `left`; offsets `x` lateral —**x > 0 = izquierda**— y `z` longitudinal respecto del centro de masa; el orden real es: 0 delantera izq., 1 delantera der., 2 trasera izq., 3 trasera der.).
- Altura de cada rueda respecto del cuerpo: `comHeight + hardpointY − rideOffset − snap.wheel_s[i]`.
- La dirección tiene el signo invertido adentro de la física (`tgt = -steer_in * maxSteer * ...`): `steer = +1` es **derecha**.

## Qué NO es del kit (y por qué)

Calibración automática de gráficos, cuentas y servidor, compras, mundo/ciudades/policía/IA, modelos de autos: están en Dream Racing pero no se copiaron porque cada uno arrastra media base de código. Si necesitás uno, pedile al dueño el archivo concreto.
