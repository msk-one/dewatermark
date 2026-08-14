import SwiftUI
import DewatermarkCore

enum MainTab: String, CaseIterable, Identifiable {
    case text = "Text"
    case file = "File"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .text: return "text.alignleft"
        case .file: return "doc"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var tab: MainTab = .text
    @State private var showSettings = false
    @State private var pythonStatus: String = "Checking…"
    @State private var pythonOK = false
    @State private var ollamaOK: Bool?

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $tab) {
                    ForEach(MainTab.allCases) { t in
                        Label(t.rawValue, systemImage: t.icon)
                            .tag(t)
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 210)
            } detail: {
                Group {
                    switch tab {
                    case .text: TextTabView()
                    case .file: FileTabView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(tab.rawValue)
            }
            .navigationSplitViewStyle(.balanced)

            statusBar
        }
        .frame(minWidth: 900, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task { await probeStatus() }
        .onChange(of: settings.pythonPathOverride) { _ in
            Task { await probeStatus() }
        }
        .onChange(of: settings.rewriteBaseURL) { _ in
            Task { await probeOllama() }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            statusItem(ok: pythonOK, label: "Python")
                .help(pythonStatus)
            if let ollamaOK {
                statusItem(ok: ollamaOK, label: "Ollama")
                    .help(ollamaOK ? "Reachable" : "Not running")
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func statusItem(ok: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption).fontWeight(.medium)
        }
    }

    private func probeStatus() async {
        switch PythonDiscovery.findPython(override: settings.pythonPathOverride.isEmpty ? nil : settings.pythonPathOverride) {
        case .success(let path):
            pythonOK = true
            pythonStatus = URL(fileURLWithPath: path).lastPathComponent + " found"
        case .failure:
            pythonOK = false
            pythonStatus = "Not found"
        }
        await probeOllama()
    }

    private func probeOllama() async {
        let opts = settings.rewriteOptions
        ollamaOK = await Engine.probeOllama(baseURL: opts.baseURL)
    }
}
