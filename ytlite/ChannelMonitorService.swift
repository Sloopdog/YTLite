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
            guard let id = entry["id"] as? String, !id.isEmpty else { return nil }
            let title = (entry["title"] as? String) ?? "YouTube video"
            let candidate = (entry["webpage_url"] as? String) ?? (entry["url"] as? String)
            let url = candidate.flatMap { value -> String? in
                guard let scheme = URL(string: value)?.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
                return value
            }
                ?? "https://www.youtube.com/watch?v=\(id)"
            return ChannelVideo(id: id, title: title, url: url)
        }
        guard !videos.isEmpty else { return .failure(ChannelMonitorError.noVideos) }
        return .success(ChannelProbeResult(channelName: name, videos: videos))
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
