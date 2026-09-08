import SwiftUI

/// Qué se muestra en el ícono de la barra de menús. Vive en UserDefaults para
/// que sobreviva a reinicios y actualizaciones del app.
final class Preferencias: ObservableObject {
    static let compartidas = Preferencias()

    @Published var mostrarSesion: Bool { didSet { d.set(mostrarSesion, forKey: "mostrarSesion") } }
    @Published var mostrarSemanal: Bool { didSet { d.set(mostrarSemanal, forKey: "mostrarSemanal") } }
    @Published var mostrarFrontera: Bool { didSet { d.set(mostrarFrontera, forKey: "mostrarFrontera") } }
    @Published var mostrarRestante: Bool { didSet { d.set(mostrarRestante, forKey: "mostrarRestante") } }
    @Published var mostrarEtiquetas: Bool { didSet { d.set(mostrarEtiquetas, forKey: "mostrarEtiquetas") } }
    @Published var mostrarIcono: Bool { didSet { d.set(mostrarIcono, forKey: "mostrarIcono") } }

    /// Multiplican los tamaños de letra. El panel y la barra se ajustan por
    /// separado: en la barra manda la altura fija que da macOS.
    @Published var escalaPanel: Double { didSet { d.set(escalaPanel, forKey: "escalaPanel") } }
    @Published var escalaBarra: Double { didSet { d.set(escalaBarra, forKey: "escalaBarra") } }

    private let d = UserDefaults.standard

    private init() {
        // Por defecto: sesión y semanal, con el tiempo que falta para que la
        // ventana de 5 h se libere. Es lo que se mira más seguido.
        d.register(defaults: [
            "mostrarSesion": true, "mostrarSemanal": true, "mostrarFrontera": false,
            "mostrarRestante": true, "mostrarEtiquetas": false, "mostrarIcono": true,
            "escalaPanel": 1.25, "escalaBarra": 1.15
        ])
        // La barra se pidió sin los prefijos «5h»/«7d»: se apagan una sola vez
        // para no pisar la elección si más adelante se vuelven a encender.
        if !d.bool(forKey: "migracionSinEtiquetas") {
            d.set(false, forKey: "mostrarEtiquetas")
            d.set(true, forKey: "migracionSinEtiquetas")
        }
        mostrarSesion = d.bool(forKey: "mostrarSesion")
        mostrarSemanal = d.bool(forKey: "mostrarSemanal")
        mostrarFrontera = d.bool(forKey: "mostrarFrontera")
        mostrarRestante = d.bool(forKey: "mostrarRestante")
        mostrarEtiquetas = d.bool(forKey: "mostrarEtiquetas")
        mostrarIcono = d.bool(forKey: "mostrarIcono")
        escalaPanel = d.double(forKey: "escalaPanel")
        escalaBarra = d.double(forKey: "escalaBarra")
    }

    /// Si el usuario apaga las tres ventanas, igual mostramos algo útil.
    var ningunaVentana: Bool { !mostrarSesion && !mostrarSemanal && !mostrarFrontera }
}
