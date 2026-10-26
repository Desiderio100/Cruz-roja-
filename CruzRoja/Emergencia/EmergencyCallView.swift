// Responsable del módulo de emergencia: Ayhan Ben Halima Martinez · A01647593
import SwiftUI

struct EmergencyCallView: View {
    let session: EmergencySession
    let endCall: () -> Void

    @State private var elapsedSeconds = 0
    @State private var isMuted = false
    @State private var usesSpeaker = true
    @State private var isVideoRequestPresented = false
    @State private var hasPresentedVideoRequest = false
    @State private var isVideoActive = false
    @State private var camara = CamaraLlamada()
    @State private var camaraNegada = false
    @Environment(\.openURL) private var abrirURL

    var body: some View {
        ZStack {
            if isVideoActive {
                // Lo que está captando la cámara, a pantalla completa.
                VistaCamara(sesion: camara.sesion)
                    .ignoresSafeArea()
                // Oscurece arriba y abajo para que se lean el texto y los botones.
                LinearGradient(
                    colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                callBackground
            }

            VStack(spacing: 0) {
                statusHeader
                Spacer()

                if isVideoActive {
                    videoStatus
                        .padding(.bottom, 24)
                }

                callControls
                    .padding(.bottom, 38)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                elapsedSeconds += 1

                if elapsedSeconds == 3 && !hasPresentedVideoRequest {
                    hasPresentedVideoRequest = true
                    isVideoRequestPresented = true
                }
            }
        }
        .alert("El operador solicita ver tu cámara", isPresented: $isVideoRequestPresented) {
            Button("Rechazar", role: .cancel) { }
            Button("Aceptar") {
                Task { await encenderVideo() }
            }
        } message: {
            Text("El video es unidireccional: solo el operador podrá ver tu cámara.")
        }
        .alert("No se puede usar la cámara", isPresented: $camaraNegada) {
            Button("Abrir Configuración") {
                if let url = URL(string: UIApplication.openSettingsURLString) { abrirURL(url) }
            }
            Button("Ahora no", role: .cancel) { }
        } message: {
            Text("Permite el acceso a la cámara en Configuración para enviar video al operador.")
        }
        .onDisappear { camara.apagar() }
    }

    @MainActor
    private func encenderVideo() async {
        guard await camara.encender() else {
            camaraNegada = true
            return
        }
        withAnimation { isVideoActive = true }
        try? await EmergencyAPI.shared.updateCall(id: session.id, videoAccepted: true)
    }

    private func apagarVideo() {
        camara.apagar()
        withAnimation { isVideoActive = false }
        Task {
            try? await EmergencyAPI.shared.updateCall(id: session.id, videoAccepted: false)
        }
    }

    private var callBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.16, blue: 0.19), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.rojoCruzRoja.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 60)
                .offset(y: -250)
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 12) {
            // Con video se quita la cruz para que se vea más de la cámara.
            if !isVideoActive {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                    Image(systemName: "cross.fill")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.rojoCruzRoja)
                }
                .accessibilityHidden(true)
            }

            Text("Cruz Roja Mexicana")
                .font(.title2.bold())
            Text(session.delegation.name)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.72))
            Text(formattedDuration)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))

            Label("GPS, nombre y número enviados", systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.9, blue: 0.58))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.1), in: Capsule())
                .padding(.top, 4)
        }
        .padding(.top, 28)
    }

    private var videoStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: "video.fill")
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.rojoCruzRoja, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Video activo")
                    .font(.headline)
                Text("Solo el operador puede verte")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
            }
            Spacer()
            Button("Cambiar cámara", systemImage: "arrow.triangle.2.circlepath.camera.fill") {
                camara.voltear()
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            Button("Detener", action: apagarVideo)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var callControls: some View {
        HStack(alignment: .top) {
            CallControl(
                title: isMuted ? "Activar audio" : "Silenciar",
                icon: isMuted ? "mic.fill" : "mic.slash.fill",
                isActive: isMuted
            ) {
                isMuted.toggle()
            }

            Spacer()

            CallControl(
                title: "Bocina",
                icon: usesSpeaker ? "speaker.wave.3.fill" : "speaker.fill",
                isActive: usesSpeaker
            ) {
                usesSpeaker.toggle()
            }

            Spacer()

            CallControl(title: "Colgar", icon: "phone.down.fill", color: .rojoCruzRoja) {
                Task {
                    try? await EmergencyAPI.shared.updateCall(
                        id: session.id,
                        status: "finalizada"
                    )
                    await MainActor.run {
                        endCall()
                    }
                }
            }
        }
    }

    private var formattedDuration: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct CallControl: View {
    let title: LocalizedStringKey
    let icon: String
    var color: Color = .white.opacity(0.16)
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 66, height: 66)
                    .background(isActive ? Color.white : color, in: Circle())
                    .foregroundStyle(isActive ? Color.black : Color.white)

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 82)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    EmergencyCallView(
        session: EmergencySession(
            id: UUID(),
            status: "en_curso",
            delegation: Delegation(
                id: 2,
                name: "Cruz Roja Monterrey",
                phone: "+528100000002"
            )
        )
    ) { }
}
