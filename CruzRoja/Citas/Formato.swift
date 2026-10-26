import Foundation

// Convierte fechas a texto, por ejemplo "Vie 23 oct" y "09:00 - 10:00".
@MainActor
enum Formato {
    private static func formateador(_ patron: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = patron
        return f
    }

    private static let diaSemana = formateador("EEE")
    private static let diaMes = formateador("d")
    private static let diaCompleto = formateador("EEE d MMM")
    private static let hora = formateador("HH:mm")

    private static func primeraMayuscula(_ texto: String) -> String {
        let limpio = texto.replacingOccurrences(of: ".", with: "")
        return limpio.prefix(1).uppercased() + String(limpio.dropFirst())
    }

    static func etiquetaDia(_ fecha: Date) -> String {
        if Calendar.current.isDateInToday(fecha) { return "Hoy" }
        return primeraMayuscula(diaSemana.string(from: fecha))
    }

    static func numeroDia(_ fecha: Date) -> String {
        diaMes.string(from: fecha)
    }

    static func rango(_ inicio: Date) -> String {
        // Cada cita dura un bloque de una hora.
        let fin = inicio.addingTimeInterval(3600)
        return "\(hora.string(from: inicio)) - \(hora.string(from: fin))"
    }

    static func fechaYRango(_ inicio: Date) -> String {
        "\(primeraMayuscula(diaCompleto.string(from: inicio))), \(rango(inicio))"
    }
}
