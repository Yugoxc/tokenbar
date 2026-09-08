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
    let nombre: String      // último segmento
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
    var porcentaje: Double
    var reinicia: Date?
    var etiqueta: String
}

/// Foto del estado de la suscripción leída de ~/.claude.json.
struct EstadoSuscripcion: Equatable {
    var plan: String = "—"
    var sesion: Ventana?
    var semanal: Ventana?
    var frontera: Ventana?          // límite por modelo (weekly_scoped)
    var leidoEn: Date?              // cuándo Claude Code refrescó el dato

    var vacio: Bool { sesion == nil && semanal == nil && frontera == nil }
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
