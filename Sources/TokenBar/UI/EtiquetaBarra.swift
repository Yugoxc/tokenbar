import SwiftUI

struct LineaBarra: Identifiable {
    let id = UUID()
    let texto: String
    let color: Color
}

/// Lo que se dibuja en la barra de menús: una o varias líneas apiladas.
///
/// El tamaño baja según cuántas líneas haya, para no pasarse de los ~22 pt de
/// alto que da macOS.
struct EtiquetaBarra: View {
    let lineas: [LineaBarra]
    var conIcono = true

    /// Con dos líneas la escala se topea: pasado ese punto macOS recorta la
    /// imagen contra el alto de la barra de menús.
    private var escala: CGFloat {
        let e = Preferencias.compartidas.escalaBarra
        return lineas.count > 1 ? min(e, 1.25) : e
    }

    private var tamano: CGFloat { (lineas.count > 1 ? 8.5 : 12) * escala }

    var body: some View {
        HStack(spacing: 3) {
            if conIcono {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: (lineas.count > 1 ? 11 : 13) * escala))
                    .foregroundStyle(lineas.first?.color ?? .primary)
            }
            VStack(alignment: .leading, spacing: lineas.count > 2 ? 0 : 1) {
                ForEach(lineas) { l in
                    Text(l.texto)
                        .font(.system(size: tamano, weight: .semibold).monospacedDigit())
                        .foregroundStyle(l.color)
                        .fixedSize()
                }
            }
        }
    }

    /// MenuBarExtra convierte la vista del label en imagen template y le quita
    /// el color; renderizándola nosotros con `isTemplate = false` el semáforo
    /// se conserva en la barra.
    @MainActor
    static func imagen(_ lineas: [LineaBarra], conIcono: Bool) -> NSImage {
        let render = ImageRenderer(content: EtiquetaBarra(lineas: lineas, conIcono: conIcono))
        render.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let img = render.nsImage else { return NSImage() }
        img.isTemplate = false
        return img
    }
}
