//
//  TranscriptorLlamada.swift
//  Transcripción de la llamada de emergencia (RF12, HU09).
//
//  Mientras dura la llamada, lo que dice la persona se convierte en texto EN EL TELÉFONO con el
//  reconocimiento de voz de Apple (framework Speech) y cada frase se manda al panel del operador
//  (POST /api/llamadas/{id}/transcripcion). Al servidor solo llega texto, nunca audio (RNF05).
//
//  Tres piezas:
//    • TextoTranscrito y ColaTranscripcion: preparan las frases y guardan las que faltan por
//      enviar. No usan micrófono ni red, así que se prueban solas (CruzRojaTests/TranscripcionTests.swift).
//    • ReconocedorDeVoz: micrófono + reconocimiento de voz. Corta una frase cuando la persona
//      hace una pausa.
//    • TranscriptorLlamada: lo que usa la pantalla de la llamada (EmergencyCallView).
//

import AVFoundation
import Foundation
import Observation
import Speech

// MARK: - Frases listas para enviar

/// Una frase ya transcrita, lista para mandarse al panel del operador.
struct LineaTranscrita: Equatable, Sendable {
    let texto: String
    /// Segundos desde que empezó la llamada.
    let segundo: Int
}

enum TextoTranscrito {
    /// Lo más largo que acepta el servidor por línea (columna `texto` de la tabla transcripcion).
    static let maximoPorLinea = 1000

    /// Deja el texto como lo acepta el servidor: en un solo renglón y sin espacios repetidos.
    static func limpiar(_ texto: String) -> String {
        texto.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// Convierte una frase en una o más líneas de hasta `maximo` caracteres, sin cortar palabras.
    /// Una frase vacía no produce ninguna línea.
    static func lineas(de texto: String, segundo: Int, maximo: Int = maximoPorLinea) -> [LineaTranscrita] {
        var lineas: [LineaTranscrita] = []
        var actual = ""
        for palabra in limpiar(texto).split(separator: " ") {
            // Una sola palabra más larga que el máximo se parte en pedazos.
            var resto = Substring(palabra)
            while resto.count > maximo {
                if !actual.isEmpty {
                    lineas.append(LineaTranscrita(texto: actual, segundo: segundo))
                    actual = ""
                }
                lineas.append(LineaTranscrita(texto: String(resto.prefix(maximo)), segundo: segundo))
                resto = resto.dropFirst(maximo)
            }
            guard !resto.isEmpty else { continue }
            if actual.isEmpty {
                actual = String(resto)
            } else if actual.count + 1 + resto.count <= maximo {
                actual += " \(resto)"
            } else {
                lineas.append(LineaTranscrita(texto: actual, segundo: segundo))
                actual = String(resto)
            }
        }
        if !actual.isEmpty {
            lineas.append(LineaTranscrita(texto: actual, segundo: segundo))
        }
        return lineas
    }
}

/// Frases que faltan por enviar. Si un envío falla, se quedan aquí y se vuelve a intentar.
struct ColaTranscripcion: Equatable {
    /// Líneas que acepta el servidor en un solo envío.
    static let maximoPorEnvio = 20
    /// Si el servidor no responde durante mucho tiempo, se conservan solo las más recientes.
    static let maximoPendientes = 200

    private(set) var pendientes: [LineaTranscrita] = []

    var estaVacia: Bool { pendientes.isEmpty }

    /// Agrega una frase terminada. Las frases vacías se ignoran.
    mutating func agregar(_ texto: String, segundo: Int) {
        pendientes += TextoTranscrito.lineas(de: texto, segundo: max(0, segundo))
        if pendientes.count > Self.maximoPendientes {
            pendientes.removeFirst(pendientes.count - Self.maximoPendientes)
        }
    }

    /// Las siguientes líneas a enviar, de la más antigua a la más nueva.
    var siguienteEnvio: [LineaTranscrita] {
        Array(pendientes.prefix(Self.maximoPorEnvio))
    }

    /// Quita las líneas que el servidor ya guardó.
    mutating func confirmar(_ cantidad: Int) {
        pendientes.removeFirst(min(max(0, cantidad), pendientes.count))
    }

    mutating func vaciar() {
        pendientes.removeAll()
    }
}

// MARK: - Micrófono y reconocimiento de voz

/// Micrófono + reconocimiento de voz del sistema.
/// Trabaja en su propia cola: el audio y los resultados llegan fuera del hilo principal,
/// por eso esta clase no está atada a él y avisa con un bloque.
final class ReconocedorDeVoz: @unchecked Sendable {
    enum Evento: Equatable, Sendable {
        /// Lo que se va entendiendo de la frase que la persona está diciendo.
        case parcial(String)
        /// Frase terminada (la persona hizo una pausa o habló mucho tiempo seguido).
        case frase(String)
        /// El reconocimiento falló varias veces seguidas y ya no se reintenta.
        case detenido
    }

