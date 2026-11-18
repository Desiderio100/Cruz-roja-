#if canImport(FoundationModels)
import AVFoundation
import Foundation
import LiveKit
import Speech

@available(iOS 26.0, *)
final class TranscripcionLlamada: NSObject, AudioRenderer, @unchecked Sendable {
    private static let idioma = Locale(identifier: "es_MX")

    private let alTerminarFrase: @Sendable (String, Int) -> Void
    private let candado = NSLock()
    private let inicio = Date()
    private var analizador: SpeechAnalyzer?
    private var entrada: AsyncStream<AnalyzerInput>.Continuation?
    private var formato: AVAudioFormat?
    private var convertidor: AVAudioConverter?
    private var tareaResultados: Task<Void, Never>?

    init(alTerminarFrase: @escaping @Sendable (String, Int) -> Void) {
        self.alTerminarFrase = alTerminarFrase
    }

    static func prepararModelo() async {
        guard SpeechTranscriber.isAvailable,
              let idiomaCompatible = await SpeechTranscriber.supportedLocale(equivalentTo: idioma) else { return }
        let transcriptor = crearTranscriptor(idiomaCompatible)
        if let peticion = try? await AssetInventory.assetInstallationRequest(supporting: [transcriptor]) {
            try? await peticion.downloadAndInstall()
        }
    }

    private static func crearTranscriptor(_ idioma: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: idioma,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
    }

    func iniciar() async -> Bool {
        guard SpeechTranscriber.isAvailable,
              let idiomaCompatible = await SpeechTranscriber.supportedLocale(equivalentTo: Self.idioma) else { return false }
        let transcriptor = Self.crearTranscriptor(idiomaCompatible)
        do {
            if let peticion = try await AssetInventory.assetInstallationRequest(supporting: [transcriptor]) {
                try await peticion.downloadAndInstall()
            }
            guard let destino = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriptor]) else { return false }
            let nuevo = SpeechAnalyzer(modules: [transcriptor])
            let (secuencia, continuacion) = AsyncStream.makeStream(of: AnalyzerInput.self)
            try await nuevo.start(inputSequence: secuencia)

            candado.withLock {
                analizador = nuevo
                entrada = continuacion
                formato = destino
            }

            tareaResultados = Task { [alTerminarFrase, inicio] in
                do {
                    for try await resultado in transcriptor.results {
                        let texto = String(resultado.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !texto.isEmpty {
                            alTerminarFrase(texto, Int(Date().timeIntervalSince(inicio)))
                        }
                    }
                } catch {}
            }
            AudioManager.shared.add(localAudioRenderer: self)
            return true
        } catch {
            return false
        }
    }

    func detener() async {
        AudioManager.shared.remove(localAudioRenderer: self)
        let (continuacion, actual) = candado.withLock {
            let pendientes = (entrada, analizador)
            entrada = nil
            analizador = nil
            convertidor = nil
            return pendientes
        }
        continuacion?.finish()
        try? await actual?.finalizeAndFinishThroughEndOfInput()
        await tareaResultados?.value
        tareaResultados = nil
    }

    func render(pcmBuffer: AVAudioPCMBuffer) {
        candado.lock()
        defer { candado.unlock() }
        guard let continuacion = entrada, let destino = formato else { return }
        if convertidor == nil || convertidor?.inputFormat != pcmBuffer.format {
            convertidor = AVAudioConverter(from: pcmBuffer.format, to: destino)
        }
        guard let convertidor else { return }
        let razon = destino.sampleRate / pcmBuffer.format.sampleRate
        let capacidad = AVAudioFrameCount((Double(pcmBuffer.frameLength) * razon).rounded(.up)) + 32
        guard let salida = AVAudioPCMBuffer(pcmFormat: destino, frameCapacity: capacidad) else { return }
        var entregado = false
        var error: NSError?
        let estado = convertidor.convert(to: salida, error: &error) { _, estadoEntrada in
            if entregado {
                estadoEntrada.pointee = .noDataNow
                return nil
            }
            entregado = true
            estadoEntrada.pointee = .haveData
            return pcmBuffer
        }
        if estado != .error && salida.frameLength > 0 {
            continuacion.yield(AnalyzerInput(buffer: salida))
        }
    }
}
#endif
