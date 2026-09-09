# Bitácora — tokenbar

Entrada nueva SIEMPRE al inicio. Plantilla:

```
## AAAA-MM-DD — <título en una línea>
**Qué**: <cambio concreto>
**Por qué**: <el problema que resuelve>
**Cómo verificar**: <comando o pasos>
**Docs**: <docs actualizados, o "ninguno">
**Pendiente**: <lo que quedó fuera, o "nada">
```

## 2026-09-09 — el consumo de la sesión salía negro en la barra

**Qué**: `Paleta.sinDato` (azul, `0.45 / 0.66 / 0.90`) reemplaza al `.secondary`
que llevaba la línea sin porcentaje, tanto en la barra como en el panel.

**Por qué**: "el color de la sesión de 5 hrs está en negro así que no se ve
bien". El label de la barra se dibuja a imagen con `isTemplate = false`, y el
renderizador resuelve los colores del sistema en modo claro: `.secondary` sale
gris oscuro y **desaparece** contra una barra de menús oscura. Se renderizaron
siete candidatos sobre negro y sobre blanco; el azul es el único que se lee bien
en los dos y además queda fuera de la escala verde→rojo, así que no se confunde
con un nivel de límite (el naranjo acento sí se confundía con `Paleta.alto`).

**Cómo verificar**: dibujar `EtiquetaBarra.imagen(co.lineasBarra(prefs), …)`
sobre fondo negro y blanco. Las dos líneas tienen que leerse en ambos.

**Docs**: `CLAUDE.md`.

**Pendiente**: nada.

## 2026-09-09 — la sesión muestra los tokens del bloque, no un guion

**Qué**: la tabla `actividad` gana la columna `tokens` y la ventana de sesión
muestra, cuando no hay porcentaje, **los tokens que pasaron por Claude Code
dentro del bloque de 5 h en curso** (`17,7 M ~4:31` en la barra, `17,7 M en
~4:31` en el panel). Migración `user_version=2`: la tabla se rehace vacía y
`Escaner.reconstruirActividad` la vuelve a llenar leyendo todos los transcripts
con el dedup DENTRO de la pasada —contra `vistos` no sumaría ni un token—. El
escaneo normal sigue apoyándose en `vistos`, que es lo correcto: ahí las líneas
nuevas son mensajes nuevos.

