import SwiftUI
import UniformTypeIdentifiers

struct DownloadView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showCommand = false
    @State private var isDropTarget = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "New download",
                    title: "What should we save?",
                    detail: "Paste one link or a whole list. YTLite handles the command line for you."
                )

                if !model.tools.ytDLP.isAvailable {
                    InfoBanner(
                        text: "yt-dlp needs a quick one-time setup before the first download.",
                        kind: .warning,
                        actionTitle: "Set Up",
                        action: { model.page = .settings }
                    )
                } else if model.catalogVersionMismatch {
                    InfoBanner(
                        text: "The option catalog is for yt-dlp \(model.catalog.ytDlpVersion), while \(model.tools.ytDLP.version ?? "another version") is installed.",
                        kind: .info,
                        actionTitle: "Update",
                        action: { model.page = .settings }
                    )
                }

                urlPanel
                formatPanel
                destinationPanel
                extrasPanel
                actionBar

                if !model.jobs.isEmpty { queuePanel }
                commandPanel
            }
            .padding(.horizontal, 28)
            .padding(.top, 42)
            .padding(.bottom, 34)
            .frame(maxWidth: 1040, alignment: .leading)
        }
        .background(
            LinearGradient(
                colors: [AppTheme.navy.opacity(0.10), Color.clear],
                startPoint: .topTrailing,
                endPoint: .center
            )
        )
    }

    private var urlPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    SectionTitle("Media links", detail: "One per line", icon: "link")
                    Button("Paste", systemImage: "doc.on.clipboard") { model.pasteURL() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    if !model.urlInput.isEmpty {
                        Button("Clear") { model.urlInput = "" }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .controlSize(.small)
                    }
                }

                ZStack(alignment: .topLeading) {
                    if model.urlInput.isEmpty {
                        Text("Paste a video, playlist, channel, or audio link…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 11)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $model.urlInput)
                        .font(.system(.body, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(minHeight: 78, maxHeight: 120)
                }
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(isDropTarget ? AppTheme.accent : Color.primary.opacity(0.10), lineWidth: isDropTarget ? 2 : 1)
                }
                .onDrop(of: [UTType.url, UTType.plainText], isTargeted: $isDropTarget) { providers in
                    for provider in providers {
                        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                            let text: String?
                            if let data = item as? Data { text = String(data: data, encoding: .utf8) }
                            else { text = item as? String }
                            if let text {
                                DispatchQueue.main.async {
                                    model.urlInput += (model.urlInput.isEmpty ? "" : "\n") + text
                                }
                            }
                        }
                    }
                    return true
                }
            }
        }
    }

    private var formatPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Save as", detail: "Choose the result you want", icon: "slider.horizontal.3")
                HStack(spacing: 10) {
                    ForEach(MediaMode.allCases) { mode in
                        ModeCard(mode: mode, selected: model.settings.mediaMode == mode) {
                            model.settings.mediaMode = mode
                        }
                    }
                }

                Divider()
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    if model.settings.mediaMode == .video {
                        GridRow {
                            settingLabel("Quality", icon: "4k.tv")
                            Picker("", selection: $model.settings.videoQuality) {
                                ForEach(VideoQuality.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            settingLabel("Container", icon: "shippingbox")
                            Picker("", selection: $model.settings.videoContainer) {
                                ForEach(VideoContainer.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                        }
                    } else if model.settings.mediaMode == .audio {
                        GridRow {
                            settingLabel("Audio format", icon: "waveform")
                            Picker("", selection: $model.settings.audioFormat) {
                                ForEach(AudioFormat.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            settingLabel("Cover art", icon: "photo")
                            Toggle("Embed thumbnail", isOn: $model.settings.embedThumbnail)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    } else {
                        GridRow {
                            Text("YTLite will keep the site's preferred streams and avoid unnecessary format conversion.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .gridCellColumns(4)
                        }
                    }
                }
            }
        }
    }

    private var destinationPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 13) {
                SectionTitle("Destination", icon: "folder.fill")
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.cyan)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(URL(fileURLWithPath: model.settings.outputDirectory).lastPathComponent)
                            .font(.headline)
                        Text(model.settings.outputDirectory)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Show") { model.openOutputFolder() }.buttonStyle(.bordered)
                    Button("Choose…") { model.chooseOutputFolder() }.buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var extrasPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Helpful extras", detail: "Plain-language shortcuts", icon: "sparkles")
                Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 13) {
                    GridRow {
                        Toggle("Embed title and metadata", isOn: $model.settings.embedMetadata)
                        Toggle("Embed cover thumbnail", isOn: $model.settings.embedThumbnail)
                    }
                    GridRow {
                        Toggle("Keep chapter markers", isOn: $model.settings.embedChapters)
                        Toggle("Download full playlists", isOn: $model.settings.includePlaylist)
                    }
                    GridRow {
                        Toggle("Download subtitles", isOn: $model.settings.downloadSubtitles)
                        Toggle("Remove sponsored segments", isOn: $model.settings.sponsorBlock)
                    }
                    GridRow {
                        Toggle("Remember downloaded items", isOn: $model.settings.useDownloadArchive)
                        HStack {
                            Text("Browser cookies")
                            Spacer()
                            Picker("", selection: $model.settings.cookieBrowser) {
                                ForEach(CookieBrowser.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 160)
                        }
                    }
                }
                .toggleStyle(.switch)

                if model.settings.downloadSubtitles {
                    HStack(spacing: 12) {
                        Text("Subtitle languages")
                        TextField("en.*,es", text: $model.settings.subtitleLanguages)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Include auto-generated", isOn: $model.settings.autoSubtitles)
                            .toggleStyle(.checkbox)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("More options", systemImage: "switch.2") { model.page = .advanced }
                .buttonStyle(.bordered)
            Spacer()
            Button("Add to Queue", systemImage: "text.badge.plus") {
                model.addToQueue(startImmediately: false)
            }
            .buttonStyle(.bordered)
            .disabled(model.firstInput == nil)

            Button("Download Now", systemImage: "arrow.down.circle.fill") {
                model.addToQueue(startImmediately: true)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.firstInput == nil)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var queuePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Queue", detail: "\(model.jobs.count) item\(model.jobs.count == 1 ? "" : "s")", icon: "list.bullet.rectangle")
                    if model.jobs.contains(where: { $0.state == .queued }) && !model.isDownloading {
                        Button("Start", systemImage: "play.fill") { model.startQueue() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    Button("Clear Finished") { model.clearFinished() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .controlSize(.small)
                }
                VStack(spacing: 8) {
                    ForEach(model.jobs) { job in
                        JobRow(job: job)
                    }
                }
            }
        }
    }

    private var commandPanel: some View {
        DisclosureGroup(isExpanded: $showCommand) {
            ScrollView(.horizontal) {
                Text(model.commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .padding(.top, 8)
        } label: {
            Label("Command preview", systemImage: "terminal")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func settingLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

private struct JobRow: View {
    @EnvironmentObject private var model: AppModel
    let job: DownloadJob
    @State private var showLog = false

    private var stateColor: Color {
        switch job.state {
        case .completed: AppTheme.accent
        case .failed: .red
        case .cancelled, .interrupted: .orange
        case .running, .postprocessing: AppTheme.cyan
        case .queued: .secondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: job.state.symbol)
                    .font(.title3)
                    .foregroundStyle(stateColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(job.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let source = job.sourceLabel {
                        Label("Auto · \(source)", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.accent)
                            .lineLimit(1)
                    }
                    if [.running, .postprocessing].contains(job.state) {
                        ProgressView(value: job.progress)
                            .progressViewStyle(.linear)
                            .tint(AppTheme.accent)
                    }
                }
                Spacer(minLength: 10)
                if !job.speed.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(job.speed).font(.caption.monospacedDigit())
                        if !job.eta.isEmpty { Text("ETA \(job.eta)").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                jobActions
            }
            .padding(11)

            if showLog {
                Divider()
                ScrollView {
                    Text(job.logLines.joined(separator: "\n"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(maxHeight: 150)
                .background(Color.black.opacity(0.10))
            }
        }
        .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.07)) }
        .contextMenu {
            if [.failed, .cancelled, .interrupted].contains(job.state) {
                Button("Retry") { model.retry(jobID: job.id) }
            }
            Button("Reveal in Finder") { model.reveal(jobID: job.id) }
            if job.state != .running && job.state != .postprocessing {
                Button("Remove", role: .destructive) { model.remove(jobID: job.id) }
            }
        }
    }

    @ViewBuilder
    private var jobActions: some View {
        if [.running, .postprocessing, .queued].contains(job.state) {
            Button {
                model.cancel(jobID: job.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Cancel")
        } else if [.failed, .cancelled, .interrupted].contains(job.state) {
            Button {
                model.retry(jobID: job.id)
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.cyan)
            .help("Retry")
        } else if job.state == .completed {
            Button {
                model.reveal(jobID: job.id)
            } label: {
                Image(systemName: "folder.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .help("Reveal in Finder")
        }

        if !job.logLines.isEmpty {
            Button {
                withAnimation { showLog.toggle() }
            } label: {
                Image(systemName: showLog ? "chevron.up.circle" : "ellipsis.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Show log")
        }
    }
}