    enum ErrorDeVoz: Error {
        case sinMicrofono
    }

    /// Silencio después del cual una frase se da por terminada.
    static let segundosDePausa = 1.6
    /// Si la persona no hace pausas, la frase se corta para que el operador no espere de más.
    static let segundosMaximosPorFrase = 20.0

    private let voz: SFSpeechRecognizer
    private let soloEnDispositivo: Bool
    private let avisar: @Sendable (Evento) -> Void
    private let cola = DispatchQueue(label: "CruzRoja.reconocedorDeVoz")
    private let motor = AVAudioEngine()

    /// La petición que recibe el audio. La usa también el hilo del audio, por eso el candado.
    private let candado = NSLock()
    private var peticionConAudio: SFSpeechAudioBufferRecognitionRequest?

    // Lo siguiente solo se toca dentro de `cola`.
    private var activo = false
    private var tarea: SFSpeechRecognitionTask?
    /// Cambia con cada frase: así se ignoran los resultados que llegan tarde de una frase anterior.
    private var generacion = 0
    private var textoParcial = ""
    private var inicioDeFrase = Date()
    private var fallosSeguidos = 0
    private var pausa: DispatchWorkItem?
    private var limite: DispatchWorkItem?

    /// - Parameters:
    ///   - soloEnDispositivo: `true` para que el audio nunca salga del teléfono (RNF05).
    ///   - avisar: se llama fuera del hilo principal con cada avance.
    init(voz: SFSpeechRecognizer, soloEnDispositivo: Bool, avisar: @escaping @Sendable (Evento) -> Void) {
        self.voz = voz
        self.soloEnDispositivo = soloEnDispositivo
        self.avisar = avisar
    }

    /// Pregunta a la persona si permite convertir su voz en texto (alerta de iOS).
    static func pedirPermiso() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuacion in
            SFSpeechRecognizer.requestAuthorization { estado in
                continuacion.resume(returning: estado)
            }
        }
    }

    /// Enciende el micrófono y empieza a transcribir.
    func iniciar() throws {
        let sesion = AVAudioSession.sharedInstance()
        try sesion.setCategory(.record, mode: .measurement, options: .duckOthers)
        try sesion.setActive(true, options: .notifyOthersOnDeactivation)

        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else { throw ErrorDeVoz.sinMicrofono }

        entrada.removeTap(onBus: 0)
        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak self] audio, _ in
            self?.peticionActual()?.append(audio)
        }
        motor.prepare()
        try motor.start()

        cola.async { [self] in
            activo = true
            fallosSeguidos = 0
            nuevaFrase()
        }
    }

    /// Apaga el micrófono. Lo que se estaba diciendo se descarta (quien llama ya tiene el parcial).
    func detener() {
        motor.stop()
        motor.inputNode.removeTap(onBus: 0)
        cola.async { [self] in
            activo = false
            generacion += 1
            pausa?.cancel()
            limite?.cancel()
            pausa = nil
            limite = nil
            cambiarPeticion(nil)?.endAudio()
            tarea?.cancel()
            tarea = nil
            textoParcial = ""
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Una frase a la vez (todo dentro de `cola`)

    private func nuevaFrase() {
        guard activo else { return }
        generacion += 1
        let esta = generacion
        textoParcial = ""
        inicioDeFrase = Date()

        let peticion = SFSpeechAudioBufferRecognitionRequest()
        peticion.shouldReportPartialResults = true
        peticion.requiresOnDeviceRecognition = soloEnDispositivo
        peticion.taskHint = .dictation
        peticion.addsPunctuation = true
        cambiarPeticion(peticion)

        tarea = voz.recognitionTask(with: peticion) { [weak self] resultado, error in
            // Se saca lo necesario aquí: el resultado no se puede pasar a otra cola.
            let texto = resultado?.bestTranscription.formattedString ?? ""
            let esFinal = resultado?.isFinal ?? false
            let fallo = error != nil
            self?.cola.async {
                self?.recibir(texto: texto, esFinal: esFinal, fallo: fallo, generacion: esta)
            }
        }
    }

    private func recibir(texto: String, esFinal: Bool, fallo: Bool, generacion esta: Int) {
        guard activo, esta == generacion else { return }

        if !texto.isEmpty {
            fallosSeguidos = 0
            textoParcial = texto
            if !esFinal {
                avisar(.parcial(texto))
                programarPausa()
                if limite == nil { programarLimite() }
            }
        }
        if esFinal || fallo {
            cerrarFrase(huboFallo: fallo)
        }
    }

    /// Entrega la frase actual (si hay) y empieza a escuchar la siguiente.
    private func cerrarFrase(huboFallo: Bool) {
        pausa?.cancel()
        limite?.cancel()
        pausa = nil
        limite = nil
        generacion += 1
        cambiarPeticion(nil)?.endAudio()
        tarea?.cancel()
        tarea = nil

        let frase = textoParcial
        textoParcial = ""
        if !frase.isEmpty {
            avisar(.frase(frase))
            nuevaFrase()
            return
        }
        guard huboFallo else {
            nuevaFrase()
            return
        }

        // Sin texto y con error. Si tardó, solo fue silencio: se sigue escuchando.
        // Si falló de inmediato varias veces seguidas, el reconocimiento no funciona aquí.
        let fueInmediato = Date().timeIntervalSince(inicioDeFrase) < 1
        fallosSeguidos = fueInmediato ? fallosSeguidos + 1 : 0
        if fallosSeguidos >= 5 {
            activo = false
            avisar(.detenido)
            return
        }
        let esta = generacion
        cola.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.generacion == esta else { return }
            self.nuevaFrase()
        }
    }

    private func programarPausa() {
        pausa?.cancel()
        pausa = programar(en: Self.segundosDePausa)
    }

    private func programarLimite() {
        limite = programar(en: Self.segundosMaximosPorFrase)
    }

    /// Cierra la frase actual dentro de `segundos`, salvo que antes empiece otra.
    private func programar(en segundos: Double) -> DispatchWorkItem {
        let esta = generacion
        let trabajo = DispatchWorkItem { [weak self] in
            guard let self, self.activo, self.generacion == esta else { return }
            self.cerrarFrase(huboFallo: false)
        }
        cola.asyncAfter(deadline: .now() + segundos, execute: trabajo)
        return trabajo
    }

    // MARK: Petición compartida con el hilo del audio

    private func peticionActual() -> SFSpeechAudioBufferRecognitionRequest? {
        candado.lock()
        defer { candado.unlock() }
        return peticionConAudio
    }

    @discardableResult
    private func cambiarPeticion(_ nueva: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        candado.lock()
        defer { candado.unlock() }
        let anterior = peticionConAudio
        peticionConAudio = nueva
        return anterior
    }
}

