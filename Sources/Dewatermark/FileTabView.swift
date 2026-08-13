import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DewatermarkCore

struct FileTabView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var selectedURL: URL?
    @State private var inspectReport: FileInspectReport?
    @State private var cleanResult: FileCleanResult?
    @State private var errorMessage: String?
    @State private var busy: Action?
    @State private var isDropTargeted = false

    enum Action {
        case inspect, clean
    }

    static let supportedTypes: [UTType] = [
        .png, .jpeg, .svg, .pdf, .html, .plainText, .text, .utf8PlainText,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "odt") ?? .data,
        UTType(filenameExtension: "md") ?? .text,
        UTType(filenameExtension: "markdown") ?? .text,
        UTType(filenameExtension: "txt") ?? .text,
        UTType(filenameExtension: "css") ?? .text,
        UTType(filenameExtension: "js") ?? .text,
        UTType(filenameExtension: "py") ?? .text,
        UTType(filenameExtension: "rs") ?? .text,
        UTType(filenameExtension: "go") ?? .text,
        UTType(filenameExtension: "json") ?? .text,
        UTType(filenameExtension: "yaml") ?? .text,
        UTType(filenameExtension: "yml") ?? .text,
        UTType(filenameExtension: "toml") ?? .text,
        UTType(filenameExtension: "csv") ?? .text,
        .data, // fallback for extension-less sniffing
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            dropZone

            if let selectedURL {
                fileHeader(selectedURL)
            }

            if let inspectReport {
                inspectSection(inspectReport)
            }

            if let cleanResult {
                cleanSection(cleanResult)
            }

            Spacer()
        }
        .padding(16)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Drop a file here")
                    .font(.headline)
                Text("PNG, JPEG, SVG, PDF, DOCX, ODT, HTML, Markdown, or text/code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Choose File…") { chooseFile() }
                    .controlSize(.small)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let url {
                    DispatchQueue.main.async { selectFile(url) }
                }
            }
            return true
        }
    }

    private func fileHeader(_ url: URL) -> some View {
        HStack {
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(url.lastPathComponent).font(.headline)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            actionButton(title: "Inspect", action: .inspect) { await runInspect(url) }
            actionButton(title: "Clean", action: .clean) { await runClean(url) }
            Button("Clear") { clearAll() }
        }
    }

    private func inspectSection(_ report: FileInspectReport) -> some View {
        GroupBox("Inspect report") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    Label(report.kind.capitalized, systemImage: "doc.badge.magnifyingglass")
                    if let format = report.format {
                        Label(format, systemImage: "shippingbox")
                    }
                }
                .font(.callout)

                HStack(spacing: 16) {
                    flag(label: "C2PA", present: report.hasC2PA)
                    flag(label: "AI metadata", present: report.hasAIMetadata)
                    if let total = report.suspiciousTotal {
                        Label("\(total) suspicious chars", systemImage: total == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(total == 0 ? .green : .orange)
                    }
                }
                .font(.callout)

                if let findings = report.findings, !findings.isEmpty {
                    Divider()
                    Text("Findings").font(.caption).bold()
                    ForEach(findings, id: \.self) { f in
                        Text("• \(f)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let hits = report.hits, !hits.isEmpty {
                    Divider()
                    Text("Unicode hits").font(.caption).bold()
                    ForEach(hits) { hit in
                        Text("[\(hit.kind)] \(hit.label) ×\(hit.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cleanSection(_ result: FileCleanResult) -> some View {
        GroupBox("Clean result") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(result.output).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.output)])
                    }
                    .controlSize(.small)
                }

                if let bytesIn = result.bytesIn, let bytesOut = result.bytesOut {
                    Text("\(bytesIn) → \(bytesOut) bytes")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let stats = result.stats {
                    Text("Removed \(stats.removedCount) • Replaced \(stats.replacedCount) • \(stats.inputLength) → \(stats.outputLength) chars")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let actions = result.actions, !actions.isEmpty {
                    Divider()
                    Text("Actions").font(.caption).bold()
                    ForEach(actions, id: \.self) { a in
                        Text("• \(a)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if result.stillHasC2PA == true || result.stillHasAIMetadata == true {
                    Divider()
                    Label("Residual C2PA/AI signals may remain. PDF stripping is best-effort without exiftool; pixel/soft-bound marks are out of scope.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if let post = result.postFindings {
                        ForEach(post, id: \.self) { f in
                            Text("! \(f)").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func flag(label: String, present: Bool?) -> some View {
        let ok = present == false
        return Label(label, systemImage: ok ? "checkmark.circle" : "exclamationmark.triangle")
            .foregroundStyle(ok ? Color.green : Color.orange)
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
        .disabled(busy != nil)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.supportedTypes
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            selectFile(url)
        }
    }

    private func selectFile(_ url: URL) {
        selectedURL = url
        inspectReport = nil
        cleanResult = nil
        Task { await runInspect(url) }
    }

    private func clearAll() {
        selectedURL = nil
        inspectReport = nil
        cleanResult = nil
    }

    private func runInspect(_ url: URL) async {
        busy = .inspect
        defer { busy = nil }
        do {
            let engine = try settings.makeEngine()
            let path = url.path
            let report = try await Task.detached {
                try engine.inspectFile(at: path)
            }.value
            inspectReport = report
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runClean(_ url: URL) async {
        // Default output: <name>.cleaned.<ext> next to the original.
        let ext = url.pathExtension
        let base = url.deletingPathExtension()
        let defaultDest = base.appendingPathExtension("cleaned.\(ext)")

        let panel = NSSavePanel()
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = defaultDest.lastPathComponent
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        busy = .clean
        defer { busy = nil }
        do {
            let engine = try settings.makeEngine()
            let src = url.path
            let destPath = dest.path
            let result = try await Task.detached {
                try engine.cleanFile(at: src, output: destPath)
            }.value
            cleanResult = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
