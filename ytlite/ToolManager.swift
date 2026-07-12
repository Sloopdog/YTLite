import CryptoKit
import Foundation

enum ToolLocator {
    static var managedYTDLPURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("YTLite/bin/yt-dlp")
    }

    static func findYTDLP(customPath: String) -> URL? {
        let candidates = [
            customPath,
            managedYTDLPURL.path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/yt-dlp").path,
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        return firstExecutable(in: candidates)
    }

    static func findFFmpeg(customPath: String) -> URL? {
        let candidates = [
            customPath,
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        return firstExecutable(in: candidates)
    }

    static func findJavaScriptRuntime() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return firstExecutable(in: [
            "/opt/homebrew/bin/deno",
            "/usr/local/bin/deno",
            home.appendingPathComponent(".deno/bin/deno").path,
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
            "/opt/homebrew/bin/bun",
            "/usr/local/bin/bun",
            "/opt/homebrew/bin/qjs",
            "/usr/local/bin/qjs"
        ])
    }

    static func javaScriptRuntimeArgument(path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let executable = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let kind: String
        switch executable {
        case "deno": kind = "deno"
        case "node", "nodejs": kind = "node"
        case "bun": kind = "bun"
        case "qjs", "quickjs": kind = "quickjs"
        default: return nil
        }
        return "\(kind):\(path)"
    }

    static func inspect(preferences: ToolPreferences) -> ToolsStatus {
        let ytDLP = findYTDLP(customPath: preferences.customYTDLPPath)
        let ffmpeg = findFFmpeg(customPath: preferences.customFFmpegPath)
        let js = findJavaScriptRuntime()

        return ToolsStatus(
            ytDLP: DependencyStatus(
                name: "yt-dlp",
                path: ytDLP?.path,
                version: ytDLP.flatMap { runCapture(executable: $0, arguments: ["--ignore-config", "--version"]) }
            ),
            ffmpeg: DependencyStatus(
                name: "FFmpeg",
                path: ffmpeg?.path,
                version: ffmpeg.flatMap { firstLine(runCapture(executable: $0, arguments: ["-version"])) }
            ),
            javaScriptRuntime: DependencyStatus(
                name: js?.lastPathComponent.capitalized ?? "JavaScript runtime",
                path: js?.path,
                version: js.flatMap { firstLine(runCapture(executable: $0, arguments: ["--version"])) }
            ),
            isRefreshing: false
        )
    }

    private static func firstExecutable(in paths: [String]) -> URL? {
        for path in paths where !path.isEmpty {
            let expanded = NSString(string: path).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        return nil
    }

    private static func firstLine(_ value: String?) -> String? {
        value?.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    static func runCapture(executable: URL, arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        process.environment = processEnvironment()
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "PYTHONPATH")
        environment.removeValue(forKey: "PYTHONHOME")
        for key in environment.keys where key.hasPrefix("DYLD_") {
            environment.removeValue(forKey: key)
        }
        let knownPaths = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".deno/bin").path
        ]
        environment["PATH"] = knownPaths.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }
}

enum ManagedYTDLPInstaller {
    static func installLatest(channel: UpdateChannel) async throws -> URL {
        let repository = channel == .nightly ? "yt-dlp/yt-dlp-nightly-builds" : "yt-dlp/yt-dlp"
        let base = "https://github.com/\(repository)/releases/latest/download"
        guard let binaryURL = URL(string: "\(base)/yt-dlp_macos"),
              let checksumsURL = URL(string: "\(base)/SHA2-256SUMS") else {
            throw InstallError.invalidURL
        }

        async let binaryResponse = URLSession.shared.data(from: binaryURL)
        async let checksumResponse = URLSession.shared.data(from: checksumsURL)
        let ((binary, binaryHTTP), (checksums, checksumsHTTP)) = try await (binaryResponse, checksumResponse)

        try validateHTTP(binaryHTTP)
        try validateHTTP(checksumsHTTP)

        guard let checksumText = String(data: checksums, encoding: .utf8),
              let expected = checksum(for: "yt-dlp_macos", in: checksumText) else {
            throw InstallError.checksumMissing
        }
        let actual = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw InstallError.checksumMismatch
        }

        let destination = ToolLocator.managedYTDLPURL
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent("yt-dlp.download")
        try? fileManager.removeItem(at: temporary)
        try binary.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw InstallError.downloadFailed
        }
    }

    private static func checksum(for filename: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            let listedName = fields.last.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if listedName == filename { return String(fields[0]) }
        }
        return nil
    }

    enum InstallError: LocalizedError {
        case invalidURL
        case downloadFailed
        case checksumMissing
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .invalidURL: "The official yt-dlp download address is invalid."
            case .downloadFailed: "The official yt-dlp download could not be completed."
            case .checksumMissing: "The official checksum list did not contain the Mac executable."
            case .checksumMismatch: "The download did not match yt-dlp's official checksum and was rejected."
            }
        }
    }
}
