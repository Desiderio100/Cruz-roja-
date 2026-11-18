//
//  PagoViewModel.swift
//  Ventas
//
//  Toda la lógica de la compra: qué se ve en cada momento, cuánto se paga y qué hacer cuando
//  Stripe contesta. NO importa Stripe (eso vive en PagoStripe.swift), así que se puede probar
//  con un servidor falso (CruzRojaTests/PagosTests.swift).
//
//  Camino feliz:
//    editando → preparando (se crea el pedido) → listoParaPagar (se abre la hoja de Stripe)
//    → confirmando (Stripe cobró; se espera que el servidor lo confirme) → pagado
//
//  La app NUNCA decide que algo "ya está pagado": solo lo cree cuando el servidor lo dice,
//  y el servidor solo lo dice cuando Stripe le avisa por el webhook.
//

import Combine
import Foundation

/// Cómo terminó la hoja de pago de Stripe (la traduce PagoStripe.swift).
enum ResultadoDePago: Equatable {
    case completado
    case cancelado
    case fallido(String)
}

enum FasePago: Equatable {
    case editando
    /// Se está creando el pedido en el servidor.
    case preparando
    /// El pedido existe; la hoja de Stripe se está abriendo o está abierta.
    case listoParaPagar(Pedido)
    /// Stripe cobró; falta que el servidor lo confirme.
    case confirmando(Pedido)
    case pagado(Pedido)
    /// Stripe cobró pero el servidor no lo confirmó a tiempo. NO hay que volver a pagar.
    case enRevision(Pedido)
}

@MainActor
final class PagoViewModel: ObservableObject {
    enum Disponibilidad: Equatable {
        case consultando
        case sinConexion(String)
        /// Pagos apagados en el servidor, o el paquete de Stripe no está agregado a la app.
        case noDisponible
        case disponible
    }

    let producto: Producto

    @Published var cantidad = 1
    @Published var datos: DatosEnvio
    @Published var mensajeError: String?
    @Published private(set) var fase: FasePago = .editando
    @Published private(set) var condiciones: CondicionesDeCompra?
    @Published private(set) var errorCondiciones: String?
    @Published private(set) var cargandoCondiciones = false

    private let repositorio: PedidosRepositorio
    private let stripeListo: Bool
    private let intentosDeConfirmacion: Int
    private let esperar: () async -> Void

    /// - Parameters:
    ///   - datosIniciales: si es nil se precargan el nombre y teléfono del registro (Perfil).
    ///   - stripeListo: false si el paquete de Stripe no está agregado al proyecto.
    ///   - intentosDeConfirmacion / esperar: cuántas veces y cada cuánto se le pregunta al servidor
    ///     si ya recibió el aviso de Stripe (en las pruebas se pone sin espera).
    init(
        producto: Producto,
        repositorio: PedidosRepositorio = PedidosAPI(),
        datosIniciales: DatosEnvio? = nil,
        stripeListo: Bool = PagoStripe.disponible,
        intentosDeConfirmacion: Int = 10,
        esperar: @escaping () async -> Void = { _ = try? await Task.sleep(nanoseconds: 2_000_000_000) }
    ) {
        self.producto = producto
        self.repositorio = repositorio
        self.datos = datosIniciales ?? DatosEnvio(nombre: Perfil.nombre, telefono: Perfil.telefono)
        self.stripeListo = stripeListo
        self.intentosDeConfirmacion = max(1, intentosDeConfirmacion)
        self.esperar = esperar
    }

    // MARK: - Lo que ve la pantalla

    /// Nunca menos de 1 (así `1...cantidadMaxima` siempre es un rango válido).
    var cantidadMaxima: Int { max(1, condiciones?.cantidadMaxima ?? 10) }

    /// La cantidad siempre dentro de 1…máximo, aunque alguien la cambie desde fuera.
    private var cantidadValida: Int { min(max(cantidad, 1), cantidadMaxima) }

    var subtotalCentavos: Int { Dinero.centavos(producto.precioMXN) * cantidadValida }
    var envioCentavos: Int? { condiciones.map { Dinero.centavos($0.envioMxn) } }
    var totalCentavos: Int? { envioCentavos.map { subtotalCentavos + $0 } }

    var disponibilidad: Disponibilidad {
        if !stripeListo { return .noDisponible }
        if let condiciones { return condiciones.disponible ? .disponible : .noDisponible }
        if let errorCondiciones { return .sinConexion(errorCondiciones) }
        return .consultando
    }

