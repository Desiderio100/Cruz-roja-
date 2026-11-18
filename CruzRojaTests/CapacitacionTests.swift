//
//  CapacitacionTests.swift
//  Pruebas unitarias de HU14 · Inscripción a capacitación.
//
//  Cada prueba usa su propio almacén vacío y un servidor falso en memoria, así no toca
//  las inscripciones guardadas en el simulador ni necesita el backend.
//

import Foundation
import Testing
@testable import CruzRoja

/// Servidor falso: guarda el cupo en memoria y responde como el backend (409 si está lleno).
@MainActor
final class ServidorDeCursosFalso: FuenteCapacitacion {
    var lista: [Curso]
    var sinConexion = false
    private(set) var inscritos: [(cursoId: String, celular: String)] = []

    init(_ lista: [Curso] = Curso.ejemplos) { self.lista = lista }

    func cursos() async throws -> [Curso] {
        if sinConexion { throw ErrorAPI(mensaje: "No hay conexión con el servidor") }
        return lista
    }

    func inscribir(cursoId: String, nombre: String, celular: String) async throws -> String {
        if sinConexion { throw ErrorAPI(mensaje: "No hay conexión con el servidor") }
        guard let i = lista.firstIndex(where: { $0.id == cursoId }) else {
            throw ErrorAPI(mensaje: "El curso no existe.", estado: 404)
        }
        guard !lista[i].estaLleno else {
            throw ErrorAPI(mensaje: "Este curso ya no tiene lugares. Revisa otras fechas.", estado: 409)
        }
        lista[i].inscritos += 1
        inscritos.append((cursoId, celular))
        return "CR-\(String(format: "%08lX", inscritos.count))"
    }

    func misInscripciones() async throws -> [Inscripcion] { [] }
}

@MainActor
@Suite("HU14 · Inscripción a capacitación")
struct CapacitacionTests {
    typealias ErrorInscripcion = CapacitacionModelo.ErrorInscripcion

    /// Datos de una persona que sí cumplen la validación.
    let nombreValido = "Ana López"
    let celularValido = "8112345678"

    /// Modelo con un almacén vacío y un servidor falso, ya con los cursos cargados.
    static func modeloNuevo(_ servidor: ServidorDeCursosFalso? = nil) async
        -> (modelo: CapacitacionModelo, almacen: UserDefaults, servidor: ServidorDeCursosFalso) {
        let servidor = servidor ?? ServidorDeCursosFalso()
        let suite = "pruebas.capacitacion.\(UUID().uuidString)"
        let almacen = UserDefaults(suiteName: suite)!
        almacen.removePersistentDomain(forName: suite)
        let modelo = CapacitacionModelo(almacen: almacen, fuente: servidor)
        await modelo.cargar()
        return (modelo, almacen, servidor)
    }

    // MARK: - CA14.1 · Los cursos aparecen con fecha y lugares disponibles

    @Test("Los cursos aparecen con fecha y lugares disponibles")
    func cursosConFechaYLugares() async {
        let modelo = await Self.modeloNuevo().modelo
        #expect(!modelo.cursos.isEmpty)

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

    @Test("Sin internet se ven los cursos guardados en el teléfono")
    func cursosGuardadosSinInternet() async {
        let (modelo, almacen, servidor) = await Self.modeloNuevo()
        servidor.sinConexion = true

        let reabierto = CapacitacionModelo(almacen: almacen, fuente: servidor)
        await reabierto.cargar()

        #expect(reabierto.cursos.map(\.id) == modelo.cursos.map(\.id))
        #expect(reabierto.errorCarga != nil)
    }

    // MARK: - CA14.2 · Con cupo, al inscribirme recibo una confirmación

    @Test("Con cupo, inscribirme da el folio de confirmación del servidor")
    func inscripcionConCupo() async throws {
        let (modelo, _, servidor) = await Self.modeloNuevo()
        let curso = try #require(modelo.cursos.first { !$0.estaLleno })
        let lugaresAntes = curso.lugaresDisponibles

        let folio = try await modelo.inscribir(en: curso, nombre: nombreValido, celular: celularValido)

        #expect(folio.hasPrefix("CR-"))
        #expect(modelo.folio(de: curso.id) == folio)
        #expect(servidor.inscritos.count == 1)
        let actualizado = try #require(modelo.cursos.first { $0.id == curso.id })
        #expect(actualizado.lugaresDisponibles == lugaresAntes - 1)
    }

    @Test("No puedo inscribirme dos veces y la inscripción queda guardada")
    func noDosVecesYQuedaGuardada() async throws {
        let (modelo, almacen, servidor) = await Self.modeloNuevo()
        let curso = try #require(modelo.cursos.first { !$0.estaLleno })
        let folio = try await modelo.inscribir(en: curso, nombre: nombreValido, celular: celularValido)

        await #expect(throws: ErrorInscripcion.yaInscrito) {
            try await modelo.inscribir(en: curso, nombre: nombreValido, celular: celularValido)
        }
        #expect(servidor.inscritos.count == 1)

        // Al volver a abrir la app, la inscripción se lee del teléfono.
        let reabierto = CapacitacionModelo(almacen: almacen, fuente: servidor)
        #expect(reabierto.folio(de: curso.id) == folio)
    }

    // MARK: - CA14.3 · Si el curso está lleno no puedo inscribirme

    @Test("Si el curso está lleno no puedo inscribirme")
    func cursoLleno() async throws {
        let (modelo, _, servidor) = await Self.modeloNuevo()
        let lleno = try #require(modelo.cursos.first { $0.estaLleno })

        await #expect(throws: ErrorInscripcion.cursoLleno) {
            try await modelo.inscribir(en: lleno, nombre: nombreValido, celular: celularValido)
        }
        #expect(modelo.folio(de: lleno.id) == nil)
        #expect(servidor.inscritos.isEmpty)
    }

    @Test("Si alguien más ganó el último lugar, el servidor lo rechaza y el curso queda lleno")
    func ultimoLugarGanadoPorOtro() async throws {
        let (modelo, _, servidor) = await Self.modeloNuevo()
        let curso = try #require(modelo.cursos.first { $0.lugaresDisponibles == 1 })

        // Otra persona se inscribe desde otro teléfono: el teléfono aún cree que queda 1 lugar.
        let i = try #require(servidor.lista.firstIndex { $0.id == curso.id })
        servidor.lista[i].inscritos += 1

        await #expect(throws: ErrorInscripcion.cursoLleno) {
            try await modelo.inscribir(en: curso, nombre: nombreValido, celular: celularValido)
        }
        #expect(modelo.cursos.first { $0.id == curso.id }?.estaLleno == true)
    }

    // MARK: - CA14.4 · Con datos incompletos no puedo inscribirme

    @Test("Con datos incompletos no puedo inscribirme", arguments: [
        ("Al", "8112345678"),
        ("Ana López", "81123"),
        ("   ", "8112345678"),
    ])
    func datosIncompletos(nombre: String, celular: String) async throws {
        #expect(!CapacitacionModelo.datosValidos(nombre: nombre, celular: celular))

        let (modelo, _, servidor) = await Self.modeloNuevo()
        let curso = try #require(modelo.cursos.first { !$0.estaLleno })
        await #expect(throws: ErrorInscripcion.faltanDatos) {
            try await modelo.inscribir(en: curso, nombre: nombre, celular: celular)
        }
        #expect(servidor.inscritos.isEmpty)
    }

    @Test("El celular con lada +52 cuenta como 10 dígitos")
    func celularConLada() {
        #expect(CapacitacionModelo.datosValidos(nombre: "Ana López", celular: "+52 81 1234 5678"))
    }
}
