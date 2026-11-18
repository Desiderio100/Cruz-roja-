// HU14 · Inscripción a capacitación.
//
//   • Los cursos salen del backend (GET /api/cursos) y se guardan en el teléfono para verlos sin internet.
//   • Inscribirse requiere internet: el cupo vive en el servidor (POST /api/cursos/:id/inscripcion),
//     que aparta el lugar dentro de una transacción; así dos personas no se quedan con el último lugar.
//   • Las inscripciones confirmadas se guardan en el teléfono y se sincronizan con las del servidor.

import Foundation
import Observation

/// Una inscripción confirmada. Se guarda en el teléfono para verla aun sin internet.
struct Inscripcion: Codable, Identifiable, Hashable {
    let folio: String
    let cursoId: String
    let titulo: String
    let fecha: Date
    let sede: String
    var id: String { folio }
}

/// De dónde salen los cursos y adónde van las inscripciones. La app usa el backend;
/// las vistas previas y las pruebas, una fuente en memoria.
@MainActor
protocol FuenteCapacitacion {
    func cursos() async throws -> [Curso]
    /// Aparta un lugar y devuelve el folio de confirmación.
    func inscribir(cursoId: String, nombre: String, celular: String) async throws -> String
    /// Inscripciones hechas desde este dispositivo.
    func misInscripciones() async throws -> [Inscripcion]
}

/// Estado de Capacitación (HU14): los próximos cursos y las inscripciones de la persona.
/// Lo crea la app una vez y lo comparten las pantallas de Capacitación por `.environment`.
@MainActor
@Observable
final class CapacitacionModelo {
    /// Próximos cursos, del más cercano en fecha al más lejano.
    private(set) var cursos: [Curso] = []
    /// Inscripciones confirmadas, guardadas en el teléfono.
    private(set) var inscripciones: [Inscripcion] = []
    /// Última vez que se bajaron los cursos del servidor (`nil` = nunca).
    private(set) var actualizadoEn: Date?
    private(set) var cargando = false
    /// Mensaje si la última descarga falló (los cursos guardados se siguen mostrando).
    private(set) var errorCarga: String?

    @ObservationIgnored private let almacen: UserDefaults
    @ObservationIgnored private let fuente: any FuenteCapacitacion

    private static let claveInscripciones = "capacitacion.inscripciones.v2"
    private static let claveCursos = "capacitacion.cursos"

    /// - Parameters:
    ///   - almacen: dónde guardar cursos e inscripciones (por defecto, el del teléfono; las pruebas usan uno vacío).
    ///   - fuente: de dónde salen los cursos (por defecto, el backend).
    init(almacen: UserDefaults = .standard, fuente: (any FuenteCapacitacion)? = nil) {
        self.almacen = almacen
        self.fuente = fuente ?? ServidorCapacitacion()
        inscripciones = Self.leer([Inscripcion].self, de: almacen, clave: Self.claveInscripciones) ?? []
        if let guardados = Self.leer(CursosGuardados.self, de: almacen, clave: Self.claveCursos) {
            cursos = guardados.cursos.filter { $0.fecha > .now }
            actualizadoEn = guardados.fecha
        }
    }

    /// Folio de la inscripción a un curso, o `nil` si la persona no está inscrita.
    func folio(de cursoId: String) -> String? {
        inscripciones.first { $0.cursoId == cursoId }?.folio
    }

