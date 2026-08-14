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
        .data,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                dropCard

                if let selectedURL {
                    fileCard(selectedURL)
                }
                if let inspectReport {
                    inspectCard(inspectReport)
                }
                if let cleanResult {
                    cleanCard(cleanResult)
                }
            }
            .padding(24)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Clean a File")
                .font(.largeTitle).bold()
            Text("Remove AI provenance metadata and invisible characters from documents and images.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var dropCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 36))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
            Text("Drop a file here")
                .font(.title3).fontWeight(.medium)
            Text("PDF, Word, Markdown, HTML, SVG, PNG, JPEG, text, code")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                chooseFile()
            } label: {
                Label("Choose File…", systemImage: "folder")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3))
        )
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

    private func fileCard(_ url: URL) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent).font(.headline)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            actionButton(title: "Inspect", icon: "magnifyingglass", action: .inspect) { await runInspect(url) }
            actionButton(title: "Clean", icon: "sparkles", action: .clean) { await runClean(url) }
                .buttonStyle(.borderedProminent)
            Button {
                clearAll()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func inspectCard(_ report: FileInspectReport) -> some View {
        card(title: "What's in the file", icon: "doc.badge.magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 20) {
                    metaChip(report.kind.capitalized, icon: "doc")
                    if let format = report.format {
                        metaChip(format.uppercased(), icon: "shippingbox")
                    }
                }

                HStack(spacing: 20) {
                    flagChip("C2PA provenance", present: report.hasC2PA)
                    flagChip("AI metadata", present: report.hasAIMetadata)
                    if let total = report.suspiciousTotal {
                        flagChip("\(total) invisible chars", present: total > 0 ? true : false)
                    }
                }

                if let findings = report.findings, !findings.isEmpty {
                    Divider()
                    Text("Details").font(.subheadline).bold()
                    ForEach(findings, id: \.self) { f in
                        Text("• \(f)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if let hits = report.hits, !hits.isEmpty {
                    Divider()
                    Text("Invisible characters").font(.subheadline).bold()
                    ForEach(hits) { hit in
                        Text("[\(hit.kind)] \(hit.label) ×\(hit.count)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func cleanCard(_ result: FileCleanResult) -> some View {
        card(title: "Cleaned", icon: "checkmark.circle.fill", tint: .green) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "doc.badge.checkmark")
                        .foregroundStyle(.green)
                    Text(URL(fileURLWithPath: result.output).lastPathComponent)
                        .font(.headline)
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.output)])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .controlSize(.small)
                }
                Text(result.output)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let stats = result.stats {
                    HStack(spacing: 20) {
                        miniStat("\(stats.removedCount)", "removed")
                        miniStat("\(stats.replacedCount)", "replaced")
                        miniStat("\(stats.inputLength) → \(stats.outputLength)", "chars")
                    }
                }

                if let actions = result.actions, !actions.isEmpty {
                    Divider()
                    Text("Actions taken").font(.subheadline).bold()
                    ForEach(actions, id: \.self) { a in
                        Text("• \(a)").font(.callout).foregroundStyle(.secondary)
                    }
                }

                if result.stillHasC2PA == true || result.stillHasAIMetadata == true {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Some provenance signals may remain. Pixel watermarks and C2PA soft-binding are outside what any tool can remove.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func card<Content: View>(title: String, icon: String, tint: Color = .accentColor, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func metaChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }

    private func flagChip(_ label: String, present: Bool?) -> some View {
        let ok = present == false
        return Label(label, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(ok ? Color.green : Color.orange)
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.callout).bold()
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
