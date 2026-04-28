// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import SwiftData
import SwiftUI

/// Categories picker — extracted from the old `dataTypesSection` in ContentView.
/// Lives in its own NavigationStack pushed from the Dashboard so the
/// `.searchable` modifier and Quick Presets toolbar behave like every other
/// iOS screen with a search field, instead of being faked inside a List row.
///
/// State that lived in ContentView migrated here verbatim:
/// - typeSearch (search query)
/// - expandedCategories (which DisclosureGroups are open)
/// - showSensitiveConfirmation (preset that includes sensitive types)
/// - pendingSensitiveType (single sensitive type the user just turned on)
///
/// Mutation still routes through AppState.toggleType / setEnabledTypes — this
/// view owns presentation-only state.
struct CategoriesView: View {
    @Environment(AppState.self) private var appState
    @State private var typeSearch: String = ""
    @State private var expandedCategories: Set<HealthDataType.Category> = Set(
        HealthDataType.Category.allCases.filter { $0.defaultExpanded }
    )
    @State private var showSensitiveConfirmation: HealthDataType.Preset?
    @State private var pendingSensitiveType: HealthDataType?

    var body: some View {
        List {
            ForEach(HealthDataType.Category.allCases, id: \.self) { category in
                if !typesIn(category).isEmpty {
                    categoryRow(for: category)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $typeSearch,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search categories"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                presetMenuToolbar
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Categories")
                        .font(.headline)
                    Text("\(appState.syncConfiguration.enabledTypes.count) of \(HealthDataType.allCases.count) enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .alert(
            "Enable sensitive types?",
            isPresented: Binding(
                get: { showSensitiveConfirmation != nil },
                set: { if !$0 { showSensitiveConfirmation = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { showSensitiveConfirmation = nil }
            Button("Apply Preset", role: .destructive) {
                if let preset = showSensitiveConfirmation {
                    applyPreset(preset)
                }
                showSensitiveConfirmation = nil
            }
        } message: {
            Text("This preset enables types covering sensitive health data including reproductive health and cardiac events. You can disable individual types afterward.")
        }
        .alert(
            "Enable sensitive category?",
            isPresented: Binding(
                get: { pendingSensitiveType != nil },
                set: { if !$0 { pendingSensitiveType = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingSensitiveType = nil }
            Button("Enable", role: .destructive) {
                if let type = pendingSensitiveType {
                    appState.toggleType(type, enabled: true)
                }
                pendingSensitiveType = nil
            }
        } message: {
            if let type = pendingSensitiveType {
                Text("Share \(type.displayName) with your Mac? You can turn this off any time.")
            }
        }
    }

    /// Quick Presets menu — wand-and-stars icon in nav bar trailing.
    /// "Disable All" intentionally NOT in this menu (one fat-finger nukes
    /// everything). Sensitive presets route through a confirmation alert.
    private var presetMenuToolbar: some View {
        Menu {
            Section("Apply Preset") {
                ForEach(HealthDataType.Preset.allCases, id: \.self) { preset in
                    Button {
                        HapticFeedback.impact(.light)
                        let hasSensitive = preset.types.contains(where: { $0.isSensitive })
                        if hasSensitive {
                            showSensitiveConfirmation = preset
                        } else {
                            applyPreset(preset)
                        }
                    } label: {
                        Label(preset.displayName, systemImage: preset.iconSystemName)
                    }
                }
            }
        } label: {
            Image(systemName: "wand.and.stars")
                .accessibilityLabel("Quick Presets")
        }
    }

    private func categoryRow(for category: HealthDataType.Category) -> some View {
        let types = typesIn(category)
        let enabledCount = types.filter { appState.syncConfiguration.enabledTypes.contains($0) }.count
        let isExpanded = Binding(
            get: { expandedCategories.contains(category) || !typeSearch.isEmpty },
            set: { newValue in
                if newValue { expandedCategories.insert(category) }
                else { expandedCategories.remove(category) }
            }
        )

        return DisclosureGroup(isExpanded: isExpanded) {
            ForEach(types) { type in
                typeToggleRow(type)
            }
        } label: {
            HStack {
                Image(systemName: category.iconSystemName)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                Text(category.displayName)
                Spacer()
                Text("\(enabledCount)/\(types.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func typeToggleRow(_ type: HealthDataType) -> some View {
        let isOn = appState.syncConfiguration.enabledTypes.contains(type)
        return Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in
                // Sensitive types require explicit confirmation when turning ON.
                // Turning off is always immediate.
                if newValue && type.isSensitive && !isOn {
                    pendingSensitiveType = type
                } else {
                    appState.toggleType(type, enabled: newValue)
                }
            }
        )) {
            HStack(spacing: 8) {
                Text(type.displayName)
                if type.isSensitive {
                    Text("Sensitive")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.orange.opacity(0.18)))
                        .foregroundStyle(.orange)
                }
            }
        }
        .accessibilityHint(type.isSensitive ? "Sensitive health data category" : "")
    }

    private func typesIn(_ category: HealthDataType.Category) -> [HealthDataType] {
        let all = HealthDataType.allCases.filter { $0.category == category }
        guard !typeSearch.isEmpty else { return all }
        let q = typeSearch.lowercased()
        return all.filter { $0.displayName.lowercased().contains(q) || $0.rawValue.lowercased().contains(q) }
    }

    private func applyPreset(_ preset: HealthDataType.Preset) {
        appState.setEnabledTypes(Array(preset.types))
    }
}
