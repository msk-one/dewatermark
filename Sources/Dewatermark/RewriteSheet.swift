import SwiftUI
import DewatermarkCore

struct RewriteSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let text: String
    let onResult: (RewriteResult) -> Void

    @State private var running = false
    @State private var errorMessage: String?
    @State private var previewPrompt = ""
    @State private var showPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Layer B — statistical rewrite")
                .font(.title2).bold()
            Text("Best-effort reduction of token-sampling watermarks via an LLM rewrite. Cannot certify vendor detectors will fail. Rewritten output is scrubbed with Layer A afterwards.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Picker("Backend", selection: $settings.rewriteBackendRaw) {
                    ForEach(RewriteBackend.allCases, id: \.rawValue) { b in
                        Text(b.displayName).tag(b.rawValue)
                    }
                }
                Picker("Strength", selection: $settings.rewriteStrengthRaw) {
                    ForEach(RewriteStrength.allCases, id: \.rawValue) { s in
                        Text(s.displayName).tag(s.rawValue)
                    }
                }
                if backend != .printPrompt {
                    TextField("Model", text: $settings.rewriteModel)
                    TextField("Base URL", text: $settings.rewriteBaseURL)
                    if backend == .openAICompatible {
                        SecureField("API key (optional)", text: $settings.rewriteAPIKey)
                    }
                    Stepper("Candidates: \(settings.rewriteCandidates)", value: $settings.rewriteCandidates, in: 1...5)
                    HStack {
                        Text("Temperature")
                        Slider(value: $settings.rewriteTemperature, in: 0...1.5)
                        Text(String(format: "%.1f", settings.rewriteTemperature))
                            .monospacedDigit()
                    }
                }
            }
            .formStyle(.grouped)

            if options.isRemote && backend != .printPrompt {
                Label("Base URL is not localhost — your text will leave this machine.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if showPrompt {
                GroupBox("Prompt preview (print-prompt)") {
                    ScrollView {
                        Text(previewPrompt)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)
                }
            }

            HStack {
                if backend == .printPrompt {
                    Button("Preview prompt") { Task { await preview() } }
                        .disabled(running || text.isEmpty)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await run() }
                } label: {
                    if running {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(backend == .printPrompt ? "Generate" : "Rewrite")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(running || text.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .alert("Rewrite failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var backend: RewriteBackend {
        RewriteBackend(rawValue: settings.rewriteBackendRaw) ?? .ollama
    }

    private var options: RewriteOptions {
        settings.rewriteOptions
    }

    private func preview() async {
        do {
            let engine = try settings.makeEngine()
            var mutableOpts = options
            mutableOpts.backend = .printPrompt
            let opts = mutableOpts
            let result = try await Task.detached {
                try engine.rewrite(text, options: opts)
            }.value
            previewPrompt = result.text
            showPrompt = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run() async {
        running = true
        defer { running = false }
        do {
            let engine = try settings.makeEngine()
            let opts = options
            let input = text
            let result = try await Task.detached {
                try engine.rewrite(input, options: opts)
            }.value
            onResult(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
