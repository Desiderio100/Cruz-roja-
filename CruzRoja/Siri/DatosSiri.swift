import AppIntents
import CoreLocation
import Foundation
import UIKit

enum UltimaUbicacion {
    private static let llaveLatitud = "ultima_ubicacion_latitud"
    private static let llaveLongitud = "ultima_ubicacion_longitud"

    static func guardar(_ punto: CLLocationCoordinate2D) {
        UserDefaults.standard.set(punto.latitude, forKey: llaveLatitud)
        UserDefaults.standard.set(punto.longitude, forKey: llaveLongitud)
    }

    static func leer() -> CLLocationCoordinate2D? {
        let datos = UserDefaults.standard
        guard datos.object(forKey: llaveLatitud) != nil, datos.object(forKey: llaveLongitud) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: datos.double(forKey: llaveLatitud), longitude: datos.double(forKey: llaveLongitud))
    }
}

enum DiasCitas {
    static func disponibles() -> [Date] {
        var resultado: [Date] = []
        var dia = Calendar.current.startOfDay(for: Date())
        while resultado.count < 5 {
            if !Calendar.current.isDateInWeekend(dia) { resultado.append(dia) }
            dia = Calendar.current.date(byAdding: .day, value: 1, to: dia) ?? dia.addingTimeInterval(86400)
        }
        return resultado
    }

    static func dia(de texto: String, entre dias: [Date]) -> Date? {
        let limpio = texto.folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let calendario = Calendar.current
        let hoy = calendario.startOfDay(for: Date())

        func desplazado(_ cantidad: Int) -> Date? {
            guard let fecha = calendario.date(byAdding: .day, value: cantidad, to: hoy) else { return nil }
            return dias.first { calendario.isDate($0, inSameDayAs: fecha) }
        }

        if limpio.contains("pasado manana") { return desplazado(2) }
        if limpio.contains("manana") { return desplazado(1) }
        if limpio.contains("hoy") { return desplazado(0) }

        let semana = ["domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4, "jueves": 5, "viernes": 6, "sabado": 7]
        for (nombre, numero) in semana where limpio.contains(nombre) {
            return dias.first { calendario.component(.weekday, from: $0) == numero }
        }

        let lector = DateFormatter()
        lector.locale = Locale(identifier: "en_US_POSIX")
        lector.dateFormat = "yyyy-MM-dd"
        if let fecha = lector.date(from: limpio) {
            return dias.first { calendario.isDate($0, inSameDayAs: fecha) }
        }
        return nil
    }

    static func etiqueta(_ fecha: Date) -> String {
        fecha.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_MX")))
    }

    static func lista(_ dias: [Date]) -> String {
        dias.map { etiqueta($0) }.joined(separator: ", ")
    }
}

enum HorarioSiri {
    private static let palabras: [String: Int] = [
        "una": 1, "uno": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7,
        "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14,
        "quince": 15, "dieciseis": 16, "diecisiete": 17, "dieciocho": 18
    ]

    static func elegir(_ texto: String, entre horarios: [Horario]) -> Horario? {
        let limpio = texto.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        guard let (hora, minuto) = horaYMinuto(limpio) else { return nil }
        let esTarde = limpio.contains("tarde") || limpio.contains("noche")
        let esManana = limpio.contains("manana")

        var candidatas = [hora]
        if hora < 12 && esTarde {
            candidatas = [hora + 12]
        } else if hora < 12 && !esManana {
            candidatas.append(hora + 12)
        }

        for candidata in candidatas {
            let encontrado = horarios.first { horario in
                let partes = Calendar.current.dateComponents([.hour, .minute], from: horario.inicio)
                return partes.hour == candidata && partes.minute == minuto
            }
            if let encontrado { return encontrado }
        }
        return nil
    }

    static func texto(_ fecha: Date) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_MX")
        formato.dateFormat = "H:mm"
        return formato.string(from: fecha)
    }

    private static func horaYMinuto(_ texto: String) -> (Int, Int)? {
        if let regla = try? NSRegularExpression(pattern: "(\\d{1,2})(?:[:.](\\d{2}))?"),
           let coincidencia = regla.firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)),
           let rangoHora = Range(coincidencia.range(at: 1), in: texto),
           let hora = Int(texto[rangoHora]) {
            var minuto = 0
            if let rangoMinuto = Range(coincidencia.range(at: 2), in: texto), let valor = Int(texto[rangoMinuto]) {
                minuto = valor
            } else if texto.contains("media") {
                minuto = 30
            }
            return (hora, minuto)
        }
        let separadores = CharacterSet.letters.inverted
        for palabra in texto.components(separatedBy: separadores) {
            if let hora = palabras[palabra] {
                return (hora, texto.contains("media") ? 30 : 0)
            }
        }
        return nil
    }
}

enum ResultadoHorario {
    case elegido(dia: Date, horario: Horario)
    case aviso(String)
}

