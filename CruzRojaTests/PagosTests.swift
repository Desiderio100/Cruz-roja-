//
//  PagosTests.swift
//  Pruebas unitarias del pago con Stripe en la tienda (Productos con causa).
//
//  Usan un servidor FALSO: no tocan internet ni Stripe. Revisan toda la lógica de la app:
//  datos de envío, totales, qué pasa cuando Stripe contesta y cómo se lee lo que manda el backend.
//  (El cobro real con Stripe y el webhook se prueban en backend/test/pagos.test.js.)
//

import Foundation
import Testing
@testable import CruzRoja

// MARK: - Datos y servidor falso

enum DatosDePrueba {
    static let envio = DatosEnvio(
        nombre: "Ana Prueba", telefono: "8112345678", calleNumero: "Av. Juárez 100",
        colonia: "Centro", ciudad: "Monterrey", entidad: "Nuevo León", codigoPostal: "64000", referencias: "")

    static let condiciones = CondicionesDeCompra(
        disponible: true, envioMxn: 99, cantidadMaxima: 10, totalMinimoMxn: 10)

    static let pedido = Pedido(
        id: "0b9a3c7e-1111-4222-8333-444455556666", folio: "PC-000012", productoNombre: "Bolsa solidaria",
        cantidad: 2, envioMxn: 99, totalMxn: 399, clientSecret: "pi_prueba_secret_abc", publishableKey: "pk_test_prueba")
}

/// Servidor falso: guarda lo que la app le pide y contesta lo que cada prueba necesite.
final class PedidosFalso: PedidosRepositorio {
    var respuestaCondiciones: Result<CondicionesDeCompra, Error> = .success(DatosDePrueba.condiciones)
    var respuestaCrear: Result<Pedido, Error> = .success(DatosDePrueba.pedido)
    /// Lo que contesta "¿ya se pagó?", en orden (nil = sin internet). Al acabarse repite el último.
    var estados: [EstadoPedido?] = [.pendiente] { didSet { indice = 0 } }
    var falloAlCancelar = false

    private var indice = 0
    private(set) var pedidosCreados: [(productoId: Int, cantidad: Int, datos: DatosEnvio)] = []
    private(set) var consultasDeEstado = 0
    private(set) var cancelados: [String] = []

    func condiciones() async throws -> CondicionesDeCompra {
        try respuestaCondiciones.get()
    }

    func crear(productoId: Int, cantidad: Int, datos: DatosEnvio) async throws -> Pedido {
        pedidosCreados.append((productoId, cantidad, datos))
        return try respuestaCrear.get()
    }

    func estado(de pedidoId: String) async throws -> EstadoPedido {
        consultasDeEstado += 1
        let actual = estados[min(indice, estados.count - 1)]
        indice += 1
        guard let actual else { throw ErrorAPI(mensaje: "No hay conexión con el servidor") }
        return actual
    }

    func cancelar(pedidoId: String) async throws {
        if falloAlCancelar { throw ErrorAPI(mensaje: "Ocurrió un error") }
        cancelados.append(pedidoId)
    }
}

/// Cuenta cuántas veces la app "esperó" entre una pregunta y otra (sin esperar de verdad).
final class ContadorDeEsperas {
    var cuenta = 0
}

// MARK: - Datos de envío y dinero

@Suite("Pago con Stripe · datos de envío y dinero")
struct DatosEnvioTests {
    private func problema(_ cambiar: (inout DatosEnvio) -> Void) -> String? {
        var datos = DatosDePrueba.envio
        cambiar(&datos)
        return datos.problema
    }

    @Test("Datos completos y bien escritos son válidos")
    func datosValidos() {
        #expect(DatosDePrueba.envio.problema == nil)
        #expect(DatosDePrueba.envio.esValido)
    }

