import AppIntents
import Foundation

enum ServicioSiri: String, AppEnum {
    case nutricion
    case psicologia

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Servicio"

    static var caseDisplayRepresentations: [ServicioSiri: DisplayRepresentation] = [
        .nutricion: "Nutrición",
        .psicologia: "Psicología"
    ]

    var servicio: Servicio {
        switch self {
        case .nutricion: return .nutricion
        case .psicologia: return .psicologia
        }
    }
}

enum AppMapaSiri: String, AppEnum {
    case apple
    case google
    case waze

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Aplicación de mapas"

    static var caseDisplayRepresentations: [AppMapaSiri: DisplayRepresentation] = [
        .apple: "Apple Maps",
        .google: "Google Maps",
        .waze: "Waze"
    ]

    var aplicacion: AppMapa {
        switch self {
        case .apple: return .apple
        case .google: return .google
        case .waze: return .waze
        }
    }
}

struct CitaEntidad: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Cita"
    static var defaultQuery = CitaEntidadQuery()

    var id: String
    var texto: String
    var folio: String
    var servicio: String
    var inicio: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(texto)", subtitle: "Folio \(folio)")
    }
}

struct CitaEntidadQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CitaEntidad] {
        try await DatosSiri.citasCancelables().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CitaEntidad] {
        try await DatosSiri.citasCancelables()
    }

    func entities(matching string: String) async throws -> [CitaEntidad] {
        try await DatosSiri.citasCancelables().filter { DatosSiri.coincide($0.texto, con: string) }
    }
}

struct CitaPospuestaEntidad: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Cita pospuesta"
    static var defaultQuery = CitaPospuestaEntidadQuery()

    var id: String
    var texto: String
    var folio: String
    var servicio: String
    var delegacionId: Int?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(texto)", subtitle: "Folio \(folio)")
    }
}

struct CitaPospuestaEntidadQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CitaPospuestaEntidad] {
        try await DatosSiri.citasPospuestas().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CitaPospuestaEntidad] {
        try await DatosSiri.citasPospuestas()
    }

    func entities(matching string: String) async throws -> [CitaPospuestaEntidad] {
        try await DatosSiri.citasPospuestas().filter { DatosSiri.coincide($0.texto, con: string) }
    }
}
