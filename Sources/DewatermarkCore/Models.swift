import Foundation

// MARK: - Text inspect (inspect_text.py --json)

public struct TextHit: Codable, Sendable, Identifiable {
    public let codepoint: String   // e.g. "U+200B"
    public let label: String       // e.g. "U+200B ZERO WIDTH SPACE (Cf)"
    public let count: Int
    public let kind: String        // strip | bidi | tag_chars | variation_selector | zwj_family | space | confusable | other_cf
    public let sampleOffsets: [Int]

    public var id: String { "\(codepoint)-\(kind)" }

    enum CodingKeys: String, CodingKey {
        case codepoint, label, count, kind
        case sampleOffsets = "sample_offsets"
    }
}

public struct TextInspectReport: Codable, Sendable {
    public let kind: String?
    public let length: Int
    public let suspiciousTotal: Int
    public let hits: [TextHit]
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case kind, length, hits, notes
        case suspiciousTotal = "suspicious_total"
    }
}

// MARK: - Text clean stats (clean_text.py --stats on stderr)

public struct CleanStats: Codable, Sendable {
    public let inputLength: Int
    public let outputLength: Int
    public let removed: [String: Int]
    public let replaced: [String: Int]
    public let removedCount: Int
    public let replacedCount: Int

    enum CodingKeys: String, CodingKey {
        case removed, replaced
        case inputLength = "input_length"
        case outputLength = "output_length"
        case removedCount = "removed_count"
        case replacedCount = "replaced_count"
    }
}

// MARK: - File inspect (inspect_file.py --json)
// Shape varies by kind (text/image/container); keep common fields + findings.

public struct FileInspectReport: Codable, Sendable {
    public let kind: String                       // text | image | container
    public let path: String?
    public let format: String?
    public let hasC2PA: Bool?
    public let hasAIMetadata: Bool?
    public let findings: [String]?
    public let details: [String: JSONValue]?

    // text-kind reports reuse TextInspectReport fields
    public let length: Int?
    public let suspiciousTotal: Int?
    public let hits: [TextHit]?
    public let notes: [String]?

    enum CodingKeys: String, CodingKey {
        case kind, path, format, findings, details, hits, notes, length
        case hasC2PA = "has_c2pa"
        case hasAIMetadata = "has_ai_metadata"
        case suspiciousTotal = "suspicious_total"
    }
}

// MARK: - File clean (clean_file.py --json)

public struct FileCleanResult: Codable, Sendable {
    public let kind: String
    public let input: String?
    public let output: String
    public let stats: CleanStats?                 // text kind
    public let format: String?                    // container kind
    public let actions: [String]?                 // image/container kinds
    public let bytesIn: Int?
    public let bytesOut: Int?
    public let stillHasC2PA: Bool?
    public let stillHasAIMetadata: Bool?
    public let postFindings: [String]?

    enum CodingKeys: String, CodingKey {
        case kind, input, output, stats, format, actions
        case bytesIn = "bytes_in"
        case bytesOut = "bytes_out"
        case stillHasC2PA = "still_has_c2pa"
        case stillHasAIMetadata = "still_has_ai_metadata"
        case postFindings = "post_findings"
    }
}

// MARK: - Rewrite (rewrite_text.py --json-stats on stderr)

public struct RewriteInfo: Codable, Sendable {
    public let backend: String
    public let strength: String
    public let model: String?
    public let baseURL: String?
    public let temperature: Double?
    public let promptChars: Int?
    public let inputChars: Int?
    public let outputChars: Int?
    public let mode: String?
    public let candidates: Int?
    public let candidateScores: [Double]?
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case backend, strength, model, temperature, mode, candidates, note
        case baseURL = "base_url"
        case promptChars = "prompt_chars"
        case inputChars = "input_chars"
        case outputChars = "output_chars"
        case candidateScores = "candidate_scores"
    }
}

// MARK: - Loose JSON value for heterogeneous `details` payloads

public enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    public var displayString: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .array(let a): return "[\(a.count) items]"
        case .object(let o): return "{\(o.count) keys}"
        case .null: return "null"
        }
    }
}
