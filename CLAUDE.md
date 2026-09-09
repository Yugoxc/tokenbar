# CLAUDE.md — tokenbar

App de barra de menús de macOS (SwiftUI, `MenuBarExtra`) que muestra el consumo
de tokens de Claude Code por carpeta, con histórico, y el estado de los límites
del plan (sesión de 5 h, semanal, y semanal del modelo frontera). Reemplaza a
ClaudeBar de TDDWorks. Corre local; no tiene backend ni red.

## Regla de mantenimiento de docs (OBLIGATORIA — leer antes de cambiar código)

Al terminar CUALQUIER cambio en este repo, antes de commitear:

1. Agrega una entrada al INICIO de `docs/BITACORA.md` con la plantilla que está ahí mismo.
2. Recorre el "Mapa de docs" de este archivo: si tu cambio invalida algo que un doc
   afirma (comportamiento, contratos, modelos de datos, deploy, gotchas, convenciones),
   actualiza ese doc EN EL MISMO COMMIT que el código.
3. Si ningún doc quedó afectado, decláralo en la bitácora: `Docs: ninguno`.
4. Si cambiaste un contrato con otro sistema, actualiza la sección de ecosistema
   de este archivo y anota en `Pendiente` que falta la contraparte.

Un cambio sin entrada en la bitácora está INCOMPLETO, aunque compile y funcione.

Si eres una IA y detectas que un doc contradice al código: el código manda; corrige
el doc y regístralo en la bitácora como entrada propia.

## Mapa de docs

| Doc | Qué responde | Actualízalo cuando… |
|---|---|---|
| `docs/BITACORA.md` | Qué cambió, cuándo y por qué | SIEMPRE — cada cambio deja entrada |

## De dónde salen los datos (lo esencial)

Dos fuentes, ambas de solo lectura. **Este app nunca escribe en `~/.claude`.**

| Dato | Fuente | Detalle |
|---|---|---|
| Tokens por carpeta / día / modelo | `~/.claude/projects/*/*.jsonl` | Cada línea `assistant` trae `message.usage` y el `cwd` real de la sesión |
| Sesión 5 h, semanal, modelo frontera, plan | `~/.claude.json` | Claves `cachedUsageUtilization` y `oauthAccount` |

`cachedUsageUtilization.utilization` trae `five_hour` y `seven_day` sueltos, y un
arreglo `limits[]` donde el elemento de `kind == "weekly_scoped"` es el límite del
modelo frontera (`scope.model.display_name`, hoy "Fable").

El plan sale de `oauthAccount.organizationRateLimitTier`
(`default_claude_max_20x` → "Max 20×").

**Ese dato se cae solo**: Claude Code deja de reescribir `cachedUsageUtilization`
por horas (se le vio 22,7 h seguidas mientras reescribía el resto del archivo
cada pocos minutos). Cuando su `resets_at` de la sesión ya pasó, la ventana de
5 h vigente se deduce de la tabla `actividad` —un instante por respuesta de la
API, con lo que costó, sacado del `timestamp` de los transcripts— encadenando
bloques de 5 h desde el último corte que Claude sí confirmó. Esa misma tabla da
el consumo del bloque en curso, que es lo que se muestra donde iría el
porcentaje. Ver `Bloques.swift`.

## Arquitectura

```
TokenBarApp.swift   MenuBarExtra; el label se renderiza a imagen (ver abajo)
Preferencias.swift  Qué mostrar en la barra y tamaños de letra (UserDefaults)
Coordinador.swift   ObservableObject: orquesta escaneo, rango y formateo
Escaner.swift       Lee los .jsonl de forma incremental (por offset)
Almacen.swift       SQLite: agregados, dedup, control de archivos, histórico
Suscripcion.swift   Lee ~/.claude.json
Bloques.swift       Deduce la ventana de 5 h vigente desde la actividad local
Arbol.swift         Arma el árbol de carpetas desde las filas agregadas
UI/                 VistaPrincipal, VistaArbol, VistaHistorico, VistaAjustes,
                    EtiquetaBarra, Componentes
```

Base de datos: `~/Library/Application Support/TokenBar/tokenbar.sqlite`.

## Comandos clave

```bash
swift build -c release          # verificación: si compila, está sano
./scripts/empaquetar.sh         # arma build/TokenBar.app (firma ad-hoc)
./scripts/instalar.sh           # copia a /Applications + LaunchAgent + relanza
swift scripts/icono.swift Recursos/AppIcon.iconset && \
  iconutil -c icns Recursos/AppIcon.iconset -o Recursos/AppIcon.icns   # regenerar ícono
```

