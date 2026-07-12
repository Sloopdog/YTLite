import Foundation

enum DownloadEvent {
    case progress(fraction: Double?, speed: String?, eta: String?)
    case postprocessing
    case title(String)
    case outputFile(String)
    case log(String)
}

final class DownloadRunner {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    var isRunning: Bool { process?.isRunning == true }

    func start(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        onEvent: @escaping (DownloadEvent) -> Void,
        onCompletion: @escaping (Int32) -> Void
    ) throws {
        guard process == nil else { throw RunnerError.alreadyRunning }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutLines = LineAccumulator()
        let stderrLines = LineAccumulator()

        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = ToolLocator.processEnvironment()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let consume: (String) -> Void = { line in
            let event = ProgressDecoder.decode(line: line)
            DispatchQueue.main.async { onEvent(event) }
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                if let remainder = stdoutLines.flush() { consume(remainder) }
            } else {
                stdoutLines.feed(data: data).forEach(consume)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                if let remainder = stderrLines.flush() { consume(remainder) }
            } else {
                stderrLines.feed(data: data).forEach(consume)
            }
        }

        process.terminationHandler = { [weak self] finished in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            stdoutLines.feed(data: stdout.fileHandleForReading.readDataToEndOfFile()).forEach(consume)
            stderrLines.feed(data: stderr.fileHandleForReading.readDataToEndOfFile()).forEach(consume)
            if let remainder = stdoutLines.flush() { consume(remainder) }
            if let remainder = stderrLines.flush() { consume(remainder) }
            DispatchQueue.main.async {
                self?.process = nil
                self?.stdoutPipe = nil
                self?.stderrPipe = nil
                onCompletion(finished.terminationStatus)
            }
        }

        self.process = process
        stdoutPipe = stdout
        stderrPipe = stderr
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            stdoutPipe = nil
            stderrPipe = nil
            throw error
        }
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        process.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak process] in
            guard let process, process.isRunning else { return }
            process.terminate()
        }
    }

    func terminateForAppExit() {
        guard let process, process.isRunning else { return }
        process.interrupt()
        process.terminate()
    }

    enum RunnerError: LocalizedError {
        case alreadyRunning

        var errorDescription: String? { "A download is already running." }
    }
}

private final class LineAccumulator {
    private var buffer = Data()
    private let lock = NSLock()

    func feed(data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line.trimmingCharacters(in: .newlines))
            }
        }
        return lines
    }

    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(data: buffer, encoding: .utf8)
    }
}

enum ProgressDecoder {
    private static let progressPrefix = "__YTLITE_PROGRESS__"
    private static let postPrefix = "__YTLITE_POST__"
    private static let titlePrefix = "__YTLITE_TITLE__"
    private static let resultPrefix = "__YTLITE_RESULT__"

    static func decode(line rawLine: String) -> DownloadEvent {
        let line = stripANSI(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix(progressPrefix) {
            let payload = String(line.dropFirst(progressPrefix.count))
            guard let json = jsonObject(payload) else { return .log(line) }
            let downloaded = number(json["downloaded_bytes"])
            let total = number(json["total_bytes"]) ?? number(json["total_bytes_estimate"])
            let fraction = (downloaded != nil && total != nil && total! > 0) ? min(1, downloaded! / total!) : nil
            let speed = number(json["speed"]).map(formatSpeed)
            let eta = number(json["eta"]).map { formatDuration(Int($0)) }
            return .progress(fraction: fraction, speed: speed, eta: eta)
        }
        if line.hasPrefix(postPrefix) { return .postprocessing }
        if line.hasPrefix(titlePrefix) {
            let payload = String(line.dropFirst(titlePrefix.count))
            if let title = jsonObject(payload)?["title"] as? String { return .title(title) }
        }
        if line.hasPrefix(resultPrefix) {
            let payload = String(line.dropFirst(resultPrefix.count))
            if let filepath = jsonObject(payload)?["filepath"] as? String { return .outputFile(filepath) }
        }
        return .log(line)
    }

    private static func jsonObject(_ value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func stripANSI(_ input: String) -> String {
        input.replacingOccurrences(of: "\\u{001B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }
}
