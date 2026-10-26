// Responsable del módulo de emergencia: Ayhan Ben Halima Martinez · A01647593
//
//  EmergenciaInicio.swift
//  Botón de EMERGENCIA de la pantalla principal + lo que abre (Ayhan):
//    • con servidor: la llamada (EmergencyCallView), con la delegación más cercana que elige el backend;
//    • sin internet o si el servidor falla: el respaldo (RespaldoSinInternetView), con el centro más
//      cercano de centros.json y tus coordenadas, para llamar por línea telefónica.
//  La llamada nunca se queda en un error.
//

import CoreLocation
import SwiftUI

struct EmergenciaInicio: View {
    @Environment(Ubicacion.self) private var ubicacion
    @Environment(Internet.self) private var internet
    /// Último centro cercano que vio la persona (lo guarda Centro más cercano).
    @AppStorage("ultimoCentroCercano") private var ultimoCentroId = ""

    @State private var abierta: PantallaEmergencia?
    @State private var conectando = false

    var body: some View {
        VStack(spacing: 12) {
            // TEMPORAL: mientras el servidor no tenga delegaciones, siempre abre la llamada.
            // Cuando las tenga, vuelve a usar: Task { await iniciarLlamada() }
            EmergenciaBoton(estaConectando: conectando) {
                abierta = .llamada(Self.sesionTemporal)
            }

            // TEMPORAL: para probar el respaldo telefónico. Se quitará después.
            Button {
                abierta = respaldo(ubicacion.coordenada)
            } label: {
                Label("Llamada sin internet", systemImage: "phone.fill")
            }
            .buttonStyle(BotonBorde())
        }
        .fullScreenCover(item: $abierta) { pantalla in
            switch pantalla {
            case .llamada(let sesion):
                EmergencyCallView(session: sesion) { abierta = nil }
            case .respaldo(let centro, let punto):
                RespaldoSinInternetView(centro: centro, punto: punto) { abierta = nil }
            }
        }
    }

    @MainActor
    private func iniciarLlamada() async {
        guard !conectando else { return }

        guard ubicacion.tienePermiso else {
            if ubicacion.permisoNegado {
                abierta = respaldo(nil)    // sin ubicación: respaldo telefónico igual
            } else {
                ubicacion.pedirPermiso()   // alerta de iOS; después vuelve a tocar el botón
            }
            return
        }

        conectando = true
        defer { conectando = false }

        let gps = await esperarUbicacion()

        // Sin internet (o sin GPS) no esperamos al servidor: directo al respaldo telefónico.
        guard internet.hayConexion, let punto = gps else {
            abierta = respaldo(gps)
            return
        }
        do {
            let sesion = try await EmergencyAPI.shared.startCall(
                latitude: punto.latitude,
                longitude: punto.longitude
            )
            abierta = .llamada(sesion)
        } catch is CancellationError {
            return
        } catch {
            // Servidor apagado, sin base de datos, sin delegación…: respaldo telefónico.
            abierta = respaldo(punto)
        }
    }

    /// TEMPORAL: llamada de muestra mientras el servidor no tenga delegaciones.
    private static let sesionTemporal = EmergencySession(
        id: UUID(),
        status: "en_curso",
        delegation: Delegation(id: 0, name: "Delegación más cercana", phone: Telefono.emergencias)
    )

    private func respaldo(_ punto: CLLocationCoordinate2D?) -> PantallaEmergencia {
        let centro = punto.flatMap { Centro.masCercano(a: $0) }
            ?? Centro.todos.first { $0.id == ultimoCentroId }
        return .respaldo(centro, punto)
    }

    /// Espera hasta ~10 segundos a que el GPS entregue la primera ubicación.
    @MainActor
    private func esperarUbicacion() async -> CLLocationCoordinate2D? {
        for _ in 0..<20 {
            if let punto = ubicacion.coordenada { return punto }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }
}

/// Lo que abre el botón de emergencia (una sola pantalla completa a la vez).
enum PantallaEmergencia: Identifiable {
    case llamada(EmergencySession)
    case respaldo(Centro?, CLLocationCoordinate2D?)

    var id: String {
        switch self {
        case .llamada(let sesion): "llamada-\(sesion.id)"
        case .respaldo: "respaldo"
        }
    }
}

#Preview {
    EmergenciaInicio()
        .padding()
        .environment(Ubicacion())
        .environment(Internet())
}
