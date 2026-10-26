// Por ahora todo es local (cursos de ejemplo). Cuando Sebastián tenga el backend,
// solo cambian `cursos` (descargarlos) y el cuerpo de `inscribir` (mandarlo al servidor).
//
// Inscribirse requiere internet: el cupo vive en el servidor y sin conexión
// podríamos darle a dos personas el último lugar.

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

/// Estado de Capacitación (HU14): los próximos cursos y las inscripciones de la persona.
/// Lo crea la app una vez y lo comparten las pantallas de Capacitación por `.environment`.
@Observable
final class CapacitacionModelo {
    /// Próximos cursos, del más cercano en fecha al más lejano.
    private(set) var cursos: [Curso] = Curso.ejemplos.sorted { $0.fecha < $1.fecha }

    /// Inscripciones confirmadas, guardadas en el teléfono.
    private(set) var inscripciones: [Inscripcion]

    /// Dónde se guardan las inscripciones. La app usa `.standard`; las pruebas, uno vacío aparte.
    @ObservationIgnored private let almacen: UserDefaults

    private static let clave = "capacitacion.inscripciones"

    /// - Parameter almacen: dónde leer y guardar las inscripciones (por defecto, el del teléfono).
    init(almacen: UserDefaults = .standard) {
        self.almacen = almacen
        self.inscripciones = Self.cargarInscripciones(de: almacen)
    }

    /// Folio de la inscripción a un curso, o `nil` si la persona no está inscrita.
    func folio(de cursoId: String) -> String? {
        inscripciones.first { $0.cursoId == cursoId }?.folio
    }

    /// Motivos por los que no se puede completar una inscripción (con su mensaje para la persona).
    enum ErrorInscripcion: LocalizedError {
        case cursoLleno, yaInscrito, faltanDatos

        var errorDescription: String? {
            switch self {
            case .cursoLleno: "Este curso ya no tiene lugares. Revisa otras fechas."
            case .yaInscrito: "Ya estás inscrito en este curso."
            case .faltanDatos: "Escribe tu nombre y un celular de 10 dígitos."
            }
        }
    }

    /// Inscribe a la persona en un curso con cupo y guarda la inscripción en el teléfono.
    /// - Returns: el folio de confirmación, por ejemplo "CR-482913".
    /// - Throws: `ErrorInscripcion` si el curso está lleno, ya estaba inscrita o faltan datos.
    func inscribir(en curso: Curso, nombre: String, celular: String) throws -> String {
        guard let i = cursos.firstIndex(where: { $0.id == curso.id }) else { throw ErrorInscripcion.cursoLleno }
        guard folio(de: curso.id) == nil else { throw ErrorInscripcion.yaInscrito }
        guard !cursos[i].estaLleno else { throw ErrorInscripcion.cursoLleno }
        guard Self.datosValidos(nombre: nombre, celular: celular) else { throw ErrorInscripcion.faltanDatos }

        // Aquí irá la llamada al backend.
        let folio = "CR-" + String(Int.random(in: 100_000...999_999))
        cursos[i].inscritos += 1

        inscripciones.append(Inscripcion(folio: folio, cursoId: curso.id, titulo: curso.titulo,
                                         fecha: curso.fecha, sede: curso.sede))
        inscripciones.sort { $0.fecha < $1.fecha }
        if let datos = try? JSONEncoder().encode(inscripciones) {
            almacen.set(datos, forKey: Self.clave)
        }
        return folio
    }

    /// `true` si el nombre tiene al menos 3 letras y el celular 10 dígitos.
    static func datosValidos(nombre: String, celular: String) -> Bool {
        let digitos = celular.filter { $0.isASCII && $0.isNumber }
        return nombre.trimmingCharacters(in: .whitespaces).count >= 3 && digitos.count == 10
    }

    /// Lee las inscripciones guardadas; si no hay o están dañadas, regresa una lista vacía.
    private static func cargarInscripciones(de almacen: UserDefaults) -> [Inscripcion] {
        guard let datos = almacen.data(forKey: clave),
              let lista = try? JSONDecoder().decode([Inscripcion].self, from: datos)
        else { return [] }
        return lista
    }
}
