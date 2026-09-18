import Foundation

/// Consulta el medidor real del plan: `GET api.anthropic.com/api/oauth/usage`.
///
/// Es el mismo endpoint que Claude Code llama al abrir `/usage`, y devuelve el
/// mismo objeto que después deja en `cachedUsageUtilization.utilization` de
/// `~/.claude.json`; por eso el cuerpo pasa por el mismo parser
/// (`LectorSuscripcion.estado(utilization:)`). Es el único host al que este
/// app se conecta.
///
/// Existe porque Claude Code **solo** escribe ese bloque cuando alguien abre
/// `/usage` o un panel de editor le pide el uso; la CLI en terminal no lo
/// refresca nunca por su cuenta (ver CLAUDE.md), así que sin esta consulta el
/// medidor se queda con la foto de días atrás.
final class LectorMedidor: @unchecked Sendable {
    static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    enum Fallo: Error, CustomStringConvertible {
        case http(Int)
        case red(String)
        case formato

        var description: String {
            switch self {
            case .http(401): return "la API rechazó la sesión de Claude Code (401)"
            case .http(429): return "la API pidió esperar (429)"
            case .http(let c): return "la API respondió HTTP \(c)"
            case .red(let m): return "sin conexión con api.anthropic.com (\(m))"
            case .formato: return "la API respondió algo que no es el medidor"
            }
        }
    }

    private let sesion: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Una lectura. El token se usa en esta petición y se suelta.
    func leer(token: String, version: String) async throws -> EstadoSuscripcion {
        var req = URLRequest(url: Self.url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Sin esta cabecera el endpoint OAuth no acepta el token de Claude Code.
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("TokenBar/\(version)", forHTTPHeaderField: "User-Agent")

        let datos: Data, resp: URLResponse
        do { (datos, resp) = try await sesion.data(for: req) }
        catch { throw Fallo.red(error.localizedDescription) }

        let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard codigo == 200 else { throw Fallo.http(codigo) }
        guard let u = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              var estado = LectorSuscripcion.estado(utilization: u), !estado.vacio
        else { throw Fallo.formato }

        estado.leidoEn = Date()
        estado.fuente = .endpoint
        return estado
    }
}