    /// Qué falta llenar (se muestra junto al botón para que se entienda por qué está apagado).
    var ayuda: String? { datos.problema }

    var puedePagar: Bool {
        guard fase == .editando, disponibilidad == .disponible, datos.esValido else { return false }
        guard let condiciones, let total = totalCentavos else { return false }
        return total >= Dinero.centavos(condiciones.totalMinimoMxn)
    }

    /// Mientras se cobra no se puede cerrar la hoja ni editar nada.
    var ocupado: Bool {
        switch fase {
        case .preparando, .listoParaPagar, .confirmando:
            return true
        case .editando, .pagado, .enRevision:
            return false
        }
    }

    /// El pedido cuya hoja de Stripe hay que abrir ahora (la pantalla lo vigila).
    var pedidoParaPagar: Pedido? {
        if case .listoParaPagar(let pedido) = fase { return pedido }
        return nil
    }

    // MARK: - Acciones

    func cargarCondiciones() async {
        guard !cargandoCondiciones, condiciones == nil else { return }
        cargandoCondiciones = true
        defer { cargandoCondiciones = false }
        do {
            condiciones = try await repositorio.condiciones()
            errorCondiciones = nil
        } catch is CancellationError {
            return
        } catch {
            errorCondiciones = Self.mensaje(error)
        }
    }

    /// Botón "Pagar": crea el pedido en el servidor. Después la pantalla abre la hoja de Stripe.
    func pagar() async {
        guard puedePagar else { return }
        mensajeError = nil
        fase = .preparando
        do {
            let pedido = try await repositorio.crear(productoId: producto.id, cantidad: cantidadValida, datos: datos)
            fase = .listoParaPagar(pedido)
        } catch is CancellationError {
            fase = .editando
        } catch {
            fase = .editando
            mensajeError = Self.mensaje(error)
        }
    }

    /// La hoja de Stripe terminó (la pantalla llama esto con lo que contestó Stripe).
    func resultadoDePago(_ resultado: ResultadoDePago) async {
        guard case .listoParaPagar(let pedido) = fase else { return }
        switch resultado {
        case .completado:
            await confirmar(pedido)
        case .cancelado:
            // La persona cerró la hoja sin pagar: queda donde estaba y el pedido se cancela.
            fase = .editando
            await cancelarSinAvisar(pedido)
        case .fallido(let texto):
            // Antes de decir que falló, se revisa si el cobro sí entró (por ejemplo, se cortó el
            // internet justo al final). Si ya está pagado, no se cancela nada.
            if await estadoActual(pedido) == .pagado {
                fase = .pagado(pedido)
                return
            }
            fase = .editando
            mensajeError = texto
            await cancelarSinAvisar(pedido)
        }
    }

    /// Desde la pantalla "estamos confirmando tu pago": volver a preguntarle al servidor.
    func revisarDeNuevo() async {
        guard case .enRevision(let pedido) = fase else { return }
        await confirmar(pedido)
    }

    // MARK: - Internos

    /// Le pregunta al servidor si ya recibió el aviso de Stripe. Casi siempre tarda 1–3 segundos.
    private func confirmar(_ pedido: Pedido) async {
        fase = .confirmando(pedido)
        for intento in 0..<intentosDeConfirmacion {
            if intento > 0 { await esperar() }
            if await estadoActual(pedido) == .pagado {
                fase = .pagado(pedido)
                return
            }
        }
        fase = .enRevision(pedido)
    }

    /// nil si no se pudo preguntar (sin internet): se trata como "todavía no".
    private func estadoActual(_ pedido: Pedido) async -> EstadoPedido? {
        try? await repositorio.estado(de: pedido.id)
    }

    /// Cancelar es de cortesía (para no dejar pedidos pendientes): si falla no pasa nada,
    /// el servidor tampoco cancela un pedido que justo se pagó.
    private func cancelarSinAvisar(_ pedido: Pedido) async {
        try? await repositorio.cancelar(pedidoId: pedido.id)
    }

    /// Los mensajes del servidor vienen en minúscula ("el código postal debe tener 5 dígitos").
    static func mensaje(_ error: Error) -> String {
        let texto = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let primera = texto.first else { return "Ocurrió un error. Intenta de nuevo." }
        var resultado = primera.uppercased() + String(texto.dropFirst())
        if let ultima = resultado.last, !".!?".contains(ultima) { resultado += "." }
        return resultado
    }
}
