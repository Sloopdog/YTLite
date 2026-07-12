import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var page: AppPage = .download
    @Published var urlInput = ""
    @Published var settings: DownloadSettings {
        didSet { persist(settings, key: Keys.settings) }
    }
    @Published var preferences: ToolPreferences {
        didSet { persist(preferences, key: Keys.preferences) }
    }
    @Published var advancedSelections: [String: AdvancedSelection] {
        didSet { persistSafeAdvancedSelections() }
    }
    @Published var customArguments: String
    @Published var jobs: [DownloadJob]
    @Published var presets: [CustomPreset] {
        didSet { persist(presets, key: Keys.presets) }
    }
    @Published var tools = ToolsStatus()
    @Published var currentJobID: UUID?
    @Published var notice: String?
    @Published var catalogError: String?
    @Published var isInstallingYTDLP = false
    @Published var installError: String?
    @Published var channelSubscriptions: [ChannelSubscription] {
        didSet { persist(channelSubscriptions, key: Keys.channels) }
    }
    @Published var checkingChannelIDs: Set<UUID> = []
    @Published var channelAddError: String?
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginError: String?

    let catalog: OptionCatalog
    private let runner = DownloadRunner()
    private let channelMonitor = ChannelMonitorService()
    private var monitorTimer: Timer?
    private var terminationObserver: NSObjectProtocol?

    init() {
        settings = Self.restore(DownloadSettings.self, key: Keys.settings) ?? .standard
        preferences = Self.restore(ToolPreferences.self, key: Keys.preferences) ?? ToolPreferences()
        advancedSelections = Self.restore([String: AdvancedSelection].self, key: Keys.advanced) ?? [:]
        // Raw arguments can contain credentials or tokens, so they intentionally
        // live only for the current app session.
        customArguments = ""
        presets = Self.restore([CustomPreset].self, key: Keys.presets) ?? []
        let restoredChannels = Self.restore([ChannelSubscription].self, key: Keys.channels) ?? []
        channelSubscriptions = Self.migratedChannelSubscriptions(restoredChannels)

        var restoredJobs = Self.restore([DownloadJob].self, key: Keys.jobs) ?? []
        for index in restoredJobs.indices where [.running, .postprocessing].contains(restoredJobs[index].state) {
            restoredJobs[index].state = .interrupted
            restoredJobs[index].statusMessage = "The app closed before this finished. Retry to resume."
        }
        jobs = restoredJobs

        do {
            catalog = try OptionCatalogLoader.load()
        } catch {
            catalog = .empty
            catalogError = error.localizedDescription
        }
        launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
        for subscription in channelSubscriptions {
            try? FileManager.default.createDirectory(
                at: URL(fileURLWithPath: subscription.settings.outputDirectory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        persist(channelSubscriptions, key: Keys.channels)
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDueChannels() }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.runner.terminateForAppExit() }
        }
        refreshTools()
    }

    var activeSelectedOptionCount: Int {
        advancedSelections.values.filter(\.enabled).count
    }

    var isDownloading: Bool { currentJobID != nil }

    var catalogVersionMismatch: Bool {
        guard let installed = tools.ytDLP.version, installed != catalog.ytDlpVersion else { return false }
        return true
    }

    var firstInput: String? { parsedInputs().first }

    var commandPreview: String {
        guard let input = firstInput else { return "Paste a URL to preview the command." }
        let executable = tools.ytDLP.path ?? "yt-dlp"
        let plan = ArgumentCompiler.makePlan(
            url: input,
            settings: settings,
            preferences: preferences,
            ffmpegPath: tools.ffmpeg.path,
            javaScriptRuntimePath: tools.javaScriptRuntime.path,
            catalog: catalog,
            selections: advancedSelections,
            customArguments: customArguments
        )
        return ArgumentCompiler.displayCommand(executable: executable, arguments: plan.arguments)
    }

    func pasteURL() {
        guard let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty else { return }
        if urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            urlInput = pasted
        } else {
            urlInput += "\n" + pasted
        }
        page = .download
    }

    func addToQueue(startImmediately: Bool) {
        let inputs = parsedInputs()
        guard !inputs.isEmpty else {
            notice = "Paste at least one media link first."
            return
        }

        let newJobs = inputs.map {
            DownloadJob(
                url: $0,
                settings: settings,
                advancedSelections: advancedSelections,
                customArguments: customArguments
            )
        }
        jobs.insert(contentsOf: newJobs, at: 0)
        urlInput = ""
        notice = newJobs.count == 1 ? "Added to the queue." : "Added \(newJobs.count) items to the queue."
        persistJobs()
        if startImmediately { startQueue() }
    }

    func startQueue() {
        guard currentJobID == nil else { return }
        guard tools.ytDLP.path != nil else {
            notice = "yt-dlp is not available yet. Open Settings and install it."
            page = .settings
            return
        }
        if jobs.contains(where: { $0.state == .queued && Self.requiresFFmpeg($0.settings) }), !tools.ffmpeg.isAvailable {
            notice = "FFmpeg is required for the queued format. Install FFmpeg or choose it in Settings."
            page = .settings
            return
        }
        startNextQueuedJob()
    }

    func cancel(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        if currentJobID == jobID {
            jobs[index].state = .cancelled
            jobs[index].statusMessage = "Stopping safely…"
            runner.cancel()
        } else if jobs[index].state == .queued {
            jobs[index].state = .cancelled
            jobs[index].statusMessage = "Removed from the active queue"
        }
        persistJobs()
    }

    func retry(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].state = .queued
        jobs[index].progress = 0
        jobs[index].speed = ""
        jobs[index].eta = ""
        jobs[index].statusMessage = "Ready to retry"
        jobs[index].logLines = []
        persistJobs()
        startQueue()
    }

    func remove(jobID: UUID) {
        guard currentJobID != jobID else { return }
        jobs.removeAll { $0.id == jobID }
        persistJobs()
    }

    func clearFinished() {
        jobs.removeAll { [.completed, .failed, .cancelled, .interrupted].contains($0.state) }
        persistJobs()
    }

    func reveal(jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        let url: URL
        if let outputPath = job.outputPath {
            url = URL(fileURLWithPath: outputPath)
        } else {
            url = URL(fileURLWithPath: job.settings.outputDirectory)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where downloads are saved"
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.outputDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.outputDirectory = url.path
    }

    func openOutputFolder() {
        let url = URL(fileURLWithPath: settings.outputDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func chooseYTDLP() {
        guard let path = chooseExecutable(title: "Choose the yt-dlp executable") else { return }
        preferences.customYTDLPPath = path
        refreshTools()
    }

    func chooseFFmpeg() {
        guard let path = chooseExecutable(title: "Choose the ffmpeg executable") else { return }
        preferences.customFFmpegPath = path
        refreshTools()
    }

    func clearCustomYTDLP() {
        preferences.customYTDLPPath = ""
        refreshTools()
    }

    func clearCustomFFmpeg() {
        preferences.customFFmpegPath = ""
        refreshTools()
    }

    func refreshTools() {
        let snapshot = preferences
        let ytDLP = ToolLocator.findYTDLP(customPath: snapshot.customYTDLPPath)
        let ffmpeg = ToolLocator.findFFmpeg(customPath: snapshot.customFFmpegPath)
        let runtime = ToolLocator.findJavaScriptRuntime()
        tools = ToolsStatus(
            ytDLP: DependencyStatus(name: "yt-dlp", path: ytDLP?.path, version: tools.ytDLP.version),
            ffmpeg: DependencyStatus(name: "FFmpeg", path: ffmpeg?.path, version: tools.ffmpeg.version),
            javaScriptRuntime: DependencyStatus(
                name: runtime?.lastPathComponent.capitalized ?? "JavaScript runtime",
                path: runtime?.path,
                version: tools.javaScriptRuntime.version
            ),
            isRefreshing: true
        )
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let inspected = ToolLocator.inspect(preferences: snapshot)
            DispatchQueue.main.async {
                self?.tools = inspected
                self?.checkDueChannels()
            }
        }
    }

    func installOrUpdateYTDLP() {
        guard !isInstallingYTDLP else { return }
        isInstallingYTDLP = true
        installError = nil
        let channel = preferences.updateChannel
        Task {
            do {
                _ = try await ManagedYTDLPInstaller.installLatest(channel: channel)
                preferences.customYTDLPPath = ""
                refreshTools()
                notice = "yt-dlp was installed from the official \(channel.title) release."
            } catch {
                installError = error.localizedDescription
            }
            isInstallingYTDLP = false
        }
    }

    func setAdvancedSelection(_ selection: AdvancedSelection, for optionID: String) {
        advancedSelections[optionID] = selection
    }

    func resetAdvancedOptions() {
        advancedSelections = [:]
        customArguments = ""
    }

    func apply(_ preset: BuiltInPreset) {
        var next = DownloadSettings.standard
        next.outputDirectory = settings.outputDirectory
        next.cookieBrowser = settings.cookieBrowser

        switch preset {
        case .bestVideo:
            next.mediaMode = .video
            next.videoQuality = .best
            next.videoContainer = .automatic
        case .compatibleMP4:
            next.mediaMode = .video
            next.videoQuality = .fullHD
            next.videoContainer = .mp4
        case .musicMP3:
            next.mediaMode = .audio
            next.audioFormat = .mp3
            next.embedThumbnail = true
            next.embedMetadata = true
        case .audioM4A:
            next.mediaMode = .audio
            next.audioFormat = .m4a
        case .original:
            next.mediaMode = .original
            next.embedThumbnail = false
        case .subtitled:
            next.mediaMode = .video
            next.videoQuality = .fullHD
            next.videoContainer = .mp4
            next.downloadSubtitles = true
            next.autoSubtitles = true
        }
        settings = next
        advancedSelections = [:]
        customArguments = ""
        notice = "Applied “\(preset.title)”."
        page = .download
    }

    func savePreset(named name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        presets.insert(
            CustomPreset(
                id: UUID(),
                name: cleanName,
                createdAt: Date(),
                settings: settings,
                advancedSelections: safeSelections(advancedSelections),
                customArguments: safeCustomArguments(customArguments)
            ),
            at: 0
        )
        notice = "Saved preset “\(cleanName)”."
    }

    func apply(_ preset: CustomPreset) {
        var next = preset.settings
        next.outputDirectory = settings.outputDirectory
        settings = next
        advancedSelections = preset.advancedSelections
        customArguments = preset.customArguments
        notice = "Applied “\(preset.name)”."
        page = .download
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
    }

    func addChannel(
        url: String,
        interval: ChannelCheckInterval,
        maxDownloadsPerCheck: Int,
        mediaMode: MediaMode,
        videoQuality: VideoQuality,
        videoContainer: VideoContainer,
        audioFormat: AudioFormat,
        downloadNewestNow: Bool
    ) {
        channelAddError = nil
        guard let normalized = normalizedChannelURL(url) else {
            channelAddError = ChannelMonitorError.invalidURL.localizedDescription
            return
        }
        guard !channelSubscriptions.contains(where: { normalizedComparableURL($0.channelURL) == normalizedComparableURL(normalized) }) else {
            channelAddError = ChannelMonitorError.duplicate.localizedDescription
            return
        }
        guard let executablePath = tools.ytDLP.path else {
            channelAddError = ChannelMonitorError.missingEngine.localizedDescription
            return
        }

        var channelSettings = settings
        channelSettings.mediaMode = mediaMode
        channelSettings.videoQuality = videoQuality
        channelSettings.videoContainer = videoContainer
        channelSettings.audioFormat = audioFormat
        channelSettings.includePlaylist = false
        channelSettings.useDownloadArchive = true
        let subscription = ChannelSubscription(
            channelURL: normalized,
            interval: interval,
            maxDownloadsPerCheck: maxDownloadsPerCheck,
            settings: channelSettings
        )
        channelSubscriptions.insert(subscription, at: 0)
        checkingChannelIDs.insert(subscription.id)

        channelMonitor.fetchLatest(
            executable: URL(fileURLWithPath: executablePath),
            channelURL: normalized,
            limit: 25,
            preferences: preferences,
            javaScriptRuntimePath: tools.javaScriptRuntime.path
        ) { [weak self] result in
            guard let self else { return }
            checkingChannelIDs.remove(subscription.id)
            guard let index = channelSubscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
            switch result {
            case let .success(probe):
                channelSubscriptions[index].displayName = probe.channelName
                channelSubscriptions[index].settings.outputDirectory = ChannelOutputFolder.path(
                    baseDirectory: channelSubscriptions[index].settings.outputDirectory,
                    channelName: probe.channelName
                )
                do {
                    try FileManager.default.createDirectory(
                        at: URL(fileURLWithPath: channelSubscriptions[index].settings.outputDirectory, isDirectory: true),
                        withIntermediateDirectories: true
                    )
                } catch {
                    channelSubscriptions[index].lastStatus = "Could not create the channel folder"
                    channelAddError = "Could not create the channel folder: \(error.localizedDescription)"
                    return
                }
                channelSubscriptions[index].knownVideoIDs = Array(probe.videos.map(\.id).prefix(500))
                channelSubscriptions[index].lastCheckedAt = Date()
                channelSubscriptions[index].lastStatus = "Ready · watching for new uploads"
                if downloadNewestNow, let newest = probe.videos.first {
                    enqueue(videos: [newest], from: channelSubscriptions[index])
                    channelSubscriptions[index].lastDownloadAt = Date()
                    channelSubscriptions[index].lastStatus = "Newest video added to Downloads"
                    startQueue()
                }
                notice = "Now monitoring \(probe.channelName)."
            case let .failure(error):
                channelSubscriptions.remove(at: index)
                channelAddError = error.localizedDescription
            }
        }
    }

    func checkAllChannels() {
        for id in channelSubscriptions.filter(\.enabled).map(\.id) {
            checkChannel(id: id, force: true)
        }
    }

    func checkChannel(id: UUID, force: Bool) {
        guard !checkingChannelIDs.contains(id),
              let index = channelSubscriptions.firstIndex(where: { $0.id == id }),
              channelSubscriptions[index].enabled,
              let executablePath = tools.ytDLP.path else { return }
        if !force, let lastCheck = channelSubscriptions[index].lastCheckedAt,
           Date().timeIntervalSince(lastCheck) < channelSubscriptions[index].interval.seconds { return }

        let snapshot = channelSubscriptions[index]
        checkingChannelIDs.insert(id)
        channelSubscriptions[index].lastStatus = "Checking for uploads…"
        channelMonitor.fetchLatest(
            executable: URL(fileURLWithPath: executablePath),
            channelURL: snapshot.channelURL,
            limit: max(25, snapshot.maxDownloadsPerCheck * 4),
            preferences: preferences,
            javaScriptRuntimePath: tools.javaScriptRuntime.path
        ) { [weak self] result in
            guard let self else { return }
            checkingChannelIDs.remove(id)
            guard let currentIndex = channelSubscriptions.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case let .success(probe):
                let known = Set(channelSubscriptions[currentIndex].knownVideoIDs)
                let establishingBaseline = channelSubscriptions[currentIndex].lastCheckedAt == nil && known.isEmpty
                let unseen = establishingBaseline ? [] : probe.videos.filter { !known.contains($0.id) }
                let selected = Array(unseen.prefix(channelSubscriptions[currentIndex].maxDownloadsPerCheck))
                channelSubscriptions[currentIndex].displayName = probe.channelName
                channelSubscriptions[currentIndex].knownVideoIDs = mergedKnownIDs(
                    newest: establishingBaseline ? probe.videos.map(\.id) : selected.map(\.id),
                    existing: channelSubscriptions[currentIndex].knownVideoIDs
                )
                channelSubscriptions[currentIndex].lastCheckedAt = Date()
                if establishingBaseline {
                    channelSubscriptions[currentIndex].lastStatus = "Ready · watching for new uploads"
                } else if selected.isEmpty {
                    channelSubscriptions[currentIndex].lastStatus = "Up to date · no new uploads"
                } else {
                    let source = channelSubscriptions[currentIndex]
                    enqueue(videos: selected, from: source)
                    channelSubscriptions[currentIndex].lastDownloadAt = Date()
                    channelSubscriptions[currentIndex].lastStatus = "Added \(selected.count) new upload\(selected.count == 1 ? "" : "s")"
                    startQueue()
                }
            case let .failure(error):
                channelSubscriptions[currentIndex].lastCheckedAt = Date()
                channelSubscriptions[currentIndex].lastStatus = "Check failed: \(error.localizedDescription)"
            }
        }
    }

    func removeChannel(id: UUID) {
        channelSubscriptions.removeAll { $0.id == id }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
            launchAtLoginError = nil
            if enabled && !launchAtLoginEnabled {
                launchAtLoginError = "macOS needs approval in System Settings → General → Login Items."
            }
        } catch {
            launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }

    func updateChannel(_ updated: ChannelSubscription) {
        guard let index = channelSubscriptions.firstIndex(where: { $0.id == updated.id }) else { return }
        channelSubscriptions[index] = updated
    }

    private func checkDueChannels() {
        guard preferences.autoChannelMonitoringEnabled, tools.ytDLP.isAvailable else { return }
        for id in channelSubscriptions.filter(\.enabled).map(\.id) {
            checkChannel(id: id, force: false)
        }
    }

    private func enqueue(videos: [ChannelVideo], from subscription: ChannelSubscription) {
        for video in videos.reversed() {
            var job = DownloadJob(
                url: video.url,
                settings: subscription.settings,
                advancedSelections: [:],
                customArguments: "",
                sourceSubscriptionID: subscription.id,
                sourceLabel: subscription.displayName
            )
            job.title = video.title
            jobs.insert(job, at: 0)
        }
        persistJobs()
    }

    private func normalizedChannelURL(_ value: String) -> String? {
        ChannelURLNormalizer.videosURL(from: value)
    }

    private func normalizedComparableURL(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func mergedKnownIDs(newest: [String], existing: [String]) -> [String] {
        var seen = Set<String>()
        return (newest + existing).filter { seen.insert($0).inserted }.prefix(500).map { $0 }
    }

    private func parsedInputs() -> [String] {
        let text = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            let links = detector.matches(in: text, options: [], range: range).compactMap { $0.url?.absoluteString }
            if !links.isEmpty { return Array(NSOrderedSet(array: links)) as? [String] ?? links }
        }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func startNextQueuedJob() {
        let nextIndex = jobs.indices
            .filter { jobs[$0].state == .queued }
            .min { jobs[$0].createdAt < jobs[$1].createdAt }
        guard currentJobID == nil,
              let executablePath = tools.ytDLP.path,
              let index = nextIndex else { return }

        let jobID = jobs[index].id
        let outputURL = URL(fileURLWithPath: jobs[index].settings.outputDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        } catch {
            jobs[index].state = .failed
            jobs[index].statusMessage = "Could not create the destination folder: \(error.localizedDescription)"
            persistJobs()
            startNextQueuedJob()
            return
        }

        let plan = ArgumentCompiler.makePlan(
            url: jobs[index].url,
            settings: jobs[index].settings,
            preferences: preferences,
            ffmpegPath: tools.ffmpeg.path,
            javaScriptRuntimePath: tools.javaScriptRuntime.path,
            catalog: catalog,
            selections: jobs[index].advancedSelections,
            customArguments: jobs[index].customArguments
        )
        jobs[index].state = .running
        jobs[index].statusMessage = "Connecting…"
        jobs[index].logLines = plan.warnings
        currentJobID = jobID
        persistJobs()

        do {
            try runner.start(
                executable: URL(fileURLWithPath: executablePath),
                arguments: plan.arguments,
                workingDirectory: outputURL,
                onEvent: { [weak self] event in self?.handle(event, for: jobID) },
                onCompletion: { [weak self] code in self?.finish(jobID: jobID, exitCode: code) }
            )
        } catch {
            jobs[index].state = .failed
            jobs[index].statusMessage = error.localizedDescription
            currentJobID = nil
            persistJobs()
            startNextQueuedJob()
        }
    }

    private func handle(_ event: DownloadEvent, for jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        guard ![.completed, .failed, .cancelled, .interrupted].contains(jobs[index].state) else { return }
        switch event {
        case let .progress(fraction, speed, eta):
            if let fraction { jobs[index].progress = max(jobs[index].progress, fraction) }
            jobs[index].speed = speed ?? jobs[index].speed
            jobs[index].eta = eta ?? jobs[index].eta
            jobs[index].statusMessage = "Downloading"
        case .postprocessing:
            jobs[index].state = .postprocessing
            jobs[index].statusMessage = "Merging and finishing the file…"
        case let .title(title):
            jobs[index].title = title
        case let .outputFile(path):
            jobs[index].outputPath = path
        case let .log(line):
            guard !line.isEmpty else { return }
            jobs[index].logLines.append(line)
            if jobs[index].logLines.count > 250 {
                jobs[index].logLines.removeFirst(jobs[index].logLines.count - 250)
            }
        }
    }

    private func finish(jobID: UUID, exitCode: Int32) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            currentJobID = nil
            startNextQueuedJob()
            return
        }
        if jobs[index].state == .cancelled {
            jobs[index].statusMessage = "Stopped. Partial files are kept so Retry can resume."
        } else if exitCode == 0 {
            jobs[index].state = .completed
            jobs[index].progress = 1
            jobs[index].statusMessage = "Saved successfully"
        } else {
            jobs[index].state = .failed
            jobs[index].statusMessage = jobs[index].logLines.last ?? "yt-dlp stopped with exit code \(exitCode)."
        }
        currentJobID = nil
        persistJobs()
        startNextQueuedJob()
    }

    private func chooseExecutable(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func safeSelections(_ value: [String: AdvancedSelection]) -> [String: AdvancedSelection] {
        var sensitive = Set(catalog.allOptions.filter(\.isSensitive).map(\.id))
        sensitive.formUnion(["--username", "--ap-username", "--twofactor"])
        return value.filter { !sensitive.contains($0.key) }
    }

    private func persistSafeAdvancedSelections() {
        persist(safeSelections(advancedSelections), key: Keys.advanced)
    }

    private func persistJobs() {
        var safeJobs = jobs
        for index in safeJobs.indices {
            safeJobs[index].advancedSelections = safeSelections(safeJobs[index].advancedSelections)
            safeJobs[index].customArguments = safeCustomArguments(safeJobs[index].customArguments)
        }
        persist(safeJobs, key: Keys.jobs)
    }

    private func safeCustomArguments(_ value: String) -> String {
        // Raw arguments may contain headers, cookies, tokens, or credentials in
        // forms the app cannot reliably classify. They are session-only.
        ""
    }

    private static func requiresFFmpeg(_ settings: DownloadSettings) -> Bool {
        settings.mediaMode != .original || settings.embedMetadata || settings.embedThumbnail || settings.embedChapters
    }

    static func migratedChannelSubscriptions(_ subscriptions: [ChannelSubscription]) -> [ChannelSubscription] {
        subscriptions.map { original in
            var subscription = original
            let normalizedURL = ChannelURLNormalizer.videosURL(from: subscription.channelURL)
            let containsNonVideoIDs = subscription.knownVideoIDs.contains { !YouTubeVideoID.isValid($0) }
            let urlChanged = normalizedURL != nil && normalizedURL != subscription.channelURL

            if let normalizedURL { subscription.channelURL = normalizedURL }
            if urlChanged || containsNonVideoIDs {
                // Previous versions could interpret the channel root's tab IDs
                // as videos. Reset to a fresh baseline without queuing anything.
                subscription.knownVideoIDs = []
                subscription.lastCheckedAt = nil
                subscription.lastStatus = "Resetting safely · old uploads will be skipped"
            }

            if subscription.displayName != "Checking channel…" {
                subscription.settings.outputDirectory = ChannelOutputFolder.path(
                    baseDirectory: subscription.settings.outputDirectory,
                    channelName: subscription.displayName
                )
            }
            subscription.settings.includePlaylist = false
            subscription.settings.useDownloadArchive = true
            return subscription
        }
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func restore<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private enum Keys {
        static let settings = "downloadSettings.v1"
        static let preferences = "toolPreferences.v1"
        static let advanced = "advancedSelections.v1"
        static let jobs = "downloadJobs.v1"
        static let presets = "customPresets.v1"
        static let channels = "channelSubscriptions.v1"
    }
}
