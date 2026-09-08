import SwiftUI

@main
struct TokenBarApp: App {
    @StateObject private var co = Coordinador()

    var body: some Scene {
        MenuBarExtra {
            VistaPrincipal(co: co)
        } label: {
            // El ícono va acompañado del límite más apretado: de un vistazo se
            // sabe cuánto queda sin abrir el panel.
            HStack(spacing: 3) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                Text(co.resumenBarra)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
