import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 176, ideal: 210, max: 235)
        } detail: {
            ZStack(alignment: .top) {
                detail
                if let notice = model.notice {
                    ToastView(message: notice) {
                        withAnimation { model.notice = nil }
                    }
                    .padding(.top, 42)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .animation(.snappy, value: model.notice)
        }
        .tint(AppTheme.accent)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(AppTheme.navy)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 0) {
                    Text("YTLite")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("Media made simple")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 34)
            .padding(.bottom, 18)

            List(AppPage.allCases, selection: $model.page) { page in
                Label {
                    HStack {
                        Text(page.title)
                        Spacer()
                        if page == .advanced, model.activeSelectedOptionCount > 0 {
                            Text("\(model.activeSelectedOptionCount)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent.opacity(0.18), in: Capsule())
                        }
                    }
                } icon: {
                    Image(systemName: page.icon)
                }
                .tag(page)
                .padding(.vertical, 3)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 10) {
                Divider()
                HStack(spacing: 8) {
                    StatusDot(available: model.tools.ytDLP.isAvailable)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.tools.ytDLP.isAvailable ? "Ready to download" : "Setup needed")
                            .font(.caption.weight(.semibold))
                        Text(model.tools.ytDLP.version ?? "yt-dlp not found")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if model.isDownloading {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Queue is running").font(.caption)
                    }
                }
            }
            .padding(14)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.page {
        case .download: DownloadView()
        case .channels: ChannelSubscriptionsView()
        case .advanced: AdvancedOptionsView()
        case .presets: PresetsView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    ContentView().environmentObject(AppModel())
}
