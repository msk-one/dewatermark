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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                inputCard
                actionRow
                if let inspectReport {
                    ReportView(report: inspectReport)
                }
                if !output.isEmpty {
                    outputCard
                }
                if !actionLog.isEmpty {
                    logCard
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showRewrite) {
            RewriteSheet(text: input) { result in
                output = result.text
                actionLog = result.log
                showRewrite = false
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Clean Text")
                .font(.largeTitle).bold()
            Text("Paste text from an LLM. Strip invisible characters, or reduce statistical watermarks with a rewrite.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Input", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                Button {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        input = s
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .controlSize(.small)
                Button {
                    input = ""; clearResults()
                } label: {
                    Label("Clear", systemImage: "xmark")
                }
                .controlSize(.small)
                .disabled(input.isEmpty)
            }

            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 260)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            DisclosureGroup("Options") {
                Toggle("Normalize Unicode (NFKC)", isOn: $nfkc)
                Toggle("Replace look-alike letters (Cyrillic/fullwidth → ASCII)", isOn: $aggressive)
                Toggle("Normalize unusual spaces", isOn: $normalizeSpaces)
            }
            .font(.callout)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            actionButton(title: "Inspect", icon: "magnifyingglass", action: .inspect) { await runInspect() }
                .help("Look for invisible characters (Layer A)")
            actionButton(title: "Clean", icon: "sparkles", action: .clean) { await runClean() }
                .help("Strip invisible characters (Layer A)")

            Spacer()

            Button {
                showRewrite = true
            } label: {
                Label("Rewrite Text", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(input.isEmpty || busy != nil)
            .help("Reduce statistical word-choice watermarks (Layer B, best-effort)")
        }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Output", systemImage: "checkmark.circle")
                    .font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                Button("Save As…") { saveOutput() }
                    .controlSize(.small)
            }

            TextEditor(text: .constant(output))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )

            if let stats {
                HStack(spacing: 20) {
                    statPill("\(stats.removedCount)", "removed", .orange)
                    statPill("\(stats.replacedCount)", "replaced", .blue)
                    statPill("\(stats.inputLength) → \(stats.outputLength)", "chars", .secondary)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Details", systemImage: "terminal")
                .font(.headline)
            ScrollView {
                Text(actionLog)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statPill(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).bold().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func actionButton(title: String, icon: String, action: Action, run: @escaping () async -> Void) -> some View {
        Button {
            Task { await run() }
        } label: {
            if busy == action {
                ProgressView().controlSize(.small)
            } else {
                Label(title, systemImage: icon)
            }
        }
        .controlSize(.large)
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
            var mutableOpts = CleanTextOptions()
            mutableOpts.nfkc = nfkc
            mutableOpts.aggressiveHomoglyphs = aggressive
            mutableOpts.normalizeSpaces = normalizeSpaces
            let opts = mutableOpts
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
