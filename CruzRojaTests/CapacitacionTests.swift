//
//  CapacitacionTests.swift
//  Pruebas unitarias de HU14 · Inscripción a capacitación.
//
//  No tocan internet: usan cursos de ejemplo o un servidor FALSO en lugar del backend.
//  Cada prueba usa su propio almacén vacío, así no toca las inscripciones guardadas
//  en el simulador ni depende de otras pruebas.
//  (El cupo real y las reglas del servidor se prueban en backend/test/cursos.test.js.)
//

import Foundation
import Testing
@testable import CruzRoja

/// Servidor falso: contesta lo que cada prueba necesite y cuenta lo que la app le pide.
final class CursosFalso: CursosRepositorio {
    var respuestaCursos: Result<[Curso], Error> = .success(Curso.ejemplos)
    var respuestaInscripciones: Result<[Inscripcion], Error> = .success([])
    /// Si no es nil, inscribirse falla con este error (por ejemplo, un 409 del servidor).
    var errorAlInscribir: Error?

    private(set) var descargas = 0
    private(set) var inscripcionesPedidas: [(cursoId: String, nombre: String, celular: String)] = []

    func cursos() async throws -> [Curso] {
        descargas += 1
        return try respuestaCursos.get()
    }

    func inscripciones() async throws -> [Inscripcion] {
        try respuestaInscripciones.get()
    }

    func inscribir(en curso: Curso, nombre: String, celular: String) async throws -> Inscripcion {
        inscripcionesPedidas.append((curso.id, nombre, celular))
        if let errorAlInscribir { throw errorAlInscribir }
        return Inscripcion(folio: "CAP-A1B2C3", cursoId: curso.id, titulo: curso.titulo,
                           fecha: curso.fecha, sede: curso.sede)
    }
}

@Suite("HU14 · Inscripción a capacitación")
@MainActor
struct CapacitacionTests {
    typealias ErrorInscripcion = CapacitacionModelo.ErrorInscripcion

    /// Datos de una persona que sí cumplen la validación.
    let nombreValido = "Ana López"
    let celularValido = "8112345678"

    /// Almacén vacío solo para una prueba.
    static func almacenNuevo() -> UserDefaults {
        let suite = "pruebas.capacitacion.\(UUID().uuidString)"
        let almacen = UserDefaults(suiteName: suite)!
        almacen.removePersistentDomain(forName: suite)
        return almacen
    }

    /// Modelo con los cursos ya descargados del repositorio que se indique.
    static func modeloCargado(
        _ repositorio: CursosRepositorio = CursosDeEjemplo(),
        almacen: UserDefaults = almacenNuevo()
    ) async -> CapacitacionModelo {
        let modelo = CapacitacionModelo(repositorio: repositorio, almacen: almacen)
        await modelo.cargar()
        return modelo
    }

    // MARK: - CA14.1 · Los cursos aparecen con fecha y lugares disponibles

    @Test("Los cursos aparecen con fecha y lugares disponibles")
    func cursosConFechaYLugares() async {
        let modelo = await Self.modeloCargado()
        #expect(!modelo.cursos.isEmpty)
        #expect(modelo.errorDeCarga == nil)

        let fechas = modelo.cursos.map(\.fecha)
        #expect(fechas == fechas.sorted())

        for curso in modelo.cursos {
            #expect(curso.lugaresDisponibles == max(0, curso.cupo - curso.inscritos))
            #expect(!curso.textoFecha.isEmpty)
        }
    }

    @Test("Texto de lugares disponibles", arguments: [
        (20, 12, "Quedan 8 lugares"),
        (20, 19, "Queda 1 lugar"),
        (20, 20, "Curso lleno"),
    ])
    func textoDeLugares(cupo: Int, inscritos: Int, esperado: String) {
        let curso = Curso(id: "prueba", titulo: "Curso de prueba", descripcion: "", fecha: .now,
                          duracion: "1 hora", sede: "Sede de prueba", cupo: cupo,
                          inscritos: inscritos, costo: nil)
        #expect(curso.textoLugares == esperado)
    }

