//
//  CamaraLlamada.swift
//  Cámara REAL de la llamada de emergencia: se enciende solo si el operador la pide y la
//  persona acepta. La persona ve en pantalla lo que la cámara está captando.
//
//  Por ahora el video se ve en el teléfono; mandarlo al operador necesita un servidor de
//  video (WebRTC o similar) que todavía no existe. Cuando exista, se conecta a `sesion`.
//

import AVFoundation
import SwiftUI

final class CamaraLlamada {
    let sesion = AVCaptureSession()
    /// AVCaptureSession se configura y arranca fuera del hilo principal (Apple lo recomienda).
    private let cola = DispatchQueue(label: "CruzRoja.camaraLlamada")
    private var entrada: AVCaptureDeviceInput?
    /// Empieza con la trasera: al operador le sirve más ver la escena que la cara.
    private var usaTrasera = true

    /// Pide permiso si hace falta y empieza a captar. Devuelve false si no hay permiso o cámara.
    func encender() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        default:
            return false
        }
        return await withCheckedContinuation { continuacion in
            cola.async { [self] in
                let lista = entrada != nil || configurar(trasera: usaTrasera)
                if lista && !sesion.isRunning { sesion.startRunning() }
                continuacion.resume(returning: lista)
            }
        }
    }

    func apagar() {
        cola.async { [sesion] in
            if sesion.isRunning { sesion.stopRunning() }
        }
    }

    /// Cambia entre la cámara trasera y la frontal.
    func voltear() {
        cola.async { [self] in
            if configurar(trasera: !usaTrasera) { usaTrasera.toggle() }
        }
    }

    /// Pone la cámara pedida como entrada. Si falla, deja la que había.
    private func configurar(trasera: Bool) -> Bool {
        guard let dispositivo = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video,
                                                        position: trasera ? .back : .front),
              let nueva = try? AVCaptureDeviceInput(device: dispositivo) else { return false }

        sesion.beginConfiguration()
        defer { sesion.commitConfiguration() }
        sesion.sessionPreset = .high
        if let entrada { sesion.removeInput(entrada) }
        guard sesion.canAddInput(nueva) else {
            if let entrada { sesion.addInput(entrada) }
            return false
        }
        sesion.addInput(nueva)
        entrada = nueva
        return true
    }
}

/// Muestra en pantalla lo que capta la cámara.
struct VistaCamara: UIViewRepresentable {
    let sesion: AVCaptureSession

    func makeUIView(context: Context) -> VistaPrevia {
        let vista = VistaPrevia()
        vista.capa.session = sesion
        vista.capa.videoGravity = .resizeAspectFill
        return vista
    }

    func updateUIView(_ vista: VistaPrevia, context: Context) {}

    final class VistaPrevia: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // La capa siempre es AVCaptureVideoPreviewLayer por `layerClass`.
        var capa: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