    @Test("Avisa qué falta o qué está mal, con las mismas reglas del servidor")
    func avisaQueFalta() {
        #expect(problema({ $0.nombre = "" }) == "Falta el nombre.")
        #expect(problema({ $0.nombre = "Al" }) == "Revisa el nombre: es muy corto.")
        #expect(problema({ $0.nombre = String(repeating: "a", count: 121) }) == "Revisa el nombre: es muy largo.")
        #expect(problema({ $0.telefono = "" }) == "Falta el teléfono.")
        #expect(problema({ $0.telefono = "12345" }) == "El teléfono debe tener entre 10 y 15 dígitos.")
        #expect(problema({ $0.calleNumero = "" }) == "Falta la calle y el número.")
        #expect(problema({ $0.colonia = "" }) == "Falta la colonia.")
        #expect(problema({ $0.ciudad = "" }) == "Falta la ciudad.")
        #expect(problema({ $0.entidad = "" }) == "Falta el estado.")
        #expect(problema({ $0.codigoPostal = "" }) == "Falta el código postal.")
        #expect(problema({ $0.codigoPostal = "6400" }) == "El código postal debe tener 5 dígitos.")
        #expect(problema({ $0.codigoPostal = "640000" }) == "El código postal debe tener 5 dígitos.")
        #expect(problema({ $0.referencias = String(repeating: "a", count: 201) })
                == "Las referencias son muy largas (máximo 200 letras).")
    }

    @Test("Las referencias son opcionales")
    func referenciasOpcionales() {
        #expect(problema({ $0.referencias = "" }) == nil)
        #expect(problema({ $0.referencias = "Casa azul, entre Hidalgo y Morelos" }) == nil)
    }

    @Test("Limpia espacios, saltos de línea, símbolos del teléfono y letras del código postal")
    func limpiaLosDatos() {
        var datos = DatosDePrueba.envio
        datos.nombre = "  Ana\nPrueba  "
        datos.telefono = "(81) 1234-5678"
        datos.codigoPostal = "C.P. 64000"
        datos.referencias = "   "

        let limpios = datos.normalizado
        #expect(limpios.nombre == "Ana Prueba")
        #expect(limpios.telefono == "8112345678")
        #expect(limpios.codigoPostal == "64000")
        #expect(limpios.referencias == "")
        #expect(datos.esValido)
    }

    @Test("Acepta teléfono con lada internacional")
    func telefonoConMas() {
        #expect(problema({ $0.telefono = "+52 81 1234 5678" }) == nil)
    }

    @Test("El dinero se calcula en centavos enteros")
    func dineroEnCentavos() {
        #expect(Dinero.centavos(Decimal(150)) == 15000)
        #expect(Dinero.centavos(Decimal(string: "150.50")!) == 15050)
        #expect(Dinero.centavos(99.0) == 9900)
        #expect(Dinero.centavos(0.29) == 29) // 0.29 × 100 en decimales de computadora es 28.999…
    }

    @Test("El dinero se escribe como en el catálogo")
    func dineroComoTexto() {
        #expect(Dinero.texto(centavos: 15000) == "$150 MXN")
        #expect(Dinero.texto(centavos: 9900) == "$99 MXN")
        #expect(Dinero.texto(centavos: 39950) == "$399.50 MXN")
    }
}

// MARK: - Lo que manda el backend

@Suite("Pago con Stripe · respuestas del backend")
@MainActor
struct RespuestasDelBackendTests {
    @Test("Lee la respuesta de POST /api/pedidos tal como la manda el backend")
    func leePedido() throws {
        let json = """
        {"id":"0b9a3c7e-1111-4222-8333-444455556666","folio":"PC-000012","producto_nombre":"Bolsa solidaria",
         "cantidad":2,"envio_mxn":99,"total_mxn":399,"client_secret":"pi_123_secret_abc","publishable_key":"pk_test_abc"}
        """
        let pedido = try ClienteAPI.compartido.decodificar(Pedido.self, Data(json.utf8))
        #expect(pedido.id == "0b9a3c7e-1111-4222-8333-444455556666")
        #expect(pedido.folio == "PC-000012")
        #expect(pedido.productoNombre == "Bolsa solidaria")
        #expect(pedido.cantidad == 2)
        #expect(pedido.envioMxn == 99)
        #expect(pedido.clientSecret == "pi_123_secret_abc")
        #expect(pedido.publishableKey == "pk_test_abc")
        #expect(pedido.totalCentavos == 39900)
        #expect(pedido.totalTexto == "$399 MXN")
    }

