import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "App setup",
                    title: "Settings",
                    detail: "Keep the download engine healthy and choose how YTLite behaves."
                )

                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionTitle("Download engine", detail: "Managed separately from the app", icon: "gearshape.2.fill")
                            if model.tools.isRefreshing { ProgressView().controlSize(.small) }
                            Button("Refresh") { model.refreshTools() }
                                .buttonStyle(.plain)
                                .controlSize(.small)
                                .foregroundStyle(.secondary)
                        }

                        ToolStatusRow(
                            name: "yt-dlp",
                            detail: model.tools.ytDLP.version.map { "Version \($0)" } ?? "Required",
                            path: model.tools.ytDLP.path,
                            icon: "arrow.down.circle.fill",
                            available: model.tools.ytDLP.isAvailable
                        )

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Release channel").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Picker("", selection: $model.preferences.updateChannel) {
                                    ForEach(UpdateChannel.allCases) { channel in
                                        Text(channel.title).tag(channel)
                                    }
                                }
                                .labelsHidden()
                            }
                            Text(model.preferences.updateChannel.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Choose Existing…") { model.chooseYTDLP() }
                                .buttonStyle(.bordered)
                            Button {
                                model.installOrUpdateYTDLP()
                            } label: {
                                if model.isInstallingYTDLP {
                                    HStack(spacing: 7) { ProgressView().controlSize(.small); Text("Installing…") }
                                } else {
                                    Label(model.tools.ytDLP.isAvailable ? "Install Latest" : "Install yt-dlp", systemImage: "arrow.down.to.line")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isInstallingYTDLP)
                        }

                        if let error = model.installError {
                            InfoBanner(text: error, kind: .warning)
                        }
                        if model.catalogVersionMismatch {
                            InfoBanner(
                                text: "The app's full option catalog is based on yt-dlp \(model.catalog.ytDlpVersion). Updating aligns the engine with the controls.",
                                kind: .info
                            )
                        }
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Media helpers", detail: "Detected automatically", icon: "wrench.and.screwdriver.fill")
                        ToolStatusRow(
                            name: "FFmpeg",
                            detail: model.tools.ffmpeg.isAvailable ? "Merging and conversion are ready" : "Needed for audio conversion and best-quality video",
                            path: model.tools.ffmpeg.path,
                            icon: "film.stack.fill",
                            available: model.tools.ffmpeg.isAvailable
                        )
                        HStack {
                            Spacer()
                            Button("Choose FFmpeg…") { model.chooseFFmpeg() }.buttonStyle(.bordered)
                        }
                        Divider()
                        ToolStatusRow(
                            name: model.tools.javaScriptRuntime.name,
                            detail: model.tools.javaScriptRuntime.isAvailable ? "Full modern site extraction is available" : "Deno is recommended for full YouTube support",
                            path: model.tools.javaScriptRuntime.path,
                            icon: "curlybraces.square.fill",
                            available: model.tools.javaScriptRuntime.isAvailable
                        )
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Behavior", icon: "slider.horizontal.3")
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Use my existing yt-dlp config").font(.callout.weight(.medium))
                                Text("Off by default so hidden Terminal settings do not change what the GUI does.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $model.preferences.useUserConfiguration)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Automatic channel checks").font(.callout.weight(.medium))
                                Text("Checks enabled channels on their schedules while YTLite is running.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $model.preferences.autoChannelMonitoringEnabled)
                                .labelsHidden().toggleStyle(.switch)
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Launch YTLite at login").font(.callout.weight(.medium))
                                Text("Recommended for unattended channel monitoring. Closing the window keeps YTLite running; Quit stops checks.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { model.launchAtLoginEnabled },
                                set: { model.setLaunchAtLogin($0) }
                            )).labelsHidden().toggleStyle(.switch)
                        }
                        if let error = model.launchAtLoginError {
                            InfoBanner(text: error, kind: .warning)
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Default download folder").font(.callout.weight(.medium))
                                Text(model.settings.outputDirectory).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Choose…") { model.chooseOutputFolder() }.buttonStyle(.bordered)
                        }
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("About YTLite", icon: "heart.fill")
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("YTLite 1.1").font(.headline)
                                Text("Native macOS interface · \(model.catalog.optionCount) yt-dlp options · catalog \(model.catalog.ytDlpVersion)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Link("yt-dlp project", destination: URL(string: "https://github.com/yt-dlp/yt-dlp")!)
                        }
                        Divider()
                        Text("Download only media you have permission to save. YTLite does not bypass DRM. yt-dlp and FFmpeg are independent projects with their own licenses.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 42)
            .padding(.bottom, 34)
            .frame(maxWidth: 1040, alignment: .leading)
        }
    }
}

private struct ToolStatusRow: View {
    let name: String
    let detail: String
    let path: String?
    let icon: String
    let available: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(available ? AppTheme.accent : .orange)
                .frame(width: 42, height: 42)
                .background((available ? AppTheme.accent : .orange).opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(name).font(.headline)
                    StatusDot(available: available)
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if let path {
                    Text(path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Text(available ? "Ready" : "Missing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(available ? AppTheme.accent : .orange)
        }
        .padding(12)
        .background(Color.primary.opacity(0.026), in: RoundedRectangle(cornerRadius: 11))
    }
}
