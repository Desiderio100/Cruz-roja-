import Combine
import Foundation

// Datos y acciones de la pantalla Agenda de citas.
@MainActor
final class AgendaViewModel: ObservableObject {
    @Published var servicio: Servicio
    @Published var diaElegido = 0
    @Published var horarioElegido: Date?
    @Published var horarios: [Horario] = []
    @Published var cargando = false
    @Published var enviando = false
    @Published var mensajeError: String?
    @Published var citaConfirmada: Cita?
    @Published var pidiendoPerfil = false

    let dias: [Date]
    let reprogramando: Cita?

    var esReprogramacion: Bool { reprogramando != nil }

    var clave: String { "\(servicio.rawValue)-\(diaElegido)" }

    // El aviso de posposición solo se muestra en psicología.
    var mostrarAviso: Bool { servicio == .psicologia }

    var puedeConfirmar: Bool { horarioElegido != nil && !enviando }

    init(reprogramando cita: Cita? = nil) {
        self.reprogramando = cita
        self.servicio = cita.flatMap { Servicio(rawValue: $0.servicio) } ?? .psicologia
        self.dias = AgendaViewModel.proximosDias(5)
    }

    private static func proximosDias(_ cantidad: Int) -> [Date] {
        var resultado: [Date] = []
        var dia = Calendar.current.startOfDay(for: Date())
        while resultado.count < cantidad {
            if !Calendar.current.isDateInWeekend(dia) { resultado.append(dia) }
            dia = Calendar.current.date(byAdding: .day, value: 1, to: dia) ?? dia.addingTimeInterval(86400)
        }
        return resultado
    }

    // Pide a la API los horarios libres del día y servicio elegidos.
    func cargarHorarios() async {
        cargando = true
        horarioElegido = nil
        horarios = []
        defer { cargando = false }
        do {
            let lista = try await ClienteAPI.compartido.horarios(
                delegacionId: reprogramando?.delegacionId ?? Configuracion.delegacionId,
                servicio: servicio,
                fecha: dias[diaElegido]
            )
            horarios = lista
        } catch is CancellationError {
            return
        } catch {
            horarios = []
            mensajeError = error.localizedDescription
        }
    }

    // Agenda la cita, o la reprograma si viene de una cita pospuesta.
    func confirmar() async {
        guard let inicio = horarioElegido else { return }
        if !esReprogramacion && !Perfil.completo {
            pidiendoPerfil = true
            return
        }
        enviando = true
        defer { enviando = false }
        do {
            if let cita = reprogramando {
                citaConfirmada = try await ClienteAPI.compartido.reprogramar(citaId: cita.id, inicio: inicio)
            } else {
                citaConfirmada = try await ClienteAPI.compartido.agendar(
                    delegacionId: Configuracion.delegacionId,
                    servicio: servicio,
                    inicio: inicio,
                    nombre: Perfil.nombre,
                    telefono: Perfil.telefono
                )
            }
        } catch {
            let mensaje = error.localizedDescription
            if (error as? ErrorAPI)?.estado == 409 {
                await cargarHorarios()
            }
            mensajeError = mensaje
        }
    }
}
