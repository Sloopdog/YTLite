import Foundation

enum AppPage: String, CaseIterable, Identifiable {
    case download
    case channels
    case advanced
    case presets
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: "Downloads"
        case .channels: "Auto Channels"
        case .advanced: "All Options"
        case .presets: "Presets"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .download: "arrow.down.circle.fill"
        case .channels: "dot.radiowaves.left.and.right"
        case .advanced: "switch.2"
        case .presets: "square.stack.3d.up.fill"
        case .settings: "gearshape.fill"
        }
    }
}

enum MediaMode: String, Codable, CaseIterable, Identifiable {
    case video
    case audio
    case original

    var id: String { rawValue }
    var title: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio only"
        case .original: "Original"
        }
    }
    var detail: String {
        switch self {
        case .video: "Best picture and sound"
        case .audio: "Music or spoken audio"
        case .original: "Minimal conversion"
        }
    }
    var icon: String {
        switch self {
        case .video: "play.rectangle.fill"
        case .audio: "waveform"
        case .original: "shippingbox.fill"
        }
    }
}

enum VideoQuality: String, Codable, CaseIterable, Identifiable {
    case best
    case ultraHD
    case fullHD
    case hd
    case compact

    var id: String { rawValue }
    var title: String {
        switch self {
        case .best: "Best available"
        case .ultraHD: "Up to 4K"
        case .fullHD: "Up to 1080p"
        case .hd: "Up to 720p"
        case .compact: "Up to 480p"
        }
    }
    var heightLimit: Int? {
        switch self {
        case .best: nil
        case .ultraHD: 2160
        case .fullHD: 1080
        case .hd: 720
        case .compact: 480
        }
    }
}

enum VideoContainer: String, Codable, CaseIterable, Identifiable {
    case automatic
    case mp4
    case mkv
    case webm

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic (best quality)"
        case .mp4: "MP4 (most compatible)"
        case .mkv: "MKV"
        case .webm: "WebM"
        }
    }
}

enum AudioFormat: String, Codable, CaseIterable, Identifiable {
    case mp3
    case m4a
    case flac
    case wav
    case opus
    case best

    var id: String { rawValue }
    var title: String { rawValue == "best" ? "Best available" : rawValue.uppercased() }
}

enum CookieBrowser: String, Codable, CaseIterable, Identifiable {
    case none
    case safari
    case chrome
    case firefox
    case edge
    case brave

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .firefox: "Firefox"
        case .edge: "Microsoft Edge"
        case .brave: "Brave"
        }
    }
}

enum UpdateChannel: String, Codable, CaseIterable, Identifiable {
    case nightly
    case stable

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var detail: String {
        switch self {
        case .nightly: "Recommended by yt-dlp for regular use"
        case .stable: "Monthly, more conservative releases"
        }
    }
}

struct DownloadSettings: Codable, Equatable {
    var outputDirectory: String
    var mediaMode: MediaMode = .video
    var videoQuality: VideoQuality = .best
    var videoContainer: VideoContainer = .automatic
    var audioFormat: AudioFormat = .mp3
    var filenameTemplate = "%(title).180B [%(id)s].%(ext)s"
    var includePlaylist = false
    var embedMetadata = true
    var embedThumbnail = true
    var embedChapters = true
    var downloadSubtitles = false
    var autoSubtitles = false
    var subtitleLanguages = "en.*"
    var sponsorBlock = false
    var cookieBrowser: CookieBrowser = .none
    var concurrentFragments = 4
    var speedLimit = ""
    var useDownloadArchive = false

    static var standard: DownloadSettings {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        return DownloadSettings(outputDirectory: downloads.appendingPathComponent("YTLite").path)
    }
}

struct ToolPreferences: Codable, Equatable {
    var customYTDLPPath = ""
    var customFFmpegPath = ""
    var useUserConfiguration = false
    var updateChannel: UpdateChannel = .stable
    var autoChannelMonitoringEnabled = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        customYTDLPPath = try container.decodeIfPresent(String.self, forKey: .customYTDLPPath) ?? ""
        customFFmpegPath = try container.decodeIfPresent(String.self, forKey: .customFFmpegPath) ?? ""
        useUserConfiguration = try container.decodeIfPresent(Bool.self, forKey: .useUserConfiguration) ?? false
        updateChannel = try container.decodeIfPresent(UpdateChannel.self, forKey: .updateChannel) ?? .stable
        autoChannelMonitoringEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoChannelMonitoringEnabled) ?? true
    }
}

enum ChannelCheckInterval: Int, Codable, CaseIterable, Identifiable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case hourly = 60
    case threeHours = 180
    case sixHours = 360
    case twelveHours = 720
    case daily = 1440

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    var title: String {
        switch self {
        case .fifteenMinutes: "Every 15 minutes"
        case .thirtyMinutes: "Every 30 minutes"
        case .hourly: "Every hour"
        case .threeHours: "Every 3 hours"
        case .sixHours: "Every 6 hours"
        case .twelveHours: "Every 12 hours"
        case .daily: "Daily"
        }
    }
}

