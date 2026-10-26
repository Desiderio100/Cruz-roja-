import Foundation

enum Servicio: String, CaseIterable, Identifiable {
    case nutricion
    case psicologia

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .nutricion: return "Nutrición"
        case .psicologia: return "Psicología"
        }
    }
}

// Un horario libre que devuelve la API.
struct Horario: Decodable, Identifiable, Hashable {
    let inicio: Date
    let especialistasLibres: Int

    var id: Date { inicio }
}

// Una cita del usuario, tal como la devuelve la API.
struct Cita: Decodable, Identifiable, Hashable {
    let id: String
    let folio: String
    let servicio: String
    let inicio: Date
    let estado: String
    let delegacionId: Int?
    let delegacion: String?

    var nombreServicio: String {
        Servicio(rawValue: servicio)?.nombre ?? servicio.capitalized
    }

    var estaPospuesta: Bool {
        estado == "pospuesta"
    }
}

// ErrorAPI (el error con mensaje para el usuario) vive en Comun/ClienteAPI.swift.
