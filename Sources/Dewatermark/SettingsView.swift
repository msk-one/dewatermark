import SwiftUI
import DewatermarkCore

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var pythonProbe: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.title2).bold()

            Form {
                Section("Engine") {
                    TextField("Python path (blank = auto-detect)", text: $settings.pythonPathOverride)
                    Button("Test Python") { probePython() }
                    if let pythonProbe {
                        Text(pythonProbe)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Requires Python 3.10+ (stdlib only). Optional system tools: exiftool (better PDF strip), c2patool (C2PA inspection).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Layer B defaults") {
                    Picker("Backend", selection: $settings.rewriteBackendRaw) {
                        ForEach(RewriteBackend.allCases, id: \.rawValue) { b in
                            Text(b.displayName).tag(b.rawValue)
                        }
                    }
                    TextField("Model", text: $settings.rewriteModel)
                    TextField("Base URL", text: $settings.rewriteBaseURL)
                    SecureField("API key (optional)", text: $settings.rewriteAPIKey)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func probePython() {
        let override = settings.pythonPathOverride
        switch PythonDiscovery.findPython(override: override.isEmpty ? nil : override) {
        case .success(let path):
            pythonProbe = "OK: \(path)"
        case .failure(let error):
            pythonProbe = error.localizedDescription
        }
    }
}
