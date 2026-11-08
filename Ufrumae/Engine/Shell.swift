import Foundation

/// Führt Kommandozeilen-Werkzeuge aus (xcrun, npm …), ohne Shell-Interpretation der Argumente.
enum Shell {
    struct Output: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { status == 0 }
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 300) async -> Output {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(executable, arguments, timeout: timeout))
            }
        }
    }

    static func runSync(_ executable: String, _ arguments: [String], timeout: TimeInterval = 300) -> Output {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        // Apps aus dem Finder kennen den PATH aus dem Terminal nicht.
        env["PATH"] = ([home("/.nvm/current/bin"), "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] + [env["PATH"] ?? ""]).joined(separator: ":")
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch {
            return Output(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        // Ausgaben parallel lesen, sonst blockiert der Prozess bei grossen Ausgaben.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate() }
        p.waitUntilExit()
        group.wait()
        return Output(status: p.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self))
    }

    /// Sucht ein Werkzeug an den üblichen Orten (GUI-Apps haben keinen Terminal-PATH).
    static func which(_ tool: String) -> String? {
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", home("/.volta/bin"), home("/.nvm/current/bin"), home("/.local/bin")]
        for dir in candidates {
            let path = dir + "/" + tool
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        // nvm legt Versionen in Unterordnern ab
        let nvm = URL(fileURLWithPath: home("/.nvm/versions/node"))
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm.path).sorted().reversed() {
            for v in versions {
                let path = nvm.path + "/" + v + "/bin/" + tool
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    private static func home(_ suffix: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser.path + suffix
    }
}
