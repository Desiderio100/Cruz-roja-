import AppIntents
import Foundation

struct MisCitasIntent: AppIntent {
    static var title: LocalizedStringResource { "Mis citas" }
    static var description = IntentDescription("Te dice cuáles son tus citas de nutrición y psicología.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let citas: [Cita]
        do {
            citas = try await ClienteAPI.compartido.misCitas()
        } catch {
            return .result(dialog: "\(DatosSiri.mensaje(error))")
        }
        if citas.isEmpty { return .result(dialog: "No tienes citas.") }

        let lineas = citas.map { cita -> String in
            let base = "\(cita.nombreServicio), \(DatosSiri.fechaHablada(cita.inicio))"
            return cita.estaPospuesta ? "\(base). Está pospuesta y necesita un nuevo horario" : base
        }
        let encabezado = citas.count == 1 ? "Tienes una cita." : "Tienes \(citas.count) citas."
        return .result(dialog: "\(encabezado) \(lineas.joined(separator: ". ")).")
    }
}

struct AgendarCitaIntent: AppIntent {
    static var title: LocalizedStringResource { "Agendar cita" }
    static var description = IntentDescription("Agenda una cita de nutrición o psicología.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Servicio", requestValueDialog: IntentDialog("¿La cita es de nutrición o de psicología?"))
    var servicio: ServicioSiri

    @Parameter(title: "Día", requestValueDialog: IntentDialog("¿Para qué día? Puedes decir hoy, mañana o un día de la semana."))
    var dia: String

    @Parameter(title: "Horario", default: "")
    var horario: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if !Perfil.completo {
            return .result(dialog: "Faltan tu nombre o tu celular en Mi perfil. Complétalos en la app de Cruz Roja y vuelve a intentarlo.")
        }

        let eleccion = try await DatosSiri.elegirHorario(
            servicio: servicio.servicio,
            diaInicial: dia,
            parametroDia: $dia,
            horarioInicial: horario,
            parametroHorario: $horario
        )
        let elegido: Horario
        switch eleccion {
        case .aviso(let texto):
            return .result(dialog: "\(texto)")
        case .elegido(_, let horarioElegido):
            elegido = horarioElegido
        }

        let nombreServicio = servicio.servicio.nombre
        let cuando = DatosSiri.fechaHablada(elegido.inicio)
        let confirmado = try await $horario.requestConfirmation(
            for: HorarioSiri.texto(elegido.inicio),
            dialog: IntentDialog("Voy a agendar tu cita de \(nombreServicio) para el \(cuando). ¿Confirmas?")
        )
        if !confirmado { return .result(dialog: "\(TextosChat.accionCancelada)") }

        do {
            let cita = try await ClienteAPI.compartido.agendar(
                delegacionId: Configuracion.delegacionId,
                servicio: servicio.servicio,
                inicio: elegido.inicio,
                nombre: Perfil.nombre,
                telefono: Perfil.telefono
            )
            return .result(dialog: "Tu cita de \(cita.nombreServicio) quedó agendada para el \(DatosSiri.fechaHablada(cita.inicio)). Tu folio es \(cita.folio).")
        } catch {
            return .result(dialog: "\(DatosSiri.mensaje(error))")
        }
    }
}

struct CancelarCitaIntent: AppIntent {
    static var title: LocalizedStringResource { "Cancelar cita" }
    static var description = IntentDescription("Cancela una de tus citas.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Cita", requestValueDialog: IntentDialog("¿Cuál cita quieres cancelar?"))
    var cita: CitaEntidad

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let confirmado = try await $cita.requestConfirmation(
            for: cita,
            dialog: IntentDialog("Voy a cancelar tu cita: \(cita.texto). El horario quedará libre para otra persona. ¿Confirmas?")
        )
        if !confirmado { return .result(dialog: "\(TextosChat.accionCancelada)") }

        do {
            try await ClienteAPI.compartido.cancelar(citaId: cita.id)
            return .result(dialog: "Tu cita de \(cita.texto) quedó cancelada.")
        } catch {
            return .result(dialog: "\(DatosSiri.mensaje(error))")
        }
    }
}

struct ReprogramarCitaIntent: AppIntent {
    static var title: LocalizedStringResource { "Reprogramar cita" }
    static var description = IntentDescription("Elige un nuevo horario para una cita pospuesta.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Cita pospuesta", requestValueDialog: IntentDialog("¿Cuál cita pospuesta quieres reprogramar?"))
    var cita: CitaPospuestaEntidad

    @Parameter(title: "Día", requestValueDialog: IntentDialog("¿Para qué día? Puedes decir hoy, mañana o un día de la semana."))
    var dia: String

    @Parameter(title: "Horario", default: "")
    var horario: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let delegacion = cita.delegacionId, delegacion != Configuracion.delegacionId {
            return .result(dialog: "Esa cita es de otro centro y no se puede reprogramar por Siri. Hazlo en Agenda de citas dentro de la app.")
        }
        guard let servicio = Servicio(rawValue: cita.servicio) else {
            return .result(dialog: "\(TextosChat.errorGenerico)")
        }

        let eleccion = try await DatosSiri.elegirHorario(
            servicio: servicio,
            diaInicial: dia,
            parametroDia: $dia,
            horarioInicial: horario,
            parametroHorario: $horario
        )
        let elegido: Horario
        switch eleccion {
        case .aviso(let texto):
            return .result(dialog: "\(texto)")
        case .elegido(_, let horarioElegido):
            elegido = horarioElegido
        }

        let cuando = DatosSiri.fechaHablada(elegido.inicio)
        let confirmado = try await $horario.requestConfirmation(
            for: HorarioSiri.texto(elegido.inicio),
            dialog: IntentDialog("Voy a reprogramar tu cita de \(servicio.nombre) para el \(cuando). ¿Confirmas?")
        )
        if !confirmado { return .result(dialog: "\(TextosChat.accionCancelada)") }

        do {
            let nueva = try await ClienteAPI.compartido.reprogramar(citaId: cita.id, inicio: elegido.inicio)
            return .result(dialog: "Tu cita de \(nueva.nombreServicio) quedó reprogramada para el \(DatosSiri.fechaHablada(nueva.inicio)).")
        } catch {
            return .result(dialog: "\(DatosSiri.mensaje(error))")
        }
    }
}
