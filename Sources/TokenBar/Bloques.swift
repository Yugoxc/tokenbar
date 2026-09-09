import Foundation

/// La ventana de 5 h del plan, deducida de la actividad local.
///
/// Existe porque Claude Code deja de refrescar `cachedUsageUtilization` por
/// horas —se le vio más de un día entero—: cuando eso pasa, el `resets_at` que
/// trae el archivo apunta a una ventana ya cerrada y el reloj de la barra se
/// clava en `0:00`. Encadenando bloques de 5 h desde el último corte que Claude
/// sí confirmó se recupera un reloj que avanza.
///
/// Es una estimación, no la verdad. La ventana es de la cuenta completa y
/// también la abren claude.ai, la app de escritorio o el móvil, que no dejan
/// rastro en los transcripts: el bloque estimado puede empezar más tarde que el
/// real —nunca antes—, así que el tiempo que muestra es un techo.
enum Bloques {
    static let duracion: TimeInterval = 5 * 3600

    struct Bloque: Equatable {
        let inicio: Date
        let fin: Date
    }

    /// El bloque de 5 h que sigue abierto en `ahora`, o `nil` si no hubo
    /// actividad desde el último corte.
    ///
    /// - Parameters:
    ///   - actividad: instantes (epoch en segundos) con al menos una respuesta
    ///     de la API, en orden ascendente.
    ///   - ancla: fin de la última ventana que Claude confirmó. El primer
    ///     bloque nace con la primera actividad posterior a ese instante; así
    ///     la cadena no arrastra el error de los bloques anteriores. Sin ancla
    ///     se parte del último silencio de 5 h o más.
    static func abierto(actividad: [Int], ancla: Date?, ahora: Date) -> Bloque? {
        guard !actividad.isEmpty else { return nil }

        // Puntero que solo avanza: recorrer la lista una vez alcanza para toda
        // la cadena, aunque haya que saltar varios bloques ya cerrados.
        var i = 0
        func primera(desde t: TimeInterval) -> TimeInterval? {
            while i < actividad.count, TimeInterval(actividad[i]) < t { i += 1 }
            return i < actividad.count ? TimeInterval(actividad[i]) : nil
        }

        var inicio: TimeInterval?
        if let ancla {
            inicio = primera(desde: ancla.timeIntervalSince1970)
        } else {
            // Sin dato de Claude: el bloque vigente nace después del último
            // hueco de 5 h, que es cuando la ventana anterior alcanzó a vencer.
            var candidato = TimeInterval(actividad[0])
            var previo = candidato
            for s in actividad.dropFirst() {
                let t = TimeInterval(s)
                if t - previo >= duracion { candidato = t }
                previo = t
            }
            inicio = candidato
        }

        let corte = ahora.timeIntervalSince1970
        while let arranque = inicio {
            let fin = arranque + duracion
            if fin > corte {
                return Bloque(inicio: Date(timeIntervalSince1970: arranque),
                              fin: Date(timeIntervalSince1970: fin))
            }
            inicio = primera(desde: fin)
        }
        return nil
    }
}
