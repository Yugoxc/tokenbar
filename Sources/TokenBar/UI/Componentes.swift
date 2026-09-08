import SwiftUI

enum Paleta {
    static let ok = Color(red: 0.30, green: 0.72, blue: 0.53)
    static let aviso = Color(red: 0.94, green: 0.71, blue: 0.24)
    static let alto = Color(red: 0.93, green: 0.52, blue: 0.24)
    static let critico = Color(red: 0.89, green: 0.35, blue: 0.35)
    static let acento = Color(red: 0.83, green: 0.45, blue: 0.28)   // naranjo Claude

    /// Un solo criterio de color para todo el app: barras, texto y la barra de menús.
    static func semaforo(_ pct: Double) -> Color {
        switch pct {
        case ..<50: return ok
        case ..<75: return aviso
        case ..<90: return alto
        default: return critico
        }
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
                    Text(Formato.porcentaje(v.porcentaje))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Paleta.semaforo(v.porcentaje))
                    Text(Formato.restante(v.reinicia))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("sin datos").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    if let v = ventana {
                        Capsule()
                            .fill(Paleta.semaforo(v.porcentaje))
                            .frame(width: max(2, geo.size.width * min(v.porcentaje, 100) / 100))
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
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(valor)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
            if let detalle {
                Text(detalle).font(.system(size: 9)).foregroundStyle(.tertiary)
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            if let accion {
                Button(action: accion) { Image(systemName: iconoAccion).font(.system(size: 9)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
