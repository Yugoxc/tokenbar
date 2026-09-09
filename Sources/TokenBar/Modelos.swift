import Foundation

/// Tokens de un tramo de uso. Se suma en todos los niveles del árbol.
struct Tokens: Equatable {
    var entrada = 0
    var salida = 0
    var cacheEscritura = 0
    var cacheLectura = 0
    var mensajes = 0

    /// El total que se reparte en porcentajes. Incluye caché porque es lo que
    /// realmente se factura contra los límites del plan.
    var total: Int { entrada + salida + cacheEscritura + cacheLectura }

    static func + (a: Tokens, b: Tokens) -> Tokens {
        Tokens(entrada: a.entrada + b.entrada,
               salida: a.salida + b.salida,
               cacheEscritura: a.cacheEscritura + b.cacheEscritura,
               cacheLectura: a.cacheLectura + b.cacheLectura,
               mensajes: a.mensajes + b.mensajes)
    }

    static func += (a: inout Tokens, b: Tokens) { a = a + b }
}

/// Fila agregada tal como vive en SQLite.
struct FilaUso {
    let dia: String        // YYYY-MM-DD en hora local
    let cwd: String
    let modelo: String
    var tokens: Tokens
}

/// Nodo del árbol de carpetas. Los hijos se arman al vuelo desde las filas.
final class NodoArbol: Identifiable {
    let id: String          // ruta absoluta completa
    var nombre: String      // último segmento
    var tokens = Tokens()
    var hijos: [NodoArbol] = []
    /// Tokens registrados en esta ruta exacta (sin contar subcarpetas).
    var propios = Tokens()

    init(id: String, nombre: String) {
        self.id = id
        self.nombre = nombre
    }

    var esHoja: Bool { hijos.isEmpty }
}

/// Una ventana de límite del plan (sesión de 5h, semanal, o por modelo).
struct Ventana: Equatable {
    /// `nil` cuando no se sabe: la ventana en curso empezó después de la última
    /// lectura que dio Claude, y el consumo de una ventana no lo sabe nadie más
    /// que la API. Vale más un guion que un número de otra ventana.
    var porcentaje: Double?
    var reinicia: Date?
    var etiqueta: String
    /// `reinicia` no lo dio Claude: se dedujo de la actividad local (ver
    /// `Bloques`). La UI lo marca con «~» para no hacerlo pasar por exacto.
    var estimada: Bool = false
}

/// Foto del estado de la suscripción leída de ~/.claude.json.
struct EstadoSuscripcion: Equatable {
    var plan: String = "—"
    var sesion: Ventana?
    var semanal: Ventana?
    var frontera: Ventana?          // límite por modelo (weekly_scoped)
    var leidoEn: Date?              // cuándo Claude Code refrescó el dato
    var ultimaActividad: Date?      // última respuesta de la API en los transcripts

    var vacio: Bool { sesion == nil && semanal == nil && frontera == nil }

    /// Claude solo reescribe su medidor mientras responde. Si se siguió
    /// trabajando bastante después de su última lectura, los porcentajes
    /// describen un consumo viejo y se quedaron cortos: hay que avisarlo.
    ///
    /// No basta con "el dato está añejo": si simplemente no se usó Claude, el
    /// dato viejo sigue siendo correcto y un aviso sería ruido.
    var rezagada: Bool {
        guard let leidoEn, let ultimaActividad else { return false }
        return ultimaActividad.timeIntervalSince(leidoEn) > 15 * 60
    }
}

/// Punto del histórico de suscripción.
struct MuestraSuscripcion: Identifiable {
    var id: Int { ts }
    let ts: Int
    let sesion: Double?
    let semanal: Double?
    let frontera: Double?
    let modeloFrontera: String?
}
