# Estado de SimCars Extreme

## Hecho (probado en la PC, sin GPU de teléfono)
- **6 autos reales, tal cual el original** (sin reducir triángulos ni texturas, con su interior): CLS 63 AMG, Aventador S, McLaren F1, McLaren F1 GTR, Ranger Limited, RX-3 Savanna.
  - Ruedas: las que faltaban se copiaron y las del lado opuesto se giraron 180° (no se espejan: la cara de afuera queda afuera). El eje trasero del CLS y de la Ranger se ubicó **midiendo el pasaruedas** de la carrocería (el CLS tenía la rueda 15 cm adelantada).
  - Aventador: la puerta izquierda venía corrida 57 cm hacia adelante (se ubicó midiendo el hueco); la derecha venía abierta y torcida: ahora es el espejo exacto de la izquierda.
  - Los autos ya no flotan: el modelo se dibujaba con su piso a la altura del centro de gravedad.
  - Piezas que se dañan y se caen (puertas, capó, baúl, paragolpes, parabrisas, patente), abolladuras en las piezas, pintura (9 colores).
- **Pilotos**: Aiden, Kate y Mujer adulta, completos (con las 122 formas de la cara para el modo historia, texturas originales). Se elige uno en el menú. Manos en el volante (mano sobre mano), mano a la palanca en cada cambio, pie en el pedal, cuerpo y cabeza con las fuerzas G.
- **Estacionamiento de pruebas**: lomadas pintadas, chapa de serrucho, rampa, cordón, rampa diagonal, peralte de drift, tierra con piedras y montículos, autos estacionados, postes que se rompen, conos que vuelan (Jolt), pirámide de conos, slalom, barreras, neumáticos, canteros con árboles, pasto y flores que se mecen, muros (no se puede salir) y edificios de cartón de fondo. Texturas y sprites hechos en Blender.
- **Ajustes**: resolución de pantalla (nativa, 1440p … 360p: baja TODO el cuadro, la interfaz no cambia de tamaño), resolución 3D (25 % … 100 %), MSAA, FPS (30 … sin tope), VSync, distancia de dibujo (80 … 650 m), distancia de detalle, sombras y su distancia, partículas sí/no y cantidad, piloto visible desde afuera, auto ORIGINAL/LIVIANO, autos estacionados, pasto, árboles, edificios, conos.
- **Cámaras** (botón de cámara o tecla C): **primera persona (casco)** · **tercera persona interior (butacas)**: atrás y arriba de los dos asientos, se ven el piloto, las butacas y el tablero (en los biplaza se arrima a la mampara del motor) · **seguimiento** (media, cerca/alta, lejos/baja, aérea: todo el auto) · **cámara libre**: se arrastra para girar alrededor del auto, se pellizca o se usan ＋/－ para acercar y alejar (en la PC: mouse y rueda) · capó · paragolpes. Botón ⚙ CÁMARA: altura, distancia, lateral y ángulo de cada una (se guardan).
- **Vidrios polarizados**: oscuros desde afuera, claros desde adentro (con las cámaras de la cabina se ve clarito hacia adelante y a los costados).
- **Diagnóstico de rendimiento** (pausa → RENDIMIENTO): mide cuánto cuesta cada sistema en el teléfono apagándolo de a uno, lista los materiales más pesados y se copia con un botón.
- **HUD liviano**: el volante y los pedales se redibujan sólo cuando cambian; los textos 4 veces por segundo y sólo si cambian.
- **APK liviano firmado** con llave fija (`godot/keystore/simcars.keystore`): las actualizaciones se instalan encima sin perder el progreso. El juego (`content.pck`) y los autos y pilotos (`cars.pck`) se bajan solos al abrir.

## Para probar en el teléfono
1. Instalar `SimCars-Extreme.apk` (release `simcars-apk`). La primera vez baja ~250 MB.
2. Elegir auto (GARAJE), piloto (PILOTO) y JUGAR.
3. Si va lento: pausa → RENDIMIENTO → MEDIR AHORA → COPIAR INFORME y pegármelo.

## Pendiente / a revisar con el dueño
- Nada probado todavía en un teléfono real (FPS, tacto, sonido).
- Los autos originales son pesados (la Ranger tiene 870 mil triángulos): el informe de rendimiento dirá cuánto bajar y en qué auto.
- El Aventador no trae vidrios laterales en el modelo (la ventanilla se ve abierta).
- Segundo ocupante (copiloto): la estructura del IK ya lo soporta; falta sumarlo.

