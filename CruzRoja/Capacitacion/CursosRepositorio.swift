// De dónde salen los cursos y a dónde van las inscripciones (HU14).
// CapacitacionModelo solo conoce este protocolo: en la app habla con el backend (CursosAPI)
// y en las vistas previas y las pruebas se usa uno sin servidor.

import Foundation

protocol CursosRepositorio {
    /// Próximos cursos con sus lugares.
    func cursos() async throws -> [Curso]
    /// Inscripciones hechas desde este teléfono.
    func inscripciones() async throws -> [Inscripcion]
    /// Aparta un lugar. El cupo lo decide el servidor, no la app.
    func inscribir(en curso: Curso, nombre: String, celular: String) async throws -> Inscripcion
}

/// Habla con el backend: backend/src/rutas/cursos.js (llamadas en ClienteAPI+Cursos.swift).
struct CursosAPI: CursosRepositorio {
    func cursos() async throws -> [Curso] {
        try await ClienteAPI.compartido.cursosProximos()
    }

    func inscripciones() async throws -> [Inscripcion] {
        try await ClienteAPI.compartido.misInscripciones()
    }

    func inscribir(en curso: Curso, nombre: String, celular: String) async throws -> Inscripcion {
        try await ClienteAPI.compartido.inscribirme(cursoId: curso.id, nombre: nombre, telefono: celular)
    }
}

/// Cursos de ejemplo, sin servidor: para las vistas previas de Xcode y las pruebas unitarias.
struct CursosDeEjemplo: CursosRepositorio {
    func cursos() async throws -> [Curso] {
        Curso.ejemplos
    }

    func inscripciones() async throws -> [Inscripcion] {
        []
    }

    func inscribir(en curso: Curso, nombre: String, celular: String) async throws -> Inscripcion {
        Inscripcion(folio: "CR-" + String(Int.random(in: 100_000...999_999)), cursoId: curso.id,
                    titulo: curso.titulo, fecha: curso.fecha, sede: curso.sede)
    }
}
