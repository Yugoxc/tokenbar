import SwiftUI

struct VistaPrincipal: View {
    @ObservedObject var co: Coordinador
    @ObservedObject var prefs = Preferencias.compartidas
    @State private var pestana = 0
    @State private var ajustesAbiertos = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecera
            Divider()
            aviso
            limites
            Divider()
            totales
            Divider()
            selector
            Divider()

            if pestana == 0 {
                VistaArbol(co: co)
            } else {
                VistaHistorico(co: co)
            }

            Divider()
            pie
        }
        .frame(width: esc(420), height: min(esc(600), 780))
    }

    // MARK: - Bloques

    private var cabecera: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.doc.horizontal")
                .foregroundStyle(Paleta.acento)
            Text("TokenBar").font(fuente(13, .semibold))
            Text(co.suscripcion.plan)
                .font(fuente(9, .medium))
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(Capsule().fill(Paleta.acento.opacity(0.15)))
                .foregroundStyle(Paleta.acento)
            Spacer()
            if co.escaneando {
                ProgressView().controlSize(.mini)
                if co.progreso.total > 0 {
                    Text("\(co.progreso.hechos)/\(co.progreso.total)")
                        .font(fuente(9, mono: true))
                        .foregroundStyle(.tertiary)
                }
            }
            Button { co.refrescar() } label: { Image(systemName: "arrow.clockwise").font(fuente(10)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Refrescar ahora")
            Button { ajustesAbiertos.toggle() } label: { Image(systemName: "gearshape").font(fuente(10)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Qué mostrar en la barra")
                .popover(isPresented: $ajustesAbiertos, arrowEdge: .bottom) {
                    VistaAjustes(co: co, prefs: prefs)
                }
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power").font(fuente(10)) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Salir")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    /// Aviso de que el medidor de Claude quedó atrás.
    ///
    /// Claude Code solo reescribe `cachedUsageUtilization` mientras responde, y
    /// a veces deja de hacerlo por horas: los porcentajes se quedan quietos y el
    /// reloj de la ventana de 5 h se clava. Sin este cartel, la barra parece
    /// simplemente rota.
    ///
    /// Son dos cosas distintas y no siempre pasan juntas, así que cada frase se
    /// arma sola: los porcentajes se quedan cortos si hubo trabajo DESPUÉS de la
    /// última lectura (`rezagada`), y la sesión pasa a estimarse solo cuando el
    /// corte que dio Claude ya venció (`sesion.estimada`). Antes el cartel
    /// prometía un reloj estimado que a veces no lo era, y callaba justo cuando
    /// sí lo era.
    private var textoAviso: String? {
        let viejos = co.suscripcion.rezagada
        let estimado = co.suscripcion.sesion?.estimada == true
        var frases: [String] = []
        if viejos {
            frases.append("Claude no refresca su medidor \(Formato.hace(co.suscripcion.leidoEn)): los porcentajes son de entonces y se quedaron cortos.")
        }
        if estimado {
            frases.append(viejos
                ? "En la sesión van los tokens que gastaste en Claude Code y el reloj estimado con tu actividad."
                : "La ventana de 5 h que dio Claude ya venció: en la sesión van los tokens que gastaste en Claude Code y el reloj estimado con tu actividad.")
        }
        return frases.isEmpty ? nil : frases.joined(separator: " ")
    }

    @ViewBuilder private var aviso: some View {
        if let texto = textoAviso {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(fuente(9))
                    .foregroundStyle(Paleta.aviso)
                Text(texto)
                    .font(fuente(9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Paleta.aviso.opacity(0.12))
            Divider()
        }
    }

    private var limites: some View {
        VStack(spacing: 8) {
            BarraLimite(titulo: "Sesión (5 h)", ventana: co.suscripcion.sesion)
            BarraLimite(titulo: "Semanal (todos los modelos)", ventana: co.suscripcion.semanal)
            BarraLimite(titulo: co.suscripcion.frontera.map { "Semanal · \($0.etiqueta)" } ?? "Semanal · modelo frontera",
                        ventana: co.suscripcion.frontera,
                        destacado: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
    }

    private var totales: some View {
        HStack(spacing: 0) {
            Metrica(titulo: "Tokens",
                    valor: Formato.tokens(co.raiz.tokens.total),
                    detalle: "\(Formato.entero(co.raiz.tokens.mensajes)) mensajes")
            Metrica(titulo: "Caché leída",
                    valor: Formato.tokens(co.raiz.tokens.cacheLectura),
                    detalle: porcentajeCache)
            Metrica(titulo: "Salida",
                    valor: Formato.tokens(co.raiz.tokens.salida),
                    detalle: "entrada \(Formato.tokens(co.raiz.tokens.entrada))")
            Metrica(titulo: "Carpetas",
                    valor: Formato.entero(cuentaHojas(co.raiz)),
                    detalle: "\(co.porModelo.count) modelos")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var selector: some View {
        HStack(spacing: 8) {
            Picker("", selection: $co.rango) {
                ForEach(Rango.allCases) { r in Text(r.rawValue).tag(r) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            Picker("", selection: $pestana) {
                Text("Carpetas").tag(0)
                Text("Histórico").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 140)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var pie: some View {
        HStack(spacing: 6) {
            if let e = co.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Paleta.critico)
                Text(e).lineLimit(1)
            } else {
                Text("Datos de Claude \(Formato.hace(co.suscripcion.leidoEn))")
            }
            Spacer()
            Text("Revisado \(Formato.hace(co.ultimoRefresco))")
        }
        .font(fuente(9))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10).padding(.vertical, 5)
    }

    // MARK: - Auxiliares

    private var porcentajeCache: String {
        let t = co.raiz.tokens.total
        guard t > 0 else { return "—" }
        return Formato.porcentaje(Double(co.raiz.tokens.cacheLectura) / Double(t) * 100) + " del total"
    }

    /// Cuenta rutas con consumo propio, que es lo que el usuario reconoce como
    /// "carpetas donde trabajé".
    private func cuentaHojas(_ n: NodoArbol) -> Int {
        (n.propios.total > 0 ? 1 : 0) + n.hijos.reduce(0) { $0 + cuentaHojas($1) }
    }
}
