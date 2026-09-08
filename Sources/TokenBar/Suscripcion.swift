import Foundation

/// Lee el estado del plan desde ~/.claude.json.
///
/// Claude Code guarda ahí (`cachedUsageUtilization`) los porcentajes que vienen
/// en las cabeceras de la API y los refresca cada ~5 min mientras hay una sesión
/// viva. Leer ese archivo evita tocar credenciales o llamar a la API por fuera.
final class LectorSuscripcion: @unchecked Sendable {
    static let archivo = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude.json")

    private var ultimoMtime: Double = 0
    private var cache: EstadoSuscripcion?

    /// Nombres legibles para los tiers que reporta la cuenta.
    private static let planes: [String: String] = [
        "default_claude_max_20x": "Max 20×",
        "default_claude_max_5x": "Max 5×",
        "default_claude_pro": "Pro",
        "default_claude_team": "Team"
    ]

    func leer() -> EstadoSuscripcion? {
        let ruta = Self.archivo.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: ruta)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        if mtime == ultimoMtime, let cache { return cache }

        guard let datos = try? Data(contentsOf: Self.archivo),
              let raiz = try? JSONSerialization.jsonObject(with: datos) as? [String: Any]
        else { return cache }

        var estado = EstadoSuscripcion()

        if let cuenta = raiz["oauthAccount"] as? [String: Any] {
            let tier = cuenta["organizationRateLimitTier"] as? String ?? ""
            estado.plan = Self.planes[tier] ?? (cuenta["organizationType"] as? String ?? "—")
        }

        if let cache = raiz["cachedUsageUtilization"] as? [String: Any] {
            if let ms = cache["fetchedAtMs"] as? Double {
                estado.leidoEn = Date(timeIntervalSince1970: ms / 1000)
            }
            if let u = cache["utilization"] as? [String: Any] {
                estado.sesion = ventana(u["five_hour"], etiqueta: "Sesión (5 h)")
                estado.semanal = ventana(u["seven_day"], etiqueta: "Semanal")

                // El límite por modelo llega en `limits` como weekly_scoped; es
                // el que primero se agota cuando se trabaja con el modelo
                // frontera (hoy Fable/Opus según la cuenta).
                if let limites = u["limits"] as? [[String: Any]] {
                    for l in limites where (l["kind"] as? String) == "weekly_scoped" {
                        let modelo = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                        estado.frontera = Ventana(
                            porcentaje: (l["percent"] as? NSNumber)?.doubleValue ?? 0,
                            reinicia: fecha(l["resets_at"] as? String),
                            etiqueta: modelo ?? "Modelo frontera")
                        break
                    }
                }
            }
        }

        ultimoMtime = mtime
        cache = estado
        return estado
    }

    private func ventana(_ crudo: Any?, etiqueta: String) -> Ventana? {
        guard let d = crudo as? [String: Any],
              let pct = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
        return Ventana(porcentaje: pct, reinicia: fecha(d["resets_at"] as? String), etiqueta: etiqueta)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func fecha(_ s: String?) -> Date? {
        guard let s else { return nil }
        if let d = Self.iso.date(from: s) { return d }
        // Los timestamps traen microsegundos (6 dígitos) y el parser estricto
        // a veces los rechaza; se recorta a milisegundos y se reintenta.
        if let punto = s.firstIndex(of: "."), let mas = s.lastIndex(where: { $0 == "+" || $0 == "Z" }) {
            let frac = s[s.index(after: punto)..<mas].prefix(3)
            let recortado = s[s.startIndex..<punto] + "." + frac + s[mas...]
            return Self.iso.date(from: String(recortado))
        }
        return nil
    }
}
