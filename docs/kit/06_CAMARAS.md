# 06 · Cámaras y sus ajustes

Archivo: `proyecto_godot/game/car/camera_rig.gd` (`CameraRig`, `RefCounted`). Se crea con `CameraRig.new(camera3d, track)` y se actualiza **cada cuadro** con `rig.update(dt, snapshot, rough_surface)` DESPUÉS de `snap.sample(render_t)`.

## 1. Las 9 cámaras (`CameraRig.CAMERAS`)

| idx | nombre | modo | dist | altura | mira a | FOV base | en el kit |
|---|---|---|---|---|---|---|---|
| 0 | Onboard (casco) | `onboard` | — | — | — | 70 | necesita `cockpit` (habitáculo 3D) |
| 1 | Media | `chase` | 7,5 | 2,2 | 3,6 adelante, +0,75 | 58 | ✔ |
| 2 | Cerca/Alta | `chase` | 4,8 | 2,9 | 3,0, +0,6 | 64 | ✔ |
| 3 | Lejos/Baja | `chase` | 11,0 | 1,2 | 4,5, +1,0 | 54 | ✔ |
| 4 | Aérea | `chase` | 15,0 | 6,0 | 2,0, +0,2 | 50 | ✔ |
| 5 | Cámara libre | `custom` | `custom_dist` | `custom_elev` | auto | 60 | ✔ (arrastrar y pellizcar) |
| 6 | Interior (atrás del piloto) | `rearcabin` | — | — | — | 68 | necesita `cockpit` |
| 7 | Capó | `hood` | — | — | — | 66 | necesita `rig.mount["hood"]` |
| 8 | Paragolpes | `bumper` | — | — | — | 70 | necesita `rig.mount["bumper"]` |

Sin `cockpit`/`mount` las cámaras 0, 6, 7 y 8 caen automáticamente a la «Media». En la demo la tecla **C** recorre 1→5.

Para sumar una cámara de seguimiento propia: agregá un diccionario a `CAMERAS` con `mode: "chase"` y `dist, height, look, lookH, fov`.

## 2. Cámaras de seguimiento (`_chase`)

- **Rumbo suavizado**: la cámara se orienta con la mitad del ángulo entre la **dirección de la velocidad** y la del auto (`heading = yaw + 0,5·(rumbo_velocidad − yaw)`), y sigue ese rumbo con retardo `1 − exp(−dt·2,3)`. Resultado: en un derrape la cámara mira "un poco" hacia donde va el auto, no hacia donde apunta la trompa. En reversa no gira.
- **Distancia dinámica**: `dist = base + ajuste + clamp(v·0,018, 0, 1,1) − clamp(aLong·0,07, −0,4, 0,7)`: se aleja con la velocidad y al acelerar, se acerca al frenar. Se suaviza (`exp(−dt·3)`).
- **Posición**: detrás del auto, `altura + ajuste`, lateral con `side`. Suavizado separado XZ (`exp(−dt·9)`) y Y (`exp(−dt·5)`). Nunca baja de `ground_y + 0,7`.
- **Mira** a `look` metros adelante del auto y `lookH` de altura.
- **Inclinación (bank)**: `roll = clamp(−aLat·0,010, ±0,07 rad)`, suavizada: la cámara se inclina un pelín en las curvas (se siente la fuerza lateral sin marear).
- **Temblor**: onda lenta de ≤ 0,004 m que crece con la velocidad y es 2,2 veces mayor sobre superficie suelta. *(Antes era 12 mm a 6–7 Hz y en el teléfono se veía como un temblor feo: no lo subas.)*
- **FOV dinámico**: `fov = base + ajuste + min(v/45, 1)·8°` → efecto de velocidad.
- **Anti-edificios**: si la pista implementa `camera_clear(desde: Vector2, hasta: Vector2) → 0.22..1`, la cámara se acerca de golpe y vuelve despacio (`1 − exp(−dt·1,4)`), subiendo hasta 3,2 m. Sin ese método no hace nada.

## 3. Ajustes por cámara (los que ve el jugador)