@MainActor
enum DatosSiri {
    static func fechaHablada(_ fecha: Date) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_MX")
        formato.dateFormat = "EEEE d 'de' MMMM, 'a las' H:mm"
        return formato.string(from: fecha)
    }

    static func distanciaHablada(_ metros: Double) -> String {
        if metros < 1_000 { return "\(Int(metros.rounded())) metros" }
        return String(format: "%.1f kilómetros", metros / 1_000)
    }

    static func mensaje(_ error: Error) -> String {
        if let errorAPI = error as? ErrorAPI {
            if errorAPI.estado == 409 { return "Ese horario ya no está libre. Inténtalo de nuevo con otro horario." }
            return IdiomaChat.asegurar(errorAPI.mensaje, respaldo: TextosChat.errorGenerico)
        }
        return TextosChat.errorGenerico
    }

    nonisolated static func coincide(_ texto: String, con busqueda: String) -> Bool {
        let base = texto.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        let palabras = busqueda.folding(options: .diacriticInsensitive, locale: nil).lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if palabras.isEmpty { return true }
        return palabras.allSatisfy { base.contains($0) }
    }

    static func ubicacionActual() -> CLLocationCoordinate2D? {
        let manager = CLLocationManager()
        let estado = manager.authorizationStatus
        if estado == .authorizedWhenInUse || estado == .authorizedAlways, let punto = manager.location?.coordinate {
            return punto
        }
        return UltimaUbicacion.leer()
    }

    static func esperarAppActiva() async {
        var intentos = 0
        while UIApplication.shared.applicationState != .active && intentos < 30 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            intentos += 1
        }
    }

    static func abrirRuta(a centro: Centro, con aplicacion: AppMapa) async {
        switch aplicacion {
        case .apple: centro.abrirEnAppleMaps()
        case .google: _ = await UIApplication.shared.open(centro.urlGoogleMaps)
        case .waze: _ = await UIApplication.shared.open(centro.urlWaze)
        }
    }

    static func citasCancelables() async throws -> [CitaEntidad] {
        try await ClienteAPI.compartido.misCitas()
            .filter { !$0.estaPospuesta }
            .map { cita in
                CitaEntidad(
                    id: cita.id,
                    texto: "\(cita.nombreServicio), \(fechaHablada(cita.inicio))",
                    folio: cita.folio,
                    servicio: cita.servicio,
                    inicio: cita.inicio
                )
            }
    }

    static func citasPospuestas() async throws -> [CitaPospuestaEntidad] {
        try await ClienteAPI.compartido.misCitas()
            .filter { $0.estaPospuesta }
            .map { cita in
                CitaPospuestaEntidad(
                    id: cita.id,
                    texto: "\(cita.nombreServicio), pospuesta, antes \(fechaHablada(cita.inicio))",
                    folio: cita.folio,
                    servicio: cita.servicio,
                    delegacionId: cita.delegacionId
                )
            }
    }

    static func elegirHorario(
        servicio: Servicio,
        diaInicial: String,
        parametroDia: IntentParameter<String>,
        horarioInicial: String,
        parametroHorario: IntentParameter<String>
    ) async throws -> ResultadoHorario {
        let dias = DiasCitas.disponibles()
        var fecha = DiasCitas.dia(de: diaInicial, entre: dias)
        var intentos = 0
        while fecha == nil && intentos < 2 {
            let respuesta = try await parametroDia.requestValue(
                IntentDialog("Solo se puede agendar de lunes a viernes en los próximos cinco días hábiles: \(DiasCitas.lista(dias)). ¿Cuál día prefieres?")
            )
            fecha = DiasCitas.dia(de: respuesta, entre: dias)
            intentos += 1
        }
        guard let dia = fecha else {
            return .aviso("No pude entender el día. Inténtalo de nuevo en un momento.")
        }

        let horarios: [Horario]
        do {
            horarios = try await ClienteAPI.compartido.horarios(
                delegacionId: Configuracion.delegacionId,
                servicio: servicio,
                fecha: dia
            )
        } catch {
            return .aviso(mensaje(error))
        }
        if horarios.isEmpty {
            return .aviso("No hay horarios libres de \(servicio.nombre) el \(DiasCitas.etiqueta(dia)). Inténtalo con otro día.")
        }

        let libres = horarios.map { HorarioSiri.texto($0.inicio) }.joined(separator: ", ")
        var elegido = HorarioSiri.elegir(horarioInicial, entre: horarios)
        intentos = 0
        while elegido == nil && intentos < 2 {
            let respuesta = try await parametroHorario.requestValue(
                IntentDialog("Hay horarios libres de \(servicio.nombre) el \(DiasCitas.etiqueta(dia)) a las: \(libres). ¿A qué hora quieres tu cita?")
            )
            elegido = HorarioSiri.elegir(respuesta, entre: horarios)
            intentos += 1
        }
        guard let horario = elegido else {
            return .aviso("No pude entender la hora. Inténtalo de nuevo en un momento.")
        }
        return .elegido(dia: dia, horario: horario)
    }
}
