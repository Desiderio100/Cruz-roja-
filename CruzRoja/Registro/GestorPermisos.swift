// HU01 · Permisos de ubicación, micrófono, cámara y notificaciones.
// Cada vez que la persona acepta o niega uno, se guarda en la base (tabla consentimiento,
// con la versión vigente del aviso de privacidad). Si el servidor no responde, la app sigue.
//
// Los textos que ve la persona en la alerta de iOS están en el proyecto:
// target CruzRoja › Build Settings › "Privacy - … Usage Description".
//Tonchez

import AVFoundation
import CoreLocation
import Foundation
import Observation
import UserNotifications

enum TipoPermiso: String, CaseIterable, Identifiable {
    case ubicacion, microfono, camara, notificaciones

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .ubicacion: "Ubicación"
        case .microfono: "Micrófono"
        case .camara: "Cámara"
        case .notificaciones: "Notificaciones"
        }
    }

    var detalle: String {
        switch self {
        case .ubicacion: "Permite que podamos encontrarte y enviarte ayuda."
        case .microfono: "Permite que puedas hablar con nuestro equipo."
        case .camara: "Permite enviar video si el operador lo pide y tú aceptas."
        case .notificaciones: "Permite recibir alertas importantes y avisos de tus citas."
        }
    }

    var icono: String {
        switch self {
        case .ubicacion: "location.fill"
        case .microfono: "mic.fill"
        case .camara: "camera.fill"
        case .notificaciones: "bell.fill"
        }
    }
}

enum EstadoPermiso { case solicitar, permitido, denegado }

@MainActor
@Observable
final class GestorPermisos: NSObject, CLLocationManagerDelegate {
    private(set) var estados: [TipoPermiso: EstadoPermiso] = [:]
    private(set) var solicitando = false
    /// Texto para la alerta cuando falta configurar algo en el proyecto.
    var mensajeError: String?

    @ObservationIgnored private let ubicacion = CLLocationManager()
    @ObservationIgnored private var esperaUbicacion: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        ubicacion.delegate = self
        actualizar()
    }

    func estado(_ tipo: TipoPermiso) -> EstadoPermiso { estados[tipo] ?? .solicitar }

    func solicitar(_ tipo: TipoPermiso) {
        guard !solicitando else { return }
        Task {
            solicitando = true
            await pedir(tipo)
            solicitando = false
        }
    }

    /// Pide uno por uno los permisos que aún no se han solicitado.
    func solicitarPendientes() async {
        guard !solicitando else { return }
        solicitando = true
        for tipo in TipoPermiso.allCases where estado(tipo) == .solicitar {
            await pedir(tipo)
        }
        solicitando = false
    }

    private func pedir(_ tipo: TipoPermiso) async {
        guard estado(tipo) == .solicitar else { return }
        switch tipo {
        case .ubicacion:
            guard hayTexto("NSLocationWhenInUseUsageDescription") else { return }
            await withCheckedContinuation { espera in
                esperaUbicacion = espera
                ubicacion.requestWhenInUseAuthorization()
            }
        case .microfono:
            guard hayTexto("NSMicrophoneUsageDescription") else { return }
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .camara:
            guard hayTexto("NSCameraUsageDescription") else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .notificaciones:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        }
        actualizar()
    }

    /// iOS cierra la app si se pide un permiso sin su texto en el proyecto; así avisamos antes.
    private func hayTexto(_ clave: String) -> Bool {
        if let texto = Bundle.main.object(forInfoDictionaryKey: clave) as? String,
           !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        mensajeError = "Falta la clave \(clave) en los ajustes de privacidad del proyecto."
        return false
    }

    private func fijar(_ tipo: TipoPermiso, _ valor: EstadoPermiso) {
        let anterior = estados[tipo]
        estados[tipo] = valor
        // Solo se guardan cambios reales, no la primera lectura al abrir la app.
        if let anterior, anterior != valor, valor != .solicitar {
            Task {
                try? await ClienteAPI.compartido.guardarConsentimiento(permiso: tipo.rawValue,
                                                                       aceptado: valor == .permitido)
            }
        }
    }

    /// Vuelve a leer cómo están los permisos (al abrir la app o al regresar de Ajustes).
    func actualizar() {
        switch ubicacion.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: fijar(.ubicacion, .permitido)
        case .notDetermined: fijar(.ubicacion, .solicitar)
        default: fijar(.ubicacion, .denegado)
        }
        fijar(.microfono, Self.mapear(AVCaptureDevice.authorizationStatus(for: .audio)))
        fijar(.camara, Self.mapear(AVCaptureDevice.authorizationStatus(for: .video)))
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] config in
            let valor: EstadoPermiso
            switch config.authorizationStatus {
            case .authorized, .provisional, .ephemeral: valor = .permitido
            case .notDetermined: valor = .solicitar
            default: valor = .denegado
            }
            Task { @MainActor [weak self] in self?.fijar(.notificaciones, valor) }
        }
    }

    private static func mapear(_ estado: AVAuthorizationStatus) -> EstadoPermiso {
        switch estado {
        case .authorized: .permitido
        case .notDetermined: .solicitar
        default: .denegado
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            actualizar()
            // La respuesta de la persona llega aquí; libera a quien estaba esperando.
            if ubicacion.authorizationStatus != .notDetermined, let espera = esperaUbicacion {
                esperaUbicacion = nil
                espera.resume()
            }
        }
    }
}
