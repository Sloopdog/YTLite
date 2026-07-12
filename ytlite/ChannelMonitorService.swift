import Foundation

final class ChannelMonitorService {
    func fetchLatest(
        executable: URL,
        channelURL: String,
        limit: Int,
        preferences: ToolPreferences,
        javaScriptRuntimePath: String?,
        completion: @escaping (Result<ChannelProbeResult, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            var arguments: [String] = []
            if !preferences.useUserConfiguration { arguments.append("--ignore-config") }
            arguments += [
                "--flat-playlist",
                "--playlist-end", String(max(1, limit)),
                "--dump-single-json",
                "--skip-download"
            ]
            if let runtime = ToolLocator.javaScriptRuntimeArgument(path: javaScriptRuntimePath) {
                arguments += ["--js-runtimes", runtime]
            }
            arguments += ["--", channelURL]

            process.executableURL = executable
            process.arguments = arguments
            process.environment = ToolLocator.processEnvironment()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let group = DispatchGroup()
            var outputData = Data()
            var errorData = Data()
            let lock = NSLock()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                lock.lock(); outputData = data; lock.unlock()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                lock.lock(); errorData = data; lock.unlock()
                group.leave()
            }

            let timeout = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 90, execute: timeout)
            process.waitUntilExit()
            timeout.cancel()
            group.wait()

            let result: Result<ChannelProbeResult, Error>
            if process.terminationStatus != 0 {
                let message = String(data: errorData, encoding: .utf8)?
                    .split(whereSeparator: \.isNewline).last.map(String.init)
                    ?? "yt-dlp could not read this channel."
                result = .failure(ChannelMonitorError.probeFailed(message))
            } else {
                result = Self.parse(outputData)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func parse(_ data: Data) -> Result<ChannelProbeResult, Error> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(ChannelMonitorError.invalidResponse)
        }
        let name = (root["channel"] as? String)
            ?? (root["uploader"] as? String)
            ?? (root["title"] as? String)
            ?? "YouTube channel"
        let rawEntries = root["entries"] as? [[String: Any]] ?? []
        let videos = rawEntries.compactMap { entry -> ChannelVideo? in
            guard let id = entry["id"] as? String, YouTubeVideoID.isValid(id) else { return nil }
            let title = (entry["title"] as? String) ?? "YouTube video"
            // Never trust a flat-playlist entry URL here. A channel root URL
            // returns tab entries whose URLs point back to whole playlists.
            // Building a watch URL from a validated 11-character video ID
            // makes it impossible for one automatic job to expand to a channel.
            let url = "https://www.youtube.com/watch?v=\(id)"
            return ChannelVideo(id: id, title: title, url: url)
        }
        guard !videos.isEmpty else { return .failure(ChannelMonitorError.noVideos) }
        return .success(ChannelProbeResult(channelName: name, videos: videos))
    }
}

enum YouTubeVideoID {
    static func isValid(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
    }
}

enum ChannelURLNormalizer {
    private static let tabNames: Set<String> = [
        "featured", "videos", "shorts", "streams", "live", "releases", "playlists", "community"
    ]

    static func videosURL(from value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: clean),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host?.lowercased(),
              host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }

        var parts = components.path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return nil }
        let isHandle = parts[0].hasPrefix("@") && parts[0].count > 1
        let isNamedChannel = ["channel", "c", "user"].contains(parts[0].lowercased()) && parts.count >= 2
        guard isHandle || isNamedChannel else { return nil }

        if let last = parts.last?.lowercased(), tabNames.contains(last) {
            parts[parts.count - 1] = "videos"
        } else {
            parts.append("videos")
        }
        components.scheme = "https"
        components.path = "/" + parts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }
}

enum ChannelOutputFolder {
    static func safeName(for displayName: String) -> String {
        var name = displayName
            .replacingOccurrences(of: #"[/:\\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if name.isEmpty || name == "Checking channel…" { name = "YouTube Channel" }
        return String(name.prefix(100))
    }

    static func path(baseDirectory: String, channelName: String) -> String {
        let folder = safeName(for: channelName)
        let base = URL(fileURLWithPath: baseDirectory, isDirectory: true)
        if base.lastPathComponent.caseInsensitiveCompare(folder) == .orderedSame {
            return base.path
        }
        return base.appendingPathComponent(folder, isDirectory: true).path
    }
}

enum ChannelMonitorError: LocalizedError {
    case invalidURL
    case duplicate
    case missingEngine
    case invalidResponse
    case noVideos
    case probeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Paste a YouTube channel URL, preferably its /videos page."
        case .duplicate: "That channel is already being monitored."
        case .missingEngine: "Install yt-dlp in Settings before adding a channel."
        case .invalidResponse: "The channel response could not be understood."
        case .noVideos: "No public videos were found on that channel."
        case let .probeFailed(message): message
        }
    }
}
