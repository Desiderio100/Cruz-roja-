// Para agregar un video: pon el ID de YouTube (lo que va después de "watch?v=")
// en `videoID`. Si no hay video elegido, el botón abre una búsqueda en YouTube
// con `busqueda`, que siempre muestra los videos más vistos del tema.

import Foundation

struct Tema: Identifiable {
    let id: String
    let titulo: String
    let icono: String
    let pasos: [String]
    let videoID: String?
    let busqueda: String

    var urlVideo: URL {
        if let videoID, Self.esIDValido(videoID) {
            return URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
        }
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: busqueda)]
        return c.url!
    }

    var urlMiniatura: URL? {
        guard let videoID, Self.esIDValido(videoID) else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
    }

    static func esIDValido(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

extension Tema {
    static let basicos: [Tema] = [
        Tema(id: "911", titulo: "Cómo pedir ayuda", icono: "phone.fill",
             pasos: [
                "Asegúrate de que el lugar es seguro para ti.",
                "Llama al 911 y di qué pasó y cuántas personas están heridas.",
                "Da la dirección exacta y una referencia (\"frente al Oxxo\").",
                "No cuelgues hasta que te lo indiquen.",
             ],
             videoID: nil, busqueda: "cómo llamar al 911 emergencia qué decir"),

        Tema(id: "rcp", titulo: "RCP en adultos", icono: "heart.fill",
             pasos: [
                "Si no responde y no respira normal, llama al 911 y pide un desfibrilador (DEA).",
                "Pon tus manos una sobre otra en el centro del pecho.",
                "Empuja fuerte y rápido: 5 cm de profundidad, 100 a 120 veces por minuto.",
                "Deja que el pecho regrese entre cada compresión.",
                "No pares hasta que llegue ayuda o la persona reaccione.",
             ],
             videoID: "FEayzgNGGBQ", busqueda: "RCP adultos Cruz Roja"),

        Tema(id: "atragantamiento", titulo: "Atragantamiento", icono: "lungs.fill",
             pasos: [
                "Si puede toser, anímale a seguir tosiendo.",
                "Si no puede hablar ni respirar: 5 golpes fuertes en la espalda, entre los omóplatos.",
                "Luego 5 compresiones abdominales: puño arriba del ombligo, hacia adentro y arriba.",
                "Alterna hasta que salga el objeto.",
                "Si pierde el conocimiento, llama al 911 y empieza RCP.",
             ],
             videoID: "HDsBQJhIRZc", busqueda: "maniobra de Heimlich Cruz Roja"),

        Tema(id: "hemorragias", titulo: "Hemorragias", icono: "drop.fill",
             pasos: [
                "Protégete las manos (guantes o una bolsa de plástico).",
                "Presiona fuerte sobre la herida con una tela limpia.",
                "Si la tela se empapa, no la quites: pon otra encima.",
                "Mantén la presión hasta que llegue ayuda.",
             ],
             videoID: "IfSZl6izsFk", busqueda: "cómo controlar una hemorragia primeros auxilios Cruz Roja"),

        Tema(id: "posicion-lateral", titulo: "Posición lateral de seguridad", icono: "bed.double.fill",
             pasos: [
                "Úsala si la persona no responde pero sí respira normal.",
                "Acuéstala de lado con la pierna de arriba doblada.",
                "Inclina su cabeza un poco hacia atrás para que respire bien.",
                "Vigila que siga respirando hasta que llegue ayuda.",
             ],
             videoID: "cLA-g8mWal4", busqueda: "posición lateral de seguridad Cruz Roja"),

        Tema(id: "quemaduras", titulo: "Quemaduras", icono: "flame.fill",
             pasos: [
                "Enfría con agua corriente fresca (no helada) al menos 10 minutos.",
                "Quita anillos o ropa que no esté pegada a la piel.",
                "Cubre con una tela limpia, sin apretar.",
                "No pongas hielo, pasta de dientes ni remedios caseros.",
                "Ve al médico si es grande, en cara o manos, o si es un niño.",
             ],
             videoID: nil, busqueda: "primeros auxilios quemaduras Cruz Roja"),
    ]
}
