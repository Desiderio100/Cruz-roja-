#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable(description: "Datos de una emergencia que la persona dijo por teléfono")
struct DatosEmergencia {
    @Guide(description: "Qué pasó, en una frase corta. Vacío si no lo dijo")
    var motivo: String
    @Guide(description: "Cuántas personas están lesionadas, solo el número con dígitos. Vacío si no lo dijo")
    var lesionados: String
    @Guide(description: "La lesión más grave que mencionó. Vacío si no la dijo")
    var lesionPrincipal: String
    @Guide(description: "Dónde está la persona: calle, colonia o referencias. Vacío si no lo dijo")
    var lugar: String
    @Guide(description: "Otro dato importante que dijo. Vacío si no hay")
    var comentarios: String
}

@available(iOS 26.0, *)
@MainActor
final class AsistenteLlamada {
    private let llamadaId: UUID
    private var transcripcion: TranscripcionLlamada?
    private var lineas: [String] = []
    private var tareaFicha: Task<Void, Never>?
    private var ultimoEnvio: FichaIAEnvio?

    private static let instrucciones = """
    Eres un asistente de Cruz Roja Mexicana. Lees lo que una persona dijo por teléfono durante una emergencia y llenas una ficha.
    Usa solo lo que la persona dijo. No inventes nada. Si un dato no se dijo, déjalo vacío.
    Escribe todo en español, de forma corta y clara.
    """

    init(llamadaId: UUID) {
        self.llamadaId = llamadaId
    }

    static var modeloDisponible: Bool {
        let modelo = SystemLanguageModel.default
        guard case .available = modelo.availability else { return false }
        return modelo.supportsLocale(Locale(identifier: "es_MX"))
    }

    func iniciar() async -> Bool {
        guard Self.modeloDisponible else { return false }
        let nueva = TranscripcionLlamada { [weak self] texto, segundo in
            Task { @MainActor in self?.nuevaFrase(texto, segundo: segundo) }
        }
        guard await nueva.iniciar() else { return false }
        transcripcion = nueva
        return true
    }

    func detener() async {
        tareaFicha?.cancel()
        await transcripcion?.detener()
        transcripcion = nil
        await extraer()
    }

    private func nuevaFrase(_ texto: String, segundo: Int) {
        lineas.append(texto)
        let id = llamadaId
        Task {
            try? await EmergencyAPI.shared.sendTranscript(id: id, lines: [(texto: texto, segundo: segundo)])
        }
        tareaFicha?.cancel()
        tareaFicha = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.extraer()
        }
    }

    private func extraer() async {
        guard !lineas.isEmpty else { return }
        var texto = lineas.joined(separator: "\n")
        if texto.count > 2500 { texto = String(texto.suffix(2500)) }
        let sesion = LanguageModelSession(instructions: Self.instrucciones)
        guard let respuesta = try? await sesion.respond(
            to: "Esto dijo la persona:\n\(texto)",
            generating: DatosEmergencia.self
        ) else { return }
        let datos = respuesta.content
        let envio = FichaIAEnvio(
            motivo: Self.limpio(datos.motivo),
            numLesionados: Int(datos.lesionados.filter(\.isNumber)),
            lesionPrincipal: Self.limpio(datos.lesionPrincipal),
            lugar: Self.limpio(datos.lugar),
            comentarios: Self.limpio(datos.comentarios)
        )
        guard envio != ultimoEnvio, !envio.estaVacia else { return }
        ultimoEnvio = envio
        try? await EmergencyAPI.shared.sendFicha(id: llamadaId, ficha: envio)
    }

    private static func limpio(_ texto: String) -> String? {
        let recortado = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return recortado.isEmpty ? nil : recortado
    }
}
#endif
