import SwiftUI

struct VistaHistorico: View {
    @ObservedObject var co: Coordinador
    /// Ver `VistaArbol.plano`.
    var plano = false

    var body: some View {
        if plano { contenido } else { ScrollView { contenido } }
    }

    private var contenido: some View {
        VStack(alignment: .leading, spacing: 16) {
                Seccion(titulo: "Tokens por día")
                BarrasPorDia(datos: co.porDia)

                Seccion(titulo: "Por modelo")
                BarraModelos(datos: co.porModelo)

                Seccion(titulo: "Histórico de límites")
                if co.historial.count < 2 {
                    Text("Se va llenando a medida que el app observa cambios de porcentaje.")
                        .font(fuente(10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    SerieLimites(muestras: co.historial)
                }
        }
        .padding(10)
    }
}

// MARK: - Tarjeta flotante

/// Tarjeta que aparece sobre el gráfico al pasar el mouse. Evita tener que
/// mostrar una tabla completa: la info vive en el hover y no ocupa pantalla.
private struct Tarjeta<Contenido: View>: View {
    @ViewBuilder let contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: 2) { contenido }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.10))
            )
            .fixedSize()
            .allowsHitTesting(false)      // que no robe el hover de las barras
    }
}

@MainActor
private func filaDato(_ k: String, _ v: String) -> some View {
    HStack(spacing: 8) {
        Text(k).font(fuente(9)).foregroundStyle(.secondary)
        Spacer(minLength: 10)
        Text(v).font(fuente(9, .medium, mono: true))
    }
}

// MARK: - Barras por día

private struct BarrasPorDia: View {
    let datos: [(dia: String, tokens: Tokens)]
    @State private var sel: Int?

    private var maximo: Int { max(datos.map { $0.tokens.total }.max() ?? 1, 1) }

    var body: some View {
        if datos.isEmpty {
            Text("Sin datos en el rango").font(fuente(10)).foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(datos.enumerated()), id: \.element.dia) { i, d in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(i, d.tokens.total))
                                .frame(height: max(esc(3), esc(74) * CGFloat(d.tokens.total) / CGFloat(maximo)))
                                .contentShape(Rectangle())
                                .onHover { dentro in sel = dentro ? i : (sel == i ? nil : sel) }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                    if let i = sel, i < datos.count {
                        tarjeta(datos[i])
                            .offset(x: desplazamiento(i, ancho: geo.size.width), y: 0)
                    }
                }
            }
            .frame(height: esc(78))
            .onHover { if !$0 { sel = nil } }

            HStack {
                Text(Formato.diaLargo(datos.first!.dia))
                Spacer()
                Text(Formato.diaLargo(datos.last!.dia))
            }
            .font(fuente(9))
            .foregroundStyle(.tertiary)
            }
        }
    }

    private func color(_ i: Int, _ valor: Int) -> Color {
        // La barra apuntada se resalta; el resto varía con su magnitud.
        let intensidad = 0.35 + 0.5 * Double(valor) / Double(maximo)
        return sel == i ? Paleta.acento : Paleta.acento.opacity(intensidad)
    }

    /// Mantiene la tarjeta dentro del ancho visible.
    private func desplazamiento(_ i: Int, ancho: CGFloat) -> CGFloat {
        guard datos.count > 0 else { return 0 }
        let x = ancho * CGFloat(i) / CGFloat(datos.count)
        return min(max(x - 40, 0), max(ancho - 150, 0))
    }

    private func tarjeta(_ d: (dia: String, tokens: Tokens)) -> some View {
        Tarjeta {
            Text(Formato.diaLargo(d.dia)).font(fuente(10, .semibold))
            Text(Formato.tokens(d.tokens.total) + " tokens")
                .font(fuente(10, .medium, mono: true))
                .foregroundStyle(Paleta.acento)
            Divider().padding(.vertical, 1)
            filaDato("Entrada", Formato.tokens(d.tokens.entrada))
            filaDato("Salida", Formato.tokens(d.tokens.salida))
            filaDato("Caché escrita", Formato.tokens(d.tokens.cacheEscritura))
            filaDato("Caché leída", Formato.tokens(d.tokens.cacheLectura))
            filaDato("Mensajes", "\(d.tokens.mensajes)")
        }
    }
}

