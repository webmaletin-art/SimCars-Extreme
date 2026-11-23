# 10 · Guía de optimización y errores que NO hay que repetir

Cada punto salió de un problema real de Dream Racing (reporte del dueño, cierres en teléfono, medición). Están ordenados de lo que más duele a lo que menos. Las referencias `docs/…` son archivos del repositorio del juego (copias de varios están en `referencia_no_ejecutable/`).

## A. Cierres del juego (crashes nativos: SIGSEGV en Android)

| # | Error | Causa | Regla |
|---|---|---|---|
| A1 | **El juego se cerraba sin aviso** en cualquier modo, a veces tras minutos | Los bucles de audio tenían `loop_end = cantidad de muestras`. Godot reproduce hasta `loop_end` **inclusive**: leía **una muestra después del final** de los datos; si caía en el borde de una página de memoria → SIGSEGV en el hilo `AudioTrack` (confirmado con la «lápida» de Android y símbolos del motor, en 4.5.1 y 4.7.2) | **Todo bucle propio pasa por `WavLoop.make()`** (agrega una muestra copia al final). Probalo con `WavLoop.safe()` en una prueba |
| A2 | Cierres en el mundo abierto (carrera entre hilos) | Varios hilos del `WorkerThreadPool` **escribían a demanda** en un `Dictionary` compartido (`_cum`) mientras otro lo leía | **Ningún hilo escribe en una estructura compartida.** Calculá todo al cargar (acá 3686 entradas en 0,1 s) y durante el juego sólo leé |
| A3 | Corrupción al "mover el auto desde afuera" (calibración, policía, eventos, portones) | La física corre en hilos **en paralelo** con el resto del cuadro; otro código reescribía el auto mientras un hilo lo calculaba | Antes de tocar un `Car` desde fuera, esperá a que terminen los hilos de física: `Car.set_sync_hook(callable)` y `car.place()` ya lo llaman. **Nunca** escribas `phys.px/vx/...` directo desde el principal en medio de un cuadro |
| A4 | Cierre al **bajar la resolución de TODO el cuadro** (FrameRes), sobre todo en la calibración | `CanvasLayer` conecta/desconecta `child_order_changed` con el viewport en que ENTRA y al salir con el que tenga *en ese momento*: redirigir capas entre viewports dejaba una señal desconectada del lado equivocado (y otro SIGSEGV reproducido en PC) | **No uses esa técnica.** Bajá sólo `scaling_3d_scale`. Si redirigís capas, devolvelas en `tree_exiting` |
| A5 | Descarga del paquete «13/0» | `HTTPRequest.timeout = 30` es el tope **total** del pedido (no de inactividad): un archivo de 500 MB nunca terminaba | Sin timeout total; usá vigilante de progreso, `Range` y reintentos |

**Cómo se diagnosticó**: un registro propio (`CrashLog`) que escribe cada hito (`[audio] …`, `[calib] …`) a disco y, al abrir, lee la **«lápida» de Android 12+** con `ApplicationExitInfo.getTraceInputStream()` (señal, hilo, biblioteca, cuadros). Montá algo así desde el día uno: un botón «copiar registro» vale oro.

## B. Física y control

- **B1. Marcha atrás sola al largar**: la caja automática pasaba a reversa con el auto parado, el freno puesto y sin gas; con el freno de mano en la cuenta regresiva, el freno se volvía acelerador y el auto se iba marcha atrás. → La reversa **no entra con el freno de mano puesto** (ya está en el kit). Probalo: `start_hold_test` en el juego original.
- **B2. Control de tracción que "mata" el trompo**: cortaba al 20 % cuando el auto iba de costado y no se podía recuperar. → `tc_free_spin = true`: el TC se suelta en trompo, marcha atrás o en el aire.
- **B3. NaN**: un solo valor NaN rompe todo el mundo (sale volando para siempre). → El `step()` verifica `is_finite` y hace `reset()` a la última posición buena. **No lo saques.**
- **B4. Física dependiente de los FPS**: simulá SIEMPRE a 120 Hz fijos con acumulador y tope (`acc = min(acc + dt, 0.05)`). Sin el tope, un tirón del teléfono dispara 30 pasos juntos y la física se "adelanta" (la espiral de la muerte).
- **B5. El auto "salta" en el dibujo**: dibujá desde el historial interpolado (`render_t` atrasado), no desde el último estado.
- **B6. Volante que se trababa antes que la dirección**: el dibujo del volante llegaba a ±540° y la dirección ya estaba al máximo a ±180°. → El volante **se traba donde la dirección llega al tope** (`wheel_lock()` por modo).
- **B7. Dirección muy sensible a alta velocidad**: `steer_scale` reduce el ángulo con la velocidad (piso 12 %); no la saques sin una alternativa.
- **B8. Ground_info caro**: se llama ≈ 960 veces/s por auto (4 ruedas × 240 Hz): sin allocs, sin búsquedas lineales.

## C. Audio (ver doc 04)

- **C1. «Viento fuerte que se repite»**: los ruidos de fondo (rodado, tierra, lluvia) eran bucles de **2 s exactos** y sonaban **tan fuertes como el motor**. → bucles largos (12–24 s), 11–16 dB más bajos, y medidos con instrumentos (`audio_render.gd` + `analyze_audio.py`) en vez de "de oído".
- **C2. «Silbido que se queda»**: el turbo era un **seno de 8 kHz** fijo; la caja llegaba a 4,2 kHz. → topes (turbo 3,3 kHz, caja 2,4 kHz), el silbido sólo suena **mientras la carga se mueve**, y los tonos que se quedan quietos (> 2,5 s) bajan al 30 % (`_steady_gain`).
- **C3. Motor "robótico"**: un único ciclo repetido idéntico. → 7 capas con y sin carga, cruzadas por el pedal, pulsos con fluctuación aleatoria y fallas de encendido.
- **C4. El motor sonando parado**: un ralentí constante cansa. → sólo suena con el pedal o en movimiento (`alive`).
- **C5. Clics por asignar volúmenes de golpe**: todo pasa por `TIME_K` (constantes de tiempo).
- **C6. Acumular voces**: pooles fijos para disparos; si no hay libre, se descarta.

