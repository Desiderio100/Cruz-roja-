//
//  PagoStripe.swift
//  Ventas
//
//  ÚNICO archivo que conoce el SDK de Stripe. Abre la hoja de pago de Stripe (PaymentSheet),
//  donde la persona escribe su tarjeta. La tarjeta la captura Stripe: no pasa por esta app
//  ni por nuestro servidor.
//
//  Está protegido con `#if canImport(StripePaymentSheet)`: mientras el paquete de Stripe NO esté
//  agregado al proyecto, la app compila igual y la compra avisa que los pagos no están activos
//  (y deja reintentar). Para activarlo, sigue PAGOS_STRIPE.md (paso "Agregar el paquete
//  de Stripe a Xcode").
//

import SwiftUI
import UIKit
#if canImport(StripePaymentSheet)
import StripePaymentSheet
#endif

enum PagoStripe {
    /// true cuando el paquete de Stripe ya está agregado al proyecto.
    static var disponible: Bool {
        #if canImport(StripePaymentSheet)
        return true
        #else
        return false
        #endif
    }

    /// Esquema propio de la app (está en CruzRoja-Info.plist › CFBundleURLTypes). Stripe lo usa para
    /// regresar a la app si el banco pide confirmar el pago en Safari o en su propia app.
    static let esquemaDeRetorno = "cruzroja"
    static var urlDeRetorno: String { "\(esquemaDeRetorno)://stripe-redirect" }

    /// Lo llama CruzRojaApp con `.onOpenURL`. Devuelve true si el enlace era de Stripe.
    @discardableResult
    static func manejar(url: URL) -> Bool {
        #if canImport(StripePaymentSheet)
        return StripeAPI.handleURLCallback(with: url)
        #else
        return false
        #endif
    }

    #if canImport(StripePaymentSheet)
    /// Se guarda mientras la hoja está abierta (si no, iOS la libera y se cierra sola).
    @MainActor private static var hojaAbierta: PaymentSheet?
    #endif

    /// Abre la hoja de pago de Stripe para este pedido y avisa cómo terminó.
    @MainActor
    static func presentar(_ pedido: Pedido, alTerminar: @escaping (ResultadoDePago) -> Void) {
        #if canImport(StripePaymentSheet)
        guard let pantalla = controladorSuperior() else {
            alTerminar(.fallido("No pudimos abrir la hoja de pago. Intenta de nuevo."))
            return
        }

        // La llave PUBLICABLE (pk_...) viene del servidor junto con el pedido: así no vive en la app
        // y se puede cambiar de prueba a real sin publicar una versión nueva.
        STPAPIClient.shared.publishableKey = pedido.publishableKey

        var configuracion = PaymentSheet.Configuration()
        configuracion.merchantDisplayName = "Cruz Roja Mexicana"
        configuracion.returnURL = urlDeRetorno
        // Solo tarjeta: los métodos que confirman días después (transferencias) no se activan.
        configuracion.allowsDelayedPaymentMethods = false

        let hoja = PaymentSheet(paymentIntentClientSecret: pedido.clientSecret, configuration: configuracion)
        hojaAbierta = hoja
        hoja.present(from: pantalla) { resultado in
            let traducido: ResultadoDePago
            switch resultado {
            case .completed:
                traducido = .completado
            case .canceled:
                traducido = .cancelado
            case .failed:
                // El detalle técnico de Stripe no se le muestra a la persona.
                traducido = .fallido("No se pudo completar el pago. Revisa tu tarjeta o prueba con otra.")
            }
            Task { @MainActor in
                hojaAbierta = nil
                alTerminar(traducido)
            }
        }
        #else
        alTerminar(.fallido("Los pagos con tarjeta todavía no están activados en esta versión de la app."))
        #endif
    }

    #if canImport(StripePaymentSheet)
    /// La pantalla que está hasta arriba ahora mismo (la hoja de compra), para presentar encima.
    @MainActor
    private static func controladorSuperior() -> UIViewController? {
        let ventana = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var actual = ventana?.rootViewController
        while let encima = actual?.presentedViewController {
            actual = encima
        }
        return actual
    }
    #endif
}