`rig.adj` guarda `{"<índice de cámara>": {"dist": m, "height": m, "side": m, "fov": °}}`. Se leen con `adj_of(k)` y se escriben con `set_adj(k, v)` (siempre sobre la cámara actual `rig.index`). Significado por modo:

| clave | seguimiento / libre | capó, paragolpes | interior |
|---|---|---|---|
| `dist` | + = más lejos | + = más atrás | + = más atrás |
| `height` | + = más alta | + = más alta | + = más alta |
| `side` | lateral | lateral | lateral |
| `fov` | grados extra | grados extra | grados extra (sobre el FOV horizontal fijo) |

Persistí `rig.adj` en tu perfil (en Dream Racing es `profile.setting("camAdj")`, se guarda con `_save_cam_adj()`) y restauralo con `rig.adj = saved` al arrancar. La UI de Dream Racing (pausa → cámara) son 4 sliders que llaman `set_adj`.

## 4. Cámara libre (`custom`)

`rig.drag(rel: Vector2)` (arrastrar el dedo → `custom_yaw_off`, `custom_elev` en [−0,15, 1,35] rad) y `rig.zoom(factor)` (pellizco → `custom_dist` en [2,5, 40] m). Además `custom_pan_f/r/u` desplazan el punto de mira (adelante/derecha/arriba) y `custom_tgt_y` su altura. En `Controls` están las señales `cam_drag(rel)` y `cam_zoom(f)` ya conectadas a eso (basta `controls.cam_drag.connect(rig.drag)`). Sólo actúan cuando el modo es `custom`.

## 5. Capó y paragolpes (`_mounted`)

Cámaras **rígidas pegadas al auto** (`visual.global_transform`): `rig.mount = {"hood": {"y", "z", "ly"}, "bumper": {…}}` en el marco del auto (y altura, z adelante, `ly` cuánto mira hacia arriba a 12 m). Tienen la vibración del camino (≤ 1,6 mm, más fuerte en tierra) y un FOV que sube con la velocidad (+5° a 50 m/s). `rig.visual` tiene que ser el nodo del auto (en la demo es el cuerpo de cajas). Los puntos de anclaje de cada auto de Dream Racing están en `car/vehicle_mounts.gd` (no copiado).

## 6. Interiores (`_inside`) — onboard y atrás del piloto

Usan `cockpit.camera_local(modo, snapshot, tiempo, rugosidad) → {pos, look, roll, hfov}` del habitáculo 3D (**`referencia_no_ejecutable/cockpit.gd`**, 1486 líneas: lee modelos `.glb` de la cabina que no vienen en el kit). Detalles que hay que conservar si hacés tu propio habitáculo:

1. **Ángulo HORIZONTAL fijo** (`hfov`) convertido a vertical con el aspecto: `fov = 2·atan(tan(hfov/2)/aspect)`, limitado a 46–74°. Con FOV vertical fijo, en un celular largo se ve todo el habitáculo y parece un bus.
2. `cam.near = 0.04` (el volante y el tablero están pegados a la lente) y 0,08 en capó/paragolpes; las demás 0,15.
3. La cámara se **mueve con las fuerzas G** de la cabeza del piloto (`CrewMotion.cam_s`) pero **menos** que la cabeza dibujada (si no, marea).
4. En Dream Racing los pilotos y el habitáculo sólo se ven desde adentro; desde afuera el auto tiene vidrios oscuros y NO se dibujan los pilotos (ahorra mallas y animación).

## 7. Cómo usarlo

```gdscript
var rig := CameraRig.new($Camera3D, track)
rig.visual = auto_node3d                # sólo capó/paragolpes/interiores
rig.set_preset(1)
# cada cuadro, después de snap.sample(...):
rig.aspect = get_viewport().get_visible_rect().size.aspect()
rig.update(dt, snap, snap_en_superficie_suelta)
# el HUD: controls.cam_drag.connect(rig.drag); controls.cam_zoom.connect(rig.zoom); controls.camera_pressed.connect(func(): rig.next())
```
