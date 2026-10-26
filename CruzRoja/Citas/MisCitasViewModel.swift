import Combine
import Foundation

// Datos y acciones de la pantalla Mis citas.
@MainActor
final class MisCitasViewModel: ObservableObject {
    @Published var citas: [Cita] = []
    @Published var cargadoUnaVez = false
    @Published var fallo = false
    @Published var cancelando = false
    /// La cita que la persona quiere cancelar (abre la pregunta de confirmación).
    @Published var citaPorCancelar: Cita?
    @Published var mensajeError: String?

    func cargar() async {
        do {
            citas = try await ClienteAPI.compartido.misCitas()
            fallo = false
        } catch is CancellationError {
            return
        } catch {
            fallo = true
            mensajeError = error.localizedDescription
        }
        cargadoUnaVez = true
    }

    // Cancela la cita elegida y vuelve a cargar la lista.
    func cancelar(_ cita: Cita) async {
        citaPorCancelar = nil
        cancelando = true
        defer { cancelando = false }
        do {
            try await ClienteAPI.compartido.cancelar(citaId: cita.id)
        } catch {
            mensajeError = error.localizedDescription
        }
        await cargar()
    }
}
