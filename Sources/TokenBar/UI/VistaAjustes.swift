import SwiftUI

/// Qué mostrar en la barra de menús. Se abre desde el engranaje de la cabecera.
struct VistaAjustes: View {
    @ObservedObject var co: Coordinador
    @ObservedObject var prefs: Preferencias

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Qué mostrar en la barra")
                .font(fuente(11, .semibold))

            VStack(alignment: .leading, spacing: 5) {
                fila("Sesión (5 h)", $prefs.mostrarSesion, co.suscripcion.sesion)
                fila("Semanal", $prefs.mostrarSemanal, co.suscripcion.semanal)
                fila(co.suscripcion.frontera?.etiqueta ?? "Modelo frontera",
                     $prefs.mostrarFrontera, co.suscripcion.frontera)
            }

            Divider()

            Toggle(isOn: $prefs.mostrarRestante) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tiempo hasta el reinicio").font(fuente(11))
                    Text("Cuánto falta para que se libere cada ventana")
                        .font(fuente(9)).foregroundStyle(.tertiary)
                }
            }
            Toggle(isOn: $prefs.mostrarEtiquetas) {
                Text("Etiquetas «5h» y «7d»").font(fuente(11))
            }
            Toggle(isOn: $prefs.mostrarIcono) {
                Text("Ícono del medidor").font(fuente(11))
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                deslizador("Tamaño de letra", $prefs.escalaPanel, 0.85...1.9)
                deslizador("Tamaño en la barra", $prefs.escalaBarra, 0.85...1.6)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text("VISTA PREVIA")
                    .font(fuente(9, .medium)).foregroundStyle(.tertiary)
                EtiquetaBarra(lineas: co.lineasBarra(prefs), conIcono: prefs.mostrarIcono)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
            }

            if prefs.ningunaVentana {
                Text("Sin ninguna marcada se muestra el límite más apretado.")
                    .font(fuente(9)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .padding(12)
        .frame(width: esc(250))
    }

    /// Control de tamaño con su valor en porcentaje al lado.
    private func deslizador(_ titulo: String, _ valor: Binding<Double>,
                            _ rango: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(titulo).font(fuente(11))
                Spacer()
                Text("\(Int((valor.wrappedValue * 100).rounded()))%")
                    .font(fuente(10, .medium, mono: true))
                    .foregroundStyle(.secondary)
            }
            Slider(value: valor, in: rango, step: 0.05)
                .controlSize(.mini)
        }
    }

    private func fila(_ titulo: String, _ enlace: Binding<Bool>, _ v: Ventana?) -> some View {
        Toggle(isOn: enlace) {
            HStack(spacing: 5) {
                Text(titulo).font(fuente(11))
                if let v {
                    Text(v.porcentaje.map { Formato.porcentaje($0) } ?? "—")
                        .font(fuente(10, .medium, mono: true))
                        .foregroundStyle(v.porcentaje.map { Paleta.semaforo($0) } ?? .secondary)
                    Text("· libera \(Formato.restante(v.reinicia, estimado: v.estimada))")
                        .font(fuente(9)).foregroundStyle(.tertiary)
                } else {
                    Text("sin datos").font(fuente(9)).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