    @Test("Lee el estado del pedido aunque el servidor mande más campos (fechas, nulos)")
    func leeEstado() throws {
        let json = """
        {"id":"0b9a3c7e-1111-4222-8333-444455556666","folio":"PC-000012","estado":"pagado",
         "producto_nombre":"Bolsa solidaria","cantidad":2,"envio_mxn":99,"total_mxn":399,
         "creado_en":"2026-10-27T18:30:00.000Z","pagado_en":"2026-10-27T18:31:12.000Z"}
        """
        let estado = try ClienteAPI.compartido.decodificar(EstadoDelPedido.self, Data(json.utf8))
        #expect(estado.estado == .pagado)
        #expect(estado.folio == "PC-000012")

        let pendiente = """
        {"id":"x","folio":"PC-000013","estado":"pendiente","creado_en":"2026-10-27T18:30:00.000Z","pagado_en":null}
        """
        let sinPagar = try ClienteAPI.compartido.decodificar(EstadoDelPedido.self, Data(pendiente.utf8))
        #expect(sinPagar.estado == .pendiente)
    }

    @Test("Lee las condiciones de compra (costo de envío)")
    func leeCondiciones() throws {
        let json = #"{"disponible":true,"envio_mxn":99,"cantidad_maxima":10,"total_minimo_mxn":10}"#
        let condiciones = try ClienteAPI.compartido.decodificar(CondicionesDeCompra.self, Data(json.utf8))
        #expect(condiciones == DatosDePrueba.condiciones)
    }
}

// MARK: - Flujo de la compra

@Suite("Pago con Stripe · flujo de la compra")
@MainActor
struct FlujoDeCompraTests {
    private func crearVM(
        _ servidor: PedidosFalso,
        stripeListo: Bool = true,
        intentos: Int = 3,
        esperas: ContadorDeEsperas = ContadorDeEsperas()
    ) -> PagoViewModel {
        PagoViewModel(
            producto: Producto.ejemplos[0], repositorio: servidor, datosIniciales: DatosDePrueba.envio,
            stripeListo: stripeListo, intentosDeConfirmacion: intentos, esperar: { esperas.cuenta += 1 })
    }

    /// Un view model con las condiciones ya cargadas.
    private func vmListo(
        _ servidor: PedidosFalso = PedidosFalso(),
        intentos: Int = 3,
        esperas: ContadorDeEsperas = ContadorDeEsperas()
    ) async -> PagoViewModel {
        let vm = crearVM(servidor, intentos: intentos, esperas: esperas)
        await vm.cargarCondiciones()
        return vm
    }

    /// Un view model que ya creó el pedido y está esperando a Stripe.
    private func vmEsperandoAStripe(
        _ servidor: PedidosFalso,
        intentos: Int = 3,
        esperas: ContadorDeEsperas = ContadorDeEsperas()
    ) async -> PagoViewModel {
        let vm = await vmListo(servidor, intentos: intentos, esperas: esperas)
        await vm.pagar()
        return vm
    }

