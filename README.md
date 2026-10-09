# TokenBar

App de barra de menús para macOS que muestra cuánto consume **Claude Code**: tokens por carpeta, por día y por modelo, más el estado de los límites de tu plan (sesión de 5 h, semanal y semanal del modelo frontera).

Corre 100 % local, sin backend. Su única salida a la red es una consulta cada 15 min a `api.anthropic.com` para leer el medidor del plan (se puede apagar).

## Qué muestra

- **En la barra de menús**: el porcentaje usado de cada ventana con semáforo de color y, si quieres, cuánto falta para que se reinicie (`2:16` bajo las 24 h, `5d` desde un día completo).
- **Carpetas**: árbol de consumo de tokens por carpeta de trabajo, filtrable por `Hoy`, `7 días`, `30 días` o `Todo`.
- **Histórico**: tokens por día, desglose por modelo e histórico de los límites del plan a lo largo del tiempo.
- **Ajustes** (engranaje del panel): qué ventanas salen en la barra, etiquetas `5h`/`7d`, ícono, tamaño de letra del panel y de la barra, y el interruptor del medidor en línea.

## Requisitos

- macOS 14 (Sonoma) o superior.
- Toolchain de Swift 5.9+ (Xcode o Command Line Tools: `xcode-select --install`).
- [Claude Code](https://claude.com/claude-code) instalado y con sesión iniciada. TokenBar lee lo que Claude Code deja en tu equipo; sin él no hay nada que mostrar.

## Instalación

No hay binarios publicados: se compila desde el código.

```bash
git clone https://github.com/Yugoxc/tokenbar.git
cd tokenbar
./scripts/instalar.sh
```

El script compila en release, arma `TokenBar.app`, la copia a `/Applications`, crea un LaunchAgent (arranca al iniciar sesión) y la deja corriendo. El ícono aparece en la barra de menús; la app no tiene ícono en el Dock.

Si prefieres no instalarla, solo empaquetar:

```bash
./scripts/empaquetar.sh      # deja build/TokenBar.app
open build/TokenBar.app
```

La app se firma *ad-hoc* (sin cuenta de desarrollador), así que es normal que macOS la trate como de origen no identificado si la copias a otro equipo; compilándola en tu propia máquina no hay problema.

### Primer arranque

Para el medidor en línea, TokenBar lee el ítem **«Claude Code-credentials»** del Llavero (con `/usr/bin/security`, la misma herramienta con la que Claude Code lo escribe). Si macOS te pide permiso, acepta con «Permitir siempre». Si lo niegas, TokenBar sigue andando con el respaldo local (ver más abajo).

### Desinstalar

```bash
launchctl unload ~/Library/LaunchAgents/cl.terraworks.tokenbar.plist
rm ~/Library/LaunchAgents/cl.terraworks.tokenbar.plist
rm -rf /Applications/TokenBar.app
rm -rf ~/Library/Application\ Support/TokenBar     # opcional: borra el histórico propio
```

## Cómo funciona

TokenBar es un observador: lee tres fuentes y **nunca escribe** en `~/.claude/`, en `~/.claude.json` ni en el Llavero.

| Dato | Fuente |
|---|---|
| Tokens por carpeta, día y modelo | `~/.claude/projects/**/*.jsonl` (transcripts de Claude Code) |
| Sesión de 5 h, semanal y modelo frontera, **en vivo** | `GET https://api.anthropic.com/api/oauth/usage` cada 15 min |
| Mismo medidor como respaldo, y tu plan | `~/.claude.json` |

**Tokens.** Un escáner incremental lee los transcripts por offset (sin cargar archivos enteros en memoria) y guarda agregados en SQLite (`~/Library/Application Support/TokenBar/tokenbar.sqlite`). Deduplica por `message.id|requestId`, porque Claude Code reescribe mensajes al reanudar o compactar y sin eso el total se infla cerca de un 47 %. La caché de lectura es ~96 % de los tokens: se cuenta porque es lo que consume el plan, por eso las cifras salen en miles de millones.

**Medidor del plan.** Claude Code solo actualiza su medidor en disco cuando se abre `/usage` o un panel de editor se lo pide, así que por sí solo queda desactualizado. Por eso TokenBar le pregunta directamente a la API usando el token OAuth de Claude Code, que lee del Llavero con `/usr/bin/security`. Entre esa lectura y la de `~/.claude.json` gana la más nueva.

**Sin lectura en línea** (sin red, sesión vencida o consulta apagada) manda el respaldo de `~/.claude.json`. Si la ventana de 5 h ya venció, TokenBar estima la vigente encadenando bloques de 5 h desde la actividad local y muestra los **tokens del bloque** en vez de un porcentaje inventado; esa estimación va marcada con `~` porque la ventana es de la cuenta y también la abren claude.ai y la app móvil. El pie del panel indica de dónde salió el dato y hace cuánto.

## Privacidad y seguridad

- El token OAuth se lee del Llavero, vive solo lo que dura la petición, no se guarda ni se registra, y **nunca se renueva** desde TokenBar (rotarlo dejaría a Claude Code con uno inválido; si venció, se espera a que Claude Code lo renueve).
- El único host al que se conecta es `api.anthropic.com`, a un único endpoint. No hay telemetría ni servidor propio.
- Puedes apagar toda salida a la red desde **Ajustes → Medidor del plan en línea**; entonces solo lee archivos locales.
- De los transcripts solo extrae el modelo, la hora, los contadores de uso (`usage`), los identificadores para deduplicar y la carpeta (`cwd`); no guarda el texto de tus conversaciones.

## Desarrollo

```bash
swift build -c release      # si compila, está sano
./scripts/empaquetar.sh     # arma build/TokenBar.app
./scripts/instalar.sh       # instala y relanza
```

Para revisar la interfaz sin abrir la app, `scripts/previsualizar.swift` dibuja las vistas reales a PNG contra tu base de datos; las instrucciones están en [`CLAUDE.md`](CLAUDE.md).

Estructura de `Sources/TokenBar/`:

```
TokenBarApp.swift   MenuBarExtra y etiqueta de la barra
Coordinador.swift   orquesta escaneo, rango y formato
Escaner.swift       lectura incremental de los .jsonl
Almacen.swift       SQLite: agregados, dedup, histórico
Medidor.swift       consulta al endpoint de uso
Llavero.swift       lectura del token de Claude Code
Suscripcion.swift   lectura de ~/.claude.json
Bloques.swift       estimación de la ventana de 5 h
UI/                 vistas del panel, histórico y ajustes
```

Las decisiones, los problemas ya resueltos y las reglas del proyecto están en [`CLAUDE.md`](CLAUDE.md) y [`docs/BITACORA.md`](docs/BITACORA.md).

## Limitaciones

- Solo macOS 14+ (SwiftUI `MenuBarExtra`).
- Mide **Claude Code**; el consumo de claude.ai o la app móvil solo aparece indirectamente, vía el porcentaje del medidor.
- El medidor en línea depende de que Claude Code haya renovado su sesión recientemente; si no lo usas por un rato, el panel lo avisa.
- Usa un endpoint no documentado de Anthropic (`/api/oauth/usage`) que podría cambiar sin aviso.

## Licencia

Pendiente de definir.