**Por qué**: el guion de la entrada anterior era honesto pero inútil ("pero ahora
no me sale nada de consumo en la sesión"). Antes de esto se probó estimar el
porcentaje calibrando tokens↔% con las dos lecturas reales que quedaban en la
tabla `suscripcion`: dieron **4.717.298 y 227.688 tokens por punto de %**, 20× de
diferencia. La razón está a la vista en la segunda muestra: el bloque abrió a las
10:10 y el primer mensaje de Claude Code fue a las 10:43, o sea que buena parte
de ese 3 % se gastó fuera. Un porcentaje inventado sobre esa base es peor que no
darlo; los tokens del bloque, en cambio, son un número medido.

**Cómo verificar**:
```bash
sqlite3 "$HOME/Library/Application Support/TokenBar/tokenbar.sqlite" \
  "PRAGMA user_version; SELECT count(*), sum(tokens) FROM actividad;"
```
Debe decir 2, y la suma tiene que cuadrar con el total deduplicado de los
transcripts que siguen en disco (9.705.835.234 al momento del cambio — menos que
los 10.822.037.697 de `uso`, que arrastra transcripts que Claude ya borró).
El consumo del bloque se contrastó a mano: 18,3 M en 149 mensajes desde las
09:32:29, contra los 17,7 M que dibujó el panel un minuto antes.

**Docs**: `CLAUDE.md`, `~/Desktop/TYD/proyectos/tokenbar.md`.

**Pendiente**: el consumo solo cuenta lo que pasó por Claude Code; la ventana es
de la cuenta completa. La barra de progreso de esa fila queda vacía a propósito:
no hay fracción conocida que pintar.

## 2026-09-09 — el contador de sesión se quedó pegado: Claude dejó de refrescar su medidor

**Qué**: el reloj de la ventana de 5 h ya no depende de que Claude Code
refresque su dato. Cambios:

1. **`Bloques.swift`** (nuevo): encadena ventanas de 5 h desde el último
   `resets_at` que Claude sí confirmó, usando la actividad local, y devuelve la
   que sigue abierta.
2. **Tabla `actividad`** (`segundo INTEGER PRIMARY KEY`): un instante por cada
   respuesta de la API, sacado del `timestamp` de las líneas con `message.usage`.
   El instante se anota ANTES del dedup —una respuesta reescrita por un
   `--resume` no vuelve a sumar tokens, pero sí marcó actividad de la API—.
   Migración `user_version=1`: borra `archivos` para forzar UNA relectura
   completa que llene la tabla hacia atrás. No duplica nada: se verificó que las
   76.668 líneas con `usage` del corpus traen `message.id`, o sea que el dedup
   por `vistos` las cubre a todas.
3. **`Ventana.porcentaje` pasa a `Double?`** y aparece `Ventana.estimada`.
   Cuando la ventana que trae Claude ya venció, `Coordinador.conSesionVigente`
   la reemplaza por el bloque vigente con el porcentaje en desconocido: el
   consumo de la ventana nueva no lo sabe nadie fuera de la API, y mostrar el de
   la anterior era mentir con cara de dato fresco.
4. **UI**: «—» donde no se sabe el porcentaje (y sin barra de progreso, que a
   cero se leería como «no has gastado»), gris en vez de semáforo, «~» delante
   del reloj estimado, y un cartel de aviso en el panel cuando el medidor de
   Claude quedó atrás (`EstadoSuscripcion.rezagada`).
5. **`Escaner.instante`**: parser de timestamps a mano (`days_from_civil`),
   porque `ISO8601DateFormatter` se paga 78.000 veces en cada relectura completa.

**Por qué**: la queja fue "el contador de uso de claude sigue pegado… mira las
horas de la sesión". No era la barra ni los timers: era el dato.
`~/.claude.json` → `cachedUsageUtilization.fetchedAtMs` llevaba **22,7 h**
congelado (2026-09-08 10:50) aunque Claude Code reescribía el archivo cada pocos
minutos. Su `five_hour.resets_at` (2026-09-08T18:10Z) había pasado hacía 18 h y
`Formato.reloj` lo topa en `0:00`. Se descartó que hubiera otra fuente: ni el
resto de `~/.claude/`, ni las demás claves `cache*` del JSON, ni los transcripts
(no traen cabeceras de rate limit).

**Cómo verificar**:
```bash
swift build -c release
# el bloque estimado contra los datos de verdad:
mkdir -p /tmp/p && cp <este main.swift de prueba> /tmp/p/
```
Al momento del arreglo: ancla 09-08 15:10 → bloque abierto 09-09 09:32:29 →
14:32:29, y el parser coincidió con `ISO8601DateFormatter` en 4.000 timestamps
reales.

**Docs**: `CLAUDE.md` (arquitectura, fuentes de datos y gotchas),
`~/Desktop/TYD/proyectos/tokenbar.md`.

**Pendiente**:
- El porcentaje de la ventana estimada queda en desconocido. Se podría aprender
  la razón tokens↔% con los pares que ya guarda la tabla `suscripcion` cuando
  Claude sí reporta, pero hoy hay 2 muestras: muy poco para ajustar nada.
- La ventana de 5 h es de la **cuenta completa**: se comprobó que los inicios de
  bloque que reportó Claude (09-07 22:29:59 y 09-08 10:10:00 local) no tienen
  ninguna línea en los transcripts, o sea que claude.ai, la app de escritorio o
  el móvil también la abren. La estimación puede empezar más tarde que la real
  —nunca antes—, así que el tiempo que muestra es un techo.
- La ventana semanal también queda desactualizada mientras Claude no refresque,
  pero como sigue abierta se muestra tal cual; el cartel de aviso es lo que
  advierte que se quedó corta.

## 2026-09-08 — la barra se quedaba pegada: App Nap, timers y render del label

**Qué**: cuatro arreglos sobre la misma queja ("se buguea la barra y se queda
pegada de vez en cuando"):

1. **App Nap**: siendo `LSUIElement`, macOS suspendía el proceso y estiraba los
   timers varios minutos. Se sostiene con `ProcessInfo.beginActivity`
   (`userInitiatedAllowingIdleSystemSleep`), token guardado en el coordinador.
2. **Timers en modo `.common`**: con `scheduledTimer` se detenían mientras
   hubiera un menú abierto o un arrastre en curso.
3. **Latido propio del reloj** (`ahora`, cada 10 s), separado del escaneo: aunque
   un refresco se demore, la hora de la barra sigue avanzando.
4. **Cache del label**: `ImageRenderer` devuelve `nil` al despertar el equipo o
   cambiar de pantalla (`NSScreen.main` en nil) y se dibujaba una imagen vacía;
   ahora se reusa la última buena.

Además, el flag `escaneando` ya no puede bloquear el refresco para siempre: pasa
igual si el escaneo lleva más de 180 s. Y se fuerza una pasada al despertar el
equipo (`NSWorkspace.didWakeNotification`).

**Por qué**: el diagnóstico descartó que fueran los datos — el WAL de SQLite se
seguía escribiendo al segundo, con 3:22 de CPU en 18 h de vida. El que no se
actualizaba era el label.

**Cómo verificar**: dejar la app sin tocar y comprobar que el mtime de
`tokenbar.sqlite-wal` avanza cada ~30 s.

**Docs**: `CLAUDE.md` — cuatro gotchas nuevos.

**Pendiente**: nada.

## 2026-09-08 — el reloj de reinicio va en cada ventana de la barra

**Qué**: `lineasBarra` anexa el tiempo de reinicio a **cada** ventana mostrada,
no solo a la de 5 h. La barra queda como `7%  2:05` sobre `35%  5d`.

**Por qué**: la ventana semanal salía sin su tiempo, que es justamente el dato
que dice si conviene esperar al reinicio o seguir gastando.

**Cómo verificar**: `prev-barra.png` del script de previsualización.

**Docs**: `CLAUDE.md` — tabla de preferencias (`mostrarRestante`).

**Pendiente**: nada.

## 2026-09-08 — tiempos por unidad y barra sin prefijos

**Qué**: `Formato.reloj` ahora muestra **solo días** cuando falta un día o más
(`5d`, antes `5d 20:01`) y horas con minutos por debajo de las 24 h (`2:16`), que
es siempre el caso de la ventana de 5 h. Además, los prefijos «5h»/«7d» de la
barra de menús quedaron apagados por defecto; la opción sigue en Ajustes y hay
una migración de una sola pasada (`migracionSinEtiquetas`) para no pisar la
elección si se vuelven a encender.

**Por qué**: pedido del dueño — pasado el día los minutos son ruido, y en la
barra los prefijos gastan ancho sin aportar (la posición ya distingue: arriba la
sesión, abajo la semanal).

**Cómo verificar**: el panel muestra «Sesión (5 h) … en 2:16» y «Semanal … en 5d»;
la barra queda como `7%  2:16` sobre `35%`.

**Docs**: `CLAUDE.md` — sección "Formato de tiempos" y tabla de preferencias.

**Pendiente**: nada.

## 2026-09-08 — la tarjeta del histórico ahora flota de verdad

**Qué**: el estado de la tarjeta (`DatosTarjeta`: ancla, título, valor, filas)
subió a `VistaHistorico` y se dibuja en el `ZStack` raíz, fuera del `ScrollView`
y con `zIndex` alto. Cada gráfico reporta el rectángulo del elemento apuntado en
el espacio de coordenadas `"historico"`; la tarjeta se coloca arriba de ese
rectángulo, o abajo si no cabe, nunca encima. Además, en las barras por día la
zona sensible al mouse pasó a ser la columna completa (antes era solo la barra,
imposible de apuntar con 3 px de alto) y el ancla es esa misma columna.

**Por qué**: dibujada dentro del gráfico, la tarjeta quedaba tapada por las
secciones siguientes, la recortaba el contenedor y se metía justo donde estaba
el cursor.

**Cómo verificar**: `VistaHistorico(co:plano:demo:)` acepta una tarjeta fijada
para las previsualizaciones — el PNG `prev-historico-tarjeta.png` la muestra
sobre la barra de modelos sin haber corrido nada de sitio.

**Docs**: `CLAUDE.md` — gotcha del renderizado de la tarjeta.

**Pendiente**: nada.

## 2026-09-08 — configuración de la barra, semáforo continuo y rediseño del histórico

**Qué**:
- **Ajustes** (engranaje del panel): qué ventanas mostrar en la barra de menús
  (sesión / semanal / modelo frontera), si anexar el reloj de reinicio, las
  etiquetas «5h»/«7d», el ícono, y **dos controles de tamaño de letra** (panel y
  barra). Todo en `UserDefaults`.
- **La barra ahora apila las líneas y las pinta**: `MenuBarExtra` descarta el
  color del label, así que se renderiza con `ImageRenderer` e `isTemplate=false`.
  Máximo dos líneas: macOS da ~22 pt y una tercera sale recortada.
- **Semáforo continuo** verde→rojo lineal, en vez de cuatro tramos fijos.
- **Tiempos en formato reloj** (`2:31`, `5d 20:01`) en vez de «3 h 12 min».
- **Histórico rediseñado**: la tabla por modelo pasó a ser una barra apilada con
  leyenda compacta, y tanto ella como las barras por día muestran el detalle en
  una tarjeta al pasar el mouse, en vez de gastar pantalla en columnas.
- **Árbol**: la carpeta personal se muestra como `~` y al abrir el panel se
  despliega sola la rama más pesada.
- **`scripts/previsualizar.swift`**: dibuja las vistas reales a PNG contra la
  base de verdad, para revisar la interfaz sin abrir el app.

**Por qué**: el dueño pidió elegir qué porcentajes ver y el tiempo de reinicio,
la letra era ilegible, y la vista de histórico "se veía pésimo" por ser tablas.

**Cómo verificar**: `./scripts/instalar.sh` y abrir el panel; o generar los PNG
con el script de previsualización (receta en `CLAUDE.md`).

**Docs**: `CLAUDE.md` — arquitectura, preferencias, gotchas del renderizado.

**Pendiente**: nada.

## 2026-09-08 — nace tokenbar: reemplazo de ClaudeBar con árbol por carpetas

**Qué**: App de barra de menús en SwiftUI que lee los transcripts de Claude Code
y muestra (a) el árbol expandible de tokens por carpeta con su porcentaje del
total, (b) el histórico por día y por modelo, y (c) los tres límites del plan
—sesión de 5 h, semanal y semanal del modelo frontera— tomados de
`~/.claude.json`. Todo persiste en SQLite, incluido el histórico de porcentajes
del plan, que hasta ahora se perdía porque Claude sobreescribe ese archivo.

**Por qué**: ClaudeBar (TDDWorks) muestra costos y burn rate pero no responde la
pregunta central: *en qué carpetas se están yendo los tokens*. Además su dato de
uso no queda registrado en el tiempo.

**Cómo verificar**:
```bash
swift build -c release && ./scripts/empaquetar.sh
sqlite3 ~/Library/Application\ Support/TokenBar/tokenbar.sqlite \
  "SELECT sum(entrada+salida+cache_escritura+cache_lectura), count(DISTINCT cwd) FROM uso;"
```
Primer escaneo real: 1.008 archivos, 10,42 MM de tokens, 65 carpetas, 41 días,
en menos de 5 s. Refrescos posteriores son incrementales (solo la cola nueva).

**Docs**: `CLAUDE.md` y `AGENTS.md` creados con el estándar del TYD.

**Pendiente**: sin firma de desarrollador (ad-hoc, suficiente para uso local).
Desinstalar ClaudeBar y limpiar sus hooks de `~/.claude/settings.json` queda a
decisión del dueño.
