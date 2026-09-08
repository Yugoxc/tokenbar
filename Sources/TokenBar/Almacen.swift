import Foundation
import SQLite3

/// SQLite le pide a sqlite3_bind_text que copie el string; sin esto el buffer
/// de Swift muere antes del step y se leen bytes basura.
private let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Persistencia: agregados de uso, control de archivos ya leídos, dedup de
/// mensajes y el histórico de la suscripción.
final class Almacen: @unchecked Sendable {
    private var db: OpaquePointer?
    private let cola = DispatchQueue(label: "cl.terraworks.tokenbar.almacen")

    static let carpeta: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TokenBar", isDirectory: true)
    }()

    init() throws {
        try FileManager.default.createDirectory(at: Self.carpeta, withIntermediateDirectories: true)
        let ruta = Self.carpeta.appendingPathComponent("tokenbar.sqlite").path
        guard sqlite3_open_v2(ruta, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw NSError(domain: "Almacen", code: 1, userInfo: [NSLocalizedDescriptionKey: "no se pudo abrir \(ruta)"])
        }
        // WAL + synchronous NORMAL: escrituras rápidas sin arriesgar la base
        // ante un cierre abrupto del app.
        ejecutar("PRAGMA journal_mode=WAL;")
        ejecutar("PRAGMA synchronous=NORMAL;")
        ejecutar("PRAGMA temp_store=MEMORY;")
        crearEsquema()
    }

    deinit { if let db { sqlite3_close_v2(db) } }

    private func crearEsquema() {
        ejecutar("""
        CREATE TABLE IF NOT EXISTS uso (
          dia TEXT NOT NULL, cwd TEXT NOT NULL, modelo TEXT NOT NULL,
          entrada INTEGER NOT NULL DEFAULT 0, salida INTEGER NOT NULL DEFAULT 0,
          cache_escritura INTEGER NOT NULL DEFAULT 0, cache_lectura INTEGER NOT NULL DEFAULT 0,
          mensajes INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (dia, cwd, modelo)
        );
        CREATE INDEX IF NOT EXISTS idx_uso_dia ON uso(dia);
        CREATE INDEX IF NOT EXISTS idx_uso_cwd ON uso(cwd);

        CREATE TABLE IF NOT EXISTS vistos (clave TEXT PRIMARY KEY) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS archivos (
          ruta TEXT PRIMARY KEY, tam INTEGER NOT NULL,
          pos INTEGER NOT NULL, mtime REAL NOT NULL
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS suscripcion (
          ts INTEGER PRIMARY KEY, plan TEXT,
          sesion_pct REAL, sesion_reset TEXT,
          semanal_pct REAL, semanal_reset TEXT,
          frontera_pct REAL, frontera_modelo TEXT, frontera_reset TEXT
        );
        """)
    }

    private func ejecutar(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Escaneo

    /// Estado de un archivo ya procesado: hasta qué byte se leyó.
    func estadoArchivo(_ ruta: String) -> (tam: Int64, pos: Int64)? {
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        guard sqlite3_prepare_v2(db, "SELECT tam, pos FROM archivos WHERE ruta=?;", -1, &st, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(st, 1, ruta, -1, TRANSIENT)
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        return (sqlite3_column_int64(st, 0), sqlite3_column_int64(st, 1))
    }

    /// Vuelca en una transacción todo lo que produjo el escaneo de un lote.
    func aplicarLote(_ lote: LoteEscaneo) {
        cola.sync {
            ejecutar("BEGIN IMMEDIATE;")

            var stVisto: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO vistos(clave) VALUES(?);", -1, &stVisto, nil)
            for clave in lote.vistos {
                sqlite3_bind_text(stVisto, 1, clave, -1, TRANSIENT)
                sqlite3_step(stVisto); sqlite3_reset(stVisto)
            }
            sqlite3_finalize(stVisto)

            var stUso: OpaquePointer?
            sqlite3_prepare_v2(db, """
            INSERT INTO uso(dia,cwd,modelo,entrada,salida,cache_escritura,cache_lectura,mensajes)
            VALUES(?,?,?,?,?,?,?,?)
            ON CONFLICT(dia,cwd,modelo) DO UPDATE SET
              entrada=entrada+excluded.entrada, salida=salida+excluded.salida,
              cache_escritura=cache_escritura+excluded.cache_escritura,
              cache_lectura=cache_lectura+excluded.cache_lectura,
              mensajes=mensajes+excluded.mensajes;
            """, -1, &stUso, nil)
            for (llave, tk) in lote.agregados {
                sqlite3_bind_text(stUso, 1, llave.dia, -1, TRANSIENT)
                sqlite3_bind_text(stUso, 2, llave.cwd, -1, TRANSIENT)
                sqlite3_bind_text(stUso, 3, llave.modelo, -1, TRANSIENT)
                sqlite3_bind_int64(stUso, 4, Int64(tk.entrada))
                sqlite3_bind_int64(stUso, 5, Int64(tk.salida))
                sqlite3_bind_int64(stUso, 6, Int64(tk.cacheEscritura))
                sqlite3_bind_int64(stUso, 7, Int64(tk.cacheLectura))
                sqlite3_bind_int64(stUso, 8, Int64(tk.mensajes))
                sqlite3_step(stUso); sqlite3_reset(stUso)
            }
            sqlite3_finalize(stUso)

            var stArch: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO archivos(ruta,tam,pos,mtime) VALUES(?,?,?,?);", -1, &stArch, nil)
            for a in lote.archivos {
                sqlite3_bind_text(stArch, 1, a.ruta, -1, TRANSIENT)
                sqlite3_bind_int64(stArch, 2, a.tam)
                sqlite3_bind_int64(stArch, 3, a.pos)
                sqlite3_bind_double(stArch, 4, a.mtime)
                sqlite3_step(stArch); sqlite3_reset(stArch)
            }
            sqlite3_finalize(stArch)

            ejecutar("COMMIT;")
        }
    }

    /// Claves ya contabilizadas, para no sumar dos veces un mensaje que aparece
    /// repetido tras un --resume o un compact.
    func cargarVistos() -> Set<String> {
        var out = Set<String>()
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        guard sqlite3_prepare_v2(db, "SELECT clave FROM vistos;", -1, &st, nil) == SQLITE_OK else { return out }
        out.reserveCapacity(120_000)
        while sqlite3_step(st) == SQLITE_ROW {
            if let c = sqlite3_column_text(st, 0) { out.insert(String(cString: c)) }
        }
        return out
    }

    // MARK: - Lectura para la UI

    func filas(desde: String? = nil) -> [FilaUso] {
        var out: [FilaUso] = []
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        let sql = desde == nil
            ? "SELECT dia,cwd,modelo,entrada,salida,cache_escritura,cache_lectura,mensajes FROM uso;"
            : "SELECT dia,cwd,modelo,entrada,salida,cache_escritura,cache_lectura,mensajes FROM uso WHERE dia>=?;"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return out }
        if let desde { sqlite3_bind_text(st, 1, desde, -1, TRANSIENT) }
        while sqlite3_step(st) == SQLITE_ROW {
            let tk = Tokens(entrada: Int(sqlite3_column_int64(st, 3)),
                            salida: Int(sqlite3_column_int64(st, 4)),
                            cacheEscritura: Int(sqlite3_column_int64(st, 5)),
                            cacheLectura: Int(sqlite3_column_int64(st, 6)),
                            mensajes: Int(sqlite3_column_int64(st, 7)))
            out.append(FilaUso(dia: String(cString: sqlite3_column_text(st, 0)),
                               cwd: String(cString: sqlite3_column_text(st, 1)),
                               modelo: String(cString: sqlite3_column_text(st, 2)),
                               tokens: tk))
        }
        return out
    }

    // MARK: - Histórico de suscripción

    /// Guarda una muestra solo si cambió algo respecto de la última: el archivo
    /// de Claude se reescribe cada 5 min aunque los porcentajes sigan iguales.
    func guardarSuscripcion(_ e: EstadoSuscripcion) {
        cola.sync {
            let iso = ISO8601DateFormatter()
            var st: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT sesion_pct, semanal_pct, frontera_pct FROM suscripcion ORDER BY ts DESC LIMIT 1;", -1, &st, nil)
            var igual = false
            if sqlite3_step(st) == SQLITE_ROW {
                let s = sqlite3_column_double(st, 0), w = sqlite3_column_double(st, 1), f = sqlite3_column_double(st, 2)
                igual = s == (e.sesion?.porcentaje ?? -1)
                    && w == (e.semanal?.porcentaje ?? -1)
                    && f == (e.frontera?.porcentaje ?? -1)
            }
            sqlite3_finalize(st)
            if igual { return }

            var ins: OpaquePointer?
            sqlite3_prepare_v2(db, """
            INSERT OR REPLACE INTO suscripcion
            (ts,plan,sesion_pct,sesion_reset,semanal_pct,semanal_reset,frontera_pct,frontera_modelo,frontera_reset)
            VALUES(?,?,?,?,?,?,?,?,?);
            """, -1, &ins, nil)
            sqlite3_bind_int64(ins, 1, Int64(Date().timeIntervalSince1970))
            sqlite3_bind_text(ins, 2, e.plan, -1, TRANSIENT)
            sqlite3_bind_double(ins, 3, e.sesion?.porcentaje ?? -1)
            sqlite3_bind_text(ins, 4, e.sesion?.reinicia.map { iso.string(from: $0) } ?? "", -1, TRANSIENT)
            sqlite3_bind_double(ins, 5, e.semanal?.porcentaje ?? -1)
            sqlite3_bind_text(ins, 6, e.semanal?.reinicia.map { iso.string(from: $0) } ?? "", -1, TRANSIENT)
            sqlite3_bind_double(ins, 7, e.frontera?.porcentaje ?? -1)
            sqlite3_bind_text(ins, 8, e.frontera?.etiqueta ?? "", -1, TRANSIENT)
            sqlite3_bind_text(ins, 9, e.frontera?.reinicia.map { iso.string(from: $0) } ?? "", -1, TRANSIENT)
            sqlite3_step(ins)
            sqlite3_finalize(ins)
        }
    }

    func muestrasSuscripcion(ultimas n: Int = 500) -> [MuestraSuscripcion] {
        var out: [MuestraSuscripcion] = []
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        guard sqlite3_prepare_v2(db, "SELECT ts,sesion_pct,semanal_pct,frontera_pct,frontera_modelo FROM suscripcion ORDER BY ts DESC LIMIT ?;", -1, &st, nil) == SQLITE_OK else { return out }
        sqlite3_bind_int(st, 1, Int32(n))
        while sqlite3_step(st) == SQLITE_ROW {
            let neg = { (v: Double) -> Double? in v < 0 ? nil : v }
            out.append(MuestraSuscripcion(
                ts: Int(sqlite3_column_int64(st, 0)),
                sesion: neg(sqlite3_column_double(st, 1)),
                semanal: neg(sqlite3_column_double(st, 2)),
                frontera: neg(sqlite3_column_double(st, 3)),
                modeloFrontera: sqlite3_column_text(st, 4).map { String(cString: $0) }))
        }
        return out.reversed()
    }
}