## D. Rendimiento en el teléfono (GPU y CPU)

- **D1. Medí antes de optimizar**: botón de diagnóstico con A–B–B–A: apagá una cosa por vez (árboles, edificios, tránsito, vegetación) y compará FPS en el mismo punto. La mitad de las "mejoras" no cambian nada.
- **D2. GPU vs CPU**: bajá la escala 3D de 1,0 a 0,5; si los FPS suben ~proporcional, es GPU. Si no, es CPU.
- **D3. Dibujá con `MultiMesh`**: tránsito, peatones, estacionados, semáforos, **marcas de frenada** (3000 tiras en una llamada de dibujo). Un nodo por objeto no escala.
- **D4. Árboles**: imágenes (8 vistas / cruz) en una **textura de capas**, un `MultiMesh` por cuadra y por nivel de detalle; cerca = 8 vistas, medio = cruz, lejos = anillos del horizonte. Fachadas lejanas lisas, autos civiles de ~186 triángulos con normales planas.
- **D5. Sin luces dinámicas** en el mundo; sombras sólo del sol y del auto del jugador; MSAA apagado.
- **D6. Presupuesto de CPU con estrangulamiento**: cada cuadro se mide cuánto cuestan los sistemas de «vida del mundo» (tránsito 0,2 ms, peatones 0,15 ms en PC; ×3–6 en el teléfono). Si pasan el tope del perfil (1,6 / 2,6 / 4,0 ms) durante 2 s, se **baja un escalón** (menos peatones, tránsito más corto) sin rehacer los `MultiMesh` (`_shown_cap`). Lo vas a querer.
- **D7. Armar el mundo en un hilo, NO en el principal**: construir cuadras de ciudad en el principal daba tirones de 40–80 ms (p99). Pasaron a **un** hilo (`WorkerThreadPool`) que calcula sólo **datos** (arreglos de triángulos, listas) y el principal los vuelca en nodos; el hilo **nunca** toca nodos ni recursos de dibujo. p99 de cuadro: 33,7 ms. Válvula de escape: `threaded = false`.
  - Una sola cuenta de hilo a la vez; el principal espera al hilo antes de armar por su cuenta. **Sin `Mutex`** (si un error cortara el hilo, el mutex queda tomado para siempre).
  - Lo que se llena a demanda se carga **antes** en el principal.
- **D8. Carga**: `ResourceLoader.load_threaded_request` para modelos pesados, y pantalla de carga que **tapa** el precalentado de shaders y partículas.
- **D9. Memoria**: no cargues archivos enormes enteros al abrir el menú (un `.glb` de animaciones de 3 MB leía todo: ahora sólo el índice y cada animación a demanda).
- **D10. Transparencias**: pocas capas translúcidas grandes. Las partículas (humo, polvo) tienen *distance fade* para no tapar la pantalla pegadas a la cámara. Vidrios oscuros con reflejo falso en vez de transparencia.
- **D11. Texturas**: comprimidas (ETC2/ASTC) en el export; PNG de HUD chicos (< 100 KB cada uno).
- **D12. Paquetes grandes**: Play Store limita el módulo base; los autos (~600 MB) van en `assetPackInstallTime`. Plan para tu juego: separar contenido pesado en `.pck` descargable.

## E. Proceso (lo que más ahorra tiempo)

1. **Pruebas headless por sistema** (`godot --headless --script res://tests/xxx.gd`) que terminan con código 0/1 y se corren en cada cambio. Las del kit: `--autotest` de la demo, `audio_render` + `analyze_audio`.
2. **Medir con instrumentos, no de oído ni de vista**: audio (RMS, tonos que duran, repetición), física (comparar contra una referencia), FPS (con diagnóstico).
3. **No digas "arreglado" sin evidencia**: reproducí, cambiá, y volvé a medir. Si no pudiste probar en un teléfono, decilo.
4. **Registro de cada cambio**: síntoma → causa → cambio → pruebas → siguiente paso.
5. **Un experimento por vez** y volver atrás es barato (flags: `Release.X`, `FrameRes.set_enabled`, `threaded`).
6. **Lo que no se pudo confirmar se marca "causa NO confirmada"** y se deja un registro (lápida) para la próxima vez.

## F. Checklist antes de publicar

- [ ] Todos los bucles de audio con `WavLoop` y `WavLoop.safe()` en una prueba.
- [ ] Ningún hilo escribe en estructuras compartidas ni toca nodos.
- [ ] La física no puede dar NaN (corré 10 min con entradas aleatorias; `is_finite` en todo).
- [ ] `ground_info` sin allocs; 4 ruedas × 240 Hz no pasan de 1 ms en el teléfono más lento que soportás.
- [ ] Marcas de frenada: 1 `MultiMesh`, anillo de 3000, se borran con `reset()`.
- [ ] La escala 3D, sombras y partículas son opciones **manuales** y se guardan.
- [ ] Probado en un teléfono real de gama baja con «Mostrar FPS»; registrado el resultado.
- [ ] `--autotest` en verde y captura con marcas de frenada visibles (`xvfb-run … --shot=…`).
