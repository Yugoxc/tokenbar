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

    /// Texto corto para la barra de menús: manda el límite más apretado.
    var resumenBarra: String {
        let candidatos = [suscripcion.sesion, suscripcion.semanal, suscripcion.frontera].compactMap { $0 }
        guard let peor = candidatos.max(by: { $0.porcentaje < $1.porcentaje }) else { return "—" }
        return "\(Int(peor.porcentaje.rounded()))%"
    }

    var colorBarra: Color {
        let candidatos = [suscripcion.sesion, suscripcion.semanal, suscripcion.frontera].compactMap { $0 }
        let peor = candidatos.map(\.porcentaje).max() ?? 0
        return Paleta.semaforo(peor)
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

    static func coma(_ v: Double) -> String {
        String(format: v < 10 ? "%.2f" : "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func porcentaje(_ v: Double) -> String {
        (v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v))
            .replacingOccurrences(of: ".", with: ",") + "%"
    }

    /// "en 3 h 12 min" — cuánto falta para que se libere una ventana.
    static func restante(_ hasta: Date?) -> String {
        guard let hasta else { return "—" }
        let s = Int(hasta.timeIntervalSinceNow)
        if s <= 0 { return "ya" }
        let h = s / 3600, m = (s % 3600) / 60
        if h >= 24 { return "en \(h / 24) d \(h % 24) h" }
        return h > 0 ? "en \(h) h \(m) min" : "en \(m) min"
    }

    static func hace(_ fecha: Date?) -> String {
        guard let fecha else { return "nunca" }
        let s = Int(Date().timeIntervalSince(fecha))
        if s < 60 { return "hace \(s) s" }
        if s < 3600 { return "hace \(s / 60) min" }
        if s < 86400 { return "hace \(s / 3600) h" }
        return "hace \(s / 86400) d"
    }

    static func dia(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3 else { return iso }
        return "\(p[2])/\(p[1])"
    }
}
