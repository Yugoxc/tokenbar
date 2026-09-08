import SwiftUI

@main
struct TokenBarApp: App {
    @StateObject private var co = Coordinador()
    @StateObject private var prefs = Preferencias.compartidas

    var body: some Scene {
        MenuBarExtra {
            VistaPrincipal(co: co, prefs: prefs)
        } label: {
            // Se renderiza a imagen para conservar el color del semáforo, que
            // el label estándar de MenuBarExtra descartaría.
            Image(nsImage: EtiquetaBarra.imagen(co.lineasBarra(prefs), conIcono: prefs.mostrarIcono))
        }
        .menuBarExtraStyle(.window)
    }
}