// MARK: - Lo que usa la pantalla de la llamada

/// Transcribe lo que dice la persona durante la llamada y manda las frases al operador.
/// La pantalla de la llamada crea uno, lo inicia al abrir y lo detiene al colgar.
@MainActor
@Observable
final class TranscriptorLlamada {
    enum Estado: Equatable {
        case apagado
        case escuchando
        /// La persona silenció el micrófono.
        case pausado
        /// En este teléfono no se puede transcribir (con el motivo). El operador llena la ficha a mano.
        case noDisponible(String)
    }

    /// Cómo se mandan las líneas al servidor. Las pruebas ponen aquí un servidor falso.
    typealias Envio = @MainActor (_ llamada: UUID, _ lineas: [LineaTranscrita]) async throws -> Void

    private(set) var estado: Estado = .apagado
    /// Lo que se va entendiendo de la frase que la persona está diciendo.
    private(set) var fraseActual = ""
    /// La última frase terminada.
    private(set) var ultimaFrase = ""
    /// Frases que faltan por enviar al operador.
    private(set) var cola = ColaTranscripcion()

    /// Lo que se muestra en la pantalla de la llamada: la frase en curso o, si no hay, la última.
    var textoVisible: String { fraseActual.isEmpty ? ultimaFrase : fraseActual }

    @ObservationIgnored private let enviar: Envio
    @ObservationIgnored private var reconocedor: ReconocedorDeVoz?
    @ObservationIgnored private var inicioDeLlamada: Date?
    @ObservationIgnored private var enviando = false
    /// El servidor ya no acepta texto de esta llamada (terminó o se marcó como perdida).
    @ObservationIgnored private var llamadaCerrada = false

    init(enviar: @escaping Envio = { llamada, lineas in
        try await EmergencyAPI.shared.sendTranscript(id: llamada, lines: lineas)
    }) {
        self.enviar = enviar
    }

    /// Segundos transcurridos desde que empezó la llamada.
    private var segundoActual: Int {
        guard let inicioDeLlamada else { return 0 }
        return max(0, Int(Date().timeIntervalSince(inicioDeLlamada)))
    }

    // MARK: Encender y apagar