    @Test("El costo solo se muestra cuando se conoce")
    func textoDelCosto() {
        func curso(costo: Int?) -> Curso {
            Curso(id: "prueba", titulo: "Curso de prueba", descripcion: "", fecha: .now,
                  duracion: nil, sede: "Sede de prueba", cupo: 10, inscritos: 0, costo: costo)
        }
        #expect(curso(costo: 350).textoCosto == "$350 MXN")
        #expect(curso(costo: 0).textoCosto == "Gratuito")
        #expect(curso(costo: nil).textoCosto == nil)
    }

    // MARK: - CA14.2 · Con cupo, al inscribirme recibo una confirmación

    @Test("Con cupo, inscribirme da el folio del servidor y baja los lugares")
    func inscripcionConCupo() async throws {
        let servidor = CursosFalso()
        let modelo = await Self.modeloCargado(servidor)
        let curso = try #require(modelo.cursos.first { !$0.estaLleno })
        let lugaresAntes = curso.lugaresDisponibles

        let folio = try await modelo.inscribir(en: curso, nombre: "  Ana López ", celular: "81 1234 5678")

        #expect(folio == "CAP-A1B2C3")
        #expect(modelo.folio(de: curso.id) == folio)
        let actualizado = try #require(modelo.cursos.first { $0.id == curso.id })
        #expect(actualizado.lugaresDisponibles == lugaresAntes - 1)

        // Al servidor llegan el nombre sin espacios de más y el celular solo con dígitos.
        #expect(servidor.inscripcionesPedidas.count == 1)
        #expect(servidor.inscripcionesPedidas.first?.cursoId == curso.id)
        #expect(servidor.inscripcionesPedidas.first?.nombre == "Ana López")
        #expect(servidor.inscripcionesPedidas.first?.celular == "8112345678")
    }

    @Test("No puedo inscribirme dos veces y la inscripción queda guardada")
    func noDosVecesYQuedaGuardada() async throws {
        let almacen = Self.almacenNuevo()
        let servidor = CursosFalso()
        let modelo = await Self.modeloCargado(servidor, almacen: almacen)
        let curso = try #require(modelo.cursos.first { !$0.estaLleno })
        let folio = try await modelo.inscribir(en: curso, nombre: nombreValido, celular: celularValido)

        await #expect(throws: ErrorInscripcion.yaInscrito) {
            try await modelo.inscribir(en: curso, nombre: nombreValido, celular: celularValido)
        }
        #expect(servidor.inscripcionesPedidas.count == 1)

