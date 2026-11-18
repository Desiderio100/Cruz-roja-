//
//  CitasTests.swift
//  Pruebas unitarias de la Agenda de citas (HU12 y HU13).
//  Prueban cómo la app lee las respuestas de la API (mismo decodificador que ClienteAPI)
//  y cómo muestra el horario de una cita. No usan internet ni el backend.
//

import Foundation
import Testing
@testable import CruzRoja

@Suite("HU12 · Agenda de citas")
@MainActor
struct CitasTests {
    let decodificador = ClienteAPI.compartido.decodificador

    @Test("Lee los horarios libres que manda GET /api/citas/horarios")
    func horarios() throws {
        let json = Data(#"""
        [{"inicio": "2026-11-20T15:00:00.000Z", "especialistas_libres": 2},
         {"inicio": "2026-11-20T16:00:00.000Z", "especialistas_libres": 1}]
        """#.utf8)

        let horarios = try decodificador.decode([Horario].self, from: json)

        #expect(horarios.count == 2)
        #expect(horarios[0].especialistasLibres == 2)
        #expect(horarios[1].inicio.timeIntervalSince(horarios[0].inicio) == 3600)
    }

    @Test("Lee una cita de GET /api/citas y reconoce cuando está pospuesta")
    func citaPospuesta() throws {
        let json = Data(#"""
        {"id": "123e4567-e89b-42d3-a456-426614174000", "folio": "CR-000012",
         "servicio": "psicologia", "inicio": "2026-11-20T15:00:00.000Z",
         "estado": "pospuesta", "delegacion_id": 2, "delegacion": "Monterrey"}
        """#.utf8)

        let cita = try decodificador.decode(Cita.self, from: json)

        #expect(cita.folio == "CR-000012")
        #expect(cita.nombreServicio == "Psicología")
        #expect(cita.estaPospuesta)
        #expect(cita.delegacionId == 2)
    }

    @Test("Una fecha mal escrita no se acepta en silencio")
    func fechaInvalida() {
        let json = Data(#"""
        [{"inicio": "20/11/2026 9:00", "especialistas_libres": 1}]
        """#.utf8)
        #expect(throws: DecodingError.self) {
            try decodificador.decode([Horario].self, from: json)
        }
    }

    @Test("Cada cita se muestra como un bloque de una hora")
    func rangoDeUnaHora() throws {
        var partes = DateComponents()
        partes.calendar = Calendar.current
        partes.year = 2026; partes.month = 11; partes.day = 20; partes.hour = 9
        let inicio = try #require(partes.date)

        #expect(Formato.rango(inicio) == "09:00 - 10:00")
    }
}
