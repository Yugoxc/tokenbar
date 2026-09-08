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

    private var almacen: Almacen?
    private var escaner: Escaner?
    private let lector = LectorSuscripcion()
    private var filas: [FilaUso] = []
    private var timer: Timer?

    init() {
        do {
            let a = try Almacen()
            almacen = a
            escaner = Escaner(almacen: a)
        } catch {
            self.error = error.localizedDescription
        }
        refrescar()
        // Claude reescribe ~/.claude.json cada ~5 min y los transcripts en cada
        // respuesta; 30 s mantiene la barra al día sin costo perceptible.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refrescar() }
        }
    }

    /// Las líneas que se apilan en la barra de menús, cada una con su color
    /// según qué tan cerca del límite esté.
    ///
    /// Nunca más de dos: macOS da unos 22 pt de alto y una tercera línea sale
    /// recortada. Con tres ventanas activas, las dos últimas comparten línea.
    func lineasBarra(_ p: Preferencias) -> [LineaBarra] {
        var partes: [(texto: String, pct: Double)] = []

        func agregar(_ etq: String, _ v: Ventana) {
            var t = (p.mostrarEtiquetas ? etq + " " : "") + "\(Int(v.porcentaje.rounded()))%"
            // Cada ventana lleva su propio reloj: la de 5 h se libera en horas
            // y la semanal en días, y en ambas interesa saber cuánto falta.
            if p.mostrarRestante, let r = v.reinicia { t += "  " + Formato.reloj(r) }
            partes.append((t, v.porcentaje))
        }

        if p.ningunaVentana {
            if let peor = ventanas.max(by: { $0.0.porcentaje < $1.0.porcentaje }) {
                agregar(peor.1, peor.0)
            }
        } else {
            if p.mostrarSesion, let v = suscripcion.sesion { agregar("5h", v) }
            if p.mostrarSemanal, let v = suscripcion.semanal { agregar("7d", v) }
            if p.mostrarFrontera, let v = suscripcion.frontera {
                agregar(String(v.etiqueta.prefix(4)), v)
            }
        }
        guard !partes.isEmpty else { return [LineaBarra(texto: "—", color: .secondary)] }

        if partes.count <= 2 {
            return partes.map { LineaBarra(texto: $0.texto, color: Paleta.semaforo($0.pct)) }
        }
        let resto = partes.dropFirst()
        return [
            LineaBarra(texto: partes[0].texto, color: Paleta.semaforo(partes[0].pct)),
            LineaBarra(texto: resto.map(\.texto).joined(separator: " · "),
                       color: Paleta.semaforo(resto.map(\.pct).max() ?? 0))
        ]
    }

    /// Las tres ventanas presentes, con su nombre, para reutilizar en cálculos.
    private var ventanas: [(Ventana, String)] {
        [(suscripcion.sesion, "5h"), (suscripcion.semanal, "7d"), (suscripcion.frontera, "modelo")]
            .compactMap { v, n in v.map { ($0, n) } }
    }

    func refrescar() {
        guard !escaneando, let escaner, let almacen else { return }
        escaneando = true
        let lector = self.lector
        Task.detached(priority: .utility) { [weak self] in
            escaner.escanear { hechos, total in
                Task { @MainActor in self?.progreso = (hechos, total) }
            }
            let estado = lector.leer()
            if let estado { almacen.guardarSuscripcion(estado) }
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

    /// "en 2:45" — cuánto falta para que se libere una ventana.
    static func restante(_ hasta: Date?) -> String {
        guard let hasta else { return "—" }
        if hasta.timeIntervalSinceNow <= 0 { return "ya" }
        return "en " + reloj(hasta)
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
