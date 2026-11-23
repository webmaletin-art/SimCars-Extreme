# 05 · Controles táctiles (acelerador, freno, volante) y HUD con skin PNG

Archivo: `proyecto_godot/game/ui/controls.gd` (≈ 780 líneas con el skin). Es un único `Control` a pantalla completa que **dibuja** todo con `_draw()` y maneja multitoque con `_unhandled_input`. En Dream Racing vive sobre un `CanvasLayer`, por encima del 3D.

## 1. Controles que existen

| id | qué es | tamaño base (unidades `u`) | entrega |
|---|---|---|---|
| `wheel` | **volante** que gira con el dedo | 158×158 abajo-izq. | `steer −1..+1`, `wheel_visual` (rad) |
| `slider` | **barra** de dirección (alternativa) | 400×64 | `steer` |
| `pedal` | **pedal ÚNICO**: mitad de arriba = **gas**, mitad de abajo = **freno** | 70×(58 % de la altura) a la derecha | `gas`, `brake`, `pedal_v` (−1..+1) |
| `gears` | **palanca** SUBIR / marcha / BAJAR (sólo con caja manual): un toque en la mitad de arriba sube, en la de abajo baja; o arrastrar el dedo > 30·u hacia arriba/abajo | 64×158 | `shift` −1/0/+1 |
| `handbrake` | botón **H** (freno de mano) | 64×64 | `handbrake` |
| `cam`, `pause`, `shot`, `rec` | botones de cámara, pausa, captura y grabación | 40×40 arriba-der. | señales `camera_pressed`, `pause_pressed`, `shot_pressed`, `rec_pressed` |

`u = viewport_y / 393` (todo escala con la altura de pantalla: el diseño base es 393 px de alto). Las posiciones base están en `rect_of(id)`.

## 2. Cómo se lee el pedal único

La mitad superior del pedal es el gas y la inferior el freno. El valor sale de la **altura del dedo** dentro del pedal (`_pedal_from_y`): `rel = (fondo − y)/alto`, `pedal_v = clamp((rel − 0,5)·2, −1, 1)`; `pedal_v > 0` es `gas = pedal_v` y `pedal_v < 0` es `brake = −pedal_v`. O sea: centro = nada, tope de arriba = gas a fondo, tope de abajo = freno a fondo, y **es analógico** (a medio camino, medio pedal). Al levantar el dedo vuelve todo a 0. Con un solo pulgar controlás ambos y **nunca podés tener gas y freno a la vez**. En teclado: W/↑ gas, S/↓ freno (el gas gana si están los dos).

## 3. Volante

- El volante gira **exactamente lo que gira el dedo**: al apoyar guarda el ángulo del dedo respecto del centro (`wheel_touch_angle`); al mover suma la diferencia de ángulo (`d = wrap(a − anterior)`) a `wheel_rotation` (rad) y la **traba** en ±`wheel_lock()` (no puede dibujar más giro del que la dirección usa). Tope: `wheel_lock()` = `WHEEL_LOCK = ¾ de vuelta (±135°)` en **Arcade** o `WHEEL_LOCK_REAL = 3 vueltas (±540°)` en **Real**; se configura con `wheel_real` (0 = arcade, 50 = real al 50 % → ±270°, 100 = real).
- `steer = wheel_rotation / wheel_lock()` ∈ [−1, 1], suavizado: `steer += (deseado − steer)·(1 − exp(−dt·rate))` con `rate = 13` al soltar y `9,5` mientras se gira.
- Suelto el dedo, el volante **vuelve solo** al centro con el mismo ritmo.
- `steer_pct` (70–130 %) amplía/limita el ángulo de las ruedas del auto (lo aplica `CarBuild` con el reglaje «Ángulo de dirección»).
- `wheel_scale` / `pedal_scale` (0,7–1,6): tamaño. `layout[id] = {x, y, s}`: posición (fracción de pantalla) y escala; los guarda el editor.

### Giroscopio (inclinar el teléfono)
`gyro_on = true` reemplaza al volante: lee el acelerómetro/gravedad, lo convierte a ángulo y lo pasa por: **sensibilidad** (`gyro_sens` 25–130: cuánto hay que inclinar), **zona muerta** (`gyro_dead` 0–5°), **curva** (`gyro_curve` 1 lineal … 1,7 muy progresiva) y **suavizado** (`gyro_smooth` 30 directo … 5 muy suave). `recalibrate_gyro()` fija el "recto". Es `project.godot → input_devices/sensors/enable_accelerometer=true`.

## 4. Editor de layout («Modificar controles»)

`set_editing(true)` muestra una barra GUARDAR / RESTABLECER / CANCELAR; un dedo arrastra un control, dos dedos lo agrandan/achican (pinza); al terminar emite `edit_done(saved)` y vos persistís `controls.layout` en tu perfil (`{id: {x, y, s}}`; en Dream Racing es `profile.setting("controls.layout")`). Se restaura asignando el diccionario antes de mostrar el HUD.

