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
