// Cliente ÚNICO del backend para las pantallas que guardan datos de la persona
// (Registro, Permisos, Citas). Cada pantalla agrega sus llamadas en su carpeta con
// `extension ClienteAPI { ... }` (ver Citas/ClienteAPI+Citas.swift y Registro/ClienteAPI+Registro.swift).
//
// La app NUNCA habla con MySQL: todo pasa por el backend (Configuracion.apiBaseURL).

import Foundation

/// Error con el mensaje que se le muestra al usuario.
struct ErrorAPI: LocalizedError {
    let mensaje: String
    var estado: Int? = nil

    var errorDescription: String? { mensaje }
}

private struct RespuestaError: Decodable {
    let error: String
}

private struct RespuestaDispositivo: Decodable {
    let id: String
}

@MainActor
final class ClienteAPI {
    static let compartido = ClienteAPI()

    let decodificador: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let texto = try decoder.singleValueContainer().decode(String.self)
            let lector = ISO8601DateFormatter()
            lector.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let fecha = lector.date(from: texto) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "fecha no válida")
                )
            }
            return fecha
        }
        return d
    }()

    /// Crea el dispositivo en el servidor y devuelve su id (lo usa Comun/Dispositivo.swift).
    func registrarDispositivo() async throws -> String {
        let datos = try await pedir("POST", "/api/dispositivos", conDispositivo: false)
        return try decodificar(RespuestaDispositivo.self, datos).id
    }

    func decodificar<T: Decodable>(_ tipo: T.Type, _ datos: Data) throws -> T {
        do {
            return try decodificador.decode(tipo, from: datos)
        } catch {
            throw ErrorAPI(mensaje: "La respuesta del servidor no es válida")
        }
    }

    /// Hace una petición al backend y devuelve el cuerpo de la respuesta.
    /// `conDispositivo` agrega el header X-Dispositivo-Id (el servidor sabe quién eres).
    func pedir(
        _ metodo: String,
        _ ruta: String,
        consulta: [URLQueryItem] = [],
        cuerpo: [String: Any]? = nil,
        conDispositivo: Bool = true,
        reintento: Bool = false
    ) async throws -> Data {
        guard var componentes = URLComponents(string: Configuracion.urlBase + ruta) else {
            throw ErrorAPI(mensaje: "La dirección del servidor no es válida")
        }
        if !consulta.isEmpty { componentes.queryItems = consulta }
        guard let url = componentes.url else {
            throw ErrorAPI(mensaje: "La dirección del servidor no es válida")
        }

        var peticion = URLRequest(url: url)
        peticion.httpMethod = metodo
        peticion.timeoutInterval = 15
        if conDispositivo {
            let id = try await Dispositivo.compartido.id()
            peticion.setValue(id, forHTTPHeaderField: "X-Dispositivo-Id")
        }
        if let cuerpo {
            peticion.setValue("application/json", forHTTPHeaderField: "Content-Type")
            peticion.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)
        }

        let resultado: (Data, URLResponse)
        do {
            resultado = try await URLSession.shared.data(for: peticion)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw ErrorAPI(mensaje: "No hay conexión con el servidor")
        }

        guard let http = resultado.1 as? HTTPURLResponse else {
            throw ErrorAPI(mensaje: "No hay conexión con el servidor")
        }
        if (200..<300).contains(http.statusCode) { return resultado.0 }

        let mensaje = (try? decodificador.decode(RespuestaError.self, from: resultado.0))?.error ?? "Ocurrió un error"
        // Si el servidor no reconoce el dispositivo, se registra uno nuevo y se reintenta una vez.
        if conDispositivo, !reintento, http.statusCode == 400, mensaje == "dispositivo no registrado" {
            Dispositivo.compartido.olvidar()
            return try await pedir(metodo, ruta, consulta: consulta, cuerpo: cuerpo, conDispositivo: conDispositivo, reintento: true)
        }
        throw ErrorAPI(mensaje: mensaje, estado: http.statusCode)
    }
}
