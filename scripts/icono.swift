// Genera el AppIcon.icns dibujando con AppKit: evita depender de un editor
// gráfico y deja el ícono versionado como código.
import AppKit

func dibujar(_ lado: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: lado, pixelsHigh: lado,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(lado)

    // Fondo: cuadrado redondeado con el naranjo de Claude.
    let radio = s * 0.2237
    let fondo = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                             xRadius: radio, yRadius: radio)
    let grad = NSGradient(colors: [NSColor(srgbRed: 0.87, green: 0.49, blue: 0.30, alpha: 1),
                                   NSColor(srgbRed: 0.76, green: 0.35, blue: 0.20, alpha: 1)])!
    grad.draw(in: fondo, angle: -90)

    // Tres barras de largo decreciente: el árbol de carpetas por consumo.
    let anchoMax = s * 0.60, alto = s * 0.088, x = s * 0.20
    let largos: [CGFloat] = [1.0, 0.68, 0.40]
    for (i, f) in largos.enumerated() {
        let y = s * 0.62 - CGFloat(i) * (alto + s * 0.075)
        let r = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: anchoMax * f, height: alto),
                             xRadius: alto / 2, yRadius: alto / 2)
        NSColor(white: 1, alpha: 1.0 - Double(i) * 0.22).setFill()
        r.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let destino = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: destino, withIntermediateDirectories: true)
for (lado, nombre) in [(16,"icon_16x16"), (32,"icon_16x16@2x"), (32,"icon_32x32"),
                       (64,"icon_32x32@2x"), (128,"icon_128x128"), (256,"icon_128x128@2x"),
                       (256,"icon_256x256"), (512,"icon_256x256@2x"), (512,"icon_512x512"),
                       (1024,"icon_512x512@2x")] {
    let datos = dibujar(lado).representation(using: .png, properties: [:])!
    try! datos.write(to: URL(fileURLWithPath: "\(destino)/\(nombre).png"))
}
print("iconset listo en \(destino)")