// MARK: - Modelos

/// Una sola barra apilada en vez de una tabla: el reparto se ve de un vistazo
/// y el detalle aparece al pasar el mouse.
private struct BarraModelos: View {
    let datos: [(modelo: String, tokens: Tokens)]
    @State private var sel: Int?

    private static let colores: [Color] = [
        Color(hue: 0.06, saturation: 0.72, brightness: 0.88),
        Color(hue: 0.55, saturation: 0.60, brightness: 0.80),
        Color(hue: 0.78, saturation: 0.48, brightness: 0.78),
        Color(hue: 0.42, saturation: 0.55, brightness: 0.72),
        Color(hue: 0.13, saturation: 0.70, brightness: 0.85),
        Color(hue: 0.00, saturation: 0.00, brightness: 0.60)
    ]

    private var total: Int { max(datos.reduce(0) { $0 + $1.tokens.total }, 1) }

    /// La leyenda va de a tres por fila.
    private var filasLeyenda: Int { max(1, (datos.count + 2) / 3) }

    static func corto(_ n: String) -> String {
        n.replacingOccurrences(of: "claude-", with: "")
         .replacingOccurrences(of: "-20251001", with: "")
    }

    var body: some View {
        if datos.isEmpty {
            Text("Sin datos en el rango").font(fuente(10)).foregroundStyle(.tertiary)
        } else {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 1.5) {
                            ForEach(Array(datos.enumerated()), id: \.element.modelo) { i, m in
                                Rectangle()
                                    .fill(Self.colores[i % Self.colores.count])
                                    .opacity(sel == nil || sel == i ? 1 : 0.35)
                                    .frame(width: max(2, (geo.size.width - CGFloat(datos.count) * 1.5)
                                                        * CGFloat(m.tokens.total) / CGFloat(total)))
                                    .onHover { dentro in sel = dentro ? i : (sel == i ? nil : sel) }
                            }
                        }
                        .frame(height: esc(16))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                        // Leyenda compacta: nombre y porcentaje, sin tabla.
                        FlujoLeyenda(items: Array(datos.enumerated()).map { i, m in
                            (Self.corto(m.modelo),
                             Self.colores[i % Self.colores.count],
                             Formato.porcentaje(Double(m.tokens.total) / Double(total) * 100))
                        })
                    }

                    if let i = sel, i < datos.count {
                        Tarjeta {
                            Text(Self.corto(datos[i].modelo)).font(fuente(10, .semibold))
                            Text(Formato.tokens(datos[i].tokens.total) + " tokens")
                                .font(fuente(10, .medium, mono: true))
                                .foregroundStyle(Self.colores[i % Self.colores.count])
                            Divider().padding(.vertical, 1)
                            filaDato("Del total", Formato.porcentaje(Double(datos[i].tokens.total) / Double(total) * 100))
                            filaDato("Salida", Formato.tokens(datos[i].tokens.salida))
                            filaDato("Caché leída", Formato.tokens(datos[i].tokens.cacheLectura))
                            filaDato("Mensajes", "\(datos[i].tokens.mensajes)")
                        }
                        .offset(x: min(max(desplazamiento(i, ancho: geo.size.width), 0),
                                       max(geo.size.width - 150, 0)),
                                y: 20)
                    }
                }
            }
            .frame(height: esc(23) + CGFloat(filasLeyenda) * esc(15))
            .onHover { if !$0 { sel = nil } }
        }
    }

    /// Deja la tarjeta a la altura del segmento apuntado.
    private func desplazamiento(_ i: Int, ancho: CGFloat) -> CGFloat {
        let previos = datos.prefix(i).reduce(0) { $0 + $1.tokens.total }
        return ancho * CGFloat(previos) / CGFloat(total) - 20
    }
}

