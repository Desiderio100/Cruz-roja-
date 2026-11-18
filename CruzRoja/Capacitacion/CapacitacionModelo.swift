// Los cursos y las inscripciones salen del backend (GET /api/cursos, POST /api/cursos/:id/inscripciones)
// a través de CursosRepositorio. Aquí vive el estado que comparten las pantallas de Capacitación.
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
@MainActor
@Observable
final class CapacitacionModelo {
    /// Próximos cursos, del más cercano en fecha al más lejano. Al abrir la app son los
    /// últimos que se descargaron; `cargar()` los actualiza.
    private(set) var cursos: [Curso]

    /// Inscripciones confirmadas, guardadas en el teléfono.
    private(set) var inscripciones: [Inscripcion]

    /// `true` mientras se descargan los cursos.
    private(set) var cargando = false

    /// Por qué falló la última descarga, o `nil` si salió bien.
    private(set) var errorDeCarga: String?

    /// De dónde salen los cursos. La app usa el backend; las pruebas, uno sin servidor.
    @ObservationIgnored private let repositorio: CursosRepositorio

    /// Dónde se guarda la copia para ver sin internet. La app usa `.standard`; las pruebas, uno vacío aparte.
    @ObservationIgnored private let almacen: UserDefaults

    // La llave cambió respecto al Sprint 1 para no arrastrar las inscripciones de ejemplo de entonces.
    private static let claveInscripciones = "capacitacion.inscripciones.servidor"
    private static let claveCursos = "capacitacion.cursos"

    /// - Parameters:
    ///   - repositorio: de dónde salen los cursos (por defecto, el backend).
    ///   - almacen: dónde leer y guardar la copia local (por defecto, el del teléfono).
    init(repositorio: CursosRepositorio = CursosAPI(), almacen: UserDefaults = .standard) {
        self.repositorio = repositorio
        self.almacen = almacen
        self.cursos = Self.leer([Curso].self, clave: Self.claveCursos, de: almacen) ?? []
        self.inscripciones = Self.leer([Inscripcion].self, clave: Self.claveInscripciones, de: almacen) ?? []
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

    /// Descarga los cursos y las inscripciones de este teléfono.
    /// Si no hay servidor o internet, se quedan los últimos guardados y `errorDeCarga` dice por qué.
    func cargar() async {
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }

        do {
            cursos = try await repositorio.cursos().sorted { $0.fecha < $1.fecha }
            guardar(cursos, clave: Self.claveCursos)
            errorDeCarga = nil
        } catch is CancellationError {
            return
        } catch {
            errorDeCarga = error.localizedDescription
            return
        }

        // Las inscripciones del servidor se suman a las guardadas en el teléfono.
        if let delServidor = try? await repositorio.inscripciones() {
            agregar(delServidor)
        }
    }

    /// Inscribe a la persona en un curso con cupo y guarda la inscripción en el teléfono.
    /// - Returns: el folio de confirmación que asigna el servidor.
    /// - Throws: `ErrorInscripcion` si el curso está lleno, ya estaba inscrita o faltan datos;
    ///   `ErrorAPI` si el servidor rechaza la inscripción o no responde.
    func inscribir(en curso: Curso, nombre: String, celular: String) async throws -> String {
        guard let actual = cursos.first(where: { $0.id == curso.id }) else { throw ErrorInscripcion.cursoLleno }
        guard folio(de: curso.id) == nil else { throw ErrorInscripcion.yaInscrito }
        guard !actual.estaLleno else { throw ErrorInscripcion.cursoLleno }
        guard Self.datosValidos(nombre: nombre, celular: celular) else { throw ErrorInscripcion.faltanDatos }

        let inscripcion: Inscripcion
        do {
            inscripcion = try await repositorio.inscribir(
                en: actual,
                nombre: nombre.trimmingCharacters(in: .whitespaces),
                celular: celular.filter { $0.isASCII && $0.isNumber })
        } catch {
            // 409: alguien tomó el último lugar o ese celular ya estaba inscrito.
            // Se vuelve a descargar la lista para mostrar los lugares reales.
            if (error as? ErrorAPI)?.estado == 409 { await cargar() }
            throw error
        }

        if let i = cursos.firstIndex(where: { $0.id == curso.id }) {
            cursos[i].inscritos += 1
            guardar(cursos, clave: Self.claveCursos)
        }
        agregar([inscripcion])
        return inscripcion.folio
    }

    /// `true` si el nombre tiene al menos 3 letras y el celular 10 dígitos.
    static func datosValidos(nombre: String, celular: String) -> Bool {
        let digitos = celular.filter { $0.isASCII && $0.isNumber }
        return nombre.trimmingCharacters(in: .whitespaces).count >= 3 && digitos.count == 10
    }

    /// Suma inscripciones a la lista (una por curso), la ordena por fecha y la guarda.
    private func agregar(_ nuevas: [Inscripcion]) {
        var porCurso: [String: Inscripcion] = [:]
        for inscripcion in inscripciones + nuevas {
            porCurso[inscripcion.cursoId] = inscripcion
        }
        inscripciones = porCurso.values.sorted { ($0.fecha, $0.folio) < ($1.fecha, $1.folio) }
        guardar(inscripciones, clave: Self.claveInscripciones)
    }

    private func guardar<Valor: Encodable>(_ valor: Valor, clave: String) {
        if let datos = try? JSONEncoder().encode(valor) {
            almacen.set(datos, forKey: clave)
        }
    }

    /// Lee lo guardado; si no hay o está dañado, regresa `nil`.
    private static func leer<Valor: Decodable>(_ tipo: Valor.Type, clave: String, de almacen: UserDefaults) -> Valor? {
        guard let datos = almacen.data(forKey: clave) else { return nil }
        return try? JSONDecoder().decode(tipo, from: datos)
    }
}
