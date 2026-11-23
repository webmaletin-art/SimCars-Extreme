# 04 · Audio del auto y su configuración por vehículo

Archivos: `proyecto_godot/game/audio/car_audio.gd` (527 líneas), `wav_loop.gd`, `samples/*.wav` + `samples/consts.json`. Generadores: `tools/make_audio.py`, `tools/make_engine_audio.py`. Medición: `proyecto_godot/tests/audio_render.gd` + `tools/analyze_audio.py`.

## 1. Cómo suena un auto (el modelo)

Nada está "grabado" de un auto real: todo son **bucles cortos sintetizados** (WAV 16-bit) que el código **mezcla y re-afina en vivo** según el estado de la física. Cada "voz" es un `AudioStreamPlayer` que reproduce un bucle y cuyo volumen y `pitch_scale` se fijan cada cuadro (`_set_voice`). Si una voz es inaudible se **pausa** (no gasta CPU).

| voz | muestra | qué es | de qué depende |
|---|---|---|---|
| `eng_on0…6` | `eng_on*.wav` | motor **con carga** (acelerando) a 7 frecuencias de encendido (32, 55, 95, 160, 270, 450, 750 Hz) | rpm × `firingOrder` × `VOICE.f`, carga, pedal |
| `eng_off0…6` | `eng_off*.wav` | motor **sin carga** (soltando: freno motor) | lo mismo; se cruza con `on` según el pedal |
| `overrun` | `overrun.wav` | crepitar del escape al soltar con vueltas | pedal soltado, rpm > 30 %, `VOICE.pops` |
| `gearwhine` | `gearwhine.wav` | caja de engranajes rectos (zumbido con armónicos) | velocidad de eje × `GEAR_SND.tooth`; más fuerte soltando |
| `engnoise` | `engnoise.wav` | ruido mecánico / admisión | carga × `VOICE.noise` |
| `roll` | `roll.wav` | rodado de gomas en asfalto | velocidad, superficie (asfalto) |
| `squeal` | `squeal.wav` | chillido de goma al patinar | patinaje (`kappa`, `alpha`), frecuencia sube con el patinaje |
| `gravel` | `gravel.wav` | tierra / pasto | velocidad, fracción de ruedas en superficie suelta |
| `wind` | `wind.wav` | viento (grave, con ráfagas lentas) | velocidad (casi nada hasta 20 km/h) |
| `rain` | `rain.wav` | lluvia | `rain(true)` |
| `turbo` | `turbo.wav` + senos | soplido y silbido del turbo | carga del turbo (retardo `spool`), `TURBO_SND` |
| `whine1/2`, `whistle`, `gwe` | `sine.wav`, `tri.wav` | tonos puros (sólo modo simple) | caja y turbo |
| disparos | `pop`, `thump`, `backfire`, `flutter_lo/mid/hi` | petardeos, golpes, estampidos, flutter del turbo | eventos (`shift_down`, aterrizaje, impacto) |
| `engine_ai` | `engine_ai.wav` | motor de rivales cercanos | `rival(distancia, rpm, firingOrder)` |

Si faltan las muestras en capas (`consts.json` sin `eng_refs`), cae al **motor de siempre** de un solo ciclo (`engine.wav`, 1050 muestras). Si pasás `simple = true`, sólo suena `engine` + `pop` + `thump` (modo de emergencia).

## 2. Configuración **por vehículo**

Cuatro lugares. `set_vehicle(id)` toma el `id` de `vehicles.json`:

### a) La física manda lo principal
El audio lee del auto (`VehicleParams V`): `idleRpm`, `maxRpm` (el motor sube de 0 a 1 entre ralentí y corte), `firingOrder` (frecuencia = `rpm/60 × firingOrder`), `turboLvl` (0 = sin turbo; > 0 suma silbido), `finalDrive` y `wheelRadius` (frecuencia de la caja). Un auto nuevo con esos campos bien puestos **ya suena razonablemente**.

### b) `VOICE[id]` — carácter del motor (opcional)
```gdscript
"torito": {"f": 0.92, "cut": 0.85, "eng": 1.10, "noise": 1.3, "pops": 1.2}
```
`f` multiplica la frecuencia (tono: < 1 más grave), `cut` multiplica el filtro pasa-bajos (brillo: < 1 más sordo), `eng` el volumen del motor, `noise` el ruido mecánico, `pops` los petardeos/crepitar. Sin entrada = voz neutra (todo 1,0).

### c) `TURBO_SND[id]` — turbo
```gdscript
"hatch": {"f": 1.15, "spool": 0.5, "w": 0.8, "fl": 0.8}
```
`f` tono del silbido (× 1500–3400 Hz según la carga; tope `WHISTLE_MAX_HZ = 3300`), `spool` tiempo de carga del turbo (s; menos = más rápido), `w` volumen del silbido, `fl` intensidad del flutter (el soplido al soltar). Sin entrada usa `pickup`.

### d) `GEAR_SND[id]` — caja
```gdscript
"hatch": {"k": 0.35, "tooth": 38.0}
```
`k` volumen del zumbido de la caja; `tooth` "cantidad de dientes" (tono: frecuencia = `eje × tooth × 0,42`, tope 1500 Hz en la voz con armónicos y 2400 Hz en la simple). Sin entrada usa `pickup`.