        // Al volver a abrir la app, la inscripción y los cursos se leen del teléfono (sin servidor).
        let reabierto = CapacitacionModelo(repositorio: CursosFalso(), almacen: almacen)
        #expect(reabierto.folio(de: curso.id) == folio)
        #expect(reabierto.cursos.count == modelo.cursos.count)
    }

    // MARK: - CA14.3 · Si el curso está lleno no puedo inscribirme

    @Test("Si el curso está lleno no puedo inscribirme y no se le pide al servidor")
    func cursoLleno() async throws {
        let servidor = CursosFalso()
        let modelo = await Self.modeloCargado(servidor)
        let lleno = try #require(modelo.cursos.first { $0.estaLleno })

        await #expect(throws: ErrorInscripcion.cursoLleno) {
            try await modelo.inscribir(en: lleno, nombre: nombreValido, celular: celularValido)
        }
        #expect(modelo.folio(de: lleno.id) == nil)
        #expect(servidor.inscripcionesPedidas.isEmpty)
    }

    @Test("Si alguien toma el último lugar antes que yo, veo el motivo y la lista se actualiza")
    func ultimoLugarTomado() async throws {
        let servidor = CursosFalso()
        let modelo = await Self.modeloCargado(servidor)
        let curso = try #require(modelo.cursos.first { !$0.estaLleno })
        servidor.errorAlInscribir = ErrorAPI(mensaje: "Este curso ya no tiene lugares", estado: 409)

        await #expect(throws: ErrorAPI.self) {
            try await modelo.inscribir(en: curso, nombre: nombreValido, celular: celularValido)
        }
        #expect(modelo.folio(de: curso.id) == nil)
        #expect(servidor.descargas == 2) // la descarga inicial y la que sigue al 409
    }

    // MARK: - CA14.4 · Con datos incompletos no puedo inscribirme

    @Test("Con datos incompletos no puedo inscribirme", arguments: [
        ("Al", "8112345678"),
        ("Ana López", "81123"),
        ("   ", "8112345678"),
    ])
    func datosIncompletos(nombre: String, celular: String) async throws {
        #expect(!CapacitacionModelo.datosValidos(nombre: nombre, celular: celular))

        let modelo = await Self.modeloCargado()
        let curso = try #require(modelo.cursos.first { !$0.estaLleno })
        await #expect(throws: ErrorInscripcion.faltanDatos) {
            try await modelo.inscribir(en: curso, nombre: nombre, celular: celular)
        }
    }

    // MARK: - Sin servidor y respuestas del backend

    @Test("Sin servidor se ven los últimos cursos guardados y se avisa del error")
    func sinServidor() async {
        let almacen = Self.almacenNuevo()
        let conServidor = await Self.modeloCargado(CursosFalso(), almacen: almacen)
        #expect(!conServidor.cursos.isEmpty)

        let caido = CursosFalso()
        caido.respuestaCursos = .failure(ErrorAPI(mensaje: "No hay conexión con el servidor"))
        let modeloSinServidor = await Self.modeloCargado(caido, almacen: almacen)

        #expect(modeloSinServidor.cursos.count == conServidor.cursos.count)
        #expect(modeloSinServidor.errorDeCarga == "No hay conexión con el servidor")
        #expect(!modeloSinServidor.cargando)
    }

    @Test("Las inscripciones que ya tiene el servidor aparecen al cargar")
    func inscripcionesDelServidor() async throws {
        let servidor = CursosFalso()
        let curso = Curso.ejemplos[0]
        servidor.respuestaInscripciones = .success([
            Inscripcion(folio: "CAP-0F0F0F", cursoId: curso.id, titulo: curso.titulo, fecha: curso.fecha, sede: curso.sede),
        ])
        let modelo = await Self.modeloCargado(servidor)
        #expect(modelo.folio(de: curso.id) == "CAP-0F0F0F")
    }

    @Test("Lee la lista de cursos tal como la manda el backend")
    func respuestaDeCursos() throws {
        let json = #"""
        {"cursos":[{"id":7,"titulo":"RCP para adultos","descripcion":null,
                    "inicio":"2026-12-17T16:00:00.000Z","cupo":20,"sede":"Cruz Roja Monterrey","inscritos":18}]}
        """#
        let cursos = try ClienteAPI.compartido.decodificar(RespuestaCursos.self, Data(json.utf8)).cursos.map(\.curso)

        let curso = try #require(cursos.first)
        #expect(curso.id == "7")
        #expect(curso.titulo == "RCP para adultos")
        #expect(curso.descripcion.isEmpty)
        #expect(curso.sede == "Cruz Roja Monterrey")
        #expect(curso.lugaresDisponibles == 2)
        #expect(curso.duracion == nil)
        #expect(curso.textoCosto == nil)
        #expect(curso.fecha == ISO8601DateFormatter().date(from: "2026-12-17T16:00:00Z"))
    }

    @Test("Lee la confirmación de una inscripción tal como la manda el backend")
    func respuestaDeInscripcion() throws {
        let json = #"""
        {"folio":"CAP-75CEA0","curso_id":7,"titulo":"RCP para adultos",
         "inicio":"2026-12-17T16:00:00.000Z","sede":"Cruz Roja Monterrey","lugares_disponibles":1}
        """#
        let inscripcion = try ClienteAPI.compartido.decodificar(InscripcionRemota.self, Data(json.utf8)).inscripcion

        #expect(inscripcion.folio == "CAP-75CEA0")
        #expect(inscripcion.cursoId == "7")
        #expect(inscripcion.sede == "Cruz Roja Monterrey")
    }
}