### Ver el diseño sin abrir el app

`scripts/previsualizar.swift` dibuja las vistas reales a PNG contra la base de
datos de verdad. Sirve para revisar cambios de interfaz de un vistazo:

```bash
mkdir -p /tmp/p && cp scripts/previsualizar.swift /tmp/p/main.swift
FUENTES=$(ls Sources/TokenBar/*.swift Sources/TokenBar/UI/*.swift | grep -v TokenBarApp.swift | tr '\n' ' ')
swiftc -O ${=FUENTES} /tmp/p/main.swift -o /tmp/prevtb && /tmp/prevtb /tmp
```

## Reglas duras

- **Nunca escribir dentro de `~/.claude/` ni `~/.claude.json`.** Son de Claude Code;
  este app es un observador. Corromperlos rompe las sesiones del usuario.
- **Nunca leer el llavero ni credenciales OAuth.** Todo lo que se necesita ya está
  en `~/.claude.json`; no hay motivo para llamar a la API de Anthropic.
- No cargar un `.jsonl` completo en memoria: hay archivos de cientos de MB.

## Gotchas

- **Los transcripts repiten mensajes.** Al reanudar (`--resume`) o compactar, las
  mismas respuestas se reescriben. Sin deduplicar por `message.id|requestId` el
  total se infla ~47 % (37 k de 80 k líneas eran repetidas al construir esto).
- **La caché domina el total**: `cache_read_input_tokens` es ~96 % de los tokens.
  Contarla es lo correcto (es lo que consume el plan), pero explica por qué los
  números están en miles de millones y no en millones.
- **`~/.claude.json` solo se refresca con una sesión de Claude Code viva**, cada
  ~5 min, y el dato caduca a la hora. Si no hay sesión, los porcentajes se quedan
  quietos: por eso el pie del panel dice "Datos de Claude hace X".
- **Un `.jsonl` puede encoger** si Claude lo reescribe. El escáner compara el
  tamaño guardado: si es menor que el anterior, relee el archivo desde cero (el
  dedup evita el doble conteo).
- **El offset se guarda hasta el último `\n` completo**, no hasta el fin del
  archivo: si Claude está escribiendo una línea justo en ese momento, la cola
  parcial se vuelve a leer en el refresco siguiente.
- **`Package.swift` no puede tener un archivo `main.swift`** junto con `@main`;
  por eso el punto de entrada se llama `TokenBarApp.swift`. Al revés, el script
  de previsualización SÍ debe llamarse `main.swift` al compilarlo: Swift solo
  permite código suelto en un archivo con ese nombre.
- **`MenuBarExtra` descarta el color del label**: lo trata como imagen template.
  Por eso `EtiquetaBarra.imagen` lo renderiza con `ImageRenderer` y marca
  `isTemplate = false`; así el semáforo se ve en la barra.
- **La barra de menús da ~22 pt de alto**: caben dos líneas, no tres. Con las
  tres ventanas activas, las dos últimas comparten línea (ver `lineasBarra`).
- **`ImageRenderer` no dibuja el contenido de un `ScrollView`** (sale en blanco).
  Por eso `VistaArbol` y `VistaHistorico` aceptan `plano: true`, que el script
  de previsualización usa para poder retratarlas.
- **Los controles nativos (`Picker` segmentado, `Toggle`, `Slider`) salen como
  rectángulos amarillos** en esas previsualizaciones. Es un artefacto del
  renderizador, no un error del app.
- **`cachedUsageUtilization` se queda congelado por horas.** No es que no haya
  sesión: Claude Code reescribe `~/.claude.json` cada pocos minutos y aun así
  deja esa clave intacta (22,7 h en el caso que lo destapó, con Claude Code
  corriendo todo el rato). Y no hay otra fuente: no está en el resto de
  `~/.claude/`, ni en las demás claves `cache*` del JSON, ni en los transcripts
  —que no traen cabeceras de rate limit—. Por eso la ventana de 5 h se estima.
- **La ventana de 5 h es de la cuenta, no de Claude Code.** Se comprobó con dos
  cortes que reportó Claude (09-07 22:29:59 y 09-08 10:10:00 local): ninguno
  tiene línea en los transcripts, o sea que claude.ai, la app de escritorio o el
  móvil también la abren. La estimación de `Bloques` puede empezar más tarde que
  la real —nunca antes—, así que el tiempo que muestra es un techo, y por eso va
  con «~» en la interfaz.
- **El porcentaje de una ventana vencida no se recicla.** `Ventana.porcentaje`
  es opcional a propósito: cuando la ventana en curso empezó después de la
  última lectura de Claude, en su lugar van los **tokens del bloque**
  (`Ventana.consumo`) y la barra de progreso queda vacía. Un 3 % de la ventana
  anterior con cara de dato fresco es peor que no saber.
