import SwiftUI

/// Fuente del panel aplicando la escala elegida por el usuario.
///
/// Todas las vistas del panel piden su tipografía por acá; como la raíz
/// (`VistaPrincipal`) observa `Preferencias`, cambiar la escala vuelve a dibujar
/// todo el árbol de vistas con el tamaño nuevo.
@MainActor
func fuente(_ tam: CGFloat, _ peso: Font.Weight = .regular, mono: Bool = false) -> Font {
    let f = Font.system(size: tam * Preferencias.compartidas.escalaPanel, weight: peso)
    return mono ? f.monospacedDigit() : f
}

/// Escala una medida fija (alto de un gráfico, ancho de una columna) junto con
/// la letra, para que el diseño no se apriete al subir el tamaño.
@MainActor
func esc(_ v: CGFloat) -> CGFloat { v * Preferencias.compartidas.escalaPanel }

enum Paleta {
    static let ok = Color(red: 0.30, green: 0.72, blue: 0.53)
    static let aviso = Color(red: 0.94, green: 0.71, blue: 0.24)
    static let alto = Color(red: 0.93, green: 0.52, blue: 0.24)
    static let critico = Color(red: 0.89, green: 0.35, blue: 0.35)
    static let acento = Color(red: 0.83, green: 0.45, blue: 0.28)   // naranjo Claude

    /// Verde → amarillo → rojo de forma continua: el color se mueve con el
    /// porcentaje en vez de saltar por tramos, así se nota que va subiendo.
    static func semaforo(_ pct: Double) -> Color {
        let p = min(max(pct, 0), 100) / 100
        // Hue 0,33 (verde) → 0,0 (rojo), lineal: a mitad de camino ya se ve
        // amarillo, que es lo que se espera de un semáforo.
        // El brillo baja un poco en la zona amarilla, donde más deslumbra.
        let hue = 0.33 * (1 - p)
        let brillo = 0.88 - 0.10 * (1 - abs(p - 0.5) * 2)
        return Color(hue: hue, saturation: 0.85, brightness: brillo)
    }

    /// Tonos estables por profundidad del árbol, para que la jerarquía se lea.
    static func nivel(_ n: Int) -> Color {
        acento.opacity(max(0.25, 0.85 - Double(n) * 0.18))
    }
}

/// Barra de una ventana de límite: nombre, porcentaje y cuándo se libera.
struct BarraLimite: View {
    let titulo: String
    let ventana: Ventana?
    var destacado = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(titulo)
                    .font(.system(size: 11, weight: destacado ? .semibold : .regular))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let v = ventana {
                    if let pct = v.porcentaje {
                        Text(Formato.porcentaje(pct))
                            .font(fuente(11, .semibold, mono: true))
                            .foregroundStyle(Paleta.semaforo(pct))
                    } else {
                        Text("—")
                            .font(fuente(11, .semibold, mono: true))
                            .foregroundStyle(.tertiary)
                            .help("Claude no ha reportado el consumo de esta ventana")
                    }
                    Text(Formato.restante(v.reinicia, estimado: v.estimada))
                        .font(fuente(10))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("sin datos").font(fuente(10)).foregroundStyle(.tertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    // Sin porcentaje no se pinta nada: una barra a cero se
                    // leería como «no has gastado», que es justo lo que no se sabe.
                    if let pct = ventana?.porcentaje {
                        Capsule()
                            .fill(Paleta.semaforo(pct))
                            .frame(width: max(2, geo.size.width * min(pct, 100) / 100))
                    }
                }
            }
            .frame(height: 5)
        }
    }
}

/// Métrica compacta para la fila de totales.
struct Metrica: View {
    let titulo: String
    let valor: String
    var detalle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(titulo)
                .font(fuente(9, .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(valor)
                .font(fuente(13, .semibold, mono: true))
            if let detalle {
                Text(detalle).font(fuente(9)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Encabezado de sección con línea divisoria.
struct Seccion: View {
    let titulo: String
    var accion: (() -> Void)? = nil
    var iconoAccion = "arrow.clockwise"

    var body: some View {
        HStack(spacing: 6) {
            Text(titulo)
                .font(fuente(10, .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            if let accion {
                Button(action: accion) { Image(systemName: iconoAccion).font(fuente(9)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
