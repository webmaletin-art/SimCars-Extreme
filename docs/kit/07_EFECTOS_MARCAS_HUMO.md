# 07 · Efectos: marcas de frenada, humo, polvo, salpicaduras y desgaste

Archivo: `proyecto_godot/game/fx/effects.gd` (`Effects`, `Node3D`) + texturas `fx/tex/` (`smoke_atlas.png`, `chunk.png`, `splash.png`, `rain_streak.png`, `glow.png`; generables con `tools/make_fx_textures.py`).

## 1. Uso

```gdscript
var fx := Effects.new(); add_child(fx)
fx.setup(track)                # construye el MultiMesh de marcas; `track.ground_info(x,z)` da la altura del piso
fx.prepare(0)                  # crea los emisores del auto n.º 0 (clave libre: usá un índice por auto)
fx.intensity = 1.0             # 0 = sin partículas … 1 = todas (opción «Partículas»)
fx.set_quality("media")        # "baja" (×0,5) | "media" | "alta" (×1,5) la cantidad de partículas
fx.wetness = 0.0               # 0 seco … 1 lluvia fuerte → salpicadura de agua
# cada cuadro:
fx.tick(camera.position)       # los primeros 4 cuadros "precalienta" los emisores (compila shaders): tapalos con una pantalla de carga
fx.emit_from(0, snap, dt, tire_width)        # snap = CarSnapshot interpolado; tire_width = ancho de la goma (m)
fx.reset()                     # al reiniciar la carrera: borra marcas y partículas
```
Para rivales cercanos llamá `fx.emit_from(i, snap_i, dt, w, 0.5)` (`detail` 0,5 = mitad de partículas, **sin piedritas**).

## 2. Cuándo aparece cada cosa (reglas por rueda)

`wheel_fx` del snapshot trae, por rueda: `contacto, superficie, velocidad longitudinal, kappa, alfa, x, z, altura del piso`. Se define `sl = max(0, |kappa| − 0,06) + max(0, |alfa| − 0,09)` («exceso de deslizamiento»):

| efecto | condición | cantidad |
|---|---|---|
| **Humo de goma** | asfalto (`surf = 0`) y `sl > 0,14` | `clamp((sl − 0,14)·3,2, 0, 1) · min(1, v/3 + 0,3)` |
| **Polvo / tierra / pasto / barro / nieve** | superficie ≠ asfalto | `clamp(v·0,045 + sl·1,6, 0, 1) · k(superficie)`; color por superficie (`_dust_color`) |
| **Rocío de agua** | asfalto mojado (`wetness > 0,05`) y v > 6 m/s | `clamp((v − 6)·0,03, 0, 1) · wetness` |
| **Piedritas / barro** | ruedas traseras sobre superficie suelta (sólo jugador, `intensity ≥ 0,4`) | según velocidad y patinaje; 2 emisores por auto |
| **Marca de frenada (asfalto)** | asfalto y `sl > 0,22` | franja negra, alfa 0,62 |
| **Marca de tierra** | suelto, v > 4 m/s y `sl > 0,25` | franja marrón, alfa 0,26 |

Ruedas en el aire (`contacto < 0,5`) apagan todo.

## 3. Marcas de frenada — cómo funcionan (y por qué no cuestan nada)

