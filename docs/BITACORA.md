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
