import SwiftUI

/// Lo que muestra la tarjeta flotante, más el rectángulo del elemento que la
/// disparó (en coordenadas de la vista) para poder ubicarla sin tapar el mouse.
struct DatosTarjeta: Equatable {
    struct Fila: Equatable { let k: String; let v: String }

    var id: String
    var ancla: CGRect
    var titulo: String
    var valor: String
    var color: Color
    var filas: [Fila]
}

private let espacio = "historico"

struct VistaHistorico: View {
    @ObservedObject var co: Coordinador
    /// Sin ScrollView: solo para las previsualizaciones a PNG del script de
    /// desarrollo, que no saben dibujar contenido dentro de un ScrollView.
    var plano = false
    /// Tarjeta fijada a mano, solo para las previsualizaciones: el hover no se
    /// puede simular al renderizar a PNG.
    var demo: DatosTarjeta?

    @State private var tarjeta: DatosTarjeta?
    @State private var tamTarjeta: CGSize = .zero

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                if plano { contenido } else { ScrollView { contenido } }

                // La tarjeta vive acá, fuera del gráfico: así se dibuja sobre
                // todo lo demás y no corre ni un pixel del resto del panel.
                if let t = tarjeta {
                    TarjetaFlotante(datos: t)
                        .background(medidor)
                        .offset(x: x(t, en: g.size), y: y(t, en: g.size))
                        .opacity(tamTarjeta == .zero ? 0 : 1)
                        .allowsHitTesting(false)
                        .zIndex(100)
                }
            }
            .coordinateSpace(name: espacio)
            .onAppear { if let demo { tarjeta = demo } }
        }
    }

    private var contenido: some View {
        VStack(alignment: .leading, spacing: 16) {
            Seccion(titulo: "Tokens por día")
            BarrasPorDia(datos: co.porDia, tarjeta: $tarjeta)

            Seccion(titulo: "Por modelo")
            BarraModelos(datos: co.porModelo, tarjeta: $tarjeta)

            Seccion(titulo: "Histórico de límites")
            if co.historial.count < 2 {
                Text("Se va llenando a medida que el app observa cambios de porcentaje.")
                    .font(fuente(10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SerieLimites(muestras: co.historial, tarjeta: $tarjeta)
            }
        }
        .padding(10)
    }

    private var medidor: some View {
        GeometryReader { g in
            Color.clear.preference(key: ClaveTam.self, value: g.size)
        }
        .onPreferenceChange(ClaveTam.self) { tamTarjeta = $0 }
    }

    // MARK: - Ubicación

    /// Centrada sobre el elemento, sin salirse por los lados.
    private func x(_ t: DatosTarjeta, en tam: CGSize) -> CGFloat {
        let ideal = t.ancla.midX - tamTarjeta.width / 2
        return min(max(ideal, 4), max(tam.width - tamTarjeta.width - 4, 4))
    }

    /// Encima del elemento apuntado; si no cabe arriba, debajo. Nunca sobre el
    /// propio elemento, que es donde está el cursor.
    private func y(_ t: DatosTarjeta, en tam: CGSize) -> CGFloat {
        let arriba = t.ancla.minY - tamTarjeta.height - 10
        if arriba >= 4 { return arriba }
        let abajo = t.ancla.maxY + 10
        return min(abajo, max(tam.height - tamTarjeta.height - 4, 4))
    }
}

private struct ClaveTam: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - Tarjeta

private struct TarjetaFlotante: View {
    let datos: DatosTarjeta

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(datos.titulo).font(fuente(10, .semibold))
            Text(datos.valor)
                .font(fuente(10, .medium, mono: true))
                .foregroundStyle(datos.color)
            if !datos.filas.isEmpty {
                Divider().padding(.vertical, 1)
                ForEach(datos.filas, id: \.k) { f in
                    HStack(spacing: 8) {
                        Text(f.k).font(fuente(9)).foregroundStyle(.secondary)
                        Spacer(minLength: 10)
                        Text(f.v).font(fuente(9, .medium, mono: true))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
        .fixedSize()
    }
}

// MARK: - Barras por día

private struct BarrasPorDia: View {
    let datos: [(dia: String, tokens: Tokens)]
    @Binding var tarjeta: DatosTarjeta?

    private var maximo: Int { max(datos.map { $0.tokens.total }.max() ?? 1, 1) }
    private func alto(_ v: Int) -> CGFloat { max(esc(3), esc(74) * CGFloat(v) / CGFloat(maximo)) }

    var body: some View {
        if datos.isEmpty {
            Text("Sin datos en el rango").font(fuente(10)).foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    let marco = geo.frame(in: .named(espacio))
                    let ancho = (geo.size.width - CGFloat(max(datos.count - 1, 0)) * 2)
                              / CGFloat(max(datos.count, 1))
                    HStack(spacing: 2) {
                        ForEach(Array(datos.enumerated()), id: \.element.dia) { i, d in
                            // La columna entera acepta el mouse, no solo la barra:
                            // con barras de 3 px apuntar sería una tortura.
                            ZStack(alignment: .bottom) {
                                Color.clear
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color(i, d.tokens.total))
                                    .frame(height: alto(d.tokens.total))
                            }
                            .contentShape(Rectangle())
                            .onHover { dentro in
                                let id = "dia-\(d.dia)"
                                if dentro {
                                    let x = marco.minX + CGFloat(i) * (ancho + 2)
                                    tarjeta = DatosTarjeta(
                                        id: id,
                                        ancla: CGRect(x: x, y: marco.minY,
                                                      width: ancho, height: marco.height),
                                        titulo: Formato.diaLargo(d.dia),
                                        valor: Formato.tokens(d.tokens.total) + " tokens",
                                        color: Paleta.acento,
                                        filas: [
                                            .init(k: "Entrada", v: Formato.tokens(d.tokens.entrada)),
                                            .init(k: "Salida", v: Formato.tokens(d.tokens.salida)),
                                            .init(k: "Caché escrita", v: Formato.tokens(d.tokens.cacheEscritura)),
                                            .init(k: "Caché leída", v: Formato.tokens(d.tokens.cacheLectura)),
                                            .init(k: "Mensajes", v: Formato.entero(d.tokens.mensajes))
                                        ])
                                } else if tarjeta?.id == id {
                                    tarjeta = nil
                                }
                            }
                        }
                    }
                }
                .frame(height: esc(78))

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
        let intensidad = 0.35 + 0.5 * Double(valor) / Double(maximo)
        return tarjeta?.id == "dia-\(datos[i].dia)" ? Paleta.acento : Paleta.acento.opacity(intensidad)
    }
}

// MARK: - Modelos

/// Una sola barra apilada en vez de una tabla: el reparto se ve de un vistazo
/// y el detalle aparece al pasar el mouse.
private struct BarraModelos: View {
    let datos: [(modelo: String, tokens: Tokens)]
    @Binding var tarjeta: DatosTarjeta?

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
                let marco = geo.frame(in: .named(espacio))
                let util = geo.size.width - CGFloat(datos.count) * 1.5
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 1.5) {
                        ForEach(Array(datos.enumerated()), id: \.element.modelo) { i, m in
                            let ancho = max(2, util * CGFloat(m.tokens.total) / CGFloat(total))
                            Rectangle()
                                .fill(Self.colores[i % Self.colores.count])
                                .opacity(tarjeta == nil || tarjeta?.id == "mod-\(m.modelo)" ? 1 : 0.35)
                                .frame(width: ancho)
                                .onHover { dentro in
                                    let id = "mod-\(m.modelo)"
                                    if dentro {
                                        tarjeta = DatosTarjeta(
                                            id: id,
                                            ancla: CGRect(x: marco.minX + inicio(i, util: util),
                                                          y: marco.minY, width: ancho, height: esc(16)),
                                            titulo: Self.corto(m.modelo),
                                            valor: Formato.tokens(m.tokens.total) + " tokens",
                                            color: Self.colores[i % Self.colores.count],
                                            filas: [
                                                .init(k: "Del total", v: Formato.porcentaje(Double(m.tokens.total) / Double(total) * 100)),
                                                .init(k: "Salida", v: Formato.tokens(m.tokens.salida)),
                                                .init(k: "Caché leída", v: Formato.tokens(m.tokens.cacheLectura)),
                                                .init(k: "Mensajes", v: Formato.entero(m.tokens.mensajes))
                                            ])
                                    } else if tarjeta?.id == id {
                                        tarjeta = nil
                                    }
                                }
                        }
                    }
                    .frame(height: esc(16))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    FlujoLeyenda(items: Array(datos.enumerated()).map { i, m in
                        (Self.corto(m.modelo),
                         Self.colores[i % Self.colores.count],
                         Formato.porcentaje(Double(m.tokens.total) / Double(total) * 100))
                    })
                }
            }
            .frame(height: esc(23) + CGFloat(filasLeyenda) * esc(15))
        }
    }

    /// Dónde empieza el segmento i dentro de la barra apilada.
    private func inicio(_ i: Int, util: CGFloat) -> CGFloat {
        let previos = datos.prefix(i).reduce(0) { $0 + $1.tokens.total }
        return util * CGFloat(previos) / CGFloat(total) + CGFloat(i) * 1.5
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
    @Binding var tarjeta: DatosTarjeta?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                let marco = geo.frame(in: .named(espacio))
                ZStack(alignment: .topLeading) {
                    ForEach([0.0, 0.5], id: \.self) { f in
                        Rectangle().fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                            .offset(y: geo.size.height * CGFloat(f))
                    }
                    linea(\.semanal, color: Paleta.semaforo(muestras.last?.semanal ?? 0), geo: geo)
                    linea(\.frontera, color: Paleta.semaforo(muestras.last?.frontera ?? 0), geo: geo)
                    linea(\.sesion, color: Paleta.semaforo(muestras.last?.sesion ?? 0), geo: geo)

                    // Guía vertical en la muestra apuntada.
                    if let t = tarjeta, t.id.hasPrefix("lim-"), let i = Int(t.id.dropFirst(4)) {
                        Rectangle().fill(Color.primary.opacity(0.18))
                            .frame(width: 1, height: geo.size.height)
                            .offset(x: posX(i, ancho: geo.size.width))
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { fase in
                    switch fase {
                    case .active(let p):
                        let f = max(min(p.x / max(geo.size.width, 1), 1), 0)
                        let i = Int((f * CGFloat(muestras.count - 1)).rounded())
                        guard i >= 0, i < muestras.count else { return }
                        let m = muestras[i]
                        tarjeta = DatosTarjeta(
                            id: "lim-\(i)",
                            ancla: CGRect(x: marco.minX + posX(i, ancho: geo.size.width),
                                          y: marco.minY, width: 1, height: geo.size.height),
                            titulo: Formato.fechaHora(m.ts),
                            valor: m.semanal.map { "Semanal " + Formato.porcentaje($0) } ?? "—",
                            color: Paleta.semaforo(m.semanal ?? 0),
                            filas: [
                                .init(k: "Sesión", v: m.sesion.map { Formato.porcentaje($0) } ?? "—"),
                                .init(k: m.modeloFrontera?.isEmpty == false ? m.modeloFrontera! : "Frontera",
                                      v: m.frontera.map { Formato.porcentaje($0) } ?? "—")
                            ])
                    case .ended:
                        if tarjeta?.id.hasPrefix("lim-") == true { tarjeta = nil }
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

    private func posX(_ i: Int, ancho: CGFloat) -> CGFloat {
        muestras.count <= 1 ? 0 : ancho * CGFloat(i) / CGFloat(muestras.count - 1)
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
                return CGPoint(x: posX(i, ancho: geo.size.width),
                               y: geo.size.height * (1 - CGFloat(min(v, 100)) / 100))
            }
            guard let primero = puntos.first else { return }
            p.move(to: primero)
            for pt in puntos.dropFirst() { p.addLine(to: pt) }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}
