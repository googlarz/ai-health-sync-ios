// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Manual data export — fetches HealthKit samples for a chosen date range and
/// writes them to a temp file the user can share or save via the system share
/// sheet (Files app, AirDrop, Mail, Messages, iCloud Drive, etc.).
///
/// The export is composed from **channels** (Health Metrics, Workouts,
/// Symptoms, Cycle Tracking, Cardiac Events). Each channel resolves to a
/// scoped subset of the user's globally-enabled types. The user toggles
/// channels on/off for this single export — channel state is local to the
/// view and resets when the sheet closes (per Codex review: this is
/// presentation-layer regrouping, not durable sync policy).
///
/// Iteration scope (PR20):
///   - Channel taxonomy + per-channel toggles
///   - Channel-scoped type union passed to existing `runManualExport`
///   - Disable Export when no channels enabled (UX guard, not just backend error)
///   - Sub-controls (Summarize, Time Grouping, Include GPX, etc.) deferred
struct ManualExportView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var range: TimeRange = .lastWeek
    @State private var format: AppState.ManualExportFormat = .csv
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var customEnd = Date()
    @State private var enabledChannels: Set<ExportChannel> = Set(
        ExportChannel.allCases.filter { $0.defaultEnabled }
    )
    @State private var isExporting = false
    @State private var exportedFile: ExportFile?
    @State private var errorMessage: String?

    enum TimeRange: String, CaseIterable, Identifiable {
        case today, lastWeek, lastMonth, lastQuarter, custom
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .today:        return "Today"
            case .lastWeek:     return "Last 7 days"
            case .lastMonth:    return "Last 30 days"
            case .lastQuarter:  return "Last 90 days"
            case .custom:       return "Custom"
            }
        }
    }

    /// Channels — each maps to a scoped subset of the user's globally-enabled
    /// types. The Health Metrics channel is the catch-all for everything not
    /// covered by a more specific channel.
    enum ExportChannel: String, CaseIterable, Identifiable {
        case healthMetrics
        case workouts
        case symptoms
        case cycleTracking
        case cardiacEvents

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .healthMetrics:  return "Health Metrics"
            case .workouts:       return "Workouts"
            case .symptoms:       return "Symptoms"
            case .cycleTracking:  return "Cycle Tracking"
            case .cardiacEvents:  return "Cardiac Events"
            }
        }

        var iconSystemName: String {
            switch self {
            case .healthMetrics:  return "heart.text.square"
            case .workouts:       return "figure.run.square.stack"
            case .symptoms:       return "thermometer"
            case .cycleTracking:  return "calendar"
            case .cardiacEvents:  return "waveform.path.ecg"
            }
        }

        var description: String {
            switch self {
            case .healthMetrics:  return "Activity, vitals, sleep, body, nutrition, mobility, and the rest of your standard health profile."
            case .workouts:       return "Workout sessions with duration, energy, distance, and source."
            case .symptoms:       return "Logged symptoms (headache, fatigue, mood changes, etc.)."
            case .cycleTracking:  return "Menstrual cycle tracking and reproductive health entries."
            case .cardiacEvents:  return "Apple Watch heart rhythm event alerts (irregular, high, and low)."
            }
        }

        var defaultEnabled: Bool {
            switch self {
            case .healthMetrics, .workouts: return true
            default:                        return false
            }
        }

        var isSensitive: Bool {
            switch self {
            case .cycleTracking, .cardiacEvents: return true
            default:                              return false
            }
        }

        /// Resolves this channel to a set of HealthDataType values, scoped to
        /// the user's globally-enabled types. A channel that resolves to an
        /// empty set should not contribute to the export (the union union'd
        /// with empty is a no-op).
        func types(in enabled: Set<HealthDataType>) -> Set<HealthDataType> {
            switch self {
            case .healthMetrics:
                // Catch-all: everything in `enabled` except types covered by
                // the other channels.
                return enabled.filter { type in
                    type != .workouts
                        && type.category != .symptoms
                        && type.category != .reproductiveHealth
                        && !Self.isCardiacEvent(type)
                }
            case .workouts:
                return enabled.contains(.workouts) ? [.workouts] : []
            case .symptoms:
                return enabled.filter { $0.category == .symptoms }
            case .cycleTracking:
                return enabled.filter { $0.category == .reproductiveHealth }
            case .cardiacEvents:
                return enabled.filter { Self.isCardiacEvent($0) }
            }
        }

        private static func isCardiacEvent(_ t: HealthDataType) -> Bool {
            switch t {
            case .irregularHeartRhythmEvent, .highHeartRateEvent, .lowHeartRateEvent:
                return true
            default:
                return false
            }
        }
    }

    struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
        let sampleCount: Int
    }

    /// Union of types contributed by every enabled channel, scoped to the
    /// user's globally-enabled types. Drives the Export button's disabled
    /// state and the actual fetch.
    private var resolvedTypes: [HealthDataType] {
        let enabled = Set(appState.syncConfiguration.enabledTypes)
        var union: Set<HealthDataType> = []
        for channel in enabledChannels {
            union.formUnion(channel.types(in: enabled))
        }
        return Array(union)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Time Range") {
                    Picker("Range", selection: $range) {
                        ForEach(TimeRange.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    if range == .custom {
                        DatePicker("From", selection: $customStart,
                                   in: ...customEnd, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd,
                                   in: customStart...Date(), displayedComponents: .date)
                    }
                }
                Section("Format") {
                    Picker("Format", selection: $format) {
                        Text("CSV").tag(AppState.ManualExportFormat.csv)
                        Text("JSON").tag(AppState.ManualExportFormat.json)
                    }
                    .pickerStyle(.segmented)
                }

                channelsSection

                Section {
                    Button {
                        Task { await runExport() }
                    } label: {
                        if isExporting {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Exporting…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Export")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isExporting || resolvedTypes.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if resolvedTypes.isEmpty {
                        Text("Turn on at least one channel above to enable the Export button.")
                            .font(.caption)
                    } else {
                        Text("\(resolvedTypes.count) categor\(resolvedTypes.count == 1 ? "y" : "ies") will be included.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Manual Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $exportedFile) { file in
                ExportResultSheet(file: file) {
                    exportedFile = nil
                    dismiss()
                }
                .presentationDetents([.medium, .large])
            }
            .alert(
                "Export Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var channelsSection: some View {
        ForEach(ExportChannel.allCases) { channel in
            Section {
                channelToggleRow(channel)
                if enabledChannels.contains(channel) {
                    let count = channel.types(in: Set(appState.syncConfiguration.enabledTypes)).count
                    LabeledContent("Categories included") {
                        Text("\(count)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if channel.isSensitive {
                    Text("Sensitive · off by default. " + channel.description)
                        .font(.caption)
                } else {
                    Text(channel.description)
                        .font(.caption)
                }
            }
        }
    }

    private func channelToggleRow(_ channel: ExportChannel) -> some View {
        Toggle(isOn: Binding(
            get: { enabledChannels.contains(channel) },
            set: { newValue in
                if newValue { enabledChannels.insert(channel) }
                else { enabledChannels.remove(channel) }
            }
        )) {
            Label(channel.displayName, systemImage: channel.iconSystemName)
        }
    }

    private var dateRange: (Date, Date) {
        let cal = Calendar.current
        let now = Date()
        switch range {
        case .today:
            return (cal.startOfDay(for: now), now)
        case .lastWeek:
            return (cal.date(byAdding: .day, value: -7, to: now) ?? now, now)
        case .lastMonth:
            return (cal.date(byAdding: .day, value: -30, to: now) ?? now, now)
        case .lastQuarter:
            return (cal.date(byAdding: .day, value: -90, to: now) ?? now, now)
        case .custom:
            let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: customEnd) ?? customEnd
            return (cal.startOfDay(for: customStart), endOfDay)
        }
    }

    private func runExport() async {
        isExporting = true
        defer { isExporting = false }
        let (start, end) = dateRange
        do {
            let result = try await appState.runManualExport(
                types: resolvedTypes,
                startDate: start,
                endDate: end,
                format: format
            )
            exportedFile = ExportFile(url: result.url, sampleCount: result.sampleCount)
            HapticFeedback.notification(.success)
        } catch {
            errorMessage = error.localizedDescription
            HapticFeedback.notification(.error)
        }
    }
}

/// Shown on top of ManualExportView once the file is ready. Wraps a ShareLink
/// so the user can save to Files, AirDrop, email, Messages, iCloud Drive, etc.
private struct ExportResultSheet: View {
    let file: ManualExportView.ExportFile
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, options: .repeat(1))
            Text("Export Ready")
                .font(.title2.bold())
            Text("\(file.sampleCount) sample\(file.sampleCount == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Text(file.url.lastPathComponent)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 24)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
            ShareLink(item: file.url) {
                Label("Share or Save…", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            Button("Done", action: onDone)
                .padding(.bottom, 16)
        }
        .padding(.top, 48)
    }
}
