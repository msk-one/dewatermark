import SwiftUI
import AppKit
import DewatermarkCore

struct TextTabView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var input = ""
    @State private var output = ""
    @State private var nfkc = false
    @State private var aggressive = false
    @State private var normalizeSpaces = true

    @State private var inspectReport: TextInspectReport?
    @State private var stats: CleanStats?
    @State private var actionLog = ""
    @State private var errorMessage: String?
    @State private var busy: Action?
    @State private var showRewrite = false

    enum Action {
        case inspect, clean, rewrite
    }

    var body: some View {
        HSplitView {
            inputPane
                .frame(minWidth: 320)
            outputPane
                .frame(minWidth: 320)
        }
        .padding(12)
        .sheet(isPresented: $showRewrite) {
            RewriteSheet(text: input) { result in
                output = result.text
                actionLog = result.log
                showRewrite = false
            }
            .environmentObject(settings)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input").font(.headline)
                Spacer()
                Button("Paste") {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        input = s
                    }
                }
                .help("Paste from clipboard")
                Button("Clear") { input = ""; clearResults() }
                    .disabled(input.isEmpty)
            }

            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .border(.quaternary)

            DisclosureGroup("Layer A options") {
                Toggle("NFKC normalize", isOn: $nfkc)
                Toggle("Aggressive homoglyphs (Cyrillic/fullwidth → ASCII)", isOn: $aggressive)
                Toggle("Normalize exotic spaces", isOn: $normalizeSpaces)
            }
            .font(.caption)

            HStack {
                actionButton(title: "Inspect", action: .inspect) { await runInspect() }
                actionButton(title: "Clean", action: .clean) { await runClean() }
                Button("Rewrite (Layer B)…") { showRewrite = true }
                    .disabled(input.isEmpty || busy != nil)
                    .help("Statistical watermark reduction via LLM rewrite (best-effort)")
            }

            if let inspectReport {
                ReportView(report: inspectReport)
            }
        }
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output").font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output, forType: .string)
                }
                .disabled(output.isEmpty)
                Button("Save As…") { saveOutput() }
                    .disabled(output.isEmpty)
            }

            TextEditor(text: .constant(output.isEmpty ? "" : output))
                .font(.system(.body, design: .monospaced))
                .border(.quaternary)

            if let stats {
                GroupBox("Stats") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Removed \(stats.removedCount) • Replaced \(stats.replacedCount) • \(stats.inputLength) → \(stats.outputLength) chars")
                            .font(.callout)
                        if !stats.removed.isEmpty {
                            Text("Removed:").font(.caption).bold()
                            ForEach(stats.removed.sorted(by: { $0.value > $1.value }), id: \.key) { k, v in
                                Text("  \(k) ×\(v)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !stats.replaced.isEmpty {
                            Text("Replaced:").font(.caption).bold()
                            ForEach(stats.replaced.sorted(by: { $0.value > $1.value }), id: \.key) { k, v in
                                Text("  \(k) ×\(v)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !actionLog.isEmpty {
                GroupBox("Log") {
                    ScrollView {
                        Text(actionLog)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
    }

    private func actionButton(title: String, action: Action, run: @escaping () async -> Void) -> some View {
        Button {
            Task { await run() }
        } label: {
            if busy == action {
                ProgressView().controlSize(.small)
            } else {
                Text(title)
            }
        }
        .disabled(input.isEmpty || busy != nil)
    }

    private func runInspect() async {
        busy = .inspect
        defer { busy = nil }
        do {
            let engine = try settings.makeEngine()
            let inputText = input
            let aggressiveFlag = aggressive
            let report = try await Task.detached {
                try engine.inspectText(inputText, aggressive: aggressiveFlag)
            }.value
            inspectReport = report
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runClean() async {
        busy = .clean
        defer { busy = nil }
        do {
            let engine = try settings.makeEngine()
            var opts = CleanTextOptions()
            opts.nfkc = nfkc
            opts.aggressiveHomoglyphs = aggressive
            opts.normalizeSpaces = normalizeSpaces
            let inputText = input
            let result = try await Task.detached {
                try engine.cleanText(inputText, options: opts)
            }.value
            output = result.text
            stats = result.stats
            actionLog = result.log
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "cleaned.txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? output.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func clearResults() {
        output = ""
        inspectReport = nil
        stats = nil
        actionLog = ""
    }
}
