# 08 · Personajes: piloto, copiloto y peatones

## Lo primero: qué NO existe

**Dream Racing no tiene física de personaje caminando** (ni `CharacterBody3D`, ni ragdoll, ni colisión de personas con el auto). No es una omisión: es una decisión de rendimiento y de tono. Lo que hay son dos sistemas muy distintos:

1. **Piloto y copiloto dentro del auto**: figuras 3D riggeadas que se mueven con **resortes alimentados por las fuerzas G reales del auto** + cinemática inversa (IK) de manos y pies.
2. **Peatones de la ciudad**: **tarjetas de papel 2.5D** (billboards) dibujadas por un shader, deterministas, sin física; si el auto los toca "se acuestan" un rato (sin sangre) y se levantan.

Si tu juego nuevo necesita personajes que caminan con física real (CharacterBody3D, ragdoll), eso hay que **construirlo aparte**; este kit no lo resuelve. La receta recomendada es la del peatón de papel (barato) o un `CharacterBody3D` simple *sólo para pocos personajes cercanos*.

## 1. Tripulación (piloto y copiloto) — `car/crew_motion.gd` (+ `referencia_no_ejecutable/rig_pilot.gd`)

`CrewMotion` es **lógica pura** (no dibuja): cada cuadro, `step_forces(dt, snap)` mueve dos resortes encadenados con la aceleración del auto, `step_limbs`, `step_gear`, `step_grip` y las funciones de IK devuelven posiciones de manos/pies. Quien dibuja (`rig_pilot.gd`, ref.) aplica esos números a un esqueleto.

### Fuerzas G (el corazón)
- `kT = 40, cT = 8.5`: resorte/amortiguador del **torso** (firme: lo sostiene el arnés). `kH = 95, cH = 5.2`: de la **cabeza** respecto del torso (suelta).
- Entradas: `aLong`, `aLat`, `yawRate`, `vLong` y `bump` (sacudón por baches y golpes, 0..1) del snapshot.
- Límites de desplazamiento: `lim_t = 0,17 m` (torso), `lim_r = 0,11 m` (cabeza); la cabeza **se pasa y vuelve** (overshoot) como en la vida real. `gain` escala todo (accesibilidad: bajalo para no marear).
- `cam` / `cam_s`: cuánto se mueve la **cámara del casco** (menos que la cabeza visible: no marea; `cam_s` suavizado para que no salte entre cuadros).
- `kick` (patada de aceleración) y `side_sign` (hacia qué lado empuja una curva según el asiento).

### Manos y pies
- **Mano sobre mano en el volante**: cada mano agarra un punto del aro (`GRIP_R = 0,1706` m); al girar mucho se acaba el brazo, suelta y vuelve a agarrar (`step_grip`).
- Mano a la **palanca** en cada cambio (`shift_w`), mano al **freno de mano** al tirarlo.
- **Pie derecho** en acelerador/freno (`right_foot`: `press` y `onBrake`).
- **Copiloto**: se ataja con la mano al tablero en una frenada fuerte (`brace_*`), a la puerta/jaula en curvas fuertes (`brace_door`, `brace_mid`) y mira con movimientos chicos (`co_look`).

Todo corre en el hilo principal y **sólo cuando la cámara es interior** (desde afuera los pilotos no existen: ahorra animación y mallas).

Interfaz mínima:
```gdscript
var crew := CrewMotion.new()
crew.step_forces(dt, snap)
crew.step_limbs(dt, snap)
crew.step_gear(dt, snap.gear)
crew.step_grip(dt, controls.wheel_visual, busy)   # busy = manos ocupadas
# crew.body / crew.head / crew.cam_s → los aplicás a tu esqueleto/cámara
```

## 2. Peatones de papel — `referencia_no_ejecutable/ambient_peds.gd` + `city_peds.gdshader` + `PEATONES.md`

**No se ejecutan en el kit** (dependen de la ciudad: `layout`, `graph`, `WorldSeed`…). Se explican acá para que se puedan reimplementar:

- **Una sola llamada de dibujo**: un `MultiMeshInstance3D` con una instancia por peatón; cada instancia es una **tarjeta** (quad 0,9 × 1,75 m) que siempre mira a la cámara (gira sólo en Y) y **toda la figura se pinta en el shader** (cabeza, torso, brazos, piernas que se balancean al caminar, contorno, mochila/gorro/paraguas). **Cero texturas.**
- **Deterministas y sin estado**: cada tramo de vereda (26 m = `SLOT`) tiene a lo sumo un peatón que va y viene entre dos puntos; color, velocidad y fase salen de una **semilla** (`WORLD_SEED` + calle + tramo) y su posición es una función de la hora. Eso significa: no se guardan, no se sincronizan, y **todos los teléfonos ven a la misma gente** a la misma hora.
- **Rutina**: poca gente de madrugada, más a la mañana/mediodía/tarde; con lluvia casi nadie (los que hay llevan paraguas); fines de semana más paseos.
- **Presupuesto**: tope por perfil de calidad (**16 / 32 / 56** peatones), no se dibujan a más de **120 m**, aparecen/desaparecen creciendo (`_fade`), y el sistema se **estrangula** si el CPU del "mundo vivo" pasa el tope (1,6 / 2,6 / 4,0 ms; ver doc 10).
- **Con el auto**: si te acercás rápido se hacen un paso atrás (`_scare`); si los tocás, quedan acostados unos segundos (`_hit`) y se levantan. Es sólo local: no se comparte.
- Se apagan con la opción «Vida del mundo = NO».

**Cuándo conviene copiar esta idea**: mundos abiertos con muchos NPC que NO interactúan físicamente. Costo medido: ~0,15 ms/cuadro en PC (en un teléfono rinde varias veces más lento: por eso el presupuesto).

## 3. Si querés personajes con física de verdad (guía mínima)

1. Pocos (≤ 3–5) y **sólo cerca de la cámara**; el resto, tarjetas de papel.
2. `CharacterBody3D` con `move_and_slide` en el **hilo principal**; el auto no los empuja con la física propia: resolvé el choque con un chequeo círculo–círculo contra la posición del auto (como hace `Car._keep_out()` con las paredes) y aplicá un impulso al personaje.
3. Para "atropello" sin violencia: cambiá a una animación de caída, desactivá colisión unos segundos y volvé a levantarlo (lo que hace el peatón de papel).
4. Nunca hagas `move_and_slide` de un personaje desde el hilo de física del auto (ver doc 10, §Hilos).
