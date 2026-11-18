//
//  TranscripcionTests.swift
//  Pruebas unitarias de la transcripción de la llamada (RF12, HU09).
//
//  No usan micrófono ni internet: prueban cómo se preparan las frases, la cola de envío y
//  qué hace la app cuando el servidor falla, con un servidor FALSO en lugar del backend.
//  (Lo que guarda el servidor se prueba en backend/test/llamadas.test.js.)
//

import Foundation
import Testing
@testable import CruzRoja

/// Servidor falso: guarda lo que la app le manda y puede fallar cuando la prueba lo pide.
@MainActor
final class ServidorDeTranscripcionFalso {
    var error: Error?
    private(set) var envios: [(llamada: UUID, lineas: [LineaTranscrita])] = []

    func recibir(llamada: UUID, lineas: [LineaTranscrita]) throws {
        if let error { throw error }
        envios.append((llamada, lineas))
    }
}

@Suite("HU09 · Transcripción de la llamada")
@MainActor
struct TranscripcionTests {
    let llamada = UUID()

    /// Transcriptor conectado al servidor falso (no enciende el micrófono).
    static func transcriptor(con servidor: ServidorDeTranscripcionFalso) -> TranscriptorLlamada {
        TranscriptorLlamada { llamada, lineas in
            try servidor.recibir(llamada: llamada, lineas: lineas)
        }
    }

    // MARK: - Preparar el texto

    @Test("El texto se manda en un solo renglón y sin espacios de más")
    func limpiarTexto() {
        #expect(TextoTranscrito.limpiar("  Hubo un   choque\nen la avenida \t Constitución ") ==
                "Hubo un choque en la avenida Constitución")
        #expect(TextoTranscrito.limpiar(" \n ").isEmpty)
    }

    @Test("Una frase vacía no produce líneas")
    func fraseVacia() {
        #expect(TextoTranscrito.lineas(de: "   ", segundo: 5).isEmpty)
    }

    @Test("Una frase larga se parte sin cortar palabras ni perder ninguna")
    func fraseLarga() {
        let palabras = (1...60).map { "palabra\($0)" }
        let lineas = TextoTranscrito.lineas(de: palabras.joined(separator: " "), segundo: 12, maximo: 100)

        #expect(lineas.count > 1)
        #expect(lineas.allSatisfy { $0.texto.count <= 100 && $0.segundo == 12 })
        #expect(lineas.flatMap { $0.texto.split(separator: " ").map(String.init) } == palabras)
    }

    @Test("Una palabra más larga que el máximo también se manda completa")
    func palabraMuyLarga() {
        let lineas = TextoTranscrito.lineas(de: String(repeating: "a", count: 25), segundo: 0, maximo: 10)
        #expect(lineas.map(\.texto.count) == [10, 10, 5])
    }

    // MARK: - Cola de envío

    @Test("La cola entrega máximo 20 líneas por envío, de la más antigua a la más nueva")
    func colaPorEnvios() {
        var cola = ColaTranscripcion()
        for numero in 1...25 { cola.agregar("frase \(numero)", segundo: numero) }

        let primero = cola.siguienteEnvio
        #expect(primero.count == ColaTranscripcion.maximoPorEnvio)
        #expect(primero.first?.texto == "frase 1")

        cola.confirmar(primero.count)
        #expect(cola.siguienteEnvio.map(\.texto) == ["frase 21", "frase 22", "frase 23", "frase 24", "frase 25"])

        cola.confirmar(100) // confirmar de más no falla
        #expect(cola.estaVacia)
    }

    @Test("Si el servidor no responde por mucho tiempo, se conservan las frases más recientes")
    func colaConTope() {
        var cola = ColaTranscripcion()
        let total = ColaTranscripcion.maximoPendientes + 30
        for numero in 1...total { cola.agregar("frase \(numero)", segundo: numero) }

        #expect(cola.pendientes.count == ColaTranscripcion.maximoPendientes)
        #expect(cola.pendientes.first?.texto == "frase 31")
        #expect(cola.pendientes.last?.texto == "frase \(total)")
    }

    // MARK: - Envío al operador

    @Test("Las frases terminadas llegan al servidor con su segundo y salen de la cola")
    func envioAlOperador() async {
        let servidor = ServidorDeTranscripcionFalso()
        let transcriptor = Self.transcriptor(con: servidor)

        transcriptor.registrar(frase: "  Hubo un choque  ", segundo: 4)
        transcriptor.registrar(frase: "Hay dos personas lesionadas", segundo: 9)
        transcriptor.registrar(frase: "   ", segundo: 10) // una frase vacía no se manda
        #expect(transcriptor.ultimaFrase == "Hay dos personas lesionadas")

        await transcriptor.enviarPendientes(de: llamada)

        #expect(servidor.envios.count == 1)
        #expect(servidor.envios.first?.llamada == llamada)
        #expect(servidor.envios.first?.lineas == [
            LineaTranscrita(texto: "Hubo un choque", segundo: 4),
            LineaTranscrita(texto: "Hay dos personas lesionadas", segundo: 9),
        ])
        #expect(transcriptor.cola.estaVacia)

        // Sin frases nuevas no se molesta al servidor.
        await transcriptor.enviarPendientes(de: llamada)
        #expect(servidor.envios.count == 1)
    }

    @Test("Sin conexión las frases se quedan guardadas y se mandan cuando el servidor vuelve")
    func reintentoSinConexion() async {
        let servidor = ServidorDeTranscripcionFalso()
        let transcriptor = Self.transcriptor(con: servidor)
        transcriptor.registrar(frase: "Necesito una ambulancia", segundo: 3)

        servidor.error = EmergencyAPIError.sinConexion
        await transcriptor.enviarPendientes(de: llamada)
        #expect(servidor.envios.isEmpty)
        #expect(transcriptor.cola.pendientes.count == 1)

        servidor.error = nil
        await transcriptor.enviarPendientes(de: llamada)
        #expect(servidor.envios.count == 1)
        #expect(transcriptor.cola.estaVacia)
    }

    @Test("Si la llamada ya terminó en el servidor, la app deja de mandar texto")
    func llamadaTerminada() async {
        let servidor = ServidorDeTranscripcionFalso()
        let transcriptor = Self.transcriptor(con: servidor)
        transcriptor.registrar(frase: "Sigo en la línea", segundo: 2)

        servidor.error = EmergencyAPIError.callClosed
        await transcriptor.enviarPendientes(de: llamada)
        #expect(transcriptor.cola.estaVacia)

        // Aunque el servidor vuelva a aceptar, de esta llamada ya no se manda nada.
        servidor.error = nil
        transcriptor.registrar(frase: "Otra frase", segundo: 8)
        await transcriptor.enviarPendientes(de: llamada)
        #expect(servidor.envios.isEmpty)
    }

    @Test("El cuerpo del envío tiene el formato que espera el servidor")
    func formatoDelEnvio() throws {
        let cuerpo = TranscriptRequest(
            deviceId: "123e4567-e89b-42d3-a456-426614174000",
            lines: [TranscriptLine(text: "Hubo un choque", second: 4)]
        )
        let datos = try JSONEncoder().encode(cuerpo)
        let objeto = try JSONSerialization.jsonObject(with: datos)
        let json = try #require(objeto as? [String: Any])

        #expect(json["deviceId"] as? String == "123e4567-e89b-42d3-a456-426614174000")
        let lineas = try #require(json["lines"] as? [[String: Any]])
        #expect(lineas.count == 1)
        #expect(lineas[0]["text"] as? String == "Hubo un choque")
        #expect(lineas[0]["second"] as? Int == 4)
    }
}
