// Por ahora todo es local (cursos de ejemplo). Cuando Sebastián tenga el backend,
// solo cambian `cursos` (descargarlos) y el cuerpo de `inscribir` (mandarlo al servidor).
//
// Inscribirse requiere internet: el cupo vive en el servidor y sin conexión
// podríamos darle a dos personas el último lugar.

import Foundation
import Observation

struct Inscripcion: Codable, Identifiable, Hashable {
    let folio: String
    let cursoId: String
    let titulo: String
    let fecha: Date
    let sede: String
    var id: String { folio }
}

@Observable
final class CapacitacionModelo {
    private(set) var cursos: [Curso] = Curso.ejemplos.sorted { $0.fecha < $1.fecha }

    private(set) var inscripciones: [Inscripcion] = CapacitacionModelo.cargarInscripciones()

    private static let clave = "capacitacion.inscripciones"

    func folio(de cursoId: String) -> String? {
        inscripciones.first { $0.cursoId == cursoId }?.folio
    }

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
            UserDefaults.standard.set(datos, forKey: Self.clave)
        }
        return folio
    }

    static func datosValidos(nombre: String, celular: String) -> Bool {
        let digitos = celular.filter { $0.isASCII && $0.isNumber }
        return nombre.trimmingCharacters(in: .whitespaces).count >= 3 && digitos.count == 10
    }

    private static func cargarInscripciones() -> [Inscripcion] {
        guard let datos = UserDefaults.standard.data(forKey: clave),
              let lista = try? JSONDecoder().decode([Inscripcion].self, from: datos)
        else { return [] }
        return lista
    }
}
