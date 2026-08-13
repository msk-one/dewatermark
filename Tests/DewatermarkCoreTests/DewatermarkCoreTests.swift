import XCTest
@testable import DewatermarkCore

final class PythonDiscoveryTests: XCTestCase {
    func testFindsSystemPython() {
        switch PythonDiscovery.findPython() {
        case .success(let path):
            XCTAssertFalse(path.isEmpty)
        case .failure(let error):
            XCTFail("expected a python3 on this machine: \(error.localizedDescription)")
        }
    }

    func testInvalidOverrideFails() {
        let result = PythonDiscovery.findPython(override: "/nonexistent/python3")
        // Falls through to other candidates if they exist; only assert the
        // override itself wasn't accepted.
        if case .success(let path) = result {
            XCTAssertNotEqual(path, "/nonexistent/python3")
        }
    }
}

final class PythonBridgeTests: XCTestCase {
    func testEngineMissingThrows() {
        XCTAssertThrowsError(
            try PythonBridge(pythonPath: "/usr/bin/true", engineDir: URL(fileURLWithPath: "/nonexistent"))
        ) { error in
            guard case PythonBridgeError.engineMissing = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
    }

    func testNonZeroExitCodeThrows() throws {
        let engine = try makeEngine()
        XCTAssertThrowsError(
            try engine.inspectFile(at: "/nonexistent/file.md")
        ) { error in
            // engine exits 2 for missing file
            guard case PythonBridgeError.processFailed(let code, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(code, 2)
        }
    }
}

final class EngineTextTests: XCTestCase {
    var engine: Engine!

    override func setUpWithError() throws {
        engine = try makeEngine()
    }

    func testCleanTextStripsZeroWidthAndSoftHyphen() throws {
        let raw = "Hello\u{200b}World\u{00ad}!"
        let result = try engine.cleanText(raw)
        XCTAssertEqual(result.text.trimmingCharacters(in: .newlines), "HelloWorld!")
        XCTAssertGreaterThanOrEqual(result.stats?.removedCount ?? 0, 2)
    }

    func testCleanTextNormalizesExoticSpaces() throws {
        let raw = "a\u{2003}b\u{3000}c"
        let result = try engine.cleanText(raw)
        XCTAssertEqual(result.text.trimmingCharacters(in: .newlines), "a b c")
        XCTAssertGreaterThanOrEqual(result.stats?.replacedCount ?? 0, 2)
    }

    func testCleanTextPreservesNormalText() throws {
        let raw = "Normal ASCII and café — fine."
        let result = try engine.cleanText(raw)
        XCTAssertEqual(result.text.trimmingCharacters(in: .newlines), raw)
        XCTAssertEqual(result.stats?.removedCount, 0)
    }

    func testInspectFindsZWSP() throws {
        let report = try engine.inspectText("x\u{200b}y")
        XCTAssertGreaterThanOrEqual(report.suspiciousTotal, 1)
        XCTAssertTrue(report.hits.contains { $0.kind == "zwj_family" || $0.kind == "strip" })
    }

    func testInspectBidiAndTagChars() throws {
        let report = try engine.inspectText("ab\u{202e}ef" + "\u{e0041}")
        let kinds = Set(report.hits.map(\.kind))
        XCTAssertTrue(kinds.contains("bidi"))
        XCTAssertTrue(kinds.contains("tag_chars"))
    }

    func testInspectCleanTextIsZero() throws {
        let report = try engine.inspectText("perfectly ordinary prose, nothing hidden.")
        XCTAssertEqual(report.suspiciousTotal, 0)
    }

    func testAggressiveHomoglyphMapping() throws {
        let result = try engine.cleanText("p\u{0430}y", options: {
            var o = CleanTextOptions()
            o.aggressiveHomoglyphs = true
            return o
        }())
        XCTAssertEqual(result.text.trimmingCharacters(in: .newlines), "pay")
    }
}

final class EngineFileTests: XCTestCase {
    var engine: Engine!
    var tmpDir: URL!

    override func setUpWithError() throws {
        engine = try makeEngine()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dewatermark-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testCleanMarkdownFileWithAIFrontmatter() throws {
        let md = """
        ---
        title: My Notes
        generator: claude
        ---

        Body text with\u{200b} zero width.
        """
        let src = tmpDir.appendingPathComponent("notes.md")
        try md.write(to: src, atomically: true, encoding: .utf8)

        let inspect = try engine.inspectFile(at: src.path)
        XCTAssertEqual(inspect.kind, "container")

        let dest = tmpDir.appendingPathComponent("notes.cleaned.md")
        let result = try engine.cleanFile(at: src.path, output: dest.path)
        XCTAssertEqual(result.kind, "container")
        let cleaned = try String(contentsOf: dest, encoding: .utf8)
        XCTAssertFalse(cleaned.contains("generator: claude"))
        XCTAssertFalse(cleaned.contains("\u{200b}"))
        XCTAssertTrue(cleaned.contains("title: My Notes"))
    }

    func testCleanSVGWithMetadata() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg"><metadata>c2pa</metadata><rect width="10" height="10"/></svg>
        """
        let src = tmpDir.appendingPathComponent("img.svg")
        try svg.write(to: src, atomically: true, encoding: .utf8)
        let dest = tmpDir.appendingPathComponent("img.cleaned.svg")
        let result = try engine.cleanFile(at: src.path, output: dest.path)
        XCTAssertEqual(result.format, "svg")
        let cleaned = try String(contentsOf: dest, encoding: .utf8)
        XCTAssertFalse(cleaned.contains("c2pa"))
        XCTAssertTrue(cleaned.contains("<rect"))
    }

    func testCleanPlainTextFile() throws {
        let src = tmpDir.appendingPathComponent("plain.txt")
        try "hi\u{200b}there".write(to: src, atomically: true, encoding: .utf8)
        let dest = tmpDir.appendingPathComponent("plain.cleaned.txt")
        let result = try engine.cleanFile(at: src.path, output: dest.path)
        XCTAssertEqual(result.kind, "text")
        let cleaned = try String(contentsOf: dest, encoding: .utf8)
        XCTAssertEqual(cleaned, "hithere")
        XCTAssertEqual(result.stats?.removedCount, 1)
    }
}

final class RewriteTests: XCTestCase {
    var engine: Engine!

    override func setUpWithError() throws {
        engine = try makeEngine()
    }

    func testPrintPromptPassthrough() throws {
        var opts = RewriteOptions()
        opts.backend = .printPrompt
        opts.strength = .paraphrase
        let result = try engine.rewrite("Some AI generated prose.", options: opts)
        XCTAssertTrue(result.text.contains("Some AI generated prose."))
        XCTAssertTrue(result.text.contains("Rewrite the following text"))
        XCTAssertEqual(result.info?.mode, "print-prompt")
    }

    func testRemoteDetection() {
        var local = RewriteOptions()
        local.baseURL = "http://127.0.0.1:11434"
        XCTAssertFalse(local.isRemote)
        local.baseURL = "http://localhost:11434"
        XCTAssertFalse(local.isRemote)
        var remote = RewriteOptions()
        remote.baseURL = "https://api.example.com"
        XCTAssertTrue(remote.isRemote)
    }

    func testOllamaRewriteAgainstStubServer() throws {
        let server = try StubOllamaServer()
        defer { server.stop() }

        var opts = RewriteOptions()
        opts.backend = .ollama
        opts.model = "stub-model"
        opts.baseURL = server.baseURL
        opts.timeout = 5
        let result = try engine.rewrite("Watermarked input text.", options: opts)
        XCTAssertEqual(result.text.trimmingCharacters(in: .whitespacesAndNewlines), StubOllamaServer.rewrittenText)
        XCTAssertEqual(server.lastModel, "stub-model")
        XCTAssertNotNil(server.lastPrompt)
        XCTAssertTrue(server.lastPrompt!.contains("Watermarked input text."))
    }
}

// MARK: - Helpers

func makeEngine() throws -> Engine {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // DewatermarkCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // package root
    return try Engine(engineDirOverride: root.appendingPathComponent("Engine/watermarks-remover"))
}
