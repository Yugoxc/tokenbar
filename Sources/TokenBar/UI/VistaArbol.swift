import SwiftUI

struct VistaArbol: View {
    @ObservedObject var co: Coordinador

    private var total: Int { max(co.raiz.tokens.total, 1) }

    /// Aplana el árbol respetando qué nodos están abiertos: así la lista solo
    /// materializa las filas visibles aunque el árbol completo sea grande.
    private var visibles: [(nodo: NodoArbol, nivel: Int)] {
        var out: [(NodoArbol, Int)] = []
        func recorrer(_ nodos: [NodoArbol], _ nivel: Int) {
            for n in nodos {
                out.append((n, nivel))
                if co.expandidos.contains(n.id) { recorrer(n.hijos, nivel + 1) }
            }
        }
        recorrer(co.raiz.hijos, 0)
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            if co.raiz.tokens.total == 0 {
                Text(co.escaneando ? "Leyendo transcripts…" : "Sin uso en este rango")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibles, id: \.nodo.id) { par in
                            FilaArbol(nodo: par.nodo, nivel: par.nivel, total: total, co: co)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct FilaArbol: View {
    let nodo: NodoArbol
    let nivel: Int
    let total: Int
    @ObservedObject var co: Coordinador
    @State private var sobre = false

    private var pct: Double { Double(nodo.tokens.total) / Double(total) * 100 }
    private var abierto: Bool { co.expandidos.contains(nodo.id) }

    var body: some View {
        HStack(spacing: 5) {
            // Zona del triángulo: siempre ocupa lugar para que los nombres
            // queden alineados aunque el nodo sea hoja.
            Group {
                if !nodo.esHoja {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(abierto ? 90 : 0))
                        .foregroundStyle(.secondary)
                } else {
                    Circle().fill(Color.primary.opacity(0.18)).frame(width: 3, height: 3)
                }
            }
            .frame(width: 10)

            Text(nodo.nombre)
                .font(.system(size: 11, weight: nivel == 0 ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            if sobre {
                Button {
                    co.abrirEnFinder(nodo.id)
                } label: {
                    Image(systemName: "folder").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Abrir en el Finder")
            }

            Text(Formato.tokens(nodo.tokens.total))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)

            // Barra proporcional: comparar carpetas de un vistazo.
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.06))
                Capsule()
                    .fill(Paleta.nivel(nivel))
                    .frame(width: max(1.5, 46 * min(pct, 100) / 100))
            }
            .frame(width: 46, height: 4)

            Text(Formato.porcentaje(pct))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.leading, CGFloat(nivel) * 12 + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(sobre ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { if !nodo.esHoja { withAnimation(.easeOut(duration: 0.12)) { co.alternar(nodo.id) } } }
        .onHover { sobre = $0 }
        .help(nodo.id + "  ·  " + detalle)
    }

    private var detalle: String {
        let t = nodo.tokens
        return "entrada \(Formato.tokens(t.entrada)) · salida \(Formato.tokens(t.salida)) · "
             + "caché escrita \(Formato.tokens(t.cacheEscritura)) · caché leída \(Formato.tokens(t.cacheLectura)) · "
             + "\(t.mensajes) mensajes"
    }
}