    @Test("Los mensajes del servidor se muestran con mayúscula y punto")
    func mensajesLegibles() {
        #expect(PagoViewModel.mensaje(ErrorAPI(mensaje: "el código postal debe tener 5 dígitos"))
                == "El código postal debe tener 5 dígitos.")
        #expect(PagoViewModel.mensaje(ErrorAPI(mensaje: "No pudimos iniciar el pago. Intenta de nuevo."))
                == "No pudimos iniciar el pago. Intenta de nuevo.")
    }

    // MARK: Totales

    @Test("Subtotal, envío y total se calculan en centavos")
    func totales() async {
        let vm = await vmListo()
        vm.cantidad = 2
        #expect(vm.subtotalCentavos == 30000)
        #expect(vm.envioCentavos == 9900)
        #expect(vm.totalCentavos == 39900)
    }

    @Test("Sin conocer el costo de envío no hay total")
    func sinCondicionesNoHayTotal() {
        let vm = crearVM(PedidosFalso())
        #expect(vm.totalCentavos == nil)
        #expect(vm.disponibilidad == .consultando)
        #expect(!vm.puedePagar)
    }

    @Test("Si el servidor manda un máximo absurdo (0), la cantidad mínima sigue siendo 1")
    func maximoAbsurdo() async {
        let servidor = PedidosFalso()
        servidor.respuestaCondiciones = .success(
            CondicionesDeCompra(disponible: true, envioMxn: 99, cantidadMaxima: 0, totalMinimoMxn: 10))
        let vm = await vmListo(servidor)
        #expect(vm.cantidadMaxima == 1)
        #expect(vm.subtotalCentavos == 15_000)
    }

    @Test("La cantidad siempre queda entre 1 y el máximo")
    func cantidadAcotada() async {
        let vm = await vmListo()
        vm.cantidad = 50
        #expect(vm.subtotalCentavos == 150_000) // 10 × $150
        vm.cantidad = 0
        #expect(vm.subtotalCentavos == 15_000) // 1 × $150
    }

    // MARK: Disponibilidad

    @Test("Con todo en orden se puede pagar")
    func sePuedePagar() async {
        let vm = await vmListo()
        #expect(vm.disponibilidad == .disponible)
        #expect(vm.puedePagar)
    }

    @Test("Con datos de envío incompletos no se puede pagar y se explica por qué")
    func datosIncompletos() async {
        let vm = await vmListo()
        vm.datos.codigoPostal = "64"
        #expect(!vm.puedePagar)
        #expect(vm.ayuda == "El código postal debe tener 5 dígitos.")
    }

    @Test("Si el servidor tiene los pagos apagados, avisa y no deja pagar")
    func pagosApagadosEnElServidor() async {
        let servidor = PedidosFalso()
        servidor.respuestaCondiciones = .success(
            CondicionesDeCompra(disponible: false, envioMxn: 99, cantidadMaxima: 10, totalMinimoMxn: 10))
        let vm = await vmListo(servidor)
        #expect(vm.disponibilidad == .noDisponible)
        #expect(!vm.puedePagar)
    }

    @Test("Si el paquete de Stripe no está en la app, avisa y no deja pagar")
    func sinPaqueteDeStripe() async {
        let vm = crearVM(PedidosFalso(), stripeListo: false)
        await vm.cargarCondiciones()
        #expect(vm.disponibilidad == .noDisponible)
        #expect(!vm.puedePagar)
    }

    @Test("Sin conexión al pedir las condiciones se puede reintentar")
    func condicionesSinConexion() async {
        let servidor = PedidosFalso()
        servidor.respuestaCondiciones = .failure(ErrorAPI(mensaje: "No hay conexión con el servidor"))
        let vm = crearVM(servidor)
        await vm.cargarCondiciones()
        #expect(vm.disponibilidad == .sinConexion("No hay conexión con el servidor."))

        servidor.respuestaCondiciones = .success(DatosDePrueba.condiciones)
        await vm.cargarCondiciones()
        #expect(vm.disponibilidad == .disponible)
    }

    @Test("El total mínimo que cobra Stripe también se respeta")
    func totalMinimo() async {
        let servidor = PedidosFalso()
        servidor.respuestaCondiciones = .success(
            CondicionesDeCompra(disponible: true, envioMxn: 0, cantidadMaxima: 10, totalMinimoMxn: 1000))
        let vm = await vmListo(servidor)
        #expect(!vm.puedePagar) // $150 de producto, mínimo $1,000
        vm.cantidad = 7
        #expect(vm.puedePagar) // $1,050
    }

    // MARK: Crear el pedido

    @Test("Pagar crea el pedido con producto, cantidad y datos de envío (nunca un precio)")
    func pagarCreaElPedido() async {
        let servidor = PedidosFalso()
        let vm = await vmListo(servidor)
        vm.cantidad = 2
        await vm.pagar()

        #expect(servidor.pedidosCreados.count == 1)
        #expect(servidor.pedidosCreados.first?.productoId == 1)
        #expect(servidor.pedidosCreados.first?.cantidad == 2)
        #expect(servidor.pedidosCreados.first?.datos == DatosDePrueba.envio)
        #expect(vm.fase == .listoParaPagar(DatosDePrueba.pedido))
        #expect(vm.pedidoParaPagar == DatosDePrueba.pedido)
        #expect(vm.ocupado)
    }

    @Test("Si el servidor rechaza el pedido, se muestra el motivo y se puede corregir")
    func pedidoRechazado() async {
        let servidor = PedidosFalso()
        servidor.respuestaCrear = .failure(ErrorAPI(mensaje: "el código postal debe tener 5 dígitos", estado: 400))
        let vm = await vmListo(servidor)
        await vm.pagar()

        #expect(vm.fase == .editando)
        #expect(vm.mensajeError == "El código postal debe tener 5 dígitos.")
        #expect(vm.pedidoParaPagar == nil)
        #expect(!vm.ocupado)
    }

    @Test("No crea pedido si los datos no son válidos")
    func noCreaConDatosInvalidos() async {
        let servidor = PedidosFalso()
        let vm = await vmListo(servidor)
        vm.datos.nombre = ""
        await vm.pagar()
        #expect(servidor.pedidosCreados.isEmpty)
        #expect(vm.fase == .editando)
    }

    // MARK: Lo que contesta Stripe

    @Test("Pago completado: pregunta al servidor hasta que confirme y entonces muestra el folio")
    func pagoCompletado() async {
        let servidor = PedidosFalso()
        servidor.estados = [.pendiente, .pendiente, .pagado]
        let esperas = ContadorDeEsperas()
        let vm = await vmEsperandoAStripe(servidor, esperas: esperas)

        await vm.resultadoDePago(.completado)

        #expect(vm.fase == .pagado(DatosDePrueba.pedido))
        #expect(servidor.consultasDeEstado == 3)
        #expect(esperas.cuenta == 2)
        #expect(servidor.cancelados.isEmpty)
    }

    @Test("Si el internet se corta mientras confirma, sigue intentando")
    func confirmaConInternetIntermitente() async {
        let servidor = PedidosFalso()
        servidor.estados = [nil, nil, .pagado]
        let vm = await vmEsperandoAStripe(servidor)
        await vm.resultadoDePago(.completado)
        #expect(vm.fase == .pagado(DatosDePrueba.pedido))
    }

    @Test("Si el servidor no confirma a tiempo, queda 'en revisión' (no se vuelve a cobrar) y se puede revisar de nuevo")
    func enRevision() async {
        let servidor = PedidosFalso()
        servidor.estados = [.pendiente]
        let vm = await vmEsperandoAStripe(servidor)

        await vm.resultadoDePago(.completado)
        #expect(vm.fase == .enRevision(DatosDePrueba.pedido))
        #expect(servidor.consultasDeEstado == 3)
        #expect(servidor.cancelados.isEmpty) // un pago hecho nunca se cancela desde la app

        servidor.estados = [.pagado]
        await vm.revisarDeNuevo()
        #expect(vm.fase == .pagado(DatosDePrueba.pedido))
    }

    @Test("La app no se da por pagada sola: sin confirmación del servidor no hay 'pagado'")
    func noSeDaPorPagada() async {
        let servidor = PedidosFalso()
        servidor.estados = [.cancelado]
        let vm = await vmEsperandoAStripe(servidor)
        await vm.resultadoDePago(.completado)
        #expect(vm.fase == .enRevision(DatosDePrueba.pedido))
    }

    @Test("Cerrar la hoja de pago sin pagar regresa al formulario y cancela el pedido")
    func pagoCancelado() async {
        let servidor = PedidosFalso()
        let vm = await vmEsperandoAStripe(servidor)

        await vm.resultadoDePago(.cancelado)

        #expect(vm.fase == .editando)
        #expect(vm.mensajeError == nil)
        #expect(servidor.cancelados == [DatosDePrueba.pedido.id])
        #expect(vm.puedePagar) // puede intentar otra vez
    }

    @Test("Si Stripe falla y el pedido no se pagó: muestra el error y cancela el pedido")
    func pagoFallido() async {
        let servidor = PedidosFalso()
        servidor.estados = [.pendiente]
        let vm = await vmEsperandoAStripe(servidor)

        await vm.resultadoDePago(.fallido("No se pudo completar el pago."))

        #expect(vm.fase == .editando)
        #expect(vm.mensajeError == "No se pudo completar el pago.")
        #expect(servidor.cancelados == [DatosDePrueba.pedido.id])
    }

    @Test("Si Stripe 'falla' pero el cobro sí entró, se muestra como pagado y NO se cancela")
    func fallidoPeroPagado() async {
        let servidor = PedidosFalso()
        servidor.estados = [.pagado]
        let vm = await vmEsperandoAStripe(servidor)

        await vm.resultadoDePago(.fallido("Se cortó la conexión."))

        #expect(vm.fase == .pagado(DatosDePrueba.pedido))
        #expect(servidor.cancelados.isEmpty)
    }

    @Test("Si no se puede cancelar el pedido, igual regresa al formulario")
    func cancelarFalla() async {
        let servidor = PedidosFalso()
        servidor.falloAlCancelar = true
        let vm = await vmEsperandoAStripe(servidor)
        await vm.resultadoDePago(.cancelado)
        #expect(vm.fase == .editando)
    }

    @Test("Un resultado de Stripe sin pedido en curso no hace nada")
    func resultadoSinPedido() async {
        let servidor = PedidosFalso()
        let vm = await vmListo(servidor)
        await vm.resultadoDePago(.completado)
        #expect(vm.fase == .editando)
        #expect(servidor.consultasDeEstado == 0)
    }
}
