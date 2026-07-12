import SwiftUI

struct AdvancedOptionsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var selectedGroupID: String?
    @State private var showRawArguments = false

    private var selectedGroup: OptionGroup? {
        if let selectedGroupID, let group = model.catalog.groups.first(where: { $0.id == selectedGroupID }) {
            return group
        }
        return model.catalog.groups.first
    }

    private var visibleOptions: [AdvancedOptionDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return selectedGroup?.options ?? [] }
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return model.catalog.allOptions.filter { option in
            let haystack = [option.signature, option.help, option.canonicalFlag, option.metavar ?? ""]
                .joined(separator: " ")
                .lowercased()
            return terms.allSatisfy(haystack.contains)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    eyebrow: "Expert controls",
                    title: "Every yt-dlp option",
                    detail: "Search \(model.catalog.optionCount) real switches from yt-dlp \(model.catalog.ytDlpVersion). Nothing is hidden."
                )

                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search flags or plain-English descriptions", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))

                    if model.activeSelectedOptionCount > 0 {
                        Text("\(model.activeSelectedOptionCount) active")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.accent.opacity(0.12), in: Capsule())
                        Button("Reset All", role: .destructive) { model.resetAdvancedOptions() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                if model.catalogVersionMismatch {
                    InfoBanner(
                        text: "The installed yt-dlp version differs from this catalog. Existing options still work; update yt-dlp or use Raw Arguments for brand-new flags.",
                        kind: .warning,
                        actionTitle: "Tool Settings",
                        action: { model.page = .settings }
                    )
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 42)
            .padding(.bottom, 16)

            Divider()

            if model.catalog.groups.isEmpty {
                ContentUnavailableView(
                    "Option catalog unavailable",
                    systemImage: "switch.2",
                    description: Text(model.catalogError ?? "Rebuild the app with OptionCatalog.json included.")
                )
            } else {
                HSplitView {
                    groupList
                        .frame(minWidth: 190, idealWidth: 220, maxWidth: 260)
                    optionsList
                        .frame(minWidth: 600)
                }
            }
        }
        .onAppear {
            if selectedGroupID == nil { selectedGroupID = model.catalog.groups.first?.id }
        }
    }

    private var groupList: some View {
        List(selection: $selectedGroupID) {
            ForEach(model.catalog.groups) { group in
                HStack(spacing: 8) {
                    Text(group.name)
                        .lineLimit(1)
                    Spacer()
                    let count = group.options.filter { model.advancedSelections[$0.id]?.enabled == true }.count
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .tag(Optional(group.id))
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.primary.opacity(0.018))
    }

    private var optionsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(searchText.isEmpty ? (selectedGroup?.name ?? "Options") : "Search results")
                            .font(.title3.weight(.bold))
                        Text("\(visibleOptions.count) option\(visibleOptions.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if searchText.isEmpty, let group = selectedGroup,
                       group.options.contains(where: { model.advancedSelections[$0.id]?.enabled == true }) {
                        Button("Reset Section") {
                            let ids = Set(group.options.map(\.id))
                            model.advancedSelections = model.advancedSelections.filter { !ids.contains($0.key) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.bottom, 4)

                ForEach(visibleOptions) { definition in
                    AdvancedOptionRow(definition: definition)
                }

                rawArgumentsPanel
                    .padding(.top, 6)
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.32))
    }

    private var rawArgumentsPanel: some View {
        DisclosureGroup(isExpanded: $showRawArguments) {
            VStack(alignment: .leading, spacing: 9) {
                InfoBanner(
                    text: "Raw arguments are for options added after this catalog or unusual order-sensitive combinations. They are tokenized safely and never run through a shell.",
                    kind: .warning
                )
                TextEditor(text: $model.customArguments)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 90)
                    .background(Color.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.09)) }
            }
            .padding(.top, 10)
        } label: {
            Label("Raw arguments", systemImage: "terminal.fill")
                .font(.headline)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(Color.primary.opacity(0.08)) }
    }
}

private struct AdvancedOptionRow: View {
    @EnvironmentObject private var model: AppModel
    let definition: AdvancedOptionDefinition

    private var selection: AdvancedSelection {
        model.advancedSelections[definition.id] ?? AdvancedSelection()
    }

    private var enabled: Binding<Bool> {
        Binding {
            selection.enabled
        } set: { newValue in
            var updated = selection
            updated.enabled = newValue
            model.setAdvancedSelection(updated, for: definition.id)
        }
    }

    private var value: Binding<String> {
        Binding {
            selection.value
        } set: { newValue in
            var updated = selection
            updated.value = newValue
            model.setAdvancedSelection(updated, for: definition.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Enable \(definition.canonicalFlag)")

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(definition.signature)
                            .font(.system(.callout, design: .monospaced, weight: .semibold))
                            .foregroundStyle(selection.enabled ? AppTheme.accent : .primary)
                            .textSelection(.enabled)
                        if definition.repeatable {
                            optionBadge("Repeatable", color: AppTheme.cyan, icon: "plus.square.on.square")
                        }
                        if let label = definition.safety.label {
                            optionBadge(label, color: safetyColor, icon: definition.safety.symbol)
                        }
                    }
                    Text(definition.help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }

            if definition.takesValue {
                valueControl
                    .padding(.leading, 50)
            }
        }
        .padding(15)
        .background(
            selection.enabled ? AppTheme.accent.opacity(0.055) : Color.primary.opacity(0.022),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selection.enabled ? AppTheme.accent.opacity(0.32) : Color.primary.opacity(0.07))
        }
    }

    @ViewBuilder
    private var valueControl: some View {
        VStack(alignment: .leading, spacing: 5) {
            if definition.isSensitive {
                SecureField(definition.valuePrompt, text: value)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!selection.enabled)
            } else if !definition.choices.isEmpty && definition.choices.count <= 40 {
                Picker(definition.valuePrompt, selection: value) {
                    Text("Choose…").tag("")
                    ForEach(definition.choices, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .disabled(!selection.enabled)
                .frame(maxWidth: 360, alignment: .leading)
            } else {
                TextField(definition.valuePrompt, text: value, axis: definition.repeatable ? .vertical : .horizontal)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!selection.enabled)
            }
            HStack {
                if definition.repeatable {
                    Text("Put each repeated value on its own line.")
                } else if let defaultValue = definition.defaultValue, !defaultValue.isEmpty {
                    Text("yt-dlp default: \(defaultValue)")
                } else {
                    Text("Required value: \(definition.valuePrompt)")
                }
                Spacer()
                if selection.enabled && selection.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !definition.valueOptional {
                    Text("Value required").foregroundStyle(.orange)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private var safetyColor: Color {
        switch definition.safety {
        case .normal: .secondary
        case .password: .purple
        case .fileURL, .plugin: .orange
        case .exec, .certificateBypass: .red
        }
    }

    private func optionBadge(_ text: String, color: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }
}
