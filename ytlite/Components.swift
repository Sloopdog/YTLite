import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.18, green: 0.84, blue: 0.73)
    static let cyan = Color(red: 0.18, green: 0.72, blue: 0.95)
    static let navy = Color(red: 0.035, green: 0.075, blue: 0.16)
    static let indigo = Color(red: 0.18, green: 0.28, blue: 0.82)
}
struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(AppTheme.accent)
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

struct SectionTitle: View {
    let title: String
    let detail: String?
    let icon: String?

    init(_ title: String, detail: String? = nil, icon: String? = nil) {
        self.title = title
        self.detail = detail
        self.icon = icon
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(AppTheme.accent)
            }
            Text(title)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct InfoBanner: View {
    enum Kind { case info, warning, success }
    let text: String
    var kind: Kind = .info
    var actionTitle: String?
    var action: (() -> Void)?

    private var color: Color {
        switch kind {
        case .info: AppTheme.cyan
        case .warning: .orange
        case .success: AppTheme.accent
        }
    }

    private var icon: String {
        switch kind {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.callout)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(color.opacity(0.2))
        }
    }
}

struct StatusDot: View {
    let available: Bool

    var body: some View {
        Circle()
            .fill(available ? AppTheme.accent : Color.orange)
            .frame(width: 7, height: 7)
            .shadow(color: (available ? AppTheme.accent : .orange).opacity(0.5), radius: 3)
    }
}

struct ModeCard: View {
    let mode: MediaMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.title3.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(selected ? AppTheme.accent.opacity(0.2) : Color.primary.opacity(0.06), in: Circle())
                    .foregroundStyle(selected ? AppTheme.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).font(.headline)
                    Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AppTheme.accent : Color.secondary.opacity(0.45))
            }
            .padding(13)
            .contentShape(Rectangle())
            .background(
                selected ? AppTheme.accent.opacity(0.09) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? AppTheme.accent.opacity(0.55) : Color.primary.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
    }
}

struct ToastView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.accent)
            Text(message).font(.callout.weight(.medium))
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thickMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.1)) }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
    }
}
