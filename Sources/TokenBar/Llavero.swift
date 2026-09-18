import Foundation

/// La sesión OAuth de Claude Code, leída del Llavero de macOS.
///
/// Claude Code guarda su sesión en el ítem genérico «Claude Code-credentials»
/// como un JSON con `claudeAiOauth.accessToken` y `expiresAt` (epoch en ms).
/// Este app la usa **solo para leer el medidor del plan** (ver `Medidor`): el
/// token vive el tiempo de la consulta, no se guarda, no se registra en ningún
/// log y **jamás se renueva desde acá** —renovar rota el refresh token y
/// dejaría a Claude Code con uno inválido—. Cuando venció, se espera a que
/// Claude Code lo renueve en su próxima respuesta.
///
/// Se lee con `/usr/bin/security` en vez de `SecItemCopyMatching` a propósito:
/// el Llavero evalúa la lista de acceso contra el proceso que pide, y esa
/// herramienta ya está autorizada en el ítem (es con la que Claude Code lo
/// escribe). Con la API directa, la firma ad-hoc de este app cambia en cada
/// compilación y macOS volvería a pedir permiso con cada reinstalación.
enum Llavero {
    struct Credencial {
        let token: String
        /// Hasta cuándo sirve el token; `nil` si el JSON no lo trae.
        let vence: Date?
    }

    enum Fallo: Error, CustomStringConvertible {
        case sinItem
        case sinSesion
        case lectura(String)

        var description: String {
            switch self {
            case .sinItem: return "no hay sesión de Claude Code en el Llavero (¿`claude /login`?)"
            case .sinSesion: return "el ítem del Llavero no trae la sesión de claude.ai"
            case .lectura(let m): return "no se pudo leer el Llavero: \(m)"
            }
        }
    }

    static let servicio = "Claude Code-credentials"

    /// Lectura sincrónica (~50 ms): llamar fuera del hilo principal.
    static func credencialClaude() throws -> Credencial {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", servicio, "-w"]
        let salida = Pipe(), errores = Pipe()
        p.standardOutput = salida
        p.standardError = errores
        do { try p.run() } catch { throw Fallo.lectura(error.localizedDescription) }
        // Se drena antes de esperar: con el pipe lleno el proceso no termina.
        let datos = salida.fileHandleForReading.readDataToEndOfFile()
        _ = errores.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Fallo.sinItem }

        guard let raiz = try? JSONSerialization.jsonObject(with: datos) as? [String: Any],
              let oauth = raiz["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw Fallo.sinSesion }

        let vence = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credencial(token: token, vence: vence)
    }
}
