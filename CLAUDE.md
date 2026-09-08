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

## Arquitectura

```
TokenBarApp.swift   MenuBarExtra; el label muestra el límite más apretado
Coordinador.swift   ObservableObject: orquesta escaneo, rango y formateo
Escaner.swift       Lee los .jsonl de forma incremental (por offset)
Almacen.swift       SQLite: agregados, dedup, control de archivos, histórico
Suscripcion.swift   Lee ~/.claude.json
Arbol.swift         Arma el árbol de carpetas desde las filas agregadas
UI/                 VistaPrincipal, VistaArbol, VistaHistorico, Componentes
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
  por eso el punto de entrada se llama `TokenBarApp.swift`.

## Convenciones

- Comentarios en español (Chile) explicando el **porqué**, no el qué.
- Commits Conventional en español: `feat(ámbito): …`, `fix(ámbito): …`.
- Nombres de tipos y variables en español, salvo los de Apple/SQLite.
