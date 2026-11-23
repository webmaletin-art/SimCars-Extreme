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
