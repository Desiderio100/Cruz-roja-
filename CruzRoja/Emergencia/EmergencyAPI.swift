// Responsable del módulo de emergencia: Ayhan Ben Halima Martinez · A01647593
//
//  EmergencyAPI.swift
//  Llamadas de emergencia contra el backend:
//      POST  {apiBaseURL}/api/llamadas        crea la llamada y devuelve la delegación más cercana
//      PATCH {apiBaseURL}/api/llamadas/{id}   estado (finalizada…) y autorización de video
//      POST  {apiBaseURL}/api/llamadas/{id}/sala           acceso a la sala de audio y video
//      POST  {apiBaseURL}/api/llamadas/{id}/transcripcion  frases que la IA del teléfono transcribe
//      PUT   {apiBaseURL}/api/llamadas/{id}/ficha          campos de la ficha que la IA extrae
//
//  Cambios respecto a la versión original de Ayhan:
//   • La ubicación ya no se pide aquí: la entrega la app (Comun/Ubicacion.swift, una sola
//     para todo el equipo) y llega como parámetro.
//   • El id del dispositivo es el MISMO que usa Citas (Comun/Dispositivo.swift, guardado en
//     el Llavero), para que una persona sea un solo dispositivo en la base.
//   • Si ya hay nombre y teléfono guardados (Perfil), se envían con la llamada.
//   • La dirección del backend sale de Comun/Configuracion.swift.
//

import Foundation

struct EmergencySession: Codable, Sendable, Identifiable {
    let id: UUID
    let status: String
    let delegation: Delegation
}

struct Delegation: Codable, Sendable {
    let id: Int
    let name: String
    let phone: String
}

enum EmergencyAPIError: LocalizedError {
    case invalidResponse
    case locationDenied
    case locationUnavailable
    /// No se pudo hablar con el servidor (sin internet o backend apagado): se usa el respaldo.
    case sinConexion
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "La respuesta del servidor no es válida."
        case .locationDenied:
            "Necesitamos tu ubicación para encontrar la delegación más cercana."
        case .locationUnavailable:
            "No fue posible obtener tu ubicación. Inténtalo nuevamente."
        case .sinConexion:
            "No hay conexión con el servidor."
        case .server(let message):
            message
        }
    }
}

@MainActor
struct EmergencyAPI {
    static let shared = EmergencyAPI()

    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = Configuracion.apiBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func startCall(latitude: Double, longitude: Double) async throws -> EmergencySession {
        let nombre = Perfil.nombre.trimmingCharacters(in: .whitespaces)
        let payload = CreateCallRequest(
            deviceId: try await deviceId(),
            latitude: latitude,
            longitude: longitude,
            requesterName: nombre.isEmpty ? nil : nombre,
            requesterPhone: Perfil.telefonoValido(Perfil.telefono) ? Perfil.telefono : nil
        )

        var request = URLRequest(url: baseURL.appending(path: "api/llamadas"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await send(request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(EmergencySession.self, from: data)
    }

    func updateCall(
        id: UUID,
        status: String? = nil,
        videoAccepted: Bool? = nil
    ) async throws {
        let payload = UpdateCallRequest(
            deviceId: try await deviceId(),
            status: status,
            videoAccepted: videoAccepted
        )
        let path = "api/llamadas/\(id.uuidString.lowercased())"
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "PATCH"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await send(request)
        try validate(response: response, data: data)
    }

    func joinRoom(id: UUID) async throws -> AccesoSala {
        let dispositivo = try await deviceId()
        let request = try jsonRequest(
            path: "api/llamadas/\(id.uuidString.lowercased())/sala",
            method: "POST",
            body: DeviceOnlyRequest(deviceId: dispositivo)
        )
        let (data, response) = try await send(request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AccesoSala.self, from: data)
    }

    func sendTranscript(id: UUID, lines: [(texto: String, segundo: Int)]) async throws {
        let dispositivo = try await deviceId()
        let request = try jsonRequest(
            path: "api/llamadas/\(id.uuidString.lowercased())/transcripcion",
            method: "POST",
            body: TranscriptRequest(
                deviceId: dispositivo,
                lineas: lines.map { LineaTranscripcion(texto: $0.texto, momentoSeg: $0.segundo) }
            )
        )
        let (data, response) = try await send(request)
        try validate(response: response, data: data)
    }

    func sendFicha(id: UUID, ficha: FichaIAEnvio) async throws {
        let dispositivo = try await deviceId()
        let request = try jsonRequest(
            path: "api/llamadas/\(id.uuidString.lowercased())/ficha",
            method: "PUT",
            body: FichaRequest(deviceId: dispositivo, ficha: ficha)
        )
        let (data, response) = try await send(request)
        try validate(response: response, data: data)
    }

    private func jsonRequest<Body: Encodable>(path: String, method: String, body: Body) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Id del dispositivo, el mismo que usa Citas (se registra una sola vez en el servidor).
    private func deviceId() async throws -> String {
        try await Dispositivo.compartido.id().lowercased()
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw EmergencyAPIError.sinConexion
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmergencyAPIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error
            throw EmergencyAPIError.server(message ?? "No se pudo completar la solicitud.")
        }
    }
}

private struct CreateCallRequest: Encodable {
    let deviceId: String
    let latitude: Double
    let longitude: Double
    var accuracyMeters: Double? = nil
    let requesterName: String?
    let requesterPhone: String?
}

private struct UpdateCallRequest: Encodable {
    let deviceId: String
    let status: String?
    let videoAccepted: Bool?
}

struct AccesoSala: Decodable, Sendable {
    let url: String
    let token: String
}

struct FichaIAEnvio: Equatable, Sendable {
    var motivo: String?
    var numLesionados: Int?
    var lesionPrincipal: String?
    var lugar: String?
    var comentarios: String?

    var estaVacia: Bool {
        motivo == nil && numLesionados == nil && lesionPrincipal == nil && lugar == nil && comentarios == nil
    }
}

private struct DeviceOnlyRequest: Encodable {
    let deviceId: String
}

private struct LineaTranscripcion: Encodable {
    let texto: String
    let momentoSeg: Int
}

private struct TranscriptRequest: Encodable {
    let deviceId: String
    let lineas: [LineaTranscripcion]
}

private struct FichaRequest: Encodable {
    let deviceId: String
    let ficha: FichaIAEnvio

    func encode(to encoder: Encoder) throws {
        var contenedor = encoder.container(keyedBy: Claves.self)
        try contenedor.encode(deviceId, forKey: .deviceId)
        try contenedor.encodeIfPresent(ficha.motivo, forKey: .motivo)
        try contenedor.encodeIfPresent(ficha.numLesionados, forKey: .numLesionados)
        try contenedor.encodeIfPresent(ficha.lesionPrincipal, forKey: .lesionPrincipal)
        try contenedor.encodeIfPresent(ficha.lugar, forKey: .lugar)
        try contenedor.encodeIfPresent(ficha.comentarios, forKey: .comentarios)
    }

    private enum Claves: String, CodingKey {
        case deviceId, motivo, numLesionados, lesionPrincipal, lugar, comentarios
    }
}

private struct APIErrorResponse: Decodable {
    let error: String
}
