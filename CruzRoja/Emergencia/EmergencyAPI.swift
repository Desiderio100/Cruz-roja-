// Responsable del módulo de emergencia: Ayhan Ben Halima Martinez · A01647593
//
//  EmergencyAPI.swift
//  Llamadas de emergencia contra el backend:
//      POST  {apiBaseURL}/api/llamadas        crea la llamada y devuelve la delegación más cercana
//      PATCH {apiBaseURL}/api/llamadas/{id}   estado (finalizada…) y autorización de video
//      POST  {apiBaseURL}/api/llamadas/{id}/transcripcion   frases transcritas en el teléfono (RF12)
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
    /// El servidor ya no acepta cambios de esta llamada (terminó o no es de este teléfono).
    case callClosed
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
        case .callClosed:
            "La llamada ya terminó."
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

    /// Manda al panel del operador las frases que el teléfono transcribió (solo texto, nunca audio).
    /// - Throws: `EmergencyAPIError.callClosed` si la llamada ya terminó en el servidor.
    func sendTranscript(id: UUID, lines: [LineaTranscrita]) async throws {
        let payload = TranscriptRequest(
            deviceId: try await deviceId(),
            lines: lines.map { TranscriptLine(text: $0.texto, second: $0.segundo) }
        )
        let path = "api/llamadas/\(id.uuidString.lowercased())/transcripcion"
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await send(request)
        if (response as? HTTPURLResponse)?.statusCode == 404 {
            throw EmergencyAPIError.callClosed
        }
        try validate(response: response, data: data)
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

/// Cuerpo de POST /api/llamadas/{id}/transcripcion. No es `private` para que las pruebas
/// comprueben que tiene el formato que espera el servidor.
struct TranscriptRequest: Encodable, Equatable {
    let deviceId: String
    let lines: [TranscriptLine]
}

struct TranscriptLine: Encodable, Equatable {
    let text: String
    let second: Int
}

private struct APIErrorResponse: Decodable {
    let error: String
}
