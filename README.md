# SimCars Extreme

Simulador de conducción para Android (Godot 4.7.2, GL Compatibility) armado sobre el **Kit de Conducción de Dream Racing**:
física propia a 120 Hz (suspensión en las 4 ruedas, neumático tipo Pacejka, motor, caja, diferenciales, ABS/TC/estabilidad),
6 autos reales con su interior, un piloto que maneja con las manos en el volante y un estacionamiento de pruebas «papercraft».

## Instalar
Release **`simcars-apk`** → `SimCars-Extreme.apk`. Es un APK liviano: al abrirse baja el juego (`content.pck`) y los autos y pilotos
(`cars.pck`) de la release `simcars-content-4.7`. Cada push a la rama compila solo (`.github/workflows/build-apk.yml`).
La firma es siempre la misma (`godot/keystore/simcars.keystore`): **las actualizaciones se instalan encima sin perder el progreso**.

## Qué hay
| Parte | Dónde |
|---|---|
| Física del auto (kit, no tocar) | `godot/game/physics/`, `godot/game/car/car.gd` |
| Modelo 3D, ruedas, piezas que se rompen y se caen, abolladuras, pintura | `godot/game/car/car_visual.gd` |
| Piloto (esqueleto + IK: volante, palanca, pedales, fuerzas G) y cámaras de adentro | `godot/game/car/cockpit.gd`, `rig_pilot.gd`, `crew_motion.gd` |
| Estacionamiento: física (lomadas, rampas, tierra, límites, obstáculos) | `godot/game/world/lot_track.gd` |
| Estacionamiento: escenario, conos y postes con física (Jolt), vegetación en cruz que se mece, fondo de cartón | `godot/game/world/lot_world.gd`, `sway.gdshader` |
| Partida, HUD, pausa, ajuste de cámaras, diagnóstico | `godot/game/play.gd`, `godot/game/diag/perf_probe.gd` |
| Menú (sala 3D, garaje con pintura, piloto, ajustes) | `godot/game/ui/` |
| Perfil guardado (`user://profile.json`) | `godot/game/save/profile.gd` |
| Cliente liviano (descarga) | `godot/bootstrap/boot.gd` |
| Autos: procesado en Blender | `tools/blender/process_car.py` + `recipes.py` |
| Pilotos: procesado en Blender | `tools/blender/process_character.py` |
| Texturas, árboles, pasto, flores, fachadas, marcas, cielo (Blender) | `tools/blender/make_textures.py` |
| Fichas de física de los autos (datos reales) | `tools/gen_vehicles.py` → `godot/game/data/vehicles.json` |

## Autos
| id | Auto | Origen |
|---|---|---|
| `cls63_amg` | Mercedes-Benz CLS 63 AMG | Cls63.glb (traía 1 rueda: copiada a las 4, eje trasero medido en el pasaruedas) |
| `aventador_s` | Lamborghini Aventador S | elegy.glb (puerta izquierda corrida 57 cm a su hueco; la derecha es su espejo) |
| `mclaren_f1` | McLaren F1 | supergt_2.glb |
| `mclaren_f1_gtr` | McLaren F1 GTR | mclaren F1.glb (versión GTR; 2 ruedas del lado derecho copiadas y giradas 180°) |
| `ranger_limited` | Ford Ranger Limited | huntley.glb (1 rueda copiada a las 4) |
| `rx3_savanna` | Mazda RX-3 Savanna | hustler.glb (volante a la derecha) |

Los autos del jugador van **tal cual el original** (sin reducir triángulos ni texturas, con su interior). Sólo los autos estacionados usan
una versión liviana (`*_lite.glb`). Las mallas se unen por material (no cambia ningún triángulo) para dibujar menos veces.

## Pruebas en la PC
```bash
cd godot
godot --headless --import
godot --headless --script res://tests/perf_test.gd                       # 0-100, velocidad máxima y frenada de los 6 autos
xvfb-run -a godot --rendering-driver opengl3 res://game/main.tscn -- --autotest --crash --car=cls63_amg --shot=/tmp/x.png
xvfb-run -a godot --rendering-driver opengl3 res://game/main.tscn -- --play --perf   # diagnóstico de rendimiento por consola
```
