import Foundation
import SwiftUI

enum Rango: String, CaseIterable, Identifiable {
    case hoy = "Hoy"
    case semana = "7 días"
    case mes = "30 días"
    case todo = "Todo"

    var id: String { rawValue }

    /// Primer día incluido, en formato YYYY-MM-DD. `nil` = sin recorte.
    var desde: String? {
        let cal = Calendar.current
        let dias: Int
        switch self {
        case .hoy: dias = 0
        case .semana: dias = 6
        case .mes: dias = 29
        case .todo: return nil
        }
        guard let fecha = cal.date(byAdding: .day, value: -dias, to: Date()) else { return nil }
        let c = cal.dateComponents([.year, .month, .day], from: fecha)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

@MainActor
final class Coordinador: ObservableObject {
    @Published var rango: Rango = .todo { didSet { recomponer() } }
    @Published private(set) var raiz = NodoArbol(id: "", nombre: "Total")
    @Published private(set) var porDia: [(dia: String, tokens: Tokens)] = []
    @Published private(set) var porModelo: [(modelo: String, tokens: Tokens)] = []
    @Published private(set) var suscripcion = EstadoSuscripcion()
    @Published private(set) var historial: [MuestraSuscripcion] = []
    @Published private(set) var escaneando = false
    @Published private(set) var progreso: (hechos: Int, total: Int) = (0, 0)
    @Published private(set) var ultimoRefresco: Date?
    @Published private(set) var error: String?
    @Published var expandidos: Set<String> = []

    /// Se publica solo para que la barra de menús vuelva a dibujarse y el reloj
    /// no se quede congelado entre escaneos.
    @Published private(set) var ahora = Date()

    private var almacen: Almacen?
    private var escaner: Escaner?
    private let lector = LectorSuscripcion()
    private let medidor = LectorMedidor()
    private var filas: [FilaUso] = []
    private var timer: Timer?
    private var latido: Timer?
    private var timerMedidor: Timer?
    private var inicioEscaneo: Date?

    /// Cada cuánto se le pregunta al endpoint por el medidor del plan. Lo fijó
    /// el dueño: 15 min alcanza para que la barra no mienta, sin golpear la
    /// API por gusto.
    static let cadenciaMedidor: TimeInterval = 15 * 60
    /// Última lectura que dio el endpoint, tal cual (sin la ventana estimada).
    private var lecturaEnLinea: EstadoSuscripcion?
    private var problemaMedidor: String?
    private var ultimoIntentoMedidor: Date?
    private var leyendoMedidor = false
    /// Token de `beginActivity`: mientras viva, macOS no duerme el proceso.
    private var actividad: NSObjectProtocol?

    init() {
        do {
            let a = try Almacen()
            almacen = a
            escaner = Escaner(almacen: a)
        } catch {
            self.error = error.localizedDescription
        }
        // macOS aplica App Nap a las apps sin ventana (LSUIElement) y estira sus
        // timers varios minutos: la barra se quedaba pegada hasta que el usuario
        // la tocaba. Esta actividad evita la suspensión sin impedir que el
        // equipo se duerma.
        actividad = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Mantener al día el uso en la barra de menús")

        refrescar()
        Task { await leerMedidor() }

        // Los transcripts cambian con cada respuesta y ~/.claude.json cuando
        // alguien abre /usage; 30 s mantiene la barra al día sin costo
        // perceptible. El medidor en línea va aparte, a su propia cadencia.
        timer = programar(cada: 30) { [weak self] in self?.refrescar() }
        timerMedidor = programar(cada: Self.cadenciaMedidor) { [weak self] in
            Task { await self?.leerMedidor() }
        }

        // Latido aparte del escaneo: aunque un refresco se demore o falle, el
        // reloj de la barra sigue avanzando.
        latido = programar(cada: 10) { [weak self] in self?.ahora = Date() }

        // Al despertar, los timers pueden venir atrasados: se fuerza una pasada.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refrescar()
                await self?.leerMedidor()
            }
        }
    }

