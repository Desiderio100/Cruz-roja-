import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

enum DisponibilidadChat {
    static var estaDisponible: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let modelo = SystemLanguageModel.default
            guard case .available = modelo.availability else { return false }
            return modelo.supportsLocale(Locale(identifier: "es_MX"))
        }
        #endif
        return false
    }
}

enum IdiomaChat {
    static func esEspanol(_ texto: String) -> Bool {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpio.count < 20 { return true }
        let reconocedor = NLLanguageRecognizer()
        reconocedor.processString(limpio)
        // Nombres de centros, calles y colonias confunden al detector, así que solo se descarta
        // la respuesta cuando claramente está en inglés (el error real que se quiere evitar).
        let probabilidades = reconocedor.languageHypotheses(withMaximum: 3)
        let espanol = probabilidades[.spanish] ?? 0
        let ingles = probabilidades[.english] ?? 0
        return !(ingles > 0.5 && ingles > espanol)
    }

    static func asegurar(_ texto: String, respaldo: String) -> String {
        esEspanol(texto) ? texto : respaldo
    }
}

enum TextosChat {
    static let bienvenida = "Hola, soy Bot-iquin. ¿En qué te ayudo?"
    static let emergencia = "Si es una emergencia, cierra el chat y usa el botón de Emergencia de la pantalla principal. También puedes llamar al 911."
    static let sinRespuesta = "No pude responder bien. ¿Puedes escribirlo de otra forma?"
    static let noPermitido = "No puedo responder eso. Puedo ayudarte con centros, cursos y citas."
    static let accionCancelada = "Listo, no hice ningún cambio."
    static let errorGenerico = "No se pudo completar. Intenta de nuevo en un momento."
    static let sugerencias = [
        "¿Cuál es el centro más cercano?",
        "¿Qué cursos hay?",
        "Quiero agendar una cita",
        "Ver mis citas"
    ]
}