## 5. **Skin por PNG** (agregado en el kit)

Por defecto los controles se dibujan por código (círculos, arcos, degradés). El kit agrega `skin: Dictionary` (nombre → `Texture2D`) y `load_skin(dir) → cantidad`: carga `<dir>/<nombre>.png` para los nombres que existan. **Lo que no tenga PNG se dibuja por código**, así que podés vestir de a un control.

```gdscript
controls.load_skin("res://demo/hud")                  # 14 PNG de ejemplo
controls.load_skin("user://mi_tema")                  # también desde disco (el usuario puede cambiarlos)
controls.skin["wheel"] = preload("res://mis_png/volante_gt.png")   # o a mano
controls.skin.clear(); controls.queue_redraw()        # vuelve al dibujo por código
```

### Nombres, tamaño sugerido y reglas

| archivo | tamaño sugerido | cómo se usa |
|---|---|---|
| `wheel.png` | **512×512**, cuadrado, fondo transparente | se dibuja en el rectángulo del volante y **se gira alrededor del centro** por `wheel_visual`. Pintá la marca de "arriba" (la tira naranja de 12 px) para ver el giro. Dejá el aro dentro del círculo inscrito |
| `pedal_bg.png` | **140×640** (proporción 0,22) | fondo del pedal único, se estira al rectángulo. Mitad de arriba = gas, de abajo = freno, línea en el medio. El código superpone un degradé translúcido verde (gas) / rojo (freno) |
| `pedal_knob.png` | 96×96 | el botón que sube y baja con el dedo (se dibuja 40·u de lado) |
| `slider_bg.png` / `slider_knob.png` | 800×128 / 96×96 | barra de dirección y su botón (sólo con `steer_mode = "slider"`) |
| `gear_up.png`, `gear_up_on.png` | 128×128 | botón SUBIR normal / **encendido** (se ve 0,14 s al pulsar) |
| `gear_dn.png`, `gear_dn_on.png` | 128×128 | botón BAJAR |
| `gear_mid.png` | 128×128 | fondo del número de marcha (el número lo escribe el código con la fuente) |
| `handbrake.png`, `handbrake_on.png` | 128×128 | botón del freno de mano (reposo / pisado) |
| `btn_cam.png`, `btn_pause.png` | 128×128 | botones de cámara y pausa |

**Reglas para armar tu arte**: PNG RGBA (canal alfa), formas centradas; los rectángulos se estiran, así que **mantené la proporción** indicada. Para que el volante "se sienta", hacelo **simétrico respecto del centro**. Los botones deben tener ~10 % de margen transparente.

Generar plantillas nuevas de ejemplo: `python3 tools/make_hud_png.py [carpeta]` (usa Pillow; es el script que dibujó los 14 de `demo/hud/`). Está pensado para que lo edites (colores, radios) o lo reemplaces por tu arte.

### Cómo agregar un control nuevo con PNG (patrón)
1. Sumá su id a `ITEMS` y su caja a `rect_of(id)`; su nombre de PNG a `SKIN_NAMES`.
2. En `_draw()`: `if not _tex_rect("mi_png", rect_of("mi_id")): …dibujo por código…`.
3. Su toque: en `_touch_down/_touch_move/_touch_up` (`_hit(pos)` devuelve el id bajo el dedo).

## 6. Uso desde tu escena

```gdscript
var layer := CanvasLayer.new(); add_child(layer)
var controls := Controls.new(); controls.set_anchors_preset(Control.PRESET_FULL_RECT); layer.add_child(controls)
controls.load_skin("res://demo/hud")
controls.steer_mode = "wheel"     # o "slider"
controls.manual = false           # true muestra SUBIR/BAJAR
controls.wheel_real = 0           # 0 arcade · 50 · 100
# cada cuadro, ANTES de la física:
controls.update_inputs(dt)        # integra dedos, teclado, giroscopio
car.in_throttle = controls.gas; car.in_brake = controls.brake; car.in_steer = controls.steer
car.in_handbrake = controls.handbrake; if controls.shift != 0: car.in_shift = controls.shift
# y para dibujar el tablero:
controls.speed_kmh = absf(snap.vLong) * 3.6; controls.gear_text = ...; controls.rpm_frac = snap.rpm / V.maxRpm
```
`Controls.use_mph`, `show_speed` (oculta el panel de velocidad si tenés tablero 3D), `limited` (luz del limitador), `badge_dot` (punto rojo en pausa).

## 7. Teclado (para probar en PC)
W/↑ gas · S/↓ freno · A D/← → dirección · ESPACIO freno de mano · E/Q subir/bajar marcha.
