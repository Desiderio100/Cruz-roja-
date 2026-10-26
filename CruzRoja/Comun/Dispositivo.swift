//
//  Dispositivo.swift
//  Compartido: identifica a esta instalación de la app ante el servidor.
//
//  Lo usan Registro, Citas y Emergencia, por eso vive en Comun/. El id se pide al backend la
//  primera vez (POST /api/dispositivos, ver Comun/ClienteAPI.registrarDispositivo) y se guarda
//  en el Llavero. Perfil guarda el nombre y teléfono de la persona en el teléfono.
//

import Foundation
import Security

// Guarda y lee textos en el llavero seguro del iPhone.
enum Keychain {
    static func leer(_ cuenta: String) -> String? {
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: cuenta,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var resultado: AnyObject?
        let estado = SecItemCopyMatching(consulta as CFDictionary, &resultado)
        guard estado == errSecSuccess, let datos = resultado as? Data else { return nil }
        return String(data: datos, encoding: .utf8)
    }

    static func guardar(_ valor: String, cuenta: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: cuenta
        ]
        SecItemDelete(base as CFDictionary)
        var nuevo = base
        nuevo[kSecValueData as String] = Data(valor.utf8)
        nuevo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(nuevo as CFDictionary, nil)
    }

    static func borrar(_ cuenta: String) {
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: cuenta
        ]
        SecItemDelete(consulta as CFDictionary)
    }
}

// Id del dispositivo. Se pide a la API la primera vez y se guarda.
@MainActor
final class Dispositivo {
    static let compartido = Dispositivo()

    private let cuenta = "dispositivo_id"
    private var registro: Task<String, Error>?

    func id() async throws -> String {
        if let guardado = Keychain.leer(cuenta) { return guardado }
        if let registro { return try await registro.value }

        let tarea = Task { try await ClienteAPI.compartido.registrarDispositivo() }
        registro = tarea
        do {
            let nuevo = try await tarea.value
            Keychain.guardar(nuevo, cuenta: cuenta)
            registro = nil
            return nuevo
        } catch {
            registro = nil
            throw error
        }
    }

    func olvidar() {
        Keychain.borrar(cuenta)
    }
}

// Nombre y teléfono del usuario, guardados en el Llavero del iPhone (no en texto plano).
// Los llena el registro (Registro/, HU01); si la persona lo omitió, Citas los pide la primera vez.
// Los usan Emergencia (se mandan con la llamada), Citas y Capacitación.
@MainActor
enum Perfil {
    static var nombre: String {
        get { Keychain.leer("perfil_nombre") ?? "" }
        set { Keychain.guardar(newValue, cuenta: "perfil_nombre") }
    }

    static var telefono: String {
        get { Keychain.leer("perfil_telefono") ?? "" }
        set { Keychain.guardar(newValue, cuenta: "perfil_telefono") }
    }

    static func borrar() {
        Keychain.borrar("perfil_nombre")
        Keychain.borrar("perfil_telefono")
    }

    static func telefonoValido(_ texto: String) -> Bool {
        texto.range(of: "^[+]?[0-9]{10,15}$", options: .regularExpression) != nil
    }

    static func limpiarTelefono(_ texto: String) -> String {
        texto.filter { $0.isNumber || $0 == "+" }
    }

    static var completo: Bool {
        let hayNombre = !nombre.trimmingCharacters(in: .whitespaces).isEmpty
        return hayNombre && telefonoValido(telefono)
    }
}
