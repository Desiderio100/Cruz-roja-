import Foundation
import Observation
import UIKit

enum AppMapa: String {
    case apple, google, waze

    var nombre: String {
        switch self {
        case .apple: return "Apple Maps"
        case .google: return "Google Maps"
        case .waze: return "Waze"
        }
    }

    static func desde(_ texto: String) -> AppMapa? {
        let limpio = texto.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        if limpio.contains("apple") { return .apple }
        if limpio.contains("google") { return .google }
        if limpio.contains("waze") { return .waze }
        return nil
    }
}

struct AccionPendiente: Identifiable {
    enum Tipo {
        case inscribir(Curso)
        case agendar(Servicio, Date)
        case cancelar(Cita)
        case reprogramar(Cita, Date)
        case abrirRuta(Centro, AppMapa)
        case elegirRuta(Centro)
    }

    let id = UUID()
    let tipo: Tipo
    let titulo: String
    let detalle: String
    let textoConfirmar: String
}

@MainActor
@Observable
final class AccionesChat {
    private let ubicacion: Ubicacion
    private let capacitacion: CapacitacionModelo
    private let internet: Internet

    private var centros: [Centro] = []
    private var cursos: [Curso] = []
    private var horarios: [Horario] = []
    private var servicioDeHorarios: Servicio?
    private var citas: [Cita] = []

    var pendiente: AccionPendiente?
    private(set) var ejecutando = false

    private let avisoConfirmacion = "La acción quedó preparada. Dile a la persona que la confirme con el botón que aparece en pantalla. No digas que ya se realizó."
    private let avisoPerfil = "Faltan el nombre o el celular en Mi perfil. Dile a la persona que los complete en Mi perfil, en la pantalla principal."

    init(ubicacion: Ubicacion, capacitacion: CapacitacionModelo, internet: Internet) {
        self.ubicacion = ubicacion
        self.capacitacion = capacitacion
        self.internet = internet
    }

    func buscarCentros(cantidad: Int) -> String {
        let tope = min(max(cantidad, 1), 5)
        var lineas: [String] = []
        if let punto = ubicacion.coordenada {
            let ordenados = Array(Centro.ordenados(desde: punto).prefix(tope))
            centros = ordenados.map { $0.centro }
            for (i, fila) in ordenados.enumerated() {
                lineas.append(describir(fila.centro, numero: i + 1, metros: fila.metros))
            }
        } else {
            centros = Array(Centro.todos.prefix(tope))
            for (i, centro) in centros.enumerated() {
                lineas.append(describir(centro, numero: i + 1, metros: nil))
            }
        }
        if lineas.isEmpty { return "No hay centros registrados." }
        let aviso = ubicacion.coordenada == nil ? "No se conoce la ubicación de la persona, así que la lista no está ordenada por cercanía.\n" : ""
        return aviso + lineas.joined(separator: "\n")
    }

    func proponerRuta(numero: Int, aplicacion: String) -> String {
        guard let centro = elemento(centros, numero) else {
            return "Primero busca los centros y elige un número de la lista."
        }
        guard let app = AppMapa.desde(aplicacion) else {
            pendiente = AccionPendiente(
                tipo: .elegirRuta(centro),
                titulo: "Abrir ruta",
                detalle: "\(centro.nombre). ¿Con qué aplicación quieres ir?",
                textoConfirmar: ""
            )
            return "En pantalla aparece una tarjeta para que la persona elija la aplicación de mapas. No le preguntes cuál quiere. Solo dile que la elija en la tarjeta."
        }
        pendiente = AccionPendiente(
            tipo: .abrirRuta(centro, app),
            titulo: "Abrir ruta",
            detalle: "\(centro.nombre), en \(app.nombre)",
            textoConfirmar: "Abrir \(app.nombre)"
        )
        return avisoConfirmacion
    }

    func listarCursos(cantidad: Int) async -> String {
        if capacitacion.cursos.isEmpty { await capacitacion.cargar() }
        cursos = Array(capacitacion.cursos.prefix(min(max(cantidad, 1), 10)))
        if cursos.isEmpty { return "No hay cursos próximos." }
        return cursos.enumerated().map { i, curso in
            var linea = "\(i + 1). \(curso.titulo). \(curso.textoFecha). Sede: \(curso.sede). Duración: \(curso.textoDuracion). Costo: \(curso.textoCosto). \(curso.textoLugares)."
            if capacitacion.folio(de: curso.id) != nil { linea += " La persona ya está inscrita." }
            return linea
        }.joined(separator: "\n")
    }

    func detalleCurso(numero: Int) -> String {
        guard let curso = elemento(cursos, numero) else {
            return "Primero muestra la lista de cursos y elige un número."
        }
        return "\(curso.titulo). \(curso.descripcion) \(curso.textoFecha). Sede: \(curso.sede). Duración: \(curso.textoDuracion). Costo: \(curso.textoCosto). \(curso.textoLugares)."
    }

