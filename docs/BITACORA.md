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
