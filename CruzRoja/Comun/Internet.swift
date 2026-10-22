// Uso:
//     @Environment(Internet.self) private var internet
//     if !internet.hayConexion { ... }
//
// No basta con saber si el teléfono está conectado a una red (puede haber Wi-Fi
// sin internet, y el simulador casi nunca se entera de los cambios). Por eso,
// además, cada 10 segundos intentamos abrir una página mínima de Apple: si no
// responde en 4 segundos, no hay internet.

import Foundation
import Network
import Observation

@Observable
final class Internet {
    private(set) var hayConexion = true
    private(set) var revisando = false

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let sesion: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init() {
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { await self?.revisar() }
        }
        monitor.start(queue: DispatchQueue(label: "internet"))

        Task { [weak self] in
            while let self {
                await self.revisar()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// Intenta abrir la página de prueba de Apple (la misma que usa el iPhone).
    func revisar() async {
        await MainActor.run { self.revisando = true }
        defer { Task { @MainActor in self.revisando = false } }
        var hay = false
        if let url = URL(string: "https://captive.apple.com/hotspot-detect.html"),
           let (datos, respuesta) = try? await sesion.data(from: url),
           (respuesta as? HTTPURLResponse)?.statusCode == 200 {
            hay = String(decoding: datos, as: UTF8.self).contains("Success")
        }
        let resultado = hay
        await MainActor.run { self.hayConexion = resultado }
    }
}
