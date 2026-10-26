//
//  CapacitacionTests.swift
//  Pruebas unitarias de HU14 · Inscripción a capacitación.
//
//  Cada prueba usa su propio almacén vacío, así no toca las inscripciones
//  guardadas en el simulador ni depende de otras pruebas.
//

import Foundation
import Testing
@testable import CruzRoja

@Suite("HU14 · Inscripción a capacitación")
struct CapacitacionTests {
    typealias ErrorInscripcion = CapacitacionModelo.ErrorInscripcion

    /// Datos de una persona que sí cumplen la validación.
    let nombreValido = "Ana López"
    let celularValido = "8112345678"

    /// Modelo con un almacén vacío solo para esta prueba.
    static func modeloNuevo() -> (modelo: CapacitacionModelo, almacen: UserDefaults) {
        let suite = "pruebas.capacitacion.\(UUID().uuidString)"
        let almacen = UserDefaults(suiteName: suite)!
        almacen.removePersistentDomain(forName: suite)
        return (CapacitacionModelo(almacen: almacen), almacen)
    }

    // MARK: - CA14.1 · Los cursos aparecen con fecha y lugares disponibles

    @Test("Los cursos aparecen con fecha y lugares disponibles")
    func cursosConFechaYLugares() {
        let modelo = Self.modeloNuevo().modelo
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

    // MARK: - CA14.2 · Con cupo, al inscribirme recibo una confirmación

    @Test("Con cupo, inscribirme da un folio de confirmación")
    func inscripcionConCupo() throws {
        let modelo = Self.modeloNuevo().modelo
        let curso = try #require(modelo.cursos.first { !$0.estaLleno })
        let lugaresAntes = curso.lugaresDisponibles

        let folio = try modelo.inscribir(en: curso, nombre: nombreValido, celular: celularValido)

        #expect(folio.hasPrefix("CR-"))
        #expect(folio.count == 9)
        #expect(modelo.folio(de: curso.id) == folio)
        let actualizado = try #require(modelo.cursos.first { $0.id == curso.id })
        #expect(actualizado.lugaresDisponibles == lugaresAntes - 1)
    }

    @Test("No puedo inscribirme dos veces y la inscripción queda guardada")
    func noDosVecesYQuedaGuardada() throws {
        let (modelo, almacen) = Self.modeloNuevo()
        let curso = try #require(modelo.cursos.first { !$0.estaLleno })
        let folio = try modelo.inscribir(en: curso, nombre: nombreValido, celular: celularValido)

        #expect(throws: ErrorInscripcion.yaInscrito) {
            try modelo.inscribir(en: curso, nombre: nombreValido, celular: celularValido)
        }

        // Al volver a abrir la app, la inscripción se lee del teléfono.
        let reabierto = CapacitacionModelo(almacen: almacen)
        #expect(reabierto.folio(de: curso.id) == folio)
    }

    // MARK: - CA14.3 · Si el curso está lleno no puedo inscribirme

    @Test("Si el curso está lleno no puedo inscribirme")
    func cursoLleno() throws {
        let modelo = Self.modeloNuevo().modelo
        let lleno = try #require(modelo.cursos.first { $0.estaLleno })

        #expect(throws: ErrorInscripcion.cursoLleno) {
            try modelo.inscribir(en: lleno, nombre: nombreValido, celular: celularValido)
        }
        #expect(modelo.folio(de: lleno.id) == nil)
    }

    // MARK: - CA14.4 · Con datos incompletos no puedo inscribirme

    @Test("Con datos incompletos no puedo inscribirme", arguments: [
        ("Al", "8112345678"),
        ("Ana López", "81123"),
        ("   ", "8112345678"),
    ])
    func datosIncompletos(nombre: String, celular: String) throws {
        #expect(!CapacitacionModelo.datosValidos(nombre: nombre, celular: celular))

        let modelo = Self.modeloNuevo().modelo
        let curso = try #require(modelo.cursos.first { !$0.estaLleno })
        #expect(throws: ErrorInscripcion.faltanDatos) {
            try modelo.inscribir(en: curso, nombre: nombre, celular: celular)
        }
    }
}
