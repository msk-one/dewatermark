import Foundation

/// App-wide settings persisted in UserDefaults.
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private enum Keys {
        static let pythonPathOverride = "pythonPathOverride"
        static let rewriteBackend = "rewriteBackend"
        static let rewriteModel = "rewriteModel"
        static let rewriteBaseURL = "rewriteBaseURL"
        static let rewriteAPIKey = "rewriteAPIKey"
        static let rewriteStrength = "rewriteStrength"
        static let rewriteCandidates = "rewriteCandidates"
        static let rewriteTemperature = "rewriteTemperature"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.pythonPathOverride = defaults.string(forKey: Keys.pythonPathOverride) ?? ""
        self.rewriteBackendRaw = defaults.string(forKey: Keys.rewriteBackend) ?? RewriteBackend.ollama.rawValue
        self.rewriteModel = defaults.string(forKey: Keys.rewriteModel) ?? "llama3.2"
        self.rewriteBaseURL = defaults.string(forKey: Keys.rewriteBaseURL) ?? "http://127.0.0.1:11434"
        self.rewriteAPIKey = defaults.string(forKey: Keys.rewriteAPIKey) ?? ""
        self.rewriteStrengthRaw = defaults.string(forKey: Keys.rewriteStrength) ?? RewriteStrength.paraphrase.rawValue
        self.rewriteCandidates = max(1, defaults.integer(forKey: Keys.rewriteCandidates))
        self.rewriteTemperature = defaults.object(forKey: Keys.rewriteTemperature) as? Double ?? 0.9
    }

    @Published public var pythonPathOverride: String {
        didSet { defaults.set(pythonPathOverride, forKey: Keys.pythonPathOverride) }
    }
    @Published public var rewriteBackendRaw: String {
        didSet { defaults.set(rewriteBackendRaw, forKey: Keys.rewriteBackend) }
    }
    @Published public var rewriteModel: String {
        didSet { defaults.set(rewriteModel, forKey: Keys.rewriteModel) }
    }
    @Published public var rewriteBaseURL: String {
        didSet { defaults.set(rewriteBaseURL, forKey: Keys.rewriteBaseURL) }
    }
    @Published public var rewriteAPIKey: String {
        didSet { defaults.set(rewriteAPIKey, forKey: Keys.rewriteAPIKey) }
    }
    @Published public var rewriteStrengthRaw: String {
        didSet { defaults.set(rewriteStrengthRaw, forKey: Keys.rewriteStrength) }
    }
    @Published public var rewriteCandidates: Int {
        didSet { defaults.set(rewriteCandidates, forKey: Keys.rewriteCandidates) }
    }
    @Published public var rewriteTemperature: Double {
        didSet { defaults.set(rewriteTemperature, forKey: Keys.rewriteTemperature) }
    }

    public var rewriteOptions: RewriteOptions {
        var opts = RewriteOptions()
        opts.backend = RewriteBackend(rawValue: rewriteBackendRaw) ?? .ollama
        opts.strength = RewriteStrength(rawValue: rewriteStrengthRaw) ?? .paraphrase
        opts.model = rewriteModel
        opts.baseURL = rewriteBaseURL
        opts.apiKey = rewriteAPIKey.isEmpty ? nil : rewriteAPIKey
        opts.candidates = rewriteCandidates
        opts.temperature = rewriteTemperature
        return opts
    }

    /// Build an Engine honoring the python path override, if set.
    public func makeEngine() throws -> Engine {
        try Engine(pythonOverride: pythonPathOverride.isEmpty ? nil : pythonPathOverride)
    }
}
