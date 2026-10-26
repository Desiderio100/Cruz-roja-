// Llamadas de la Agenda de citas al backend (backend/src/rutas/citas.js).
// El cliente común (pedir, decodificar, el id del dispositivo) está en Comun/ClienteAPI.swift.

import Foundation

extension ClienteAPI {
    private static let fechaISOSimple = ISO8601DateFormatter()

    private static let soloFecha: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // Escribe la zona horaria del teléfono como texto, por ejemplo -06:00.
    static func zona(para fecha: Date) -> String {
        let segundos = TimeZone.current.secondsFromGMT(for: fecha)
        let signo = segundos < 0 ? "-" : "+"
        let total = abs(segundos)
        let horas = String(format: "%02d", total / 3600)
        let minutos = String(format: "%02d", (total % 3600) / 60)
        return "\(signo)\(horas):\(minutos)"
    }

    func horarios(delegacionId: Int, servicio: Servicio, fecha: Date) async throws -> [Horario] {
        let consulta = [
            URLQueryItem(name: "delegacion_id", value: String(delegacionId)),
            URLQueryItem(name: "servicio", value: servicio.rawValue),
            URLQueryItem(name: "fecha", value: ClienteAPI.soloFecha.string(from: fecha)),
            URLQueryItem(name: "zona", value: ClienteAPI.zona(para: fecha))
        ]
        let datos = try await pedir("GET", "/api/citas/horarios", consulta: consulta, conDispositivo: false)
        return try decodificar([Horario].self, datos)
    }

    func misCitas() async throws -> [Cita] {
        let datos = try await pedir("GET", "/api/citas")
        return try decodificar([Cita].self, datos)
    }

    func agendar(delegacionId: Int, servicio: Servicio, inicio: Date, nombre: String, telefono: String) async throws -> Cita {
        let cuerpo: [String: Any] = [
            "delegacion_id": delegacionId,
            "servicio": servicio.rawValue,
            "inicio": ClienteAPI.fechaISOSimple.string(from: inicio),
            "zona": ClienteAPI.zona(para: inicio),
            "nombre": nombre,
            "telefono": telefono
        ]
        let datos = try await pedir("POST", "/api/citas", cuerpo: cuerpo)
        return try decodificar(Cita.self, datos)
    }

    func cancelar(citaId: String) async throws {
        _ = try await pedir("POST", "/api/citas/\(citaId)/cancelar")
    }

    func reprogramar(citaId: String, inicio: Date) async throws -> Cita {
        let cuerpo: [String: Any] = [
            "inicio": ClienteAPI.fechaISOSimple.string(from: inicio),
            "zona": ClienteAPI.zona(para: inicio)
        ]
        let datos = try await pedir("POST", "/api/citas/\(citaId)/reprogramar", cuerpo: cuerpo)
        return try decodificar(Cita.self, datos)
    }
}