## Segunda tanda (23/11/2026, a partir de las pruebas del dueño en el teléfono)
- **Menú**: el auto ya no se hunde en la plataforma (las ruedas arrancaban a la altura del piso: también era lo que dejaba las ruedas hundidas en los autos estacionados). Flechas ◀ ▶ dentro del panel del garaje y del piloto. Ajustes en 3 pestañas con barra grande y botones ▲▼ para bajar. JUGAR → elegir mapa.
- **Autos estacionados**: versión liviana mucho más fiel (30 mil triángulos y texturas de 512 px en vez de 7 mil y 256).
- **Piloto**: cadera, pies y pedales ubicados midiendo el modelo (CLS) o por geometría (resto); estatura por defecto 1,86 m; cuero cabelludo del degradé más oscuro.
- **Cámara libre**: el ángulo es del MUNDO: ni el volante ni el pedal la mueven. Sólo se mueve con arrastrar, pellizcar o ＋/－.
- **Niveles de simulación** (de Dream Rally): ARCADE · MEDIO · PRO · AVANZADO · PERSONALIZADO (ABS, control de tracción, estabilidad, ayuda de trazada, giro del volante ¾ / 1½ / 3 vueltas, caja manual).
- **Reglaje del auto** (pausa → REGLAJE DEL AUTO): presiones, alineación, suspensión, frenos, transmisión, aerodinámica, grip. Se guarda por auto.
- **Camino de tierra**: circuito cerrado de ~1,3 km sin rivales, cerco de madera a cada lado (una cara, con colisión), bosque denso de árboles de 10 colores, charcos de barro, lomos y ondas, carteles de curva, arco de salida. Ayuda de trazada sobre el eje del camino.
- **Agarre en tierra por auto** (relativo al asfalto, razonado con el tipo de goma y tracción; no medido): Ranger 0,84 · RX-3 0,62 · CLS 0,58 · Aventador 0,52 · F1 0,50 · F1 GTR 0,42.

## Tercera tanda (23/11/2026): marioneta de Blender y pista de tierra realista
- **Marioneta (Marionette equivalente, hecha con bpy)**: el addon Animatica Marionette es pago y sólo de interfaz, no se puede usar por script; se armó un equivalente: `tools/blender/puppet_fit.py` carga cada piloto con IK de brazos y piernas, y para cada auto busca estatura, posición de cadera, inclinación del torso y apoyo de las piernas leyendo las MARCAS de la cabina (asiento, pedales, volante, palanca) de `godot/game/data/cabin_markers.json`. Resultado: `cabin_fit.json` (+ capturas de control en `docs/puppet/`). El juego lo aplica solo (`Cockpit`) y el IK sigue animando manos y pies en vivo.
- **Marcas**: pausa → MARCAR CABINA (sliders; COPIAR MARCAS). Se copia el JSON y se vuelve a correr el solver: `python tools/blender/puppet_fit.py -- --chars godot/game/models/characters --markers godot/game/data/cabin_markers.json --out godot/game/data/cabin_fit.json --renders docs/puppet`.
- **Honestidad**: 15 de las 18 combinaciones auto×piloto quedan con error de manos/pies < 9 cm y sin atravesar el asiento. Las 3 que no (Aiden en McLaren F1, Aiden y Mujer en F1 GTR) tienen las marcas del volante/pedales demasiado lejos para su estatura: se marcan `"ok": false` y el juego usa el ajuste de siempre. Se arreglan marcando mejor esos autos.
- **Camino de tierra realista**: relieve con ondulaciones, huellas de rodada y banquina/zanja, pozos con agujero real en el shader, charcos, polvo y tierra que salta según la velocidad, pasto que se aparta al pasar el auto, árboles y arbustos que se mecen, huellas de neumáticos que quedan marcadas.
- Nada probado todavía en un teléfono real.

