// HU01 · Configuración inicial: en qué paso va la persona (registro → permisos → app).
// Registro y permisos se muestran solo la primera vez y los dos se pueden omitir:
// la emergencia funciona igual sin cuenta.
//
// El nombre y el teléfono se guardan en Perfil (Comun/Dispositivo.swift, en el Llavero),
// así Emergencia, Citas y Capacitación usan los mismos datos.

import Foundation
import Observation

@MainActor
@Observable
final class SesionUsuario {
    private(set) var registroListo: Bool
    private(set) var permisosListos: Bool
    /// true si el número se verificó por SMS; false si la persona omitió el registro.
    private(set) var telefonoVerificado: Bool

    private static let claveRegistro = "registro.listo"
    private static let clavePermisos = "registro.permisosListos"
    private static let claveVerificado = "registro.telefonoVerificado"

    init() {
        let d = UserDefaults.standard
        registroListo = d.bool(forKey: Self.claveRegistro)
        permisosListos = d.bool(forKey: Self.clavePermisos)
        telefonoVerificado = d.bool(forKey: Self.claveVerificado)
        // El Llavero sobrevive a borrar la app y UserDefaults no: si el registro no está
        // marcado, lo que haya en el Llavero es de una instalación anterior.
        if !registroListo { Perfil.borrar() }
    }

    /// Se llama cuando el código SMS fue correcto.
    func registrar(nombre: String, telefono: String) {
        Perfil.nombre = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        Perfil.telefono = Perfil.limpiarTelefono(telefono)
        telefonoVerificado = true
        UserDefaults.standard.set(true, forKey: Self.claveVerificado)
        marcarRegistro()
    }

    /// "Omitir por ahora": sigue sin cuenta. El dispositivo se registra igual (sin teléfono)
    /// para guardar sus permisos; si el servidor no responde, la app sigue.
    func omitirRegistro() {
        marcarRegistro()
        Task { _ = try? await Dispositivo.compartido.id() }
    }

    func terminarPermisos() {
        permisosListos = true
        UserDefaults.standard.set(true, forKey: Self.clavePermisos)
    }

    /// Desde Mi perfil: volver a la pantalla de registro (por ejemplo, para verificar el número).
    func volverARegistrarme() {
        registroListo = false
        UserDefaults.standard.set(false, forKey: Self.claveRegistro)
    }

    /// Solo para pruebas: borra los datos y vuelve a mostrar la configuración inicial.
    func reiniciar() {
        Perfil.borrar()
        Dispositivo.compartido.olvidar()
        registroListo = false
        permisosListos = false
        telefonoVerificado = false
        for clave in [Self.claveRegistro, Self.clavePermisos, Self.claveVerificado] {
            UserDefaults.standard.removeObject(forKey: clave)
        }
    }

    private func marcarRegistro() {
        registroListo = true
        UserDefaults.standard.set(true, forKey: Self.claveRegistro)
    }
}

/// Validación del registro: una sola regla para la pantalla y el guardado.
enum ReglasRegistro {
    static let caracteresTelefono = CharacterSet(charactersIn: "+0123456789()- ")

    /// Nombre de 2 a 80 letras y teléfono de 10 a 15 dígitos.
    static func datosValidos(nombre: String, telefono: String) -> Bool {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = telefono.trimmingCharacters(in: .whitespacesAndNewlines)
        let digitos = t.unicodeScalars.filter { $0.isASCII && CharacterSet.decimalDigits.contains($0) }.count
        return (2...80).contains(n.count) && (10...15).contains(digitos)
            && t.unicodeScalars.allSatisfy { caracteresTelefono.contains($0) }
    }
}
