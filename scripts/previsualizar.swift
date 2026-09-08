// Renderiza las vistas reales a PNG para revisarlas sin abrir el app.
// Se compila con todos los fuentes menos TokenBarApp.swift (que trae el @main).
//   FUENTES=$(ls Sources/TokenBar/*.swift Sources/TokenBar/UI/*.swift | grep -v TokenBarApp)
//   cp scripts/previsualizar.swift /tmp/p/main.swift && swiftc -O $FUENTES /tmp/p/main.swift -o /tmp/prevtb
import SwiftUI
import AppKit

@MainActor
func guardar(_ vista: some View, _ nombre: String, en salida: String) {
    let r = ImageRenderer(content: vista)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("✗ \(nombre)"); return
    }
    try? png.write(to: URL(fileURLWithPath: "\(salida)/prev-\(nombre).png"))
    print("✓ \(nombre)")
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let co = Coordinador()
    let prefs = Preferencias.compartidas

    // El primer escaneo es asíncrono: se espera a que haya datos antes de dibujar.
    let limite = Date().addingTimeInterval(40)
    while co.raiz.tokens.total == 0, Date() < limite {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))

    // Se abren las primeras carpetas para que el árbol se vea con jerarquía.
    for hijo in co.raiz.hijos.prefix(2) {
        co.expandidos.insert(hijo.id)
        for nieto in hijo.hijos.prefix(3) { co.expandidos.insert(nieto.id) }
    }

    let salida = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"

    let fondo = Color(nsColor: .windowBackgroundColor)
    guardar(VistaPrincipal(co: co, prefs: prefs), "panel", en: salida)
    guardar(VistaArbol(co: co, plano: true).frame(width: esc(420)).background(fondo), "arbol", en: salida)
    guardar(VistaHistorico(co: co, plano: true)
                .frame(width: esc(420), height: esc(430)).background(fondo), "historico", en: salida)

    // Con una tarjeta fijada, para comprobar que flota sobre todo y no corre nada.
    let demo = DatosTarjeta(
        id: "demo",
        ancla: CGRect(x: esc(180), y: esc(90), width: esc(8), height: esc(40)),
        titulo: "3 de sep", valor: "285,7 M tokens", color: Paleta.acento,
        filas: [.init(k: "Entrada", v: "12,4 K"), .init(k: "Salida", v: "1,1 M"),
                .init(k: "Caché escrita", v: "8,9 M"), .init(k: "Caché leída", v: "275,7 M"),
                .init(k: "Mensajes", v: "1.204")])
    guardar(VistaHistorico(co: co, plano: true, demo: demo)
                .frame(width: esc(420), height: esc(430)).background(fondo), "historico-tarjeta", en: salida)
    guardar(VistaAjustes(co: co, prefs: prefs).background(fondo), "ajustes", en: salida)
    guardar(EtiquetaBarra(lineas: co.lineasBarra(prefs), conIcono: true)
                .padding(6).background(fondo), "barra", en: salida)

    print("datos: \(Formato.tokens(co.raiz.tokens.total)) · \(co.raiz.hijos.count) carpetas raíz "
          + "· escala panel \(prefs.escalaPanel)")
}
