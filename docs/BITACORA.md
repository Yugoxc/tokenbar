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