    /// Baja los cursos del servidor y sincroniza las inscripciones. Sin internet se quedan los guardados.
    func cargar() async {
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }
        do {
            cursos = try await fuente.cursos().sorted { $0.fecha < $1.fecha }
            actualizadoEn = .now
            errorCarga = nil
            Self.guardar(CursosGuardados(fecha: .now, cursos: cursos), en: almacen, clave: Self.claveCursos)
        } catch is CancellationError {
            return
        } catch {
            errorCarga = (error as? LocalizedError)?.errorDescription ?? "No se pudieron cargar los cursos."
            return
        }
        await sincronizarInscripciones()
    }

    /// Motivos por los que no se puede completar una inscripción (con su mensaje para la persona).
    enum ErrorInscripcion: LocalizedError, Equatable {
        case cursoLleno, yaInscrito, faltanDatos, noDisponible
        case servidor(String)

        var errorDescription: String? {
            switch self {
            case .cursoLleno: "Este curso ya no tiene lugares. Revisa otras fechas."
            case .yaInscrito: "Ya estás inscrito en este curso."
            case .faltanDatos: "Escribe tu nombre y un celular de 10 dígitos."
            case .noDisponible: "Este curso ya no está disponible."
            case .servidor(let mensaje): mensaje
            }
        }
    }

    /// Inscribe a la persona en un curso con cupo y guarda la inscripción en el teléfono.
    /// - Returns: el folio de confirmación que dio el servidor, por ejemplo "CR-1A2B3C4D".
    /// - Throws: `ErrorInscripcion` si el curso está lleno, ya estaba inscrita, faltan datos o el servidor no aceptó.
    func inscribir(en curso: Curso, nombre: String, celular: String) async throws -> String {
        guard let i = cursos.firstIndex(where: { $0.id == curso.id }) else { throw ErrorInscripcion.noDisponible }
        guard folio(de: curso.id) == nil else { throw ErrorInscripcion.yaInscrito }
        guard !cursos[i].estaLleno else { throw ErrorInscripcion.cursoLleno }
        guard Self.datosValidos(nombre: nombre, celular: celular) else { throw ErrorInscripcion.faltanDatos }

        let folio: String
        do {
            folio = try await fuente.inscribir(cursoId: curso.id,
                                               nombre: nombre.trimmingCharacters(in: .whitespaces),
                                               celular: Self.digitos(celular))
        } catch let error as ErrorAPI where error.estado == 409 {
            // Alguien más ganó el último lugar (o el curso cambió): se actualiza la lista.
            await cargar()
            if cursos.first(where: { $0.id == curso.id })?.estaLleno ?? true { throw ErrorInscripcion.cursoLleno }
            throw ErrorInscripcion.servidor(error.mensaje)
        } catch let error as ErrorInscripcion {
            throw error
        } catch {
            throw ErrorInscripcion.servidor((error as? LocalizedError)?.errorDescription ?? "No se pudo inscribir. Intenta de nuevo.")
        }

        if let j = cursos.firstIndex(where: { $0.id == curso.id }) { cursos[j].inscritos += 1 }
        agregar(Inscripcion(folio: folio, cursoId: curso.id, titulo: curso.titulo, fecha: curso.fecha, sede: curso.sede))
        return folio
    }

    /// `true` si el nombre tiene al menos 3 letras y el celular 10 dígitos.
    static func datosValidos(nombre: String, celular: String) -> Bool {
        nombre.trimmingCharacters(in: .whitespaces).count >= 3 && digitos(celular).count == 10
    }

    /// "+52 81 1234-5678" → "8112345678".
    private static func digitos(_ celular: String) -> String {
        let digitos = celular.filter { $0.isASCII && $0.isNumber }
        return digitos.count == 12 && digitos.hasPrefix("52") ? String(digitos.dropFirst(2)) : digitos
    }

    // MARK: Inscripciones guardadas

    /// Agrega al teléfono las inscripciones que el servidor tiene y el teléfono no.
    private func sincronizarInscripciones() async {
        guard let delServidor = try? await fuente.misInscripciones() else { return }
        for inscripcion in delServidor where !inscripciones.contains(where: { $0.folio == inscripcion.folio }) {
            agregar(inscripcion)
        }
    }

    private func agregar(_ inscripcion: Inscripcion) {
        inscripciones.append(inscripcion)
        inscripciones.sort { $0.fecha < $1.fecha }
        Self.guardar(inscripciones, en: almacen, clave: Self.claveInscripciones)
    }

    private struct CursosGuardados: Codable {
        let fecha: Date
        let cursos: [Curso]
    }

    private static func guardar<T: Encodable>(_ valor: T, en almacen: UserDefaults, clave: String) {
        if let datos = try? JSONEncoder().encode(valor) { almacen.set(datos, forKey: clave) }
    }

    /// Lee lo guardado; si no hay o está dañado, regresa `nil`.
    private static func leer<T: Decodable>(_ tipo: T.Type, de almacen: UserDefaults, clave: String) -> T? {
        guard let datos = almacen.data(forKey: clave) else { return nil }
        return try? JSONDecoder().decode(tipo, from: datos)
    }
}

// MARK: - Fuentes

/// Los cursos del backend.
@MainActor
struct ServidorCapacitacion: FuenteCapacitacion {
    private struct RespuestaCursos: Decodable {
        struct CursoServidor: Decodable {
            let id: Int
            let titulo: String
            let descripcion: String?
            let inicio: Date
            let duracion: String?
            let cupo: Int
            let costoMxn: Double?
            let inscritos: Int
            let sede: String
        }
        let cursos: [CursoServidor]
    }

    private struct RespuestaInscripcion: Decodable {
        let folio: String
    }

    private struct RespuestaMisInscripciones: Decodable {
        struct InscripcionServidor: Decodable {
            let folio: String
            let cursoId: Int
            let titulo: String
            let inicio: Date
            let sede: String
        }
        let inscripciones: [InscripcionServidor]
    }

    func cursos() async throws -> [Curso] {
        let api = ClienteAPI.compartido
        let datos = try await api.pedir("GET", "/api/cursos", conDispositivo: false)
        return try api.decodificar(RespuestaCursos.self, datos).cursos.map {
            Curso(id: String($0.id), titulo: $0.titulo, descripcion: $0.descripcion ?? "", fecha: $0.inicio,
                  duracion: $0.duracion ?? "", sede: $0.sede, cupo: $0.cupo, inscritos: $0.inscritos,
                  costo: $0.costoMxn.map { Int($0.rounded()) })
        }
    }

    func inscribir(cursoId: String, nombre: String, celular: String) async throws -> String {
        let api = ClienteAPI.compartido
        let datos = try await api.pedir("POST", "/api/cursos/\(cursoId)/inscripcion",
                                        cuerpo: ["nombre": nombre, "telefono": celular])
        return try api.decodificar(RespuestaInscripcion.self, datos).folio
    }

    func misInscripciones() async throws -> [Inscripcion] {
        let api = ClienteAPI.compartido
        let datos = try await api.pedir("GET", "/api/cursos/inscripciones")
        return try api.decodificar(RespuestaMisInscripciones.self, datos).inscripciones.map {
            Inscripcion(folio: $0.folio, cursoId: String($0.cursoId), titulo: $0.titulo, fecha: $0.inicio, sede: $0.sede)
        }
    }
}

/// Cursos de ejemplo en memoria, para las vistas previas de Xcode.
@MainActor
final class CapacitacionDeEjemplo: FuenteCapacitacion {
    private var lista = Curso.ejemplos

    func cursos() async throws -> [Curso] { lista }

    func inscribir(cursoId: String, nombre: String, celular: String) async throws -> String {
        guard let i = lista.firstIndex(where: { $0.id == cursoId }), !lista[i].estaLleno else {
            throw ErrorAPI(mensaje: "Este curso ya no tiene lugares. Revisa otras fechas.", estado: 409)
        }
        lista[i].inscritos += 1
        return "CR-" + String(UUID().uuidString.prefix(8))
    }

    func misInscripciones() async throws -> [Inscripcion] { [] }
}