    func proponerInscripcion(numero: Int) -> String {
        guard let curso = elemento(cursos, numero) else {
            return "Primero muestra la lista de cursos y elige un número."
        }
        if capacitacion.folio(de: curso.id) != nil { return "La persona ya está inscrita en este curso." }
        if curso.estaLleno { return "Ese curso ya no tiene lugares." }
        if !internet.hayConexion { return "Sin internet no se puede inscribir. Dile a la persona que lo intente cuando tenga conexión." }
        if datosParaInscribir() == nil { return avisoPerfil }
        pendiente = AccionPendiente(
            tipo: .inscribir(curso),
            titulo: "Inscribirte a un curso",
            detalle: "\(curso.titulo), \(curso.textoFecha). Sede: \(curso.sede).",
            textoConfirmar: "Sí, inscribirme"
        )
        return avisoConfirmacion
    }

    func verHorarios(servicio textoServicio: String, dia textoDia: String) async -> String {
        guard let servicio = servicioDe(textoServicio) else {
            return "Falta saber si es de nutrición o de psicología. Pregúntaselo a la persona."
        }
        let dias = diasDisponibles()
        guard let fecha = diaDe(textoDia, entre: dias) else {
            let lista = dias.map { etiquetaDia($0) }.joined(separator: ", ")
            return "Solo se puede agendar de lunes a viernes en los próximos cinco días hábiles: \(lista). Pide a la persona que elija uno."
        }
        do {
            let lista = try await ClienteAPI.compartido.horarios(
                delegacionId: Configuracion.delegacionId,
                servicio: servicio,
                fecha: fecha
            )
            horarios = lista
            servicioDeHorarios = servicio
            if lista.isEmpty { return "No hay horarios libres de \(servicio.nombre) ese día. Ofrece otro día." }
            return lista.enumerated().map { i, horario in
                "\(i + 1). \(Formato.fechaYRango(horario.inicio))"
            }.joined(separator: "\n")
        } catch {
            return mensaje(error)
        }
    }

    func verMisCitas(servicio textoServicio: String) async -> String {
        do {
            var lista = try await ClienteAPI.compartido.misCitas()
            if let filtro = servicioDe(textoServicio) {
                lista = lista.filter { $0.servicio == filtro.rawValue }
            }
            citas = lista
            if lista.isEmpty { return "La persona no tiene citas." }
            return lista.enumerated().map { i, cita in
                let estado = cita.estaPospuesta ? " Estado: pospuesta, necesita un nuevo horario." : ""
                return "\(i + 1). \(cita.nombreServicio), \(Formato.fechaYRango(cita.inicio)). Folio \(cita.folio).\(estado)"
            }.joined(separator: "\n")
        } catch {
            return mensaje(error)
        }
    }

    func proponerCita(numeroHorario: Int) -> String {
        guard let servicio = servicioDeHorarios, let horario = elemento(horarios, numeroHorario) else {
            return "Primero consulta los horarios y elige un número de la lista."
        }
        if !Perfil.completo { return avisoPerfil }
        pendiente = AccionPendiente(
            tipo: .agendar(servicio, horario.inicio),
            titulo: "Agendar cita de \(servicio.nombre)",
            detalle: Formato.fechaYRango(horario.inicio),
            textoConfirmar: "Sí, agendar"
        )
        return avisoConfirmacion
    }

    func proponerCancelacion(numeroCita: Int) -> String {
        guard let cita = elemento(citas, numeroCita) else {
            return "Primero consulta las citas de la persona y elige un número de la lista."
        }
        if cita.estaPospuesta {
            return "Esa cita está pospuesta y no se cancela: la persona debe elegir un nuevo horario."
        }
        pendiente = AccionPendiente(
            tipo: .cancelar(cita),
            titulo: "Cancelar cita",
            detalle: "\(cita.nombreServicio), \(Formato.fechaYRango(cita.inicio)). El horario quedará libre para otra persona.",
            textoConfirmar: "Sí, cancelar cita"
        )
        return avisoConfirmacion
    }

    func proponerReprogramacion(numeroCita: Int, numeroHorario: Int) -> String {
        guard let cita = elemento(citas, numeroCita) else {
            return "Primero consulta las citas de la persona y elige un número de la lista."
        }
        if !cita.estaPospuesta {
            return "Solo se pueden reprogramar las citas pospuestas. Una cita normal se cancela y se agenda otra."
        }
        if let delegacion = cita.delegacionId, delegacion != Configuracion.delegacionId {
            return "Esa cita es de otro centro y no se puede reprogramar desde el chat. Dile a la persona que lo haga en Agenda de citas."
        }
        guard let servicio = servicioDeHorarios,
              servicio.rawValue == cita.servicio,
              let horario = elemento(horarios, numeroHorario)
        else {
            return "Primero consulta los horarios de \(cita.nombreServicio) y elige un número de la lista."
        }
        pendiente = AccionPendiente(
            tipo: .reprogramar(cita, horario.inicio),
            titulo: "Reprogramar cita de \(cita.nombreServicio)",
            detalle: "Nuevo horario: \(Formato.fechaYRango(horario.inicio))",
            textoConfirmar: "Sí, reprogramar"
        )
        return avisoConfirmacion
    }