struct ChannelVideo: Identifiable, Equatable {
    var id: String
    var title: String
    var url: String
}

struct ChannelProbeResult: Equatable {
    var channelName: String
    var videos: [ChannelVideo]
}

struct ChannelSubscription: Identifiable, Codable, Equatable {
    let id: UUID
    var channelURL: String
    var displayName: String
    var createdAt: Date
    var enabled: Bool
    var interval: ChannelCheckInterval
    var maxDownloadsPerCheck: Int
    var lastCheckedAt: Date?
    var lastDownloadAt: Date?
    var lastStatus: String
    var knownVideoIDs: [String]
    var settings: DownloadSettings

    init(
        channelURL: String,
        displayName: String = "Checking channel…",
        interval: ChannelCheckInterval,
        maxDownloadsPerCheck: Int,
        settings: DownloadSettings
    ) {
        id = UUID()
        self.channelURL = channelURL
        self.displayName = displayName
        createdAt = Date()
        enabled = true
        self.interval = interval
        self.maxDownloadsPerCheck = maxDownloadsPerCheck
        lastCheckedAt = nil
        lastDownloadAt = nil
        lastStatus = "Establishing a starting point…"
        knownVideoIDs = []
        self.settings = settings
    }
}

struct AdvancedSelection: Codable, Equatable {
    var enabled = false
    var value = ""
}

enum JobState: String, Codable {
    case queued
    case running
    case postprocessing
    case completed
    case failed
    case cancelled
    case interrupted

    var title: String {
        switch self {
        case .queued: "Queued"
        case .running: "Downloading"
        case .postprocessing: "Finishing"
        case .completed: "Complete"
        case .failed: "Needs attention"
        case .cancelled: "Cancelled"
        case .interrupted: "Interrupted"
        }
    }

    var symbol: String {
        switch self {
        case .queued: "clock"
        case .running: "arrow.down.circle.fill"
        case .postprocessing: "wand.and.stars"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        case .interrupted: "pause.circle.fill"
        }
    }
}

struct DownloadJob: Identifiable, Codable, Equatable {
    let id: UUID
    var url: String
    var title: String
    var createdAt: Date
    var state: JobState
    var progress: Double
    var speed: String
    var eta: String
    var outputPath: String?
    var statusMessage: String
    var logLines: [String]
    var settings: DownloadSettings
    var advancedSelections: [String: AdvancedSelection]
    var customArguments: String
    var sourceSubscriptionID: UUID?
    var sourceLabel: String?

    init(
        url: String,
        settings: DownloadSettings,
        advancedSelections: [String: AdvancedSelection],
        customArguments: String,
        sourceSubscriptionID: UUID? = nil,
        sourceLabel: String? = nil
    ) {
        id = UUID()
        self.url = url
        title = URL(string: url)?.host ?? url
        createdAt = Date()
        state = .queued
        progress = 0
        speed = ""
        eta = ""
        outputPath = nil
        statusMessage = "Waiting to start"
        logLines = []
        self.settings = settings
        self.advancedSelections = advancedSelections
        self.customArguments = customArguments
        self.sourceSubscriptionID = sourceSubscriptionID
        self.sourceLabel = sourceLabel
    }
}

struct CustomPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var settings: DownloadSettings
    var advancedSelections: [String: AdvancedSelection]
    var customArguments: String
}

enum BuiltInPreset: String, CaseIterable, Identifiable {
    case bestVideo
    case compatibleMP4
    case musicMP3
    case audioM4A
    case original
    case subtitled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bestVideo: "Best video"
        case .compatibleMP4: "Compatible MP4"
        case .musicMP3: "Music MP3"
        case .audioM4A: "Audio M4A"
        case .original: "Original files"
        case .subtitled: "Video + subtitles"
        }
    }
    var detail: String {
        switch self {
        case .bestVideo: "Highest available quality"
        case .compatibleMP4: "1080p MP4 for most devices"
        case .musicMP3: "High-quality MP3 audio"
        case .audioM4A: "Efficient M4A audio"
        case .original: "Avoid format conversion"
        case .subtitled: "Video with English captions"
        }
    }
    var icon: String {
        switch self {
        case .bestVideo: "sparkles.tv.fill"
        case .compatibleMP4: "play.square.stack.fill"
        case .musicMP3: "music.note"
        case .audioM4A: "waveform.circle.fill"
        case .original: "shippingbox.fill"
        case .subtitled: "captions.bubble.fill"
        }
    }
}

struct DependencyStatus: Equatable {
    var name: String
    var path: String?
    var version: String?

    var isAvailable: Bool { path != nil }
}

struct ToolsStatus: Equatable {
    var ytDLP = DependencyStatus(name: "yt-dlp")
    var ffmpeg = DependencyStatus(name: "FFmpeg")
    var javaScriptRuntime = DependencyStatus(name: "JavaScript runtime")
    var isRefreshing = true
}
