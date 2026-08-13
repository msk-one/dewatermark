import Foundation
import DewatermarkCore

/// Lightweight no-XCTest smoke runner for machines with only Command Line Tools.
/// Exits non-zero on the first failing check.

var failures = 0
func check(_ name: String, _ condition: Bool, detail: String = "") {
    if condition {
        print("PASS  \(name)")
    } else {
        print("FAIL  \(name) \(detail)")
        failures += 1
    }
}

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // SmokeRunner
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // package root
let engineDir = root.appendingPathComponent("Engine/watermarks-remover")

// 1. Python discovery
let pythonResult = PythonDiscovery.findPython()
let pythonPath: String
switch pythonResult {
case .success(let path):
    check("python discovery", true, detail: path)
    pythonPath = path
case .failure(let error):
    check("python discovery", false, detail: error.localizedDescription)
    exit(1)
}

// 2. Bridge + engine construction
let engine: Engine
do {
    engine = try Engine(bridge: PythonBridge(pythonPath: pythonPath, engineDir: engineDir))
    check("engine init", true)
} catch {
    check("engine init", false, detail: error.localizedDescription)
    exit(1)
}

// 3. Layer A clean end-to-end
do {
    let result = try engine.cleanText("Hello\u{200b}World\u{00ad}!")
    check(
        "clean text strips ZWSP + soft hyphen",
        result.text.trimmingCharacters(in: .newlines) == "HelloWorld!"
            && (result.stats?.removedCount ?? 0) >= 2,
        detail: result.text
    )
} catch {
    check("clean text strips ZWSP + soft hyphen", false, detail: error.localizedDescription)
}

// 4. Inspect end-to-end
do {
    let report = try engine.inspectText("x\u{200b}y")
    check("inspect finds ZWSP", report.suspiciousTotal >= 1)
} catch {
    check("inspect finds ZWSP", false, detail: error.localizedDescription)
}

// 5. File clean end-to-end (markdown container)
do {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("dewatermark-smoke-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let src = tmp.appendingPathComponent("notes.md")
    try "---\ntitle: T\ngenerator: claude\n---\n\nBody\u{200b} text.\n".write(to: src, atomically: true, encoding: .utf8)
    let dest = tmp.appendingPathComponent("notes.cleaned.md")
    let result = try engine.cleanFile(at: src.path, output: dest.path)
    let cleaned = try String(contentsOf: dest, encoding: .utf8)
    check(
        "clean markdown file",
        result.kind == "container"
            && !cleaned.contains("generator: claude")
            && !cleaned.contains("\u{200b}"),
        detail: cleaned
    )
} catch {
    check("clean markdown file", false, detail: error.localizedDescription)
}

// 6. Rewrite print-prompt passthrough
do {
    var opts = RewriteOptions()
    opts.backend = .printPrompt
    let result = try engine.rewrite("Some AI generated prose.", options: opts)
    check(
        "rewrite print-prompt passthrough",
        result.text.contains("Some AI generated prose.")
            && result.info?.mode == "print-prompt"
    )
} catch {
    check("rewrite print-prompt passthrough", false, detail: error.localizedDescription)
}

print(failures == 0 ? "\nAll smoke checks passed." : "\n\(failures) smoke check(s) FAILED.")
exit(failures == 0 ? 0 : 1)