/// Leyenda que salta de línea sola cuando no cabe.
private struct FlujoLeyenda: View {
    let items: [(String, Color, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { fila in
                HStack(spacing: 10) {
                    ForEach(fila..<min(fila + 3, items.count), id: \.self) { i in
                        HStack(spacing: 3) {
                            Circle().fill(items[i].1).frame(width: 5, height: 5)
                            Text(items[i].0).font(fuente(9)).foregroundStyle(.secondary)
                            Text(items[i].2)
                                .font(fuente(9, .medium, mono: true))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Serie de límites

private struct SerieLimites: View {
    let muestras: [MuestraSuscripcion]
    @State private var sel: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Referencias al 50 % y 100 %.
                    ForEach([0.0, 0.5], id: \.self) { f in
                        Rectangle().fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                            .offset(y: geo.size.height * CGFloat(f))
                    }
                    linea(\.semanal, color: Paleta.semaforo(muestras.last?.semanal ?? 0), geo: geo)
                    linea(\.frontera, color: Paleta.semaforo(muestras.last?.frontera ?? 0), geo: geo)
                    linea(\.sesion, color: Paleta.semaforo(muestras.last?.sesion ?? 0), geo: geo)

                    if let i = sel, i < muestras.count {
                        Tarjeta {
                            Text(Formato.fechaHora(muestras[i].ts)).font(fuente(10, .semibold))
                            Divider().padding(.vertical, 1)
                            filaDato("Sesión", muestras[i].sesion.map { Formato.porcentaje($0) } ?? "—")
                            filaDato("Semanal", muestras[i].semanal.map { Formato.porcentaje($0) } ?? "—")
                            filaDato(muestras[i].modeloFrontera?.isEmpty == false ? muestras[i].modeloFrontera! : "Frontera",
                                     muestras[i].frontera.map { Formato.porcentaje($0) } ?? "—")
                        }
                        .offset(x: min(max(geo.size.width * CGFloat(i) / CGFloat(max(muestras.count - 1, 1)) - 40, 0),
                                       max(geo.size.width - 130, 0)), y: 0)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { fase in
                    switch fase {
                    case .active(let p):
                        let f = max(min(p.x / max(geo.size.width, 1), 1), 0)
                        sel = Int((f * CGFloat(muestras.count - 1)).rounded())
                    case .ended: sel = nil
                    }
                }
            }
            .frame(height: esc(58))
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.03)))

            HStack(spacing: 10) {
                leyenda("Sesión", Paleta.semaforo(muestras.last?.sesion ?? 0))
                leyenda("Semanal", Paleta.semaforo(muestras.last?.semanal ?? 0))
                leyenda(muestras.last?.modeloFrontera?.isEmpty == false
                        ? muestras.last!.modeloFrontera! : "Frontera",
                        Paleta.semaforo(muestras.last?.frontera ?? 0))
                Spacer()
                Text("\(muestras.count) muestras").font(fuente(9)).foregroundStyle(.tertiary)
            }
        }
    }

    private func leyenda(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 5, height: 5)
            Text(t).font(fuente(9)).foregroundStyle(.secondary)
        }
    }

    private func linea(_ campo: KeyPath<MuestraSuscripcion, Double?>, color: Color, geo: GeometryProxy) -> some View {
        Path { p in
            let puntos = muestras.enumerated().compactMap { i, m -> CGPoint? in
                guard let v = m[keyPath: campo] else { return nil }
                let x = muestras.count <= 1 ? 0 : geo.size.width * CGFloat(i) / CGFloat(muestras.count - 1)
                return CGPoint(x: x, y: geo.size.height * (1 - CGFloat(min(v, 100)) / 100))
            }
            guard let primero = puntos.first else { return }
            p.move(to: primero)
            for pt in puntos.dropFirst() { p.addLine(to: pt) }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}
