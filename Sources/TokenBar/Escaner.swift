import Foundation

struct LlaveUso: Hashable {
    let dia: String
    let cwd: String
    let modelo: String
}

struct ArchivoLeido {
    let ruta: String
    let tam: Int64
    let pos: Int64
    let mtime: Double
}

struct LoteEscaneo {
    var agregados: [LlaveUso: Tokens] = [:]
    var vistos: [String] = []
    var archivos: [ArchivoLeido] = []
    /// Tokens por instante (epoch en segundos) de las respuestas de la API
    /// vistas en este lote. De acá sale la ventana de 5 h cuando la de Claude
    /// queda vieja, y cuánto se lleva gastado dentro (ver `Bloques`). Un
    /// instante puede quedar en 0: la respuesta ya se había contado antes, pero
    /// igual marcó actividad de la API.
    var actividad: [Int: Int] = [:]
    var lineasNuevas = 0

    var vacio: Bool { agregados.isEmpty && archivos.isEmpty && actividad.isEmpty }
}

/// Lee los transcripts de Claude Code y saca de ahí el consumo de tokens.
///
/// Optimización central: los .jsonl solo crecen por el final, así que se guarda
/// el byte hasta donde se leyó cada archivo y en cada refresco solo se procesa
/// la cola nueva. El primer escaneo recorre todo; los siguientes son casi gratis.
final class Escaner: @unchecked Sendable {
    private let almacen: Almacen
    private var vistos: Set<String>
    private var cacheDia: [String: String] = [:]

    static let raiz = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    init(almacen: Almacen) {
        self.almacen = almacen
        self.vistos = almacen.cargarVistos()
    }

    /// Recorre todo lo pendiente. `progreso` recibe (procesados, total).
    @discardableResult
    func escanear(progreso: ((Int, Int) -> Void)? = nil) -> LoteEscaneo {
        // Una base recién migrada trae `actividad` vacía y no se llenaría sola:
        // el escaneo normal se apoya en `vistos` y no volvería a sumar tokens.
        if almacen.debeReconstruirActividad() { reconstruirActividad() }

        var lote = LoteEscaneo()
        let fm = FileManager.default
        guard let carpetas = try? fm.contentsOfDirectory(at: Self.raiz, includingPropertiesForKeys: nil) else {
            return lote
        }

        var pendientes: [(URL, Int64, Int64, Double)] = []   // url, tam, desde, mtime
        for carpeta in carpetas {
            guard let archivos = try? fm.contentsOfDirectory(
                at: carpeta,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
            for url in archivos where url.pathExtension == "jsonl" {
                let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let tam = Int64(attrs?.fileSize ?? 0)
                let mtime = attrs?.contentModificationDate?.timeIntervalSince1970 ?? 0
                var desde: Int64 = 0
                if let previo = almacen.estadoArchivo(url.path) {
                    if previo.tam == tam { continue }              // sin cambios
                    // Si encogió, el archivo se reescribió: hay que releerlo entero.
                    desde = tam >= previo.tam ? previo.pos : 0
                }
                pendientes.append((url, tam, desde, mtime))
            }
        }

        let total = pendientes.count
        for (i, item) in pendientes.enumerated() {
            procesar(url: item.0, tam: item.1, desde: item.2, mtime: item.3, lote: &lote)
            progreso?(i + 1, total)
        }
        if !lote.vacio { almacen.aplicarLote(lote) }
        return lote
    }

    /// Rehace la tabla `actividad` leyendo todos los transcripts desde cero.
    ///
    /// El dedup se hace DENTRO de la pasada, contra un conjunto vacío, y no
    /// contra el `vistos` que ya está en la base: si no, ningún mensaje viejo
    /// volvería a aportar sus tokens y la tabla quedaría en ceros. El resto del
    /// lote (agregados, archivos) se descarta a propósito — eso ya está contado.
    private func reconstruirActividad() {
        let guardados = vistos
        vistos = []
        defer { vistos = guardados }

        var lote = LoteEscaneo()
        let fm = FileManager.default
        guard let carpetas = try? fm.contentsOfDirectory(at: Self.raiz, includingPropertiesForKeys: nil) else { return }
        for carpeta in carpetas {
            guard let archivos = try? fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for url in archivos where url.pathExtension == "jsonl" {
                let tam = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                procesar(url: url, tam: tam, desde: 0, mtime: 0, lote: &lote)
            }
        }
        almacen.reemplazarActividad(lote.actividad)
    }

    // MARK: - Lectura de un archivo

    private func procesar(url: URL, tam: Int64, desde: Int64, mtime: Double, lote: inout LoteEscaneo) {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fh.close() }
        if desde > 0 { try? fh.seek(toOffset: UInt64(desde)) }

        var resto = Data()
        var leidoHasta = desde

        while true {
            guard let bloque = try? fh.read(upToCount: 4 << 20), !bloque.isEmpty else { break }
            var datos = resto
            datos.append(bloque)
            resto = Data()

            var inicio = datos.startIndex
            while let salto = datos[inicio...].firstIndex(of: 0x0A) {
                autoreleasepool {
                    consumir(datos[inicio..<salto], lote: &lote)
                }
                leidoHasta += Int64(salto - inicio + 1)
                inicio = datos.index(after: salto)
            }
            // La última línea puede venir cortada entre bloques.
            if inicio < datos.endIndex { resto = datos[inicio...] }
        }

        // Solo se marca como leído hasta el último salto de línea completo: si
        // Claude está escribiendo justo ahora, la cola parcial se relee después.
        lote.archivos.append(ArchivoLeido(ruta: url.path, tam: tam, pos: leidoHasta, mtime: mtime))
    }

