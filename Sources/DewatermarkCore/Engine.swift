import Foundation

public enum EngineError: Error, LocalizedError {
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .decodingFailed(let detail):
            return "Failed to decode engine JSON output: \(detail)"
        }
    }
}

public struct TextCleanResult: Sendable {
    public let text: String
    public let stats: CleanStats?
    public let log: String
}

public struct RewriteResult: Sendable {
    public let text: String
    public let info: RewriteInfo?
    public let log: String
}

public enum RewriteBackend: String, CaseIterable, Sendable {
    case printPrompt = "print-prompt"
    case ollama
    case openAICompatible = "openai-compatible"

    public var displayName: String {
        switch self {
        case .printPrompt: return "Print prompt only (no model)"
        case .ollama: return "Ollama (local)"
        case .openAICompatible: return "OpenAI-compatible endpoint"
        }
    }
}

public enum RewriteStrength: String, CaseIterable, Sendable {
    case paraphrase, humanize, code, backtranslate, structural

    public var displayName: String { rawValue.capitalized }
}

public struct RewriteOptions: Sendable {
    public var backend: RewriteBackend = .ollama
    public var strength: RewriteStrength = .paraphrase
    public var model: String = "llama3.2"
    public var baseURL: String = "http://127.0.0.1:11434"
    public var apiKey: String?
    public var candidates: Int = 1
    public var temperature: Double = 0.9
    public var timeout: TimeInterval = 120

    public init() {}

    /// True when the base URL points off-machine (content leaves the device).
    public var isRemote: Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return !(host == "localhost" || host == "127.0.0.1" || host == "::1")
    }
}

public struct CleanTextOptions: Sendable {
    public var nfkc: Bool = false
    public var aggressiveHomoglyphs: Bool = false
    public var normalizeSpaces: Bool = true

    public init() {}
}

/// High-level API over the vendored watermarks-remover scripts.
public final class Engine: @unchecked Sendable {
    private let bridge: PythonBridge

    public init(bridge: PythonBridge) {
        self.bridge = bridge
    }

    public convenience init(pythonOverride: String? = nil, engineDirOverride: URL? = nil) throws {
        let python: String
        switch PythonDiscovery.findPython(override: pythonOverride) {
        case .success(let path): python = path
        case .failure(let error): throw error
        }
        let engineDir = engineDirOverride ?? Engine.defaultEngineDir()
        self.init(bridge: try PythonBridge(pythonPath: python, engineDir: engineDir))
    }

    /// Engine location: DEWATERMARK_ENGINE_DIR env (dev/tests) → app bundle Resources → repo-relative dev path.
    public static func defaultEngineDir() -> URL {
        if let env = ProcessInfo.processInfo.environment["DEWATERMARK_ENGINE_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Engine"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("clean_text.py").path) {
            return bundled
        }
        // Dev fallback: <package-root>/Engine/watermarks-remover, resolved from this source file.
        let sourceFile = URL(fileURLWithPath: #filePath)
        return sourceFile
            .deletingLastPathComponent() // DewatermarkCore
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Engine/watermarks-remover")
    }

    // MARK: - Text Layer A

    public func inspectText(_ text: String, aggressive: Bool = false) throws -> TextInspectReport {
        var args = ["-", "--json"]
        if aggressive { args.append("--aggressive") }
        let result = try bridge.run(script: "inspect_text.py", args: args, stdin: text,
                                    acceptableExitCodes: [0, 1])
        return try decode(TextInspectReport.self, from: result.stdout)
    }

    public func cleanText(_ text: String, options: CleanTextOptions = .init()) throws -> TextCleanResult {
        var args = ["-", "-o", "-", "--stats"]
        if options.nfkc { args.append("--nfkc") }
        if options.aggressiveHomoglyphs { args.append("--aggressive-homoglyphs") }
        if !options.normalizeSpaces { args.append("--no-normalize-spaces") }
        let result = try bridge.run(script: "clean_text.py", args: args, stdin: text)
        let stats = try? decode(CleanStats.self, from: Data(result.stderr.utf8))
        return TextCleanResult(text: result.stdoutText, stats: stats, log: result.stderr)
    }

    // MARK: - Files

    public func inspectFile(at path: String, aggressive: Bool = false) throws -> FileInspectReport {
        var args = [path, "--json"]
        if aggressive { args.append("--aggressive") }
        let result = try bridge.run(script: "inspect_file.py", args: args,
                                    acceptableExitCodes: [0, 1])
        return try decode(FileInspectReport.self, from: result.stdout)
    }

    public func cleanFile(at path: String, output: String? = nil) throws -> FileCleanResult {
        var args = [path, "--json"]
        if let output { args += ["-o", output] }
        // Exit code 1 = residual findings may remain; still a usable result payload.
        let result = try bridge.run(script: "clean_file.py", args: args,
                                    acceptableExitCodes: [0, 1])
        return try decode(FileCleanResult.self, from: result.stdout)
    }

    // MARK: - Layer B rewrite

    public func rewrite(_ text: String, options: RewriteOptions) throws -> RewriteResult {
        var args = ["-", "-o", "-",
                    "--backend", options.backend.rawValue,
                    "--strength", options.strength.rawValue,
                    "--json-stats"]
        if options.backend != .printPrompt {
            args += ["--model", options.model,
                     "--base-url", options.baseURL,
                     "--timeout", String(Int(options.timeout)),
                     "--temperature", String(options.temperature),
                     "--candidates", String(options.candidates)]
            if let key = options.apiKey, !key.isEmpty {
                args += ["--api-key", key]
            }
        }
        // print-prompt is instant; model backends get the configured timeout plus slack.
        let timeout = options.backend == .printPrompt ? 15 : options.timeout * Double(max(1, options.candidates)) + 30
        let result = try bridge.run(script: "rewrite_text.py", args: args, stdin: text, timeout: timeout)
        let info = try? decode(RewriteInfo.self, from: Data(result.stderr.utf8))
        return RewriteResult(text: result.stdoutText, info: info, log: result.stderr)
    }

    // MARK: - Probes

    /// Best-effort check that an Ollama server answers at the given base URL.
    public static func probeOllama(baseURL: String, timeout: TimeInterval = 2) async -> Bool {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/version") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let snippet = String(decoding: data.prefix(400), as: UTF8.self)
            throw EngineError.decodingFailed("\(error.localizedDescription) — raw: \(snippet)")
        }
    }
}
