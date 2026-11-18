#if canImport(FoundationModels)
import FoundationModels
import Foundation
import Observation
import os

struct MensajeChat: Identifiable {
    enum Autor { case persona, asistente }

    let id = UUID()
    let autor: Autor
    let texto: String
}

@available(iOS 26.0, *)
@MainActor
@Observable
final class ChatModelo {
    private(set) var mensajes: [MensajeChat] = []
    private(set) var respondiendo = false
    let acciones: AccionesChat

    @ObservationIgnored private var sesion: LanguageModelSession?
    private static let registro = Logger(subsystem: "mx.tec.elrebano.CruzRoja", category: "Chat")

    init(acciones: AccionesChat) {
        self.acciones = acciones
    }

    func enviar(_ texto: String) async {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty, !respondiendo else { return }
        acciones.pendiente = nil
        mensajes.append(MensajeChat(autor: .persona, texto: limpio))

        if Self.pareceEmergencia(limpio) {
            mensajes.append(MensajeChat(autor: .asistente, texto: TextosChat.emergencia))
            return
        }

        respondiendo = true
        defer { respondiendo = false }
        let respuesta = await generar(limpio)
        mensajes.append(MensajeChat(autor: .asistente, texto: respuesta))
    }

    func confirmar() async {
        guard let texto = await acciones.confirmar() else { return }
        mensajes.append(MensajeChat(autor: .asistente, texto: texto))
    }

    func elegirApp(_ app: AppMapa) async {
        guard let texto = await acciones.elegirApp(app) else { return }
        mensajes.append(MensajeChat(autor: .asistente, texto: texto))
    }

    func descartarPendiente() {
        guard acciones.pendiente != nil else { return }
        acciones.pendiente = nil
        mensajes.append(MensajeChat(autor: .asistente, texto: TextosChat.accionCancelada))
    }

    private func generar(_ pregunta: String) async -> String {
        for intento in 0..<2 {
            let actual = sesion ?? crearSesion()
            sesion = actual
            let prompt = intento == 0 ? pregunta : pregunta + "\nResponde únicamente en español."
            do {
                let respuesta = try await actual.respond(to: prompt)
                let texto = respuesta.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !texto.isEmpty && IdiomaChat.esEspanol(texto) { return texto }
                Self.registro.notice("[Bot-iquin] Respuesta descartada (vacía o no parece español): \(texto, privacy: .public)")
            } catch let error as LanguageModelSession.GenerationError {
                Self.registro.error("[Bot-iquin] Error del modelo: \(String(describing: error), privacy: .public)")
                sesion = nil
                if case .guardrailViolation = error { return TextosChat.noPermitido }
            } catch {
                Self.registro.error("[Bot-iquin] Error al responder: \(String(describing: error), privacy: .public)")
                sesion = nil
            }
        }
        return TextosChat.sinRespuesta
    }

    private func crearSesion() -> LanguageModelSession {
        let herramientas: [any Tool] = [
            BuscarCentrosTool(acciones: acciones),
            ProponerRutaTool(acciones: acciones),
            ListarCursosTool(acciones: acciones),
            DetalleCursoTool(acciones: acciones),
            ProponerInscripcionTool(acciones: acciones),
            VerHorariosTool(acciones: acciones),
            VerMisCitasTool(acciones: acciones),
            ProponerCitaTool(acciones: acciones),
            ProponerCancelacionTool(acciones: acciones),
            ProponerReprogramacionTool(acciones: acciones)
        ]
        return LanguageModelSession(tools: herramientas, instructions: instrucciones())
    }

    private func instrucciones() -> String {
        let hoy = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "es_MX")))
        return """
        Eres Bot-iquin, el asistente de la app de Cruz Roja Mexicana. La persona usa español de México. Responde siempre y solo en español, con frases cortas, claras y amables. Hoy es \(hoy).
        Escribe en texto simple, sin Markdown: no uses asteriscos, almohadillas ni guiones para dar formato. Para una lista usa números (1., 2., 3.) y pon cada elemento en una sola línea, con sus datos separados por comas.
        Puedes ayudar con tres cosas: buscar el centro de Cruz Roja más cercano y abrir la ruta, consultar los cursos de capacitación e inscribirse, y consultar, agendar, cancelar o reprogramar citas de nutrición y psicología.
        Usa siempre las herramientas para obtener datos. Nunca inventes centros, teléfonos, cursos, horarios ni citas.
        Para abrir una ruta, inscribir, agendar, cancelar o reprogramar solo prepara la acción con la herramienta. La persona la confirma con un botón. Nunca digas que ya se hizo.
        Cuando una herramienta pida un número, usa el número de la lista que mostraste antes.
        Si piden algo distinto, como compras, su perfil o una emergencia, explica con amabilidad que eso se hace desde otra pantalla de la app y que tú solo ayudas con centros, cursos y citas.
        """
    }

    private static func pareceEmergencia(_ texto: String) -> Bool {
        let limpio = texto.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        let claves = ["emergencia", "ambulancia", "no respira", "infarto", "desmay", "sangrando", "convulsion", "me estoy muriendo", "se esta muriendo", "accidente"]
        return claves.contains { limpio.contains($0) }
    }
}
#endif
