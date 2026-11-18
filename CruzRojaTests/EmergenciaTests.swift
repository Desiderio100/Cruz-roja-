// Responsable del módulo de emergencia: Ayhan Ben Halima Martinez · A01647593
import Foundation
import Testing
@testable import CruzRoja

@Suite("Emergencia · Respuesta de la API de llamadas")
struct EmergenciaTests {
    /// Contrato de POST /api/llamadas: la app necesita la sesión y la delegación
    /// para abrir la pantalla de llamada. Usa datos ficticios, sin servidor ni DB.
    @Test("Una respuesta válida conserva la llamada y la delegación asignada")
    func respuestaValida() throws {
        // Preparación: respuesta con el mismo formato que devuelve rutas/llamadas.js.
        let respuesta = Data(#"""
        {
          "id": "123e4567-e89b-42d3-a456-426614174000",
          "status": "en_curso",
          "delegation": {
            "id": 7,
            "name": "Delegación de prueba",
            "phone": "+528100000007"
          }
        }
        """#.utf8)

        // Acción: el mismo modelo y decodificador que usa EmergencyAPI.startCall.
        let sesion = try JSONDecoder().decode(EmergencySession.self, from: respuesta)

        // Verificación: no se pierden ni intercambian los datos de la llamada.
        #expect(sesion.id.uuidString.lowercased() == "123e4567-e89b-42d3-a456-426614174000")
        #expect(sesion.status == "en_curso")
        #expect(sesion.delegation.id == 7)
        #expect(sesion.delegation.name == "Delegación de prueba")
        #expect(sesion.delegation.phone == "+528100000007")
    }

    /// Sin delegación no hay información suficiente para mostrar a quién se asignó
    /// la llamada. El decodificador debe fallar en vez de inventar esa información.
    @Test("Una respuesta sin delegación se rechaza")
    func respuestaIncompleta() {
        let respuesta = Data(#"""
        {
          "id": "123e4567-e89b-42d3-a456-426614174000",
          "status": "en_curso"
        }
        """#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(EmergencySession.self, from: respuesta)
        }
    }
}