    /// Le pregunta al endpoint por el medidor del plan y, si contesta, deja la
    /// lectura para que el próximo `refrescar()` la combine con lo demás.
    ///
    /// `forzado` salta la cadencia (botón ↻, toggle recién encendido, despertar)
    /// pero no el freno de 60 s: dos clics seguidos no son dos consultas. Los
    /// tropiezos no borran la última lectura buena —sigue siendo la más fresca
    /// que hay— y quedan en `problemaMedidor` para que el panel lo diga cuando
    /// importe.
    func leerMedidor(forzado: Bool = false) async {
        guard Preferencias.compartidas.medidorEnLinea else {
            // Apagado: se suelta la lectura y el panel vuelve al respaldo al tiro.
            lecturaEnLinea = nil
            problemaMedidor = nil
            refrescar()
            return
        }
        if leyendoMedidor { return }
        if let u = ultimoIntentoMedidor {
            let hace = Date().timeIntervalSince(u)
            if hace < 60 { return }
            if !forzado, hace < Self.cadenciaMedidor - 30 { return }
        }
        leyendoMedidor = true
        ultimoIntentoMedidor = Date()
        defer { leyendoMedidor = false }

        do {
            // El Llavero se lee con un proceso aparte: fuera del hilo principal.
            let cred = try await Task.detached(priority: .utility) { try Llavero.credencialClaude() }.value
            if let vence = cred.vence, vence < Date() {
                problemaMedidor = "la sesión de Claude Code venció \(Formato.hace(vence)); se renueva sola con tu próxima respuesta de Claude Code"
            } else {
                lecturaEnLinea = try await medidor.leer(token: cred.token, version: Self.version)
                problemaMedidor = nil
            }
        } catch {
            problemaMedidor = String(describing: error)
        }
        refrescar()
    }

    /// Versión del bundle, para el User-Agent. Sin bundle (previsualización) va "dev".
    private static let version: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

    /// Timer en modo `.common`: en el modo por omisión se detiene mientras hay
    /// un menú abierto o el usuario arrastra algo, y la barra se congela.
    private func programar(cada segundos: TimeInterval, _ accion: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: segundos, repeats: true) { _ in
            Task { @MainActor in accion() }
        }
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    /// Las líneas que se apilan en la barra de menús, cada una con su color
    /// según qué tan cerca del límite esté.
    ///
    /// Nunca más de dos: macOS da unos 22 pt de alto y una tercera línea sale
    /// recortada. Con tres ventanas activas, las dos últimas comparten línea.
    func lineasBarra(_ p: Preferencias) -> [LineaBarra] {
        var partes: [(texto: String, pct: Double?)] = []

        func agregar(_ etq: String, _ v: Ventana) {
            var t = p.mostrarEtiquetas ? etq + " " : ""
            // Sin porcentaje se muestran los tokens del bloque: reciclar el % de
            // la ventana anterior sería mentir con cara de dato fresco, pero
            // dejar un guion pelado no le sirve a nadie.
            t += v.porcentaje.map { "\(Int($0.rounded()))%" }
                ?? v.consumo.map { Formato.tokens($0) }
                ?? "—"
            // Cada ventana lleva su propio reloj: la de 5 h se libera en horas
            // y la semanal en días, y en ambas interesa saber cuánto falta.
            // El «~» avisa que el corte lo dedujimos nosotros, no Claude.
            //
            // Solo se anexa si el corte sigue en el futuro: `Formato.reloj` topa
            // en 0:00, así que una ventana ya vencida —la semanal o la del
            // modelo frontera, que no se estiman— dejaba un contador clavado en
            // cero, el mismo síntoma que este arreglo vino a resolver.
            if p.mostrarRestante, let r = v.reinicia, r > Date() {
                t += "  " + (v.estimada ? "~" : "") + Formato.reloj(r)
            }
            partes.append((t, v.porcentaje))
        }

        if p.ningunaVentana {
            if let peor = ventanas.max(by: { ($0.0.porcentaje ?? -1) < ($1.0.porcentaje ?? -1) }) {
                agregar(peor.1, peor.0)
            }
        } else {
            if p.mostrarSesion, let v = suscripcion.sesion { agregar("5h", v) }
            if p.mostrarSemanal, let v = suscripcion.semanal { agregar("7d", v) }
            if p.mostrarFrontera, let v = suscripcion.frontera {
                agregar(String(v.etiqueta.prefix(4)), v)
            }
        }
        guard !partes.isEmpty else { return [LineaBarra(texto: "—", color: Paleta.sinDato)] }

        // Sin porcentaje no hay semáforo que valga: el azul neutro de «esto no
        // es un nivel de límite», y no un verde que se leería como «vas holgado».
        func color(_ pct: Double?) -> Color { pct.map(Paleta.semaforo) ?? Paleta.sinDato }

        if partes.count <= 2 {
            return partes.map { LineaBarra(texto: $0.texto, color: color($0.pct)) }
        }
        let resto = partes.dropFirst()
        return [
            LineaBarra(texto: partes[0].texto, color: color(partes[0].pct)),
            LineaBarra(texto: resto.map(\.texto).joined(separator: " · "),
                       color: color(resto.compactMap(\.pct).max()))
        ]
    }

    /// Las tres ventanas presentes, con su nombre, para reutilizar en cálculos.
    private var ventanas: [(Ventana, String)] {
        [(suscripcion.sesion, "5h"), (suscripcion.semanal, "7d"), (suscripcion.frontera, "modelo")]
            .compactMap { v, n in v.map { ($0, n) } }
    }