    func elegirApp(_ app: AppMapa) async -> String? {
        guard case .elegirRuta(let centro)? = pendiente?.tipo else { return nil }
        pendiente = AccionPendiente(
            tipo: .abrirRuta(centro, app),
            titulo: "Abrir ruta",
            detalle: "\(centro.nombre), en \(app.nombre)",
            textoConfirmar: "Abrir \(app.nombre)"
        )
        return await confirmar()
    }

    func confirmar() async -> String? {
        guard let accion = pendiente, !ejecutando else { return nil }
        pendiente = nil
        ejecutando = true
        defer { ejecutando = false }
        switch accion.tipo {
        case .elegirRuta:
            return nil

        case .abrirRuta(let centro, let app):
            switch app {
            case .apple: centro.abrirEnAppleMaps()
            case .google: _ = await UIApplication.shared.open(centro.urlGoogleMaps)
            case .waze: _ = await UIApplication.shared.open(centro.urlWaze)
            }
            return "Abrí la ruta a \(centro.nombre) en \(app.nombre)."

        case .inscribir(let curso):
            guard let datos = datosParaInscribir() else {
                return "Faltan tu nombre o tu celular en Mi perfil. Complétalos en la pantalla principal y vuelve a intentarlo."
            }
            do {
                let folio = try await capacitacion.inscribir(en: curso, nombre: datos.nombre, celular: datos.celular)
                cursos = []
                return "Tu inscripción a \(curso.titulo) quedó confirmada. Tu folio es \(folio)."
            } catch {
                return mensaje(error)
            }

        case .agendar(let servicio, let inicio):
            do {
                let cita = try await ClienteAPI.compartido.agendar(
                    delegacionId: Configuracion.delegacionId,
                    servicio: servicio,
                    inicio: inicio,
                    nombre: Perfil.nombre,
                    telefono: Perfil.telefono
                )
                horarios = []
                return "Tu cita de \(cita.nombreServicio) quedó agendada para \(Formato.fechaYRango(cita.inicio)). Tu folio es \(cita.folio)."
            } catch {
                return mensaje(error)
            }

        case .cancelar(let cita):
            do {
                try await ClienteAPI.compartido.cancelar(citaId: cita.id)
                citas = []
                return "Tu cita de \(cita.nombreServicio) del \(Formato.fechaYRango(cita.inicio)) quedó cancelada."
            } catch {
                return mensaje(error)
            }

        case .reprogramar(let cita, let inicio):
            do {
                let nueva = try await ClienteAPI.compartido.reprogramar(citaId: cita.id, inicio: inicio)
                citas = []
                horarios = []
                return "Tu cita de \(nueva.nombreServicio) quedó reprogramada para \(Formato.fechaYRango(nueva.inicio))."
            } catch {
                return mensaje(error)
            }
        }
    }

    private func describir(_ centro: Centro, numero: Int, metros: Double?) -> String {
        var linea = "\(numero). \(centro.nombre). Dirección: \(centro.direccion). Teléfono: \(centro.telefonoParaMostrar)."
        if let metros { linea += " Está a \(textoDistancia(metros))." }
        return linea
    }

    private func elemento<T>(_ lista: [T], _ numero: Int) -> T? {
        lista.indices.contains(numero - 1) ? lista[numero - 1] : nil
    }

    private func datosParaInscribir() -> (nombre: String, celular: String)? {
        let nombre = Perfil.nombre
        let digitos = Perfil.telefono.filter { $0.isNumber }
        let celular = digitos.count > 10 ? String(digitos.suffix(10)) : digitos
        guard CapacitacionModelo.datosValidos(nombre: nombre, celular: celular) else { return nil }
        return (nombre, celular)
    }

    private func servicioDe(_ texto: String) -> Servicio? {
        let limpio = texto.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        if limpio.contains("nutri") { return .nutricion }
        if limpio.contains("psico") { return .psicologia }
        return nil
    }

    private func diasDisponibles() -> [Date] {
        var resultado: [Date] = []
        var dia = Calendar.current.startOfDay(for: Date())
        while resultado.count < 5 {
            if !Calendar.current.isDateInWeekend(dia) { resultado.append(dia) }
            dia = Calendar.current.date(byAdding: .day, value: 1, to: dia) ?? dia.addingTimeInterval(86400)
        }
        return resultado
    }

    private func diaDe(_ texto: String, entre dias: [Date]) -> Date? {
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

    private func etiquetaDia(_ fecha: Date) -> String {
        fecha.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_MX")))
    }

    private func mensaje(_ error: Error) -> String {
        if let errorAPI = error as? ErrorAPI {
            if errorAPI.estado == 409 {
                horarios = []
                return "Ese horario ya no está libre. Consulta los horarios otra vez."
            }
            return IdiomaChat.asegurar(errorAPI.mensaje, respaldo: TextosChat.errorGenerico)
        }
        if let errorInscripcion = error as? CapacitacionModelo.ErrorInscripcion {
            return errorInscripcion.localizedDescription
        }
        return TextosChat.errorGenerico
    }
}