**Receta para un auto nuevo `miauto`**: ficha en `vehicles.json` con `idleRpm, maxRpm, firingOrder, gears, finalDrive, wheelRadius` → opcionalmente `VOICE["miauto"]`, `TURBO_SND["miauto"]` y `GEAR_SND["miauto"]` en `car_audio.gd` → `audio.set_vehicle("miauto")` → medir con `audio_render.gd` (§6).

## 3. Mezcla (los controles que ve el jugador)

`audio.mix = {"eng", "surf", "wind", "turbo", "gear"}` (todos 0..~1,4; 1,0 = normal; en el juego salen de opciones 0–130 %). `audio.volume` (0–100) sube/baja el master (`apply_settings()`); `SND["master"]` es el nivel general. `surf` manda sobre rodado/chillido/tierra y `wind` sobre viento/lluvia (por defecto 30 → `SURF_DEFAULT`). `audio.set_active(false)` silencia todo y pausa (pantalla de pausa); `audio.rain(bool)`.

Buses creados por código: `GSMotor` (con pasabajos que se abre con la carga y las rpm), `GSViento` (pasabajos 1800 Hz), `GSRival` (900 Hz) y en el Master un **compresor + HardLimiter** (evita saturar con la suma de capas).

### Constantes de nivel (`SND`)
`engine 0.62 · layers 2.4 · tires 0.13 · squeal 0.17 · gravel 0.092 · wind 0.04 · turbo 0.085 · whistle 0.018 · whine 0.012 · gwhine 0.18 · overrun 0.55 · backfire 0.55 · pops 0.35 · impacts 0.8 · rain 0.06`. Están medidos (RMS por voz); **no subas un fondo sin medir**: los ruidos de fondo ya habían quedado más fuertes que el motor y el dueño lo sintió como «viento fuerte» (ver doc 10).

## 4. Uso desde el juego

```gdscript
var audio := CarAudio.new()
audio.set_vehicle("hatch")        # antes de add_child
add_child(audio)                  # carga muestras y arma buses
# cada cuadro, con el snapshot ya interpolado:
audio.update(snap, car.phys.V, dt, snap.take_events(), snap.take_impact())
audio.rival(distancia_m, rpm_rival, V.firingOrder)   # (opcional) un rival cercano
```
`update` recibe `events` (Strings `"shift_up"`, `"shift_down"`, `"limiter"` y arrays `["land", vel]`) e `impact` (m/s del golpe de rueda o choque). Los choques contra paredes los metés vos: sumá `Car.wall_hit * 0.55` al `impact`.

## 5. Bucles seguros (OBLIGATORIO) — `wav_loop.gd`

Un `AudioStreamWAV` con `loop_end = cantidad de muestras` hace que Godot lea **una muestra después del final** en cada vuelta; si el dato termina en el borde de una página de memoria, Android mata el juego (**SIGSEGV en el hilo de audio**, causa confirmada de los cierres de Dream Racing). `WavLoop.make(w, frames)` agrega una copia de la primera muestra al final y fija `loop_end = frames`. **Todo bucle propio tiene que pasar por `WavLoop.make`**; `WavLoop.safe(w)` lo verifica (úsalo en pruebas).

## 6. Generar y medir muestras

```bash
pip install numpy scipy pillow
python3 tools/make_audio.py          # ruidos de fondo, motor de un ciclo, senos, disparos, consts.json
python3 tools/make_engine_audio.py   # capas del motor (eng_on/off ×7, overrun, gearwhine, backfire); agrega a consts.json
```
`consts.json` guarda por muestra `unit` (ganancia para normalizar a RMS 0,10 = −20 dBFS), `n` (muestras), `rate`. Los bucles de ruido son **largos a propósito** (12–24 s); uno de 2 s exactos se oye como olas que vuelven.

Medición **sin oídos** (sirve en un servidor sin audio: usa el driver "Dummy" y graba el bus Master):
```bash
godot --headless --path proyecto_godot --script res://tests/audio_render.gd -- --car=hatch --scene=accel --out=/tmp/a.wav --secs=20 [--log] [--solo=wind,roll]
python3 tools/analyze_audio.py /tmp/a.wav          # niveles por banda, TONOS QUE SE QUEDAN, repetición, silencio
```
Escenas: `accel` (0→tope, crucero, soltar, frenar) · `cruise` · `coast` · `idle` · `slide` · `dirt` · `rain` · `fast` · `stop` (no tiene que sonar nada). **Qué buscar**: tonos "sobresale > 15 dB y dura > 2 s" (silbidos clavados), repetición con correlación > 0,3, y que `stop` quede < −60 dBFS.

## 7. Reglas aprendidas (ver doc 10)

1. Tonos puros (senos) que se quedan quietos suenan a silbido: `_steady_gain` los va apagando hasta 30 % si su frecuencia no se mueve (> 2,5 s).
2. Cada tono tiene **tope de frecuencia** (caja 2,4 kHz, turbo 3,3 kHz): antes llegaban a 4–8 kHz y se oían a chillido.
3. El motor **no suena parado y sin gas** (`alive`): un ralentí constante cansa; entra con el pedal o al moverse.
4. Los parámetros se suavizan con constantes de tiempo (`TIME_K`, como `setTargetAtTime` de Web Audio): nunca asignes un volumen de golpe → "clic".
5. Pooles de disparos (`pop`×6, `flutter`×3, `backfire`×4): si todos están sonando, el nuevo se descarta (no se acumulan voces).