    /// `manual`: el usuario tocó ↻, así que también se le pregunta al endpoint.
    func refrescar(manual: Bool = false) {
        guard let escaner, let almacen else { return }
        if manual { Task { await leerMedidor(forzado: true) } }
        // Si un escaneo quedó colgado, pasado un rato se intenta igual: antes
        // un solo escaneo trabado dejaba la barra muerta hasta reiniciar.
        if escaneando, let i = inicioEscaneo, Date().timeIntervalSince(i) < 180 { return }
        escaneando = true
        inicioEscaneo = Date()
        let lector = self.lector
        let enLinea = lecturaEnLinea, problema = problemaMedidor
        Task.detached(priority: .utility) { [weak self] in
            escaner.escanear { hechos, total in
                Task { @MainActor in self?.progreso = (hechos, total) }
            }
            let crudo = Coordinador.combinar(archivo: lector.leer(), enLinea: enLinea, problema: problema)
            // El histórico guarda lo que dijo la API, nunca lo que estimamos.
            if let crudo { almacen.guardarSuscripcion(crudo) }
            let estado = crudo.map { Coordinador.conSesionVigente($0, almacen: almacen) }
            let todas = almacen.filas()
            let muestras = almacen.muestrasSuscripcion()
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let estado { self.suscripcion = estado }
                self.filas = todas
                self.historial = muestras
                self.recomponer()
                self.escaneando = false
                self.ultimoRefresco = Date()
            }
        }
    }

    /// Elige entre lo que dejó Claude Code en `~/.claude.json` y lo que trajo el
    /// endpoint: **gana la lectura más nueva**. Normalmente es la del endpoint,
    /// pero si el usuario acaba de abrir `/usage`, Claude Code tiene una más
    /// fresca y no hay por qué ignorarla. El plan viene solo del archivo
    /// (`oauthAccount`); el endpoint no lo trae.
    nonisolated static func combinar(archivo: EstadoSuscripcion?, enLinea: EstadoSuscripcion?, problema: String?) -> EstadoSuscripcion? {
        var elegido: EstadoSuscripcion?
        let archivoMasNuevo = (archivo?.leidoEn ?? .distantPast) > (enLinea?.leidoEn ?? .distantPast)
        if let enLinea, !archivoMasNuevo {
            elegido = enLinea
            elegido?.plan = archivo?.plan ?? enLinea.plan
        } else {
            elegido = archivo
        }
        elegido?.problemaMedidor = problema
        return elegido
    }

    /// Sustituye la ventana de 5 h por la vigente cuando la de Claude ya venció.
    ///
    /// Con el medidor en línea esto casi no actúa: la lectura llega cada 15 min
    /// y su `resets_at` sigue vivo. Es el respaldo para cuando no hay lectura
    /// (sin red, sesión vencida, consulta apagada): ahí manda lo que dejó
    /// Claude Code —que solo escribe al abrir `/usage`— y su `resets_at` puede
    /// apuntar a una ventana cerrada, con lo que `Formato.reloj` se clava en
    /// `0:00`. Acá se reemplaza por el bloque que sí está abierto según la
    /// actividad local, con el porcentaje en desconocido —el consumo de la
    /// ventana nueva no lo sabe nadie fuera de la API—.
    nonisolated private static func conSesionVigente(_ e: EstadoSuscripcion, almacen: Almacen) -> EstadoSuscripcion {
        var e = e
        let ahora = Date()

        // Se carga desde el ancla, o desde 8 días atrás si el ancla es reciente
        // o no existe: alcanza de sobra para ubicar el bloque en curso.
        let ancla = e.sesion?.reinicia
        let piso = min(ancla?.timeIntervalSince1970 ?? .greatestFiniteMagnitude,
                       ahora.timeIntervalSince1970 - 8 * 86_400)
        let actividad = almacen.actividad(desde: Int(piso))
        e.ultimaActividad = actividad.last.map { Date(timeIntervalSince1970: TimeInterval($0.segundo)) }

        // Mientras el corte de Claude siga vivo manda él, que es el real; si ya
        // venció, se usa el bloque deducido de la actividad.
        let viva = ancla.map { $0 > ahora } ?? false
        let fin = viva ? ancla
                       : Bloques.abierto(actividad: actividad.map(\.segundo), ancla: ancla, ahora: ahora)?.fin

        // Lo único medible de la ventana: los tokens que pasaron por Claude Code
        // desde que se abrió. No es el porcentaje del plan —la ventana también la
        // gastan claude.ai, el escritorio y el móvil— pero es un número de verdad.
        let consumo = fin.map { f -> Int in
            let desdeBloque = f.timeIntervalSince1970 - Bloques.duracion
            return actividad.reduce(0) { $0 + (TimeInterval($1.segundo) >= desdeBloque ? $1.tokens : 0) }
        }

        if viva {
            e.sesion?.consumo = consumo
            return e
        }
        e.sesion = Ventana(porcentaje: nil,
                           reinicia: fin,
                           etiqueta: e.sesion?.etiqueta ?? "Sesión (5 h)",
                           estimada: true,
                           consumo: consumo)
        return e
    }

    private func recomponer() {
        let corte = rango.desde
        let visibles = corte == nil ? filas : filas.filter { $0.dia >= corte! }

        raiz = Arbol.construir(visibles)
        // Al abrir por primera vez se despliega la rama más pesada: ver un
        // árbol cerrado no dice nada.
        if expandidos.isEmpty, let mayor = raiz.hijos.first {
            expandidos.insert(mayor.id)
        }

        var dias: [String: Tokens] = [:]
        var modelos: [String: Tokens] = [:]
        for f in visibles {
            dias[f.dia, default: Tokens()] += f.tokens
            modelos[f.modelo, default: Tokens()] += f.tokens
        }
        porDia = dias.map { (dia: $0.key, tokens: $0.value) }.sorted { $0.dia < $1.dia }
        porModelo = modelos.map { (modelo: $0.key, tokens: $0.value) }
            .sorted { $0.tokens.total > $1.tokens.total }
    }

    func alternar(_ id: String) {
        if expandidos.contains(id) { expandidos.remove(id) } else { expandidos.insert(id) }
    }

    func abrirEnFinder(_ ruta: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ruta)
    }
}

