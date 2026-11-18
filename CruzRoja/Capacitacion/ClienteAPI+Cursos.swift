// Llamadas de Capacitación (HU14) al backend: backend/src/rutas/cursos.js.
// El cliente común (pedir, decodificar, el id del dispositivo) está en Comun/ClienteAPI.swift.

import Foundation

/// Un curso tal como lo manda GET /api/cursos.
struct CursoRemoto: Decodable {
    let id: Int
    let titulo: String
    let descripcion: String?
    let inicio: Date
    let sede: String
    let cupo: Int
    let inscritos: Int

    /// El servidor todavía no informa duración ni costo: se quedan en `nil` y la pantalla no los muestra.
    var curso: Curso {
        Curso(id: String(id), titulo: titulo, descripcion: descripcion ?? "", fecha: inicio,
              duracion: nil, sede: sede, cupo: cupo, inscritos: inscritos, costo: nil)
    }
}

/// Una inscripción tal como la mandan GET /api/cursos/inscripciones y
/// POST /api/cursos/:id/inscripciones.
struct InscripcionRemota: Decodable {
    let folio: String
    let cursoId: Int
    let titulo: String
    let inicio: Date
    let sede: String

    var inscripcion: Inscripcion {
        Inscripcion(folio: folio, cursoId: String(cursoId), titulo: titulo, fecha: inicio, sede: sede)
    }
}

struct RespuestaCursos: Decodable {
    let cursos: [CursoRemoto]
}

struct RespuestaInscripciones: Decodable {
    let inscripciones: [InscripcionRemota]
}

extension ClienteAPI {
    /// GET /api/cursos — pública, sin datos personales.
    func cursosProximos() async throws -> [Curso] {
        let datos = try await pedir("GET", "/api/cursos", conDispositivo: false)
        return try decodificar(RespuestaCursos.self, datos).cursos.map(\.curso)
    }

    /// GET /api/cursos/inscripciones — solo las de este dispositivo.
    func misInscripciones() async throws -> [Inscripcion] {
        let datos = try await pedir("GET", "/api/cursos/inscripciones")
        return try decodificar(RespuestaInscripciones.self, datos).inscripciones.map(\.inscripcion)
    }

    /// POST /api/cursos/:id/inscripciones — el servidor revisa el cupo y devuelve el folio.
    func inscribirme(cursoId: String, nombre: String, telefono: String) async throws -> Inscripcion {
        let cuerpo: [String: Any] = ["nombre": nombre, "telefono": telefono]
        let datos = try await pedir("POST", "/api/cursos/\(cursoId)/inscripciones", cuerpo: cuerpo)
        return try decodificar(InscripcionRemota.self, datos).inscripcion
    }
}
