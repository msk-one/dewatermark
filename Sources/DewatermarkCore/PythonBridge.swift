import Foundation

public enum PythonBridgeError: Error, LocalizedError {
    case pythonNotFound(searched: [String])
    case pythonTooOld(path: String, version: String)
    case processFailed(exitCode: Int32, stderr: String)
    case timedOut(seconds: TimeInterval)
    case engineMissing(path: String)

    public var errorDescription: String? {
        switch self {
        case .pythonNotFound(let searched):
            return "No Python 3.10+ interpreter found. Searched: \(searched.joined(separator: ", ")). Install Python (e.g. `brew install python`) or set a custom path in Settings."
        case .pythonTooOld(let path, let version):
            return "Python at \(path) is \(version); the engine requires 3.10 or newer."
        case .processFailed(let code, let stderr):
            return "Engine exited with code \(code): \(stderr)"
        case .timedOut(let seconds):
            return "Engine process timed out after \(Int(seconds))s."
        case .engineMissing(let path):
            return "Engine scripts not found at \(path)."
        }
    }
}

public struct ProcessResult: Sendable {
    public let stdout: Data
    public let stderr: String
    public let exitCode: Int32

    public var stdoutText: String {
        String(decoding: stdout, as: UTF8.self)
    }
}

/// Locates a usable Python 3 interpreter (3.10+) on the host.
public struct PythonDiscovery: Sendable {
    /// Candidate absolute paths, in priority order, before falling back to PATH lookup.
    public static let candidatePaths = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]

    /// Find the first working Python >= 3.10. If `override` is set and valid, it wins.
    public static func findPython(override: String? = nil) -> Result<String, PythonBridgeError> {
        var searched: [String] = []
        var candidates: [String] = []
        if let override, !override.isEmpty {
            candidates.append(override)
        }
        candidates.append(contentsOf: candidatePaths)
        if let pathPython = Self.which("python3"), !candidates.contains(pathPython) {
            candidates.append(pathPython)
        }

        for candidate in candidates {
            searched.append(candidate)
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            if let version = Self.pythonVersion(candidate) {
                if version >= (3, 10) {
                    return .success(candidate)
                } else {
                    return .failure(.pythonTooOld(path: candidate, version: "\(version.0).\(version.1)"))
                }
            }
        }
        return .failure(.pythonNotFound(searched: searched))
    }

    static func which(_ tool: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", tool]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus == 0 && !out.isEmpty) ? out : nil
        } catch {
            return nil
        }
    }

    static func pythonVersion(_ path: String) -> (Int, Int)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-c", "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = out.split(separator: ".").compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            return (parts[0], parts[1])
        } catch {
            return nil
        }
    }
}

/// Runs the vendored Python engine scripts as subprocesses.
public final class PythonBridge: @unchecked Sendable {
    public let pythonPath: String
    public let engineDir: URL

    public init(pythonPath: String, engineDir: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: engineDir.appendingPathComponent("clean_text.py").path, isDirectory: &isDir) else {
            throw PythonBridgeError.engineMissing(path: engineDir.path)
        }
        self.pythonPath = pythonPath
        self.engineDir = engineDir
    }

    /// Run an engine script with arguments and optional stdin text.
    /// - Parameters:
    ///   - script: script filename inside the engine dir (e.g. "clean_text.py")
    ///   - args: CLI arguments passed after the script
    ///   - stdin: optional text piped to stdin
    ///   - environment: extra environment variables merged over the current env
    ///   - timeout: seconds before the process is killed
    ///   - acceptableExitCodes: exit codes treated as success (engine uses 1 for "findings remain")
    public func run(
        script: String,
        args: [String] = [],
        stdin: String? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = 10,
        acceptableExitCodes: Set<Int32> = [0]
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [engineDir.appendingPathComponent(script).path] + args
        var env = ProcessInfo.processInfo.environment
        // Ensure common tool locations (exiftool/c2patool via homebrew) are reachable.
        let basePath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + basePath
        env.merge(environment) { _, new in new }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe = Pipe()
        process.standardInput = inPipe

        try process.run()

        if let stdin {
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        }
        inPipe.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                timedOut = true
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        // Read after termination to avoid pipe-buffer deadlocks for typical engine output sizes.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if timedOut {
            throw PythonBridgeError.timedOut(seconds: timeout)
        }
        // Ensure process status is reaped.
        process.waitUntilExit()

        let result = ProcessResult(
            stdout: outData,
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
        guard acceptableExitCodes.contains(result.exitCode) else {
            throw PythonBridgeError.processFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        return result
    }
}