/// Formateo compacto de cantidades grandes, en convención chilena (coma decimal).
enum Formato {
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch abs(d) {
        case 1_000_000_000...:  return coma(d / 1_000_000_000) + " MM"
        case 1_000_000...:      return coma(d / 1_000_000) + " M"
        case 1_000...:          return coma(d / 1_000) + " K"
        default:                return "\(n)"
        }
    }

    /// Miles con punto, como se escribe en Chile: 41.708.
    static func entero(_ n: Int) -> String {
        let s = String(n), inicio = s.hasPrefix("-") ? 1 : 0
        var out = "", cuenta = 0
        for c in s[s.index(s.startIndex, offsetBy: inicio)...].reversed() {
            if cuenta > 0, cuenta % 3 == 0 { out.append(".") }
            out.append(c); cuenta += 1
        }
        return (inicio == 1 ? "-" : "") + String(out.reversed())
    }

    static func coma(_ v: Double) -> String {
        String(format: v < 10 ? "%.2f" : "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// Sin decimales: en la barra de menús cada carácter cuenta.
    static func porcentajeCorto(_ v: Double) -> String {
        "\(Int(v.rounded()))%"
    }

    /// Cuánto falta, en la unidad que corresponde: pasado el día, los minutos
    /// no dicen nada, así que la ventana semanal muestra solo días ("5d"); bajo
    /// las 24 h —siempre el caso de la ventana de 5 h— van horas y minutos
    /// ("2:31").
    static func reloj(_ hasta: Date) -> String {
        let s = max(Int(hasta.timeIntervalSinceNow), 0)
        let dias = s / 86400
        if dias >= 1 { return "\(dias)d" }
        return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }

    static func porcentaje(_ v: Double) -> String {
        if v > 0, v < 0.1 { return "<0,1%" }
        return (v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v))
            .replacingOccurrences(of: ".", with: ",") + "%"
    }

    /// "en 2:45" — cuánto falta para que se libere una ventana. Con
    /// `estimado`, "en ~2:45": el corte lo dedujimos de la actividad local.
    static func restante(_ hasta: Date?, estimado: Bool = false) -> String {
        guard let hasta else { return "—" }
        if hasta.timeIntervalSinceNow <= 0 { return "ya" }
        return "en " + (estimado ? "~" : "") + reloj(hasta)
    }

    static func hace(_ fecha: Date?) -> String {
        guard let fecha else { return "nunca" }
        let s = Int(Date().timeIntervalSince(fecha))
        if s < 60 { return "hace \(s) s" }
        if s < 3600 { return "hace \(s / 60) min" }
        if s < 86400 { return "hace \(s / 3600) h" }
        return "hace \(s / 86400) d"
    }

    private static let meses = ["ene","feb","mar","abr","may","jun",
                                "jul","ago","sep","oct","nov","dic"]

    /// "2 de sep" — encabezado de la tarjeta del día.
    static func diaLargo(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), m >= 1, m <= 12, let d = Int(p[2]) else { return iso }
        return "\(d) de \(meses[m - 1])"
    }

    /// "07/09 23:41" — instante de una muestra del histórico de límites.
    static func fechaHora(_ ts: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    static func dia(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3 else { return iso }
        return "\(p[2])/\(p[1])"
    }
}
