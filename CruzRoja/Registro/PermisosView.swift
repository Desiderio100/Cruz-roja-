// HU01 · "Permisos": ubicación, micrófono, cámara y notificaciones.
// "Continuar" pide los que falten; "Omitir por ahora" entra sin pedir nada.
// Todos son opcionales y se pueden cambiar después en Mi perfil o en Ajustes del iPhone.
//Tonchez

import SwiftUI

struct PermisosView: View {
    @Environment(SesionUsuario.self) private var sesion
    @Environment(GestorPermisos.self) private var permisos

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Para brindarte ayuda más rápida y efectiva.")
                        .foregroundStyle(.secondary)

                    ListaPermisos()

                    Button {
                        Task {
                            await permisos.solicitarPendientes()
                            sesion.terminarPermisos()
                        }
                    } label: {
                        if permisos.solicitando { ProgressView().tint(.white) } else { Text("Continuar") }
                    }
                    .buttonStyle(BotonRojo())
                    .disabled(permisos.solicitando)
                    .padding(.top, 8)

                    Button("Omitir por ahora") { sesion.terminarPermisos() }
                        .buttonStyle(BotonTexto())
                        .disabled(permisos.solicitando)

                    Text("Todos los permisos son opcionales. Puedes cambiarlos después desde Ajustes del iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Medida.margen)
                .padding(.bottom, 24)
            }
            .pantalla("Permisos")
        }
    }
}

/// Lista de permisos con su botón (Solicitar / Permitido / Abrir Ajustes).
/// La usan PermisosView y Mi perfil.
struct ListaPermisos: View {
    @Environment(GestorPermisos.self) private var permisos
    @Environment(\.scenePhase) private var fase
    @Environment(\.openURL) private var abrirURL

    var body: some View {
        VStack(spacing: 0) {
            ForEach(TipoPermiso.allCases) { tipo in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tipo.icono)
                        .foregroundStyle(Color.rojoCruzRoja)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tipo.nombre)
                            .font(.headline)
                        Text(tipo.detalle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(titulo(tipo)) {
                        // Un permiso negado solo se puede cambiar desde Ajustes del iPhone.
                        if permisos.estado(tipo) == .denegado {
                            abrirURL(URL(string: UIApplication.openSettingsURLString)!)
                        } else {
                            permisos.solicitar(tipo)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(permisos.estado(tipo) == .permitido ? Color.secondary : Color.rojoCruzRoja)
                    .disabled(permisos.estado(tipo) == .permitido || permisos.solicitando)
                }
                .padding(.vertical, 14)
                if tipo != TipoPermiso.allCases.last { Divider() }
            }
        }
        .onAppear { permisos.actualizar() }
        .onChange(of: fase) { _, nueva in
            if nueva == .active { permisos.actualizar() }
        }
        .alert("Configuración de permisos", isPresented: hayError) {
            Button("Entendido", role: .cancel) { }
        } message: {
            Text(permisos.mensajeError ?? "")
        }
    }

    private var hayError: Binding<Bool> {
        Binding(get: { permisos.mensajeError != nil }, set: { if !$0 { permisos.mensajeError = nil } })
    }

    private func titulo(_ tipo: TipoPermiso) -> String {
        switch permisos.estado(tipo) {
        case .solicitar: "Solicitar"
        case .permitido: "Permitido"
        case .denegado: "Abrir Ajustes"
        }
    }
}

#Preview {
    PermisosView()
        .environment(SesionUsuario())
        .environment(GestorPermisos())
}
