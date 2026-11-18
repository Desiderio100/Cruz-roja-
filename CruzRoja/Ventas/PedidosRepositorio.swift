//
//  PedidosRepositorio.swift
//  Ventas
//
//  De dónde salen (y a dónde van) los pedidos. La pantalla de compra solo conoce este protocolo:
//  en producción habla con el backend (PedidosAPI) y en las pruebas se usa uno falso.
//

import Foundation

protocol PedidosRepositorio {
    /// Costo de envío y límites, para mostrar el total antes de pagar.
    func condiciones() async throws -> CondicionesDeCompra
    /// Crea el pedido y el cobro. El PRECIO lo pone el servidor: aquí solo va qué producto y cuántos.
    func crear(productoId: Int, cantidad: Int, datos: DatosEnvio) async throws -> Pedido
    /// Estado del pedido. Pasa a "pagado" cuando Stripe avisa al servidor (no cuando la app lo diga).
    func estado(de pedidoId: String) async throws -> EstadoPedido
    /// Cancela un pedido que todavía no se pagó.
    func cancelar(pedidoId: String) async throws
}

/// Habla con el backend: backend/src/rutas/pedidos.js (llamadas en ClienteAPI+Pedidos.swift).
struct PedidosAPI: PedidosRepositorio {
    func condiciones() async throws -> CondicionesDeCompra {
        try await ClienteAPI.compartido.condicionesDeCompra()
    }

    func crear(productoId: Int, cantidad: Int, datos: DatosEnvio) async throws -> Pedido {
        try await ClienteAPI.compartido.crearPedido(productoId: productoId, cantidad: cantidad, datos: datos)
    }

    func estado(de pedidoId: String) async throws -> EstadoPedido {
        try await ClienteAPI.compartido.estadoDelPedido(pedidoId)
    }

    func cancelar(pedidoId: String) async throws {
        try await ClienteAPI.compartido.cancelarPedido(pedidoId)
    }
}

/// Solo para las vistas previas de Xcode: no crea pedidos de verdad.
struct PedidosDeEjemplo: PedidosRepositorio {
    func condiciones() async throws -> CondicionesDeCompra {
        CondicionesDeCompra(disponible: true, envioMxn: 99, cantidadMaxima: 10, totalMinimoMxn: 10)
    }

    func crear(productoId: Int, cantidad: Int, datos: DatosEnvio) async throws -> Pedido {
        throw ErrorAPI(mensaje: "La vista previa no crea pedidos")
    }

    func estado(de pedidoId: String) async throws -> EstadoPedido { .pendiente }

    func cancelar(pedidoId: String) async throws {}
}
