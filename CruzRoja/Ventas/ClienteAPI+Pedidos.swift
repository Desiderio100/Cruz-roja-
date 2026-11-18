// Llamadas de la compra con pago (pantalla Productos con causa) al backend: backend/src/rutas/pedidos.js.
// El cliente común (pedir, decodificar, el id del dispositivo) está en Comun/ClienteAPI.swift.

import Foundation

extension ClienteAPI {
    /// GET /api/pedidos/condiciones — pública, sin datos personales.
    func condicionesDeCompra() async throws -> CondicionesDeCompra {
        let datos = try await pedir("GET", "/api/pedidos/condiciones", conDispositivo: false)
        return try decodificar(CondicionesDeCompra.self, datos)
    }

    /// POST /api/pedidos — crea el pedido (pendiente) y el cobro en Stripe.
    /// NO se manda precio ni total: el servidor los calcula desde la base de datos.
    func crearPedido(productoId: Int, cantidad: Int, datos: DatosEnvio) async throws -> Pedido {
        let envio = datos.normalizado
        var cuerpo: [String: Any] = [
            "producto_id": productoId,
            "cantidad": cantidad,
            "nombre": envio.nombre,
            "telefono": envio.telefono,
            "calle_numero": envio.calleNumero,
            "colonia": envio.colonia,
            "ciudad": envio.ciudad,
            "entidad": envio.entidad,
            "codigo_postal": envio.codigoPostal
        ]
        if !envio.referencias.isEmpty { cuerpo["referencias"] = envio.referencias }
        let respuesta = try await pedir("POST", "/api/pedidos", cuerpo: cuerpo)
        return try decodificar(Pedido.self, respuesta)
    }

    /// GET /api/pedidos/:id — solo el dispositivo que creó el pedido lo puede ver.
    func estadoDelPedido(_ pedidoId: String) async throws -> EstadoPedido {
        let datos = try await pedir("GET", "/api/pedidos/\(pedidoId)")
        return try decodificar(EstadoDelPedido.self, datos).estado
    }

    /// POST /api/pedidos/:id/cancelar — responde 204 (sin cuerpo).
    func cancelarPedido(_ pedidoId: String) async throws {
        _ = try await pedir("POST", "/api/pedidos/\(pedidoId)/cancelar")
    }
}