- **El porcentaje de la sesión no se puede estimar desde los tokens.** Se probó:
  calibrando contra las dos lecturas reales que había, salieron 4.717.298 y
  227.688 tokens por punto de %, 20× de diferencia. En la segunda el bloque abrió
  a las 10:10 y el primer mensaje de Claude Code fue a las 10:43 — el resto se
  gastó fuera. Por eso se muestran tokens medidos y no un porcentaje inventado.
- **`actividad` no se puede rellenar con una relectura normal.** El escáner
  dedupe contra `vistos`, así que en una relectura completa ningún mensaje viejo
  volvería a aportar tokens y la tabla quedaría en ceros. Para eso está
  `Escaner.reconstruirActividad`, que dedupe DENTRO de su propia pasada; se
  dispara sola cuando `actividad` está vacía y `archivos` no.
- **El instante de actividad se anota antes del dedup.** Una respuesta reescrita
  por un `--resume` no debe volver a sumar tokens, pero sí ocurrió: conserva su
  hora original y marca actividad real de la API. Si se anotara después del
  dedup, una relectura completa no llenaría nada.
- **App Nap congela la app.** Al ser `LSUIElement` (sin ventana), macOS la
  suspende y estira sus timers varios minutos: la barra se quedaba pegada hasta
  que el usuario la tocaba. Se sostiene con `ProcessInfo.beginActivity`
  (`userInitiatedAllowingIdleSystemSleep`, que igual deja dormir el equipo) y el
  token se guarda en `Coordinador.actividad` — si se libera, vuelve el problema.
- **Los timers deben ir en modo `.common`.** Con `Timer.scheduledTimer` (modo
  por omisión) se detienen mientras hay un menú abierto o el usuario arrastra
  algo. Por eso `Coordinador.programar(cada:)` los agrega a mano al RunLoop.
- **El reloj de la barra tiene su propio latido** (`ahora`, cada 10 s), aparte
  del escaneo: si un refresco se demora o falla, la hora igual sigue corriendo.
- **`EtiquetaBarra.imagen` cachea la última imagen buena.** `ImageRenderer`
  devuelve `nil` de vez en cuando —al despertar el equipo o cambiar de pantalla,
  con `NSScreen.main` en nil— y devolver una imagen vacía dejaba la barra en
  blanco.
- **La tarjeta del histórico no puede vivir dentro del gráfico.** Dibujada como
  hermana, las secciones que vienen después se pintan encima y además el
  contenedor la recorta. Por eso el estado (`DatosTarjeta`) sube a
  `VistaHistorico` y la tarjeta se dibuja en el `ZStack` raíz, fuera del
  `ScrollView`: así flota sobre todo y no participa del layout. Cada gráfico
  reporta el rectángulo del elemento apuntado en el espacio de coordenadas
  `"historico"`, y la tarjeta se ubica arriba o abajo de ese rectángulo —nunca
  encima— para no tapar el cursor.

## Preferencias del usuario

Se guardan en `UserDefaults` (dominio `cl.terraworks.tokenbar`) y se editan
desde el engranaje del panel:

| Clave | Qué controla | Defecto |
|---|---|---|
| `mostrarSesion` / `mostrarSemanal` / `mostrarFrontera` | Qué ventanas salen en la barra | sí / sí / no |
| `mostrarRestante` | Anexa a cada ventana su reloj de reinicio | sí |
| `mostrarEtiquetas` | Prefijos «5h» y «7d» | no |
| `mostrarIcono` | Ícono del medidor | sí |
| `escalaPanel` | Tamaño de letra del panel | 1,25 |
| `escalaBarra` | Tamaño de letra en la barra (topeado a 1,25 con dos líneas) | 1,15 |

Las vistas piden su tipografía a `fuente(_:_:mono:)` y sus medidas a `esc(_:)`,
ambas en `UI/Componentes.swift`; así un solo control reescala todo el panel.

## Formato de tiempos

`Formato.reloj` decide la unidad según lo que queda: **desde un día completo,
solo días** (`5d`), porque los minutos ya no informan nada; **bajo las 24 h,
horas y minutos** (`2:16`). La ventana de 5 h cae siempre en el segundo caso.

## Convenciones

- Comentarios en español (Chile) explicando el **porqué**, no el qué.
- Commits Conventional en español: `feat(ámbito): …`, `fix(ámbito): …`.
- Nombres de tipos y variables en español, salvo los de Apple/SQLite.
