# 09 · Gráficos y renderizado 100 % manual (sin autoajuste)

El juego original trae un sistema de **calibración automática** (`autotune.gd`, `calib_ui.gd`, `frame_res.gd`) que mide el teléfono y elige un perfil. **No viene en el kit a propósito**: este documento describe cómo se configuran los gráficos **a mano**, perilla por perilla, y qué hace cada una. `demo/graphics.gd` es la versión mínima ejecutable.

## 1. Base del proyecto (`project.godot`)

```ini
[rendering]
renderer/rendering_method="gl_compatibility"           # OBLIGATORIO en Android de gama media/baja: Mobile/Vulkan da cierres y consume más
renderer/rendering_method.mobile="gl_compatibility"
anti_aliasing/quality/msaa_3d=0                        # MSAA apagado (se cambia desde el viewport)
lights_and_shadows/directional_shadow/size.mobile=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality.mobile=1
textures/vram_compression/import_etc2_astc=true        # texturas comprimidas para Android
[physics] common/physics_ticks_per_second=120          # coincide con la física del auto (no la usa, pero es coherente)
[display] window/stretch/mode="canvas_items", aspect="expand", handheld/orientation=4   # horizontal
```
Exportación Android: ARM64, GL Compatibility, **16 KB de alineación de páginas** (Godot ≥ 4.5), sin `Vulkan`.

## 2. Las perillas (todas manuales)

| perilla | valores | qué cambia | dónde se aplica |
|---|---|---|---|
| **Escala 3D** (`res`) | 0,35 · 0,5 · 0,7 · 1,0 | píxeles que renderiza la GPU. **La que más FPS da**: GPU-bound → casi proporcional | `Viewport.scaling_3d_scale` (demo) o `SubViewport.size` (juego) |
| **Resolución de frame** (`frameRes`) | 100 · 83 · 67 · 50 · 40 % | baja TODO el cuadro (HUD incluido) | **NO la uses**: ver §4 |
| **Calidad general** (`quality`) | baja · media · alta | pone por defecto árboles, sombras y tope de resolución | `_apply_quality_settings` |
| **Árboles** (`trees`) | 0 · 1500 · 3000 · 6000 | cantidad de árboles (MultiMesh) | tu generador de mundo |
| **Sombras** (`shadowsQ`) | no · sí | sombra del sol: **sólo con la calidad alta** o a pedido | `DirectionalLight3D.shadow_enabled` |
| **Texturas** (`textures`) | baja · media · alta | `anisotropic_filtering_level`: disabled / 4× / 16× | `Viewport.anisotropic_filtering_level` |
| **Partículas** (0–10) | 0..1 | cantidad de humo/polvo (`Effects.intensity`) y calidad (`qk`) | `Effects` |
| **Mostrar FPS** | sí/no | etiqueta con FPS, ms de física y de cuadro | tu HUD |
| **Vida del mundo** | sí/no | tránsito, peatones, estacionados | tu mundo |
| **Clima del mundo** | sí/no | nubes, niebla, lluvia | tu mundo |

### Mapeo de calidad general (de `race.gd → _apply_quality_settings`)

| calidad | árboles | sombras | tope de escala 3D |
|---|---|---|---|
| baja | 1500 | no | 0,45 (y 0,40 fija) |
| media | 3000 | no | 0,65 |
| alta | 6000 | sí | 0,85 |

Cada perilla puede ir en «según la calidad» (hereda) o fijarse a mano (anula la calidad).

## 3. Cómo aplicarlas (código de la demo, `demo/graphics.gd`)

```gdscript
vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR   # bilineal: rápido (en GL Compatibility es el modo que conviene usar)
vp.scaling_3d_scale = 0.7                                # sólo el 3D; el HUD (CanvasLayer) sigue nítido
vp.msaa_3d = Viewport.MSAA_DISABLED
sun.shadow_enabled = true
sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS   # 2 cascadas
sun.directional_shadow_max_distance = 45.0               # sombras sólo cerca (más = menos nitidez y más costo)
Engine.max_fps = 60
```
Dream Racing hace lo mismo con otro método: renderiza el 3D en un **`SubViewport`** de tamaño `ventana × res_scale` y lo muestra en un `TextureRect` debajo del HUD; la ventaja es poder aplicar efectos de lente y re-escalar sin tocar el HUD. En el kit alcanza con `Viewport.scaling_3d_scale`.

## 4. Lo que NO tenés que hacer (lecciones)

1. **No bajes la resolución de TODO el cuadro con capas (FrameRes)**: en dos teléfonos (Mali y otro) la **calibración se cerraba sola** al cambiar la resolución del frame, con Godot 4.5.1 y 4.7.2. Dream Racing lo dejó **apagado**; bajá sólo la escala 3D.
2. **Evitá luces dinámicas** (OmniLight/SpotLight) en tránsito, farolas y calles: son caras en GL Compatibility y Dream Racing las evita ("sin luces dinámicas" en el mundo vivo). Si necesitás faros, limitalos al auto del jugador.
3. **MSAA 3D apagado** (0). Si querés borde suave usá la escala 3D = 1,0.
4. **Sombras sólo del sol y sólo del auto del jugador** (sin sombras por auto civil ni por peatón; los tránsitos son `MultiMesh` sin sombra).
5. **Una escala 3D fija**: el juego probó una "resolución dinámica" que cambia con los FPS y se descartó (tirones al cambiar y resultados inconsistentes). Que la elija el jugador y quede fija.
6. **Compilación de shaders**: el primer derrape/humo/lluvia puede tironear. Precalentá (`Effects.tick`) detrás de una pantalla de carga.

## 5. Cómo medir (para elegir valores a mano)

- Activá «Mostrar FPS» (promedio cada 0,5 s) y mirá además el costo de la **física** (ms por cuadro; debería ser < 1–2 ms por auto) y el de «vida del mundo».
- Para saber si el límite es **GPU o CPU**: bajá la escala 3D de 1,0 a 0,5 **en el mismo punto**. Si los FPS suben casi proporcional, es GPU/píxeles; si casi no cambian, es CPU (física, dibujo de objetos, tránsito).
- Medí siempre en el teléfono: la PC miente. Probá A–B–B–A para descartar ruido.
- Con Godot: `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)`, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, `TIME_PROCESS`, `TIME_PHYSICS_PROCESS`.

## 6. Guardado

Guardá cada perilla como una clave simple (`{"res": 0.7, "shadows": "media", ...}` en `user://settings.json`) y aplicá al arrancar y al cambiar. Los cambios de calidad/escala se pueden aplicar **en caliente**; árboles y sombras de mundos ya armados pueden requerir reconstruir.
