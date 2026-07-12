import SwiftUI

struct ChannelSubscriptionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var channelURL = ""
    @State private var interval: ChannelCheckInterval = .hourly
    @State private var maxDownloads = 3
    @State private var mediaMode: MediaMode = .video
    @State private var videoQuality: VideoQuality = .fullHD
    @State private var videoContainer: VideoContainer = .mp4
    @State private var audioFormat: AudioFormat = .mp3
    @State private var downloadNewestNow = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "Automatic downloads",
                    title: "Follow your channels",
                    detail: "YTLite checks for new uploads and adds them to Downloads automatically.",
                    trailing: AnyView(
                        Button("Check All Now", systemImage: "arrow.clockwise") { model.checkAllChannels() }
                            .buttonStyle(.bordered)
                            .disabled(model.channelSubscriptions.isEmpty || !model.tools.ytDLP.isAvailable)
                    )
                )

                InfoBanner(
                    text: "YTLite records what is already on a channel when you add it, so old videos are not downloaded. Monitoring runs while YTLite is open; Launch at Login is available in Settings.",
                    kind: .info
                )

                addPanel

                if model.channelSubscriptions.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(model.channelSubscriptions) { subscription in
                            ChannelSubscriptionCard(
                                subscription: subscription,
                                isChecking: model.checkingChannelIDs.contains(subscription.id),
                                onUpdate: model.updateChannel,
                                onCheck: { model.checkChannel(id: subscription.id, force: true) },
                                onRemove: { model.removeChannel(id: subscription.id) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 42)
            .padding(.bottom, 34)
            .frame(maxWidth: 1040, alignment: .leading)
        }
        .background(
            LinearGradient(colors: [AppTheme.cyan.opacity(0.09), .clear], startPoint: .topTrailing, endPoint: .center)
        )
    }

    private var addPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Add a YouTube channel", detail: "The /videos page is best if you do not want Shorts or live streams", icon: "plus.circle.fill")
                TextField("https://www.youtube.com/@channel/videos", text: $channelURL)
                    .textFieldStyle(.roundedBorder)

                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 12) {
                    GridRow {
                        label("Check", icon: "clock")
                        Picker("", selection: $interval) {
                            ForEach(ChannelCheckInterval.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden()
                        label("Save as", icon: "square.and.arrow.down")
                        Picker("", selection: $mediaMode) {
                            ForEach(MediaMode.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden()
                    }
                    GridRow {
                        label("New videos per check", icon: "number")
                        Picker("", selection: $maxDownloads) {
                            ForEach([1, 3, 5, 10], id: \.self) { Text("Up to \($0)").tag($0) }
                        }.labelsHidden()
                        if mediaMode == .video {
                            label("Quality", icon: "4k.tv")
                            Picker("", selection: $videoQuality) {
                                ForEach(VideoQuality.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                        } else if mediaMode == .audio {
                            label("Audio format", icon: "waveform")
                            Picker("", selection: $audioFormat) {
                                ForEach(AudioFormat.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                        } else {
                            Text("Keeps the original format").font(.caption).foregroundStyle(.secondary).gridCellColumns(2)
                        }
                    }
                    if mediaMode == .video {
                        GridRow {
                            label("Container", icon: "shippingbox")
                            Picker("", selection: $videoContainer) {
                                ForEach(VideoContainer.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                            Text("Uses your current extras and saves to \(URL(fileURLWithPath: model.settings.outputDirectory).lastPathComponent)")
                                .font(.caption).foregroundStyle(.secondary).gridCellColumns(2)
                        }
                    }
                }

                HStack {
                    Toggle("Also download the newest video now", isOn: $downloadNewestNow)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button("Add Channel", systemImage: "plus") {
                        model.addChannel(
                            url: channelURL,
                            interval: interval,
                            maxDownloadsPerCheck: maxDownloads,
                            mediaMode: mediaMode,
                            videoQuality: videoQuality,
                            videoContainer: videoContainer,
                            audioFormat: audioFormat,
                            downloadNewestNow: downloadNewestNow
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(channelURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.tools.ytDLP.isAvailable)
                }
                if let error = model.channelAddError {
                    InfoBanner(text: error, kind: .warning)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 34)).foregroundStyle(AppTheme.accent)
            Text("No channels yet").font(.title3.weight(.semibold))
            Text("Add a channel above and YTLite will watch for its next upload.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 42)
    }

    private func label(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.callout.weight(.medium)).foregroundStyle(.secondary)
    }
}

private struct ChannelSubscriptionCard: View {
    let subscription: ChannelSubscription
    let isChecking: Bool
    let onUpdate: (ChannelSubscription) -> Void
    let onCheck: () -> Void
    let onRemove: () -> Void
    @State private var confirmRemove = false

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2).foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(subscription.displayName).font(.headline)
                        Text(subscription.channelURL).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if isChecking { ProgressView().controlSize(.small) }
                    Toggle("", isOn: Binding(
                        get: { subscription.enabled },
                        set: { value in var copy = subscription; copy.enabled = value; onUpdate(copy) }
                    )).labelsHidden().toggleStyle(.switch)
                }

                Divider()
                HStack(spacing: 14) {
                    Label(subscription.lastStatus, systemImage: isChecking ? "arrow.clockwise" : "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { subscription.interval },
                        set: { value in var copy = subscription; copy.interval = value; onUpdate(copy) }
                    )) {
                        ForEach(ChannelCheckInterval.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 170)
                    Picker("", selection: Binding(
                        get: { subscription.maxDownloadsPerCheck },
                        set: { value in var copy = subscription; copy.maxDownloadsPerCheck = value; onUpdate(copy) }
                    )) {
                        ForEach([1, 3, 5, 10], id: \.self) { Text("Max \($0)").tag($0) }
                    }.labelsHidden().frame(width: 82)
                    Button("Check Now", action: onCheck).buttonStyle(.bordered).disabled(isChecking || !subscription.enabled)
                    Button(role: .destructive) { confirmRemove = true } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered)
                }

                HStack(spacing: 18) {
                    Label(formatDescription, systemImage: subscription.settings.mediaMode.icon)
                    Label(URL(fileURLWithPath: subscription.settings.outputDirectory).lastPathComponent, systemImage: "folder")
                    if let last = subscription.lastCheckedAt {
                        Label("Checked \(last.formatted(.relative(presentation: .named)))", systemImage: "clock")
                    }
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .confirmationDialog("Stop monitoring \(subscription.displayName)?", isPresented: $confirmRemove) {
            Button("Remove Channel", role: .destructive, action: onRemove)
        }
    }

    private var formatDescription: String {
        switch subscription.settings.mediaMode {
        case .video: "\(subscription.settings.videoQuality.title) · \(subscription.settings.videoContainer.title)"
        case .audio: "\(subscription.settings.audioFormat.title) audio"
        case .original: "Original format"
        }
    }
}
