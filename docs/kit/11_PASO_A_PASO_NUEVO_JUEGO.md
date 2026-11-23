# 11 · Receta: armar tu juego de conducción sobre el kit

## Paso 0 · Verificá que el kit anda en tu entorno
```bash
godot --headless --path proyecto_godot --import
godot --headless --path proyecto_godot -- --autotest --noaudio       # debe terminar con «→ OK»
```
Leé `demo/main.gd` entero (≈ 300 líneas): es el esqueleto de tu juego.

## Paso 1 · Estructura de tu proyecto
Copiá `proyecto_godot/game/` a tu proyecto y respetá las rutas `res://game/...` (todos los `preload` son absolutos). Cambiá `res://game/i18n/tr.gd` por tu traducción. `project.godot`: copiá la sección `[rendering]`, `[physics]`, `[input_devices]` y `[importer_defaults]` (WAV sin comprimir).

## Paso 2 · Tu pista
Creá `mi_pista.gd` que **extienda** `res://game/physics/track_base.gd` y devuelva `ground_info(x, z)` (altura + superficie 0–6). Para empezar: un plano con una región de tierra.
- Circuito con pared: implementá `nearest(x,z)` y los arrays de `track_base` (ver `Car._keep_in_wall`) y poné `car.wall = ancho_en_metros`.
- Mundo abierto con obstáculos: `push(x,z,r)` y `car.solid = true`.
- Con edificios: `camera_clear(desde, hasta)`.

## Paso 3 · Tus autos
1. Agregá la ficha en `game/data/vehicles.json` (copiá una parecida; ver doc 03 §1).
2. Si usás el sistema de mejoras/tienda, agregá su entrada en `catalog.json["cars"]` (`tires`, `paint`, precio…); si no, ignorá el catálogo y pasá siempre `{"upg": {}, "tune": {}, "tires": "street", "tiresOwned": ["street"]}`.
3. Modelo 3D: tu escena de auto debe tener nodos de **ruedas** (cada rueda: un `Node3D` de dirección con un hijo que gira). Copiá `_sync_body` de la demo (posición, orientación YXZ, altura de rueda `base − wheel_s[i]`, giro de dirección en las delanteras, rodado con `wheel_omega`).
4. Sonido: ver doc 04 §2 (`VOICE`, `TURBO_SND`, `GEAR_SND`).

## Paso 4 · Reglaje (taller)
Hacé una pantalla con los sliders de `catalog.json["tune"]` (grupos e ítems ya traen nombre, rango, unidad y textos de ayuda `lo`/`hi`). Guardá `tune` en el estado del auto y reaplicá con `CarBuild.build_params` → `phys.V = …; phys.setup()` (doc 03 §8). Mostrá PI/CV/vmax/0-100 con `CarBuild.perf_of` para que el jugador vea el efecto.

## Paso 5 · HUD con tus PNG
Dibujá tus PNG respetando nombres y proporciones (doc 05 §5), ponelos en una carpeta y `controls.load_skin(carpeta)`. Si querés cambiar posiciones base, editá `rect_of()`; si querés que el jugador las mueva, guardá `controls.layout` (editor integrado, `set_editing(true)`).

## Paso 6 · Cámaras
`rig.set_preset(1)` (media) y las opciones de ajuste (doc 06 §3). Interiores: necesitás tu propio habitáculo o hacelos con `rig.mount` (capó/paragolpes).

## Paso 7 · Efectos y marcas de frenada
`Effects` ya hace todo (doc 07). Si tu pista tiene relieve, `ground_info` tiene que devolver bien la altura.

## Paso 8 · Gráficos manuales
Copiá `demo/graphics.gd` y conectalo a tu pantalla de opciones (doc 09). Guardá cada perilla.

## Paso 9 · Rivales (si los hay)
Cada rival es un `Car` con `driver != null` (un objeto con `update(phys, dt) → Vector3(throttle, brake, steer)` y campos `hb`, `nitro`). Reglas de hilos en doc 10 §A3. Para pocos rivales, simulalos en el hilo principal (misma demo, un `for` más).

## Paso 10 · Pruebas y publicación
Reglas de doc 10 §E y §F. Registrá cada cambio. Exportá a Android con GL Compatibility, ARM64 y alineación de 16 KB.

## Mapa de "quiero cambiar X → archivo"

| quiero… | archivo / lugar |
|---|---|
| que el auto acelere más / agarre más / sea más estable | `vehicles.json` (`peakTorque`, `mu`, `tireFalloff`, `arbF/R`, `freqF/R`) |
| nuevo reglaje | `catalog.json["tune"]` + `car_build.gd → build_params` |
| nuevas ayudas (ABS/TC/estabilidad) | `vehicle_physics.gd → _engine` + `build_params(assists)` |
| volante real/arcade | `Controls.wheel_real` |
| nuevo botón del HUD | `controls.gd` (doc 05 §5, patrón) |
| nuevas cámaras | `CameraRig.CAMERAS` |
| marcas de frenada más largas / más gruesas | `effects.gd → emit_from` (`MARKS`, `tire_w`, umbrales `0.22`/`0.25`) |
| nuevo sonido de motor | `tools/make_engine_audio.py` + `VOICE[id]` |
| nueva superficie (hielo, arena) | `VehicleParams.SURF_NAMES` + `surfGrip` + `Effects._dust_k/_dust_color` + `CarAudio` (dirt) |

## Mensaje para el otro chat (resumen de una línea)
«No reescribas la física, el HUD ni el audio: están medidos y probados. Cambiá datos (`vehicles.json`, `catalog.json`), la pista y los PNG; si tocás código, corré `--autotest` y la prueba de audio.»