## Cuarta tanda (23/11/2026): circuito de asfalto
- **Mapa nuevo «CIRCUITO DE ASFALTO»** (JUGAR → mapa): ~1,5 km cerrado, pista de 13 m con bombeo, recta de largada con pórtico y línea a cuadros, horquilla, S y curva rápida, subidas suaves (máx. ~3 %). Curbs rojos y blancos, línea blanca de borde, zona de escape de grava (agarre de banquina) y pasto, barrera a franjas rojo/blanco que el auto no cruza, pilas de neumáticos en el lado de afuera de las curvas, carteles de curva, dos tribunas con gente de colores, edificio de boxes y bosque de fondo.
- Reutiliza el motor del camino de tierra: `asphalt_track.gd` hereda de `dirt_track.gd` (se le agregaron ganchos `_ctrl/_elev/_setup/road_half/fence_half/profile`) y `asphalt_world.gd` de `dirt_world.gd`. Ayuda de trazada, «volver a la pista» y GPS de la largada funcionan igual.
- Las marcas de patinada en asfalto son las de siempre (oscuras al patinar). Nada probado en un teléfono.

## Quinta tanda (23/11/2026): rendimiento en tierra y asfalto (informes del Z2356)
**Diagnóstico** (de los informes y de contar lo que arma cada mapa con `godot/tests/world_count.gd`): el estacionamiento tiene ~100 árboles; el camino de tierra tenía ~5.700 instancias de vegetación (2.200 árboles, 2.400 matas). Los árboles son pocos triángulos (4 cada uno): el costo es **relleno de píxeles** («Árboles −5 a −11 ms» con apenas −10 dibujos). Causas:
1. El shader del follaje (`sway.gdshader`) tenía `depth_prepass_alpha`: dibujaba **todo el follaje dos veces**. Sacado.
2. Bosque de relleno hasta 160 m del camino, escondido detrás de las dos hileras de adelante (se dibujaba igual). Ahora sólo hasta ~50 m.
3. Se dibujaba **todo el circuito** a la vez (el otro lado de la vuelta, 100–200 m en línea recta pero 800 m por la pista). Ahora hay una **ventana por tramo**: sólo se dibuja la vegetación (shader, `track_window`) y los cercos/barreras (pedazos de ~100 m) del tramo de circuito cerca del auto: 190–340 m adelante (según la velocidad) y 90 m atrás. Lo de más allá de una curva aparece al acercarse.
4. Piloto (−4,5 a −7 ms en los informes): 121 formas de cara en el cuerpo, pelo de 17 mil triángulos con mezcla + prepass, dientes, lengua y ojos procesados aunque la cabeza esté escondida. Ahora (`RigPilot._lighten`): sin formas de cara en el juego (el GLB las conserva), pelo/pestañas recortados en vez de mezclados, y pelo/ojos/dientes/lengua/cejas **apagados** en primera persona.
- También: ya no se llama a `global_shader_parameter_get_list` (tiraba un error por cada mundo armado).
- **Sin medir en el teléfono** (acá no hay GPU móvil): los números de ms de arriba son los de los informes, no una mejora comprobada. Pendiente pedirle un informe nuevo.
- Sin resolver todavía: el auto del jugador (−7 a −8 ms: 169 dibujos, 74 mil triángulos) es lo más caro que queda; la pista misma de asfalto/tierra se sigue viendo completa a lo lejos.

## Sexta tanda (23/11/2026): bosque nativo, camino hundido y optimizaciones sin cambio visual
- **Bosque nativo verde** (tierra y asfalto): ya no hay árboles de colores. Una sola hilera de árboles bajos (4,5–6,5 m, 5 verdes distintos + cipreses y álamos chicos) pegada al cerco y detrás una **pared de bosque opaca en dos capas** (png de 40×11 m y 40×8 m hechos en Blender, repetibles, sólo se recorta la silueta de arriba) que sigue el circuito a 15–34 m: se acerca donde hay otro tramo cerca y del lado de adentro de las curvas cerradas. Bandas png de pasto y de matorral al pie del cerco (`pasto_banda`, `matorral_banda`) y pasto suelto sólo en una hilera. Instancias de vegetación: tierra 5.700 → 1.500, asfalto 3.100 → 1.500. Las paredes y cercos se ocultan por tramos con la ventana del circuito.
- **Camino de tierra hundido** (referencias del dueño): tierra roja de grano fino con piedritas y pajas (`tierra_roja.png`), huellas de rueda más hondas, **taludes de tierra a los dos lados** (0,3 a 1,45 m, cambian a lo largo del camino; el auto puede subirse) y el **cerco arriba, en la meseta** (a 8,8 m del eje). Charcos rojizos. La física sigue la misma superficie (`DirtTrack.profile_at`).
- **Autos**: las mallas fijas y opacas se unen por material (`CarVisual._merge_static`: de 175 a 158 dibujos en el CLS, de 138 a 111 en el RX-3; captura idéntica con y sin unión) y el motor / piso / escape del CLS y el piso del RX-3 se esconden hasta que el capó se abre o cae, o el auto va muy inclinado. El F1, el Aventador y la Ranger casi no ganan: casi todo es de piezas móviles, ruedas y transparencias.
- Pruebas de ayuda nuevas: `tests/world_count.gd`, `tests/car_merge_test.gd`, `tests/car_tree.gd`, `tests/lot_breakdown.gd` y la opción `--arc=<m>` de `play.gd` para largar en cualquier punto del circuito.
- **Estacionamiento**: lo que más pesa son los 9 autos estacionados (394 mil triángulos, ~140 dibujos cada uno); ganan lo de la unión de mallas. Sin medir en el teléfono.

