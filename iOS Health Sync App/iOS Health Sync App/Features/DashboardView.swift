// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import SwiftData
import SwiftUI

/// Status-first dashboard — replaces the old 7-section List in ContentView.
/// The user opens the app to verify "is sharing working?", check what's been
/// shared, and trust the system. The dashboard answers those questions
/// immediately without forcing the user to scroll past 178 toggles.
///
/// Composition (top → bottom):
///   1. Hero status card — sharing on/off, paired Mac, last sync
///   2. Trust panel — TLS / fingerprint teaser / audit summary
///   3. Quick actions — Export Now · Pair Mac · Categories
///   4. Tile grid (2×2) — drill-downs to Categories / Pairing / Audit / Export
///   5. Getting Started checklist — first-launch only
///
/// Drill-downs use NavigationLinks; Manual Export uses a sheet to preserve
/// the existing flow.
struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \AuditEventRecord.timestamp, order: .reverse) private var auditEvents: [AuditEventRecord]
    @Query private var pairedDevices: [PairedDevice]
    @State private var showingManualExport = false
    @ScaledMetric(relativeTo: .body) private var stepBadgeSize: CGFloat = 28

    private var hasPairedDevice: Bool { !pairedDevices.isEmpty }
    private var enabledCount: Int { appState.syncConfiguration.enabledTypes.count }
    private var totalTypeCount: Int { HealthDataType.allCases.count }
    private var todaysEventCount: Int {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        return auditEvents.filter { $0.timestamp >= startOfDay }.count
    }
    private var unauthorizedToday: Int {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        return auditEvents.filter {
            $0.timestamp >= startOfDay && $0.eventType.hasPrefix("security.")
        }.count
    }
    private var shouldShowGettingStarted: Bool {
        !appState.healthAuthorizationStatus || !appState.isServerRunning || !hasPairedDevice
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroStatusCard
                trustPanel
                tileGrid
                if shouldShowGettingStarted {
                    gettingStartedCard
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("HealthSync")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showingManualExport) {
            ManualExportView()
                .environment(appState)
        }
    }

    // MARK: - Hero status card

    private var heroStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: appState.isServerRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.title2)
                    .foregroundStyle(appState.isServerRunning ? .green : .secondary)
                    .symbolEffect(.variableColor, isActive: appState.isServerRunning)
                Text(appState.isServerRunning ? "Sharing" : "Not Sharing")
                    .font(.title2.weight(.semibold))
                Spacer()
                if appState.isServerRunning {
                    Text("On")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if hasPairedDevice {
                    Text("\(pairedDevices.count) paired Mac\(pairedDevices.count == 1 ? "" : "s")")
                        .font(.subheadline)
                } else {
                    Text("No Mac paired yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let lastSync = appState.syncConfiguration.lastExportAt {
                    Text("Last sync \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if hasPairedDevice {
                    Text("Awaiting first fetch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if appState.isServerRunning {
                Button {
                    HapticFeedback.impact(.light)
                    Task { await appState.stopServer() }
                } label: {
                    HStack {
                        Image(systemName: "pause.fill")
                        Text("Stop Sharing")
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.red)
                }
                .liquidGlassButtonStyle(.standard)
            } else {
                Button {
                    HapticFeedback.impact(.medium)
                    Task { await appState.startServer() }
                } label: {
                    if appState.isServerStarting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Starting…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Sharing")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .liquidGlassButtonStyle(.prominent)
                .disabled(appState.isServerStarting || !appState.healthAuthorizationStatus)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .animation(.smooth, value: appState.isServerRunning)
    }

    // MARK: - Trust panel

    private var trustPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Trust")
                    .font(.headline)
                Spacer()
            }

            trustRow(icon: "lock.fill", title: "TLS 1.3 with self-signed certificate", color: .green)
            trustRow(icon: "wifi", title: "Local network only — no external access", color: .green)
            if hasPairedDevice {
                NavigationLink {
                    PairingView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.viewfinder")
                            .foregroundStyle(.green)
                        Text("Verify fingerprint")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.vertical, 2)

            HStack {
                Text("Today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if unauthorizedToday > 0 {
                    Label("\(unauthorizedToday) unauthorized", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Text("\(todaysEventCount) event\(todaysEventCount == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                AuditLogView()
            } label: {
                HStack {
                    Text("View audit log")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func trustRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
            Spacer()
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
        }
    }

    // MARK: - Tile grid

    private var tileGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            // Categories
            NavigationLink {
                CategoriesView()
            } label: {
                tile(
                    icon: "checklist",
                    title: "Categories",
                    primary: "\(enabledCount) of \(totalTypeCount)",
                    secondary: "enabled"
                )
            }
            .buttonStyle(.plain)
            .disabled(!appState.healthAuthorizationStatus)
            .opacity(appState.healthAuthorizationStatus ? 1 : 0.5)

            // Pairing
            NavigationLink {
                PairingView()
            } label: {
                tile(
                    icon: "laptopcomputer.and.iphone",
                    title: "Pairing",
                    primary: pairingTilePrimary,
                    secondary: pairingTileSecondary
                )
            }
            .buttonStyle(.plain)

            // Manual Export
            Button {
                HapticFeedback.impact(.light)
                showingManualExport = true
            } label: {
                tile(
                    icon: "square.and.arrow.up.on.square",
                    title: "Export",
                    primary: exportTilePrimary,
                    secondary: "to a file"
                )
            }
            .buttonStyle(.plain)
            .disabled(!appState.healthAuthorizationStatus)
            .opacity(appState.healthAuthorizationStatus ? 1 : 0.5)

            // Audit
            NavigationLink {
                AuditLogView()
            } label: {
                tile(
                    icon: "list.bullet.rectangle",
                    title: "Activity",
                    primary: "\(todaysEventCount)",
                    secondary: todaysEventCount == 1 ? "event today" : "events today"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var pairingTilePrimary: String {
        if pairedDevices.isEmpty { return "0" }
        return "\(pairedDevices.count)"
    }
    private var pairingTileSecondary: String {
        if pairedDevices.isEmpty { return "no Macs paired" }
        return pairedDevices.count == 1 ? "Mac paired" : "Macs paired"
    }
    private var exportTilePrimary: String {
        if let last = appState.syncConfiguration.lastExportAt {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f.localizedString(for: last, relativeTo: Date())
        }
        return "—"
    }

    private func tile(icon: String, title: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text(primary)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Getting Started checklist (extracted from old ContentView)

    private var gettingStartedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "checklist")
                Text("Getting Started")
                    .font(.headline)
                Spacer()
                Text(setupProgress)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            stepRow(
                number: 1,
                title: "Grant Health Access",
                detail: "Allows HealthSync to read your Apple Health data.",
                isComplete: appState.healthAuthorizationStatus,
                isActionable: !appState.healthAuthorizationStatus
            ) {
                HapticFeedback.impact(.medium)
                Task { await appState.requestHealthAuthorization() }
            }

            if appState.healthAuthorizationStatus,
               appState.healthDataProbeState == .limited {
                limitedAccessWarning
            }

            stepRow(
                number: 2,
                title: "Start Sharing",
                detail: "Turns on the connection so a Mac can fetch your data.",
                isComplete: appState.isServerRunning,
                isActionable: appState.healthAuthorizationStatus
                    && !appState.isServerRunning
                    && !appState.isServerStarting
            ) {
                HapticFeedback.impact(.medium)
                Task { await appState.startServer() }
            }

            // Step 3 navigates to PairingView so the user sees the QR there.
            NavigationLink {
                PairingView()
            } label: {
                stepRowContent(
                    number: 3,
                    title: "Pair Your Mac",
                    detail: "Open Pairing to see the QR code, install the CLI on your Mac, and run \u{201C}healthsync scan\u{201D}.",
                    isComplete: hasPairedDevice,
                    isActionable: appState.isServerRunning && !hasPairedDevice,
                    actionLabel: hasPairedDevice ? nil : "Open Pairing"
                )
            }
            .buttonStyle(.plain)
            .disabled(!(appState.isServerRunning && !hasPairedDevice))

            footerText
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var setupProgress: String {
        var done = 0
        if appState.healthAuthorizationStatus { done += 1 }
        if appState.isServerRunning { done += 1 }
        if hasPairedDevice { done += 1 }
        return "\(done) of 3"
    }

    @ViewBuilder
    private var footerText: some View {
        Group {
            if !appState.healthAuthorizationStatus {
                Text("Tap step 1 to begin. The whole setup takes under a minute.")
            } else if !appState.isServerRunning {
                Text("Tap step 2 to turn on sharing.")
            } else if !hasPairedDevice {
                Text("On your Mac, run the HealthSync CLI to pair. Open Pairing for instructions.")
            } else {
                Text("Setup complete. Your Mac is paired.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var limitedAccessWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("HealthSync isn't seeing any data")
                    .font(.subheadline.weight(.medium))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text("If you have data in Apple Health, open Settings to enable the categories you want to share.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.leading, stepBadgeSize + 12)
    }

    private func stepRow(
        number: Int,
        title: String,
        detail: String,
        isComplete: Bool,
        isActionable: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            stepRowContent(
                number: number,
                title: title,
                detail: detail,
                isComplete: isComplete,
                isActionable: isActionable,
                actionLabel: nil
            )
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
        .opacity(isComplete && !isActionable ? 0.7 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number) of 3: \(title)")
        .accessibilityValue(isComplete ? "Completed" : (isActionable ? "Tap to start" : "Locked"))
        .accessibilityHint(detail)
    }

    private func stepRowContent(
        number: Int,
        title: String,
        detail: String,
        isComplete: Bool,
        isActionable: Bool,
        actionLabel: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : (isActionable ? Color.accentColor : Color.secondary.opacity(0.25)))
                    .frame(width: stepBadgeSize, height: stepBadgeSize)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isComplete ? .secondary : .primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isActionable, let actionLabel {
                    Text(actionLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.top, 2)
                }
            }
            Spacer()
            if isActionable {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