    private func consumir(_ linea: Data, lote: inout LoteEscaneo) {
        guard linea.count > 40 else { return }
        // Filtro barato antes de gastar el parser en una línea que no aporta.
        guard linea.contiene(bytes: Array(#""usage""#.utf8)) else { return }

        guard let raiz = try? JSONSerialization.jsonObject(with: linea) as? [String: Any],
              let mensaje = raiz["message"] as? [String: Any],
              let uso = mensaje["usage"] as? [String: Any] else { return }

        let marca = raiz["timestamp"] as? String
        let segundo = Self.instante(marca)

        // El instante se anota ANTES del dedup: al reanudar o compactar, la
        // misma respuesta se reescribe conservando su hora original, así que
        // aunque no se vuelva a sumar sí sigue marcando actividad de la API.
        if let segundo, lote.actividad[segundo] == nil { lote.actividad[segundo] = 0 }

        // Dedup: el mismo mensaje reaparece al reanudar o compactar una sesión.
        let idMensaje = mensaje["id"] as? String
        if let idMensaje {
            let clave = idMensaje + "|" + ((raiz["requestId"] as? String) ?? "")
            if vistos.contains(clave) { return }
            vistos.insert(clave)
            lote.vistos.append(clave)
        }

        let tk = Tokens(entrada: uso["input_tokens"] as? Int ?? 0,
                        salida: uso["output_tokens"] as? Int ?? 0,
                        cacheEscritura: uso["cache_creation_input_tokens"] as? Int ?? 0,
                        cacheLectura: uso["cache_read_input_tokens"] as? Int ?? 0,
                        mensajes: 1)
        if tk.total == 0 { return }
        if let segundo { lote.actividad[segundo, default: 0] += tk.total }

        let llave = LlaveUso(dia: dia(de: marca),
                             cwd: (raiz["cwd"] as? String) ?? "(sin carpeta)",
                             modelo: (mensaje["model"] as? String) ?? "desconocido")
        lote.agregados[llave, default: Tokens()] += tk
        lote.lineasNuevas += 1
    }

    // MARK: - Fechas

    /// Epoch en segundos de un timestamp del transcript
    /// ("2026-09-09T12:32:15.409Z", siempre UTC y siempre con ese ancho).
    ///
    /// Se parsea a mano: `ISO8601DateFormatter` cuesta microsegundos por línea
    /// y acá se recorren decenas de miles en cada relectura completa.
    static func instante(_ iso: String?) -> Int? {
        guard let iso else { return nil }
        let b = Array(iso.utf8)
        guard b.count >= 19 else { return nil }
        func num(_ i: Int, _ n: Int) -> Int? {
            var v = 0
            for k in i..<(i + n) {
                let c = b[k]
                guard c >= 48, c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard let a = num(0, 4), let m = num(5, 2), let d = num(8, 2),
              let h = num(11, 2), let mi = num(14, 2), let sg = num(17, 2),
              m >= 1, m <= 12, d >= 1, d <= 31, h < 24, mi < 60, sg <= 60 else { return nil }
        return diasDesdeEpoch(a, m, d) * 86_400 + h * 3600 + mi * 60 + sg
    }

    /// Días entre 1970-01-01 y la fecha dada, en el calendario gregoriano
    /// proléptico (algoritmo `days_from_civil` de Howard Hinnant). Evita armar
    /// un `DateComponents` por línea.
    private static func diasDesdeEpoch(_ anio: Int, _ mes: Int, _ dia: Int) -> Int {
        let y = anio - (mes <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                        // [0, 399]
        let doy = (153 * (mes + (mes > 2 ? -3 : 9)) + 2) / 5 + dia - 1 // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy                // [0, 146096]
        return era * 146_097 + doe - 719_468
    }

    private static let calendarioUTC: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Convierte el timestamp UTC del transcript al día local.
    ///
    /// Se cachea por hora UTC: 80.000 líneas caen en menos de mil horas
    /// distintas, así que el trabajo real de fechas es despreciable.
    private func dia(de iso: String?) -> String {
        guard let iso, iso.count >= 13 else { return "0000-00-00" }
        let clave = String(iso.prefix(13))       // YYYY-MM-DDTHH
        if let hit = cacheDia[clave] { return hit }

        let p = clave.split(separator: "T")
        guard p.count == 2 else { return "0000-00-00" }
        let f = p[0].split(separator: "-")
        guard f.count == 3, let a = Int(f[0]), let m = Int(f[1]), let d = Int(f[2]),
              let h = Int(p[1]) else { return "0000-00-00" }

        var comps = DateComponents()
        comps.year = a; comps.month = m; comps.day = d; comps.hour = h
        guard let fecha = Self.calendarioUTC.date(from: comps) else { return "0000-00-00" }

        let local = Calendar.current.dateComponents([.year, .month, .day], from: fecha)
        let out = String(format: "%04d-%02d-%02d", local.year ?? 0, local.month ?? 0, local.day ?? 0)
        cacheDia[clave] = out
        return out
    }
}

private extension Data {
    /// Búsqueda de subsecuencia sin convertir la línea a String.
    func contiene(bytes patron: [UInt8]) -> Bool {
        guard patron.count <= count else { return false }
        let primero = patron[0]
        return withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Bool in
            let n = buf.count, m = patron.count
            var i = 0
            while i <= n - m {
                if buf[i] == primero {
                    var j = 1
                    while j < m, buf[i + j] == patron[j] { j += 1 }
                    if j == m { return true }
                }
                i += 1
            }
            return false
        }
    }
}
