import SwiftUI

struct PresetsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var presetName = ""

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "One-click setups",
                    title: "Presets",
                    detail: "Start with a sensible recipe, then adjust anything you like."
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Built for everyday downloads", icon: "sparkles.rectangle.stack")
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(BuiltInPreset.allCases) { preset in
                            PresetCard(
                                title: preset.title,
                                detail: preset.detail,
                                icon: preset.icon,
                                actionTitle: "Use Preset",
                                action: { model.apply(preset) }
                            )
                        }
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 13) {
                        SectionTitle("Save your current setup", detail: "Includes Advanced Options but never stores passwords", icon: "bookmark.fill")
                        HStack {
                            TextField("Preset name", text: $presetName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { savePreset() }
                            Button("Save Preset", systemImage: "plus") { savePreset() }
                                .buttonStyle(.borderedProminent)
                                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                if !model.presets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Your presets", detail: "\(model.presets.count) saved", icon: "person.crop.circle")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(model.presets) { preset in
                                PresetCard(
                                    title: preset.name,
                                    detail: description(for: preset),
                                    icon: "bookmark.fill",
                                    actionTitle: "Apply",
                                    action: { model.apply(preset) },
                                    deleteAction: { model.deletePreset(id: preset.id) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 42)
            .padding(.bottom, 34)
            .frame(maxWidth: 1040, alignment: .leading)
        }
    }

    private func savePreset() {
        model.savePreset(named: presetName)
        presetName = ""
    }

    private func description(for preset: CustomPreset) -> String {
        let mode = preset.settings.mediaMode.title
        let advancedCount = preset.advancedSelections.values.filter(\.enabled).count
        return advancedCount > 0 ? "\(mode) · \(advancedCount) advanced option\(advancedCount == 1 ? "" : "s")" : mode
    }
}
private struct PresetCard: View {
    let title: String
    let detail: String
    let icon: String
    let actionTitle: String
    let action: () -> Void
    var deleteAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                if let deleteAction {
                    Button(role: .destructive, action: deleteAction) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(minHeight: 168, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(Color.primary.opacity(0.08)) }
    }
}
