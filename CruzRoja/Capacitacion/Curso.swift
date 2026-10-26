import Foundation

/// Un curso de capacitación con su fecha, sede y cupo.
struct Curso: Identifiable, Hashable {
    let id: String
    let titulo: String
    let descripcion: String
    let fecha: Date
    let duracion: String
    let sede: String
    let cupo: Int
    var inscritos: Int
    let costo: Int?          // nil = gratuito

    /// Lugares que quedan; nunca es negativo.
    var lugaresDisponibles: Int { max(0, cupo - inscritos) }
    var estaLleno: Bool { lugaresDisponibles == 0 }

    /// "Curso lleno", "Queda 1 lugar" o "Quedan N lugares".
    var textoLugares: String {
        switch lugaresDisponibles {
        case 0: "Curso lleno"
        case 1: "Queda 1 lugar"
        default: "Quedan \(lugaresDisponibles) lugares"
        }
    }

    /// "$350 MXN" o "Gratuito".
    var textoCosto: String { (costo ?? 0) > 0 ? "$\(costo!) MXN" : "Gratuito" }

    var textoFecha: String { fecha.textoCurso }
}

extension Curso {
    /// Cursos de prueba (fechas relativas a hoy para que siempre se vean "próximos").
    static let ejemplos: [Curso] = [
        Curso(id: "primeros-auxilios", titulo: "Primeros auxilios básicos",
              descripcion: "Valorar a una persona lesionada, controlar hemorragias, atender quemaduras y actuar mientras llega la ambulancia.",
              fecha: .enDias(4, hora: 10), duracion: "4 horas",
              sede: "Cruz Roja Monterrey Centro", cupo: 20, inscritos: 12, costo: 350),
        Curso(id: "rcp-adultos", titulo: "RCP para adultos",
              descripcion: "Reanimación cardiopulmonar paso a paso y uso del desfibrilador (DEA).",
              fecha: .enDias(6, hora: 9), duracion: "3 horas",
              sede: "Cruz Roja San Nicolás", cupo: 15, inscritos: 15, costo: 300),
        Curso(id: "pediatricos", titulo: "Primeros auxilios pediátricos",
              descripcion: "Atragantamiento, fiebre, caídas y RCP en bebés y niños.",
              fecha: .enDias(9, hora: 16), duracion: "3 horas",
              sede: "Cruz Roja San Pedro", cupo: 12, inscritos: 11, costo: 300),
        Curso(id: "prevencion-hogar", titulo: "Prevención de accidentes en el hogar",
              descripcion: "Identificar riesgos en casa y armar un botiquín básico.",
              fecha: .enDias(12, hora: 18), duracion: "1 hora 30 min",
              sede: "Cruz Roja Guadalupe", cupo: 40, inscritos: 15, costo: nil),
    ]
}

private extension Date {
    static func enDias(_ dias: Int, hora: Int) -> Date {
        let cal = Calendar.current
        let dia = cal.date(byAdding: .day, value: dias, to: .now)!
        return cal.date(bySettingHour: hora, minute: 0, second: 0, of: dia)!
    }
}

extension Date {
    /// "sábado, 8 de noviembre · 10:00"
    var textoCurso: String {
        let mx = Locale(identifier: "es_MX")
        let dia = formatted(.dateTime.weekday(.wide).day().month(.wide).locale(mx))
        let hora = formatted(.dateTime.hour().minute().locale(mx))
        return "\(dia) · \(hora)"
    }
}
