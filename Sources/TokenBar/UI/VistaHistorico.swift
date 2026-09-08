import SwiftUI

struct VistaHistorico: View {
    @ObservedObject var co: Coordinador

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Seccion(titulo: "Tokens por día")
                BarrasPorDia(datos: co.porDia)

                Seccion(titulo: "Por modelo")
                VStack(spacing: 3) {
                    let total = max(co.porModelo.reduce(0) { $0 + $1.tokens.total }, 1)
                    ForEach(co.porModelo, id: \.modelo) { m in
                        FilaModelo(nombre: m.modelo, tokens: m.tokens.total, total: total)
                    }
                }

                Seccion(titulo: "Histórico de límites")
                if co.historial.count < 2 {
                    Text("Se va llenando a medida que el app observa cambios de porcentaje.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    SerieLimites(muestras: co.historial)
                }
            }
            .padding(10)
        }
    }
}

private struct BarrasPorDia: View {
    let datos: [(dia: String, tokens: Tokens)]

    var body: some View {
        let maximo = max(datos.map { $0.tokens.total }.max() ?? 1, 1)
        if datos.isEmpty {
            Text("Sin datos en el rango").font(.system(size: 10)).foregroundStyle(.tertiary)
        } else {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(datos, id: \.dia) { d in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Paleta.acento.opacity(0.75))
                            .frame(height: max(2, 54 * CGFloat(d.tokens.total) / CGFloat(maximo)))
                        // Con muchos días las etiquetas no caben: se muestran salteadas.
                        if datos.count <= 10 || datos.firstIndex(where: { $0.dia == d.dia })! % 5 == 0 {
                            Text(Formato.dia(d.dia))
                                .font(.system(size: 7))
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(" ").font(.system(size: 7))
                        }
                    }
                    .help("\(d.dia): \(Formato.tokens(d.tokens.total)) tokens")
                }
            }
            .frame(height: 70, alignment: .bottom)
        }
    }
}

private struct FilaModelo: View {
    let nombre: String
    let tokens: Int
    let total: Int

    /// Nombres cortos: el id completo del modelo no aporta en una fila angosta.
    private var corto: String {
        nombre
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(corto).font(.system(size: 10)).lineLimit(1)
            Spacer(minLength: 4)
            Text(Formato.tokens(tokens))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.06))
                Capsule().fill(Paleta.acento.opacity(0.6))
                    .frame(width: max(1.5, 50 * CGFloat(tokens) / CGFloat(total)))
            }
            .frame(width: 50, height: 4)
            Text(Formato.porcentaje(Double(tokens) / Double(total) * 100))
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

/// Evolución de los tres límites en el tiempo, superpuestos.
private struct SerieLimites: View {
    let muestras: [MuestraSuscripcion]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack {
                    linea(\.semanal, color: Paleta.acento, geo: geo)
                    linea(\.frontera, color: Paleta.critico, geo: geo)
                    linea(\.sesion, color: Paleta.ok, geo: geo)
                }
            }
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.03))
            )
            HStack(spacing: 10) {
                leyenda("Sesión", Paleta.ok)
                leyenda("Semanal", Paleta.acento)
                leyenda(muestras.last?.modeloFrontera?.isEmpty == false
                        ? muestras.last!.modeloFrontera! : "Frontera", Paleta.critico)
                Spacer()
                Text("\(muestras.count) muestras").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private func leyenda(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 5, height: 5)
            Text(t).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func linea(_ campo: KeyPath<MuestraSuscripcion, Double?>, color: Color, geo: GeometryProxy) -> some View {
        Path { p in
            let puntos = muestras.enumerated().compactMap { i, m -> CGPoint? in
                guard let v = m[keyPath: campo] else { return nil }
                let x = muestras.count <= 1 ? 0 : geo.size.width * CGFloat(i) / CGFloat(muestras.count - 1)
                let y = geo.size.height * (1 - CGFloat(min(v, 100)) / 100)
                return CGPoint(x: x, y: y)
            }
            guard let primero = puntos.first else { return }
            p.move(to: primero)
            for pt in puntos.dropFirst() { p.addLine(to: pt) }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
}
