// HU01 · Llamadas del registro y los permisos al backend:
//   POST /api/registro/codigo      manda el código de 6 dígitos por SMS   (backend/src/rutas/registro.js)
//   POST /api/registro/verificar   revisa el código y guarda el teléfono verificado en este dispositivo
//   POST /api/consentimientos      guarda que se aceptó o negó un permiso (backend/src/rutas/consentimientos.js)
//
// En desarrollo el backend NO manda SMS: el código sale en la terminal donde corre `npm run dev`.
//Tonchez

import Foundation

extension ClienteAPI {
    func enviarCodigo(telefono: String) async throws {
        _ = try await pedir("POST", "/api/registro/codigo",
                            cuerpo: ["telefono": Perfil.limpiarTelefono(telefono)],
                            conDispositivo: false)
    }

    func verificarCodigo(telefono: String, codigo: String) async throws {
        _ = try await pedir("POST", "/api/registro/verificar",
                            cuerpo: ["telefono": Perfil.limpiarTelefono(telefono), "codigo": codigo])
    }

    func guardarConsentimiento(permiso: String, aceptado: Bool) async throws {
        _ = try await pedir("POST", "/api/consentimientos",
                            cuerpo: ["permiso": permiso, "aceptado": aceptado])
    }
}