- **Un único `MultiMesh` de 3000 cuadrados** (`MARKS`), una sola llamada de dibujo para TODAS las marcas del juego. Nada de decales ni nodos por marca.
- Cada rueda guarda el último punto de contacto marcado (`last[i]`). Si ahora también marca, dibuja **una tira entre los dos puntos**: posición = punto medio (+6 cm para no hacer z-fighting con el piso), orientación = `Basis.from_euler(−atan2(Δaltura, dd), atan2(dx, dz), 0, YXZ)` (sigue la **pendiente** del piso), escala = `(ancho_goma·0,9, 1, largo)`.
- Sólo se genera una tira si la distancia al punto anterior está entre **0,35 m y 3 m** (menos: demasiadas tiras; más: salto de teletransporte → se reinicia el rastro).
- Es un **anillo**: al llenarse (`_mk = (_mk + 1) % 3000`) pisa las más viejas. *(Con 500 las marcas del drift se borraban en 3–4 s y parecía que no había.)*
- Material: `StandardMaterial3D` **sin sombreado** (`SHADING_MODE_UNSHADED`), color por instancia (`use_colors`), transparencia alfa, sin sombras (`SHADOW_CASTING_SETTING_OFF`), `extra_cull_margin = 4000` (para que el culling no las oculte). Las no usadas se esconden en `y = −999` con escala 0.
- Las marcas **no se guardan** al cambiar de pista: `fx.reset()` las borra.
- **Para un mundo con relieve**, la altura del piso sale de `track.ground_info(x, z).x`: asegurate de que tu pista la devuelva bien o las marcas flotan/se entierran.

Cómo cambiar el aspecto: color/alfa en `emit_from` (líneas `Color(0.03, 0.03, 0.03, 0.62)` / `Color(0.16, 0.12, 0.08, 0.26)`), ancho multiplicando `tire_w`, umbrales `0.22` / `0.25`, largo máximo (`dd < 3,0`) y duración con `MARKS`. Para marcas de **derrape** más gruesas basta subir `tire_w` a 0,4–0,5.

## 4. Partículas (GPUParticles3D)

Por auto: 4 emisores de **humo**, 4 de **polvo**, 4 de **rocío** y 2 de **piedritas**. Se **reutilizan**: `_set_emitter` mueve la posición y cambia `amount_ratio`/`emitting`; nunca se crean ni destruyen durante la partida. Las texturas son atlas (humo 4×4 con varias formas, `chunk`). Todo en espacio del **mundo** (`local_coords = false`), así que la estela queda donde se dibujó. Cada partícula es un `QuadMesh` con material **sin sombreado, sin sombras, con billboard de partículas** y *distance fade* (se desvanece a 1–4 m de la cámara para no tapar la pantalla); `fixed_fps = 0`, `visibility_aabb` fijo de 240×60×240 m (así el culling no depende de recalcularlo). `intensity` y `qk` escalan la cantidad (opciones «Partículas» 0–10 y calidad).

> **Precalentado (`warm`)**: la primera vez, los emisores se prenden 4 cuadros bajo la cámara para compilar los shaders (sino hay un tirón al primer derrape); al terminar se hace `restart()` para que no queden manchas redondas flotando. Mostralo detrás de una pantalla de carga.

## 5. Desgaste de cubiertas (`car/tire_wear.gd`, funciones puras)

`wear_step(tire_id, speed, a_lat, a_long, slip, asphalt, dt)` devuelve cuánto desgaste (0 nueva … 1 lisa) se suma en `dt`: base = `v·dt/1000/vida_km`, multiplicada por un **estrés** `1 + 1,6·|aLat|/9 + 1,2·|aLong|/8 + 5·slip` y por la superficie (deportivas sufren en tierra ×1,5; rally en asfalto ×1,45; drift ×1,4). Vida en km (manejo tranquilo): calle 1200 · deportiva 900 · rally 1200 · drift 600. El **agarre** perdido es `1 − (1 − GRIP_MIN)·desgaste^1,35` (mínimos: calle 0,66 · deportiva 0,60 · rally 0,66 · drift 0,72), que se multiplica por `surfGrip` antes de crear `VehicleParams`. Se la llama unas 10 veces por segundo (barata). Elegí vos las vidas: en Dream Racing son altas a propósito (una goma tiene que rendir varios tanques de nafta).

## 6. Otros efectos del juego que NO están en el kit (por si los querés)

Lluvia/clima/cielo (`weather.gd`, `dream_sky.gdshader`, `dream_clouds.gdshader`), lente (`lens.gd`, reflejos y viñeta), faros. Están en el repositorio del juego; avisale al dueño cuáles pedir.
