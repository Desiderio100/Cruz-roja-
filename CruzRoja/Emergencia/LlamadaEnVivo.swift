import AVFoundation
import Foundation
import LiveKit
import Observation

private final class ReceptorSala: NSObject, RoomDelegate, @unchecked Sendable {
    var alCambiarPresencia: (@Sendable (Bool) -> Void)?
    var alRecibirOrden: (@Sendable (String) -> Void)?
    var alCambiarConexion: (@Sendable (Bool) -> Void)?

    private func hayOperador(_ sala: Room) -> Bool {
        sala.remoteParticipants.keys.contains { $0.stringValue.hasPrefix("op-") }
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        alCambiarPresencia?(hayOperador(room))
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        alCambiarPresencia?(hayOperador(room))
    }

    func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        alCambiarConexion?(connectionState == .connected)
    }

    func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {
        guard topic == "llamada",
              let objeto = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tipo = objeto["tipo"] as? String else { return }
        alRecibirOrden?(tipo)
    }
}

@MainActor
@Observable
final class LlamadaEnVivo {
    enum Conexion {
        case conectando
        case conectada
        case fallo
    }

    private(set) var conexion: Conexion = .conectando
    private(set) var operadorPresente = false
    private(set) var camaraLocal: LocalVideoTrack?
    private(set) var camaraActiva = false
    var camaraNegada = false
    private(set) var microfonoActivo = true
    private(set) var microfonoDenegado = false
    private(set) var usaBocina = true
    private(set) var terminoElOperador = false
    private(set) var transcribiendo = false
    var solicitudDeCamara = false

    @ObservationIgnored private let llamadaId: UUID
    @ObservationIgnored private let sala = Room()
    @ObservationIgnored private let receptor = ReceptorSala()
    @ObservationIgnored private var detenerAsistente: (() async -> Void)?
    @ObservationIgnored private var terminada = false

    init(llamadaId: UUID) {
        self.llamadaId = llamadaId
        sala.add(delegate: receptor)
        receptor.alCambiarPresencia = { [weak self] hay in
            Task { @MainActor in self?.operadorPresente = hay }
        }
        receptor.alCambiarConexion = { [weak self] conectada in
            Task { @MainActor in
                guard let self, !self.terminada, self.conexion != .fallo else { return }
                self.conexion = conectada ? .conectada : .conectando
            }
        }
        receptor.alRecibirOrden = { [weak self] orden in
            Task { @MainActor in await self?.atender(orden) }
        }
    }

    func iniciar() async {
        do {
            let acceso = try await EmergencyAPI.shared.joinRoom(id: llamadaId)
            try await sala.connect(url: acceso.url, token: acceso.token)
        } catch {
            if !terminada { conexion = .fallo }
            return
        }
        guard !terminada else { return }
        conexion = .conectada
        operadorPresente = sala.remoteParticipants.keys.contains { $0.stringValue.hasPrefix("op-") }
        AudioManager.shared.isSpeakerOutputPreferred = usaBocina
        do {
            try await sala.localParticipant.setMicrophone(enabled: true)
        } catch {
            microfonoDenegado = true
            microfonoActivo = false
            return
        }
        await iniciarAsistente()
    }

    private func iniciarAsistente() async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let asistente = AsistenteLlamada(llamadaId: llamadaId)
            guard await asistente.iniciar() else { return }
            transcribiendo = true
            detenerAsistente = { await asistente.detener() }
        }
        #endif
    }

    private func atender(_ orden: String) async {
        switch orden {
        case "pedir_camara":
            if !camaraActiva { solicitudDeCamara = true }
        case "detener_camara":
            solicitudDeCamara = false
            if camaraActiva { await apagarCamara(avisar: true) }
        case "fin":
            terminoElOperador = true
            await terminar()
        default:
            break
        }
    }

    func aceptarCamara() async {
        solicitudDeCamara = false
        do {
            let publicacion = try await sala.localParticipant.setCamera(
                enabled: true,
                captureOptions: CameraCaptureOptions(position: .back)
            )
            camaraLocal = publicacion?.track as? LocalVideoTrack
            camaraActiva = camaraLocal != nil
            await enviar(["tipo": "camara", "estado": camaraActiva ? "aceptada" : "sin_permiso"])
            if camaraActiva {
                try? await EmergencyAPI.shared.updateCall(id: llamadaId, videoAccepted: true)
            } else {
                camaraNegada = true
            }
        } catch {
            camaraNegada = true
            await enviar(["tipo": "camara", "estado": "sin_permiso"])
        }
    }

    func rechazarCamara() async {
        solicitudDeCamara = false
        await enviar(["tipo": "camara", "estado": "rechazada"])
    }

    func apagarCamara(avisar: Bool = true) async {
        _ = try? await sala.localParticipant.setCamera(enabled: false)
        camaraLocal = nil
        camaraActiva = false
        if avisar { await enviar(["tipo": "camara", "estado": "apagada"]) }
        try? await EmergencyAPI.shared.updateCall(id: llamadaId, videoAccepted: false)
    }

    func cambiarCamara() async {
        guard let captor = camaraLocal?.capturer as? CameraCapturer else { return }
        _ = try? await captor.switchCameraPosition()
    }

    func alternarMicrofono() async {
        let nuevo = !microfonoActivo
        do {
            try await sala.localParticipant.setMicrophone(enabled: nuevo)
            microfonoActivo = nuevo
        } catch {
            microfonoDenegado = true
        }
    }

    func alternarBocina() {
        usaBocina.toggle()
        AudioManager.shared.isSpeakerOutputPreferred = usaBocina
    }

    func terminar() async {
        guard !terminada else { return }
        terminada = true
        solicitudDeCamara = false
        transcribiendo = false
        camaraActiva = false
        camaraLocal = nil
        let pararAsistente = detenerAsistente
        detenerAsistente = nil
        Task { await pararAsistente?() }
        await sala.disconnect()
    }

    private func enviar(_ mensaje: [String: String]) async {
        guard let datos = try? JSONSerialization.data(withJSONObject: mensaje) else { return }
        try? await sala.localParticipant.publish(
            data: datos,
            options: DataPublishOptions(topic: "llamada", reliable: true)
        )
    }
}
