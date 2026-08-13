import SwiftUI
import DewatermarkCore

enum MainTab: String, CaseIterable {
    case text = "Text"
    case file = "File"
}

struct ContentView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var tab: MainTab = .text
    @State private var showSettings = false
    @State private var pythonStatus: String = "Checking Python…"
    @State private var pythonOK = false
    @State private var ollamaOK: Bool?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(MainTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Group {
                switch tab {
                case .text: TextTabView()
                case .file: FileTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: 12) {
                statusDot(pythonOK ? .green : .red)
                Text(pythonStatus)
                Spacer()
                if let ollamaOK {
                    statusDot(ollamaOK ? .green : .gray)
                    Text(ollamaOK ? "Ollama reachable" : "Ollama offline")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 760, minHeight: 560)
        .toolbar {
            ToolbarItem {
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
                .environmentObject(settings)
        }
        .task { await probeStatus() }
        .onChange(of: settings.pythonPathOverride) { _ in
            Task { await probeStatus() }
        }
        .onChange(of: settings.rewriteBaseURL) { _ in
            Task { await probeOllama() }
        }
    }

    private func statusDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }

    private func probeStatus() async {
        switch PythonDiscovery.findPython(override: settings.pythonPathOverride.isEmpty ? nil : settings.pythonPathOverride) {
        case .success(let path):
            pythonOK = true
            pythonStatus = "Python: \(path)"
        case .failure(let error):
            pythonOK = false
            pythonStatus = error.localizedDescription
        }
        await probeOllama()
    }

    private func probeOllama() async {
        let opts = settings.rewriteOptions
        ollamaOK = await Engine.probeOllama(baseURL: opts.baseURL)
    }
}