    /// Pide los permisos que falten y empieza a transcribir. Si no se puede, `estado` dice por qué
    /// y la llamada sigue igual.
    func iniciar() async {
        guard estado == .apagado else { return }
        if inicioDeLlamada == nil { inicioDeLlamada = .now }

        guard let voz = SFSpeechRecognizer(locale: Locale(identifier: "es-MX")), voz.isAvailable else {
            estado = .noDisponible("La transcripción no está disponible en este iPhone.")
            return
        }
        // RNF05: el audio no sale del teléfono. Si este iPhone no puede transcribir por sí solo,
        // no se transcribe y el operador llena la ficha a mano (HU10).
        let soloEnDispositivo = voz.supportsOnDeviceRecognition
        guard soloEnDispositivo || Self.permiteReconocimientoEnLinea else {
            estado = .noDisponible("Este iPhone no puede transcribir la llamada sin enviar el audio fuera del teléfono.")
            return
        }
        guard await tienePermisos() else {
            estado = .noDisponible("Sin permiso de micrófono y de reconocimiento de voz no hay transcripción.")
            return
        }
        // Mientras se contestaban los permisos la pantalla pudo cerrarse o silenciarse.
        guard estado == .apagado else { return }

        let nuevo = ReconocedorDeVoz(voz: voz, soloEnDispositivo: soloEnDispositivo) { [weak self] evento in
            Task { @MainActor in self?.recibir(evento) }
        }
        do {
            try nuevo.iniciar()
            reconocedor = nuevo
            estado = .escuchando
        } catch {
            estado = .noDisponible("No se pudo usar el micrófono para transcribir.")
        }
    }

    /// Deja de escuchar. Lo que se estaba diciendo queda como última frase.
    func detener() {
        apagarReconocedor()
        if estado == .escuchando || estado == .pausado { estado = .apagado }
    }

    /// El micrófono se silenció: tampoco se transcribe.
    func pausar() {
        guard estado == .escuchando else { return }
        apagarReconocedor()
        estado = .pausado
    }

    func reanudar() async {
        guard estado == .pausado else { return }
        estado = .apagado
        await iniciar()
    }

    private func apagarReconocedor() {
        reconocedor?.detener()
        reconocedor = nil
        if !fraseActual.isEmpty { registrar(frase: fraseActual) }
    }

    /// El simulador no trae el modelo de voz en el dispositivo. Solo ahí, para poder probar, se
    /// permite el reconocimiento de Apple por internet. En un iPhone real siempre es `false`.
    private static var permiteReconocimientoEnLinea: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func tienePermisos() async -> Bool {
        // iOS cierra la app si se pide un permiso sin su texto en el proyecto.
        let claves = ["NSSpeechRecognitionUsageDescription", "NSMicrophoneUsageDescription"]
        guard claves.allSatisfy({ Bundle.main.object(forInfoDictionaryKey: $0) != nil }) else { return false }

        var voz = SFSpeechRecognizer.authorizationStatus()
        if voz == .notDetermined { voz = await ReconocedorDeVoz.pedirPermiso() }
        guard voz == .authorized else { return false }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: Frases

    private func recibir(_ evento: ReconocedorDeVoz.Evento) {
        // Avisos que llegan después de apagar o silenciar ya no cuentan.
        guard estado == .escuchando else { return }
        switch evento {
        case .parcial(let texto):
            fraseActual = TextoTranscrito.limpiar(texto)
        case .frase(let texto):
            registrar(frase: texto)
        case .detenido:
            reconocedor = nil
            estado = .noDisponible("La transcripción se detuvo. El operador llenará la ficha a mano.")
        }
    }

    /// Guarda una frase terminada para enviarla al operador.
    /// - Parameter segundo: segundos desde el inicio de la llamada; si es `nil` se usa el momento actual.
    func registrar(frase: String, segundo: Int? = nil) {
        fraseActual = ""
        let limpia = TextoTranscrito.limpiar(frase)
        guard !limpia.isEmpty else { return }
        ultimaFrase = limpia
        cola.agregar(limpia, segundo: segundo ?? segundoActual)
    }

    // MARK: Envío al operador

    /// Manda al servidor las frases pendientes (hasta 20 por envío).
    /// Si el envío falla, las frases se quedan y se vuelve a intentar en la siguiente llamada a este método.
    func enviarPendientes(de llamada: UUID) async {
        guard !enviando, !llamadaCerrada else { return }
        let envio = cola.siguienteEnvio
        guard !envio.isEmpty else { return }

        enviando = true
        defer { enviando = false }
        do {
            try await enviar(llamada, envio)
            cola.confirmar(envio.count)
        } catch EmergencyAPIError.callClosed {
            // La llamada ya terminó en el servidor: no tiene caso seguir mandando.
            llamadaCerrada = true
            cola.vaciar()
        } catch {
            // Sin conexión o error del servidor: se reintenta después.
        }
    }
}