## Séptima tanda (23/11/2026): volante que gira, tierra pura, sin piedras 3D
- **Volante (pedido 3 veces)**: la causa era que Godot le saca el sufijo «_wheel» a los nodos al importar y el volante llegaba como `steer`, pero el código buscaba `steer_wheel`: **no giraba en ningún auto**. Ahora se busca `steer`. El Aventador y el McLaren F1 no traen el volante como pieza (viene pegado al interior): se separa por geometría al cargar (`CarVisual._extract_steer`; en el F1 el centro del JSON estaba a ~15 cm del volante real y se recalcula con los materiales «steer»). Comprobado con capturas con el volante a fondo (`--steer=1.0 --cam=0`): el aro gira junto con las manos en Ranger, Aventador y F1. También: en primera persona se esconde el cuello (en el Aventador un globo de piel tapaba toda la pantalla).
- **Camino de tierra**: sin piedras 3D; textura nueva de **tierra pura** (`tierra_roja.png`, sin piedritas ni pajas, ruido periódico sin costuras, hecha en `tex_tierra_pura`).
- **Circuito urbano** (nuevo mapa en JUGAR → mapa): el mismo trazado de asfalto pero con una pared de edificios en png (dos capas, opacas, hechas en `city_band` de `tools/blender/make_textures.py`: fachadas con ventanas, comercios y toldos, azoteas), suelo de concreto y postes de luz cada 36 m. El circuito rural sigue con la pared de bosque.
- **Edificios del circuito urbano, rehechos al estilo Dream City** (el png se veía falso): cajas de ~10 triángulos (frente, costados y techo) y el shader `city_facade.gdshader` copiado de Dream Rally, que dibuja ventanas, postigos, balcones, vidrieras y marquesinas por medidas de pared y las funde en pared lisa a lo lejos. Dos filas (baja pegada y alta detrás) a lo largo del circuito, sin pisar otros tramos, partidas en pedazos que se ocultan con la ventana del circuito. Los png de ciudad se sacaron.
- **Pausa con desplazamiento** (no dejaba bajar hasta los últimos botones): el menú está dentro de un `ScrollContainer`, se arrastra con el dedo.
- **Volante completo y bien agarrado**: al separarlo por geometría (Aventador, F1) se suman las caras pegadas a las elegidas para que no quede ningún pedazo atrás, y las manos agarran el volante que de verdad se ve (su centro de giro y su radio real, no los del JSON).

## Octava tanda (24/11/2026): reporte del teléfono
- **Árboles de más en las curvas**: ventana del circuito más corta (adelante 120–210 m según la velocidad, atrás 60 m) y paredes de bosque más bajas (7,5 y 5,5 m: antes 11 y 8 m asomaban por encima de los árboles cercanos).
- **Saltos en el camino de tierra**: las lomas del eje bajaron a ~60 % (pendientes del 12–24 % en tramos cortos) y los lomos, ondas y baches se achicaron a la mitad (`tests/ground_roughness.gd` mide el piso). El asfalto no tenía saltos (máx. 3 % de pendiente).
- **Volante al revés**: sólo la animación; ahora el aro y las manos giran al lado correcto.
- **Interior deformado**: las abolladuras ya no tocan interior, cockpit, asientos, tablero ni volante.
- **Pantalla nueva antes de manejar**: tras elegir el mapa pregunta **ARCADE** o **SIMULACIÓN** (aplica los niveles `arcade` / `pro` de Ajustes; se retoca después).
- Pendiente (sin cambiar a ciegas): manos que agarran mal el volante y piernas que atraviesan el asiento en algunos autos: hace falta ver capturas por auto (MARCAR CABINA ya permite corregirlo).
