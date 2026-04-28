// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import SwiftData
import SwiftUI
import UIKit

/// Pairing screen — extracted from the old serverSection + pairingSection +
/// connectedMacsSection in ContentView. Pushed from the Dashboard via a
/// NavigationLink. Owns all the QR/share/copy/revoke local UI state.
///
/// Server start/stop control still lives here so the user can pair without
/// going back to the Dashboard. The Dashboard hero card has its own
/// duplicate Start/Stop button — both call AppState.startServer / stopServer.
struct PairingView: View {
    @Environment(AppState.self) private var appState
    @Query private var pairedDevices: [PairedDevice]

    @State private var showingShareSheet = false
    @State private var qrImageToShare: UIImage?
    @State private var qrPayloadToShare: String?
    @State private var qrExpirationToShare: Date?
    @State private var showCopiedFeedback = false
    @State private var showRevokeConfirmation = false
    @State private var showFingerprintExpanded = false

    private var hasPairedDevice: Bool { !pairedDevices.isEmpty }

    var body: some View {
        List {
            sharingSection
            pairingSection
            if hasPairedDevice {
                connectedMacsSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pairing")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.smooth, value: appState.isServerRunning)
        .animation(.smooth, value: appState.pairingQRCode != nil)
        .animation(.smooth, value: appState.isRefreshing)
    }

    // MARK: - Sharing section (server start/stop)

    private var sharingSection: some View {
        Section {
            HStack {
                Image(systemName: appState.isServerRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(appState.isServerRunning ? .green : .secondary)
                    .symbolEffect(.variableColor, isActive: appState.isServerRunning)
                Text("Status")
                Spacer()
                Text(appState.isServerRunning ? "Running" : "Stopped")
                    .foregroundStyle(.secondary)
            }

            if appState.isServerRunning {
                LabeledContent("Port", value: String(appState.serverPort))
                Button {
                    HapticFeedback.impact(.light)
                    Task { await appState.stopServer() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.fill")
                        Text("Stop Sharing")
                    }
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
                            ProgressView()
                            Text("Starting...")
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Start Sharing")
                        }
                    }
                }
                .liquidGlassButtonStyle(.prominent)
                .disabled(appState.isServerStarting)
            }
        } header: {
            Text("Sharing")
        } footer: {
            if appState.isServerRunning {
                Label("Screen stays on while pairing. You can lock the phone after a Mac connects.",
                      systemImage: "sun.max.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !hasPairedDevice {
                Text("Turn this on to make your iPhone visible to the HealthSync CLI on your Mac.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Pairing section (QR + buttons + instructions)

    private var pairingSection: some View {
        Section("Pairing") {
            if let qr = appState.pairingQRCode {
                let payload = qrPayloadString(for: qr)

                QRCodeView(text: payload)
                    .padding(.vertical, 8)

                LabeledContent("Code") {
                    Button {
                        UIPasteboard.general.string = qr.code
                        HapticFeedback.notification(.success)
                    } label: {
                        HStack(spacing: 4) {
                            Text(qr.code)
                                .font(.system(.body, design: .monospaced))
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pairing code \(qr.code), tap to copy")
                }
                expirationCountdown(for: qr.expiresAt)
                fingerprintRow(qr.certificateFingerprint)

                Button {
                    HapticFeedback.impact(.light)
                    Task { await appState.refreshPairingCode() }
                } label: {
                    if appState.isRefreshing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Refreshing...")
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Code")
                        }
                    }
                }
                .liquidGlassButtonStyle(.standard)
                .disabled(appState.isRefreshing)

                Button {
                    guard let currentQR = appState.pairingQRCode else { return }
                    let currentPayload = qrPayloadString(for: currentQR)
                    copyPayloadToClipboard(currentPayload, expiresAt: currentQR.expiresAt)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        Text(showCopiedFeedback ? "Copied!" : "Copy to Clipboard")
                    }
                }
                .liquidGlassButtonStyle(showCopiedFeedback ? .prominent : .standard)
                .disabled(appState.isRefreshing)

                Button {
                    HapticFeedback.impact(.light)
                    guard let currentQR = appState.pairingQRCode else { return }
                    let currentPayload = qrPayloadString(for: currentQR)
                    if let image = QRCodeRenderer.render(payload: currentPayload) {
                        qrImageToShare = image
                        qrPayloadToShare = currentPayload
                        qrExpirationToShare = currentQR.expiresAt
                        showingShareSheet = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share QR Code")
                    }
                }
                .liquidGlassButtonStyle(.standard)
                .disabled(appState.isRefreshing)
                .sheet(isPresented: $showingShareSheet) {
                    if let image = qrImageToShare,
                       let payload = qrPayloadToShare,
                       let expiration = qrExpirationToShare {
                        ShareSheet(
                            items: [image],
                            activities: [CopyPayloadActivity(payload: payload, image: image, expiration: expiration)],
                            excludedActivityTypes: [.copyToPasteboard]
                        )
                    } else if let image = qrImageToShare {
                        ShareSheet(items: [image])
                    }
                }

                if !hasPairedDevice {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Open Terminal on your Mac and install the CLI:")
                                .font(.footnote)
                            Text("brew install mneves75/tap/healthsync")
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            Text("2. Tap \u{201C}Copy to Clipboard\u{201D} above, then run on your Mac:")
                                .font(.footnote)
                            Text("healthsync scan")
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            Text("3. Keep this iPhone app open until pairing finishes.")
                                .font(.footnote)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    } label: {
                        Label("How to pair your Mac", systemImage: "info.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if hasPairedDevice {
                ContentUnavailableView {
                    Label("Sharing Off", systemImage: "qrcode")
                } description: {
                    Text("Tap \u{201C}Start Sharing\u{201D} above when you want your paired Mac to fetch fresh data.")
                }
                .listRowBackground(Color.clear)
            } else {
                ContentUnavailableView {
                    Label("Not Sharing Yet", systemImage: "qrcode")
                } description: {
                    Text("Tap \u{201C}Start Sharing\u{201D} above to generate a pairing QR code for your Mac.")
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Connected Macs section

    private var connectedMacsSection: some View {
        Section {
            ForEach(pairedDevices, id: \.id) { device in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: device.isActive ? "laptopcomputer" : "laptopcomputer.slash")
                            .foregroundStyle(device.isActive ? .green : .secondary)
                        Text(device.name)
                            .font(.body)
                        Spacer()
                        if device.isActive {
                            Text("Active").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let lastSeen = device.lastSeenAt {
                        Text("Last seen \(lastSeen, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Awaiting first connection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            Button(role: .destructive) {
                HapticFeedback.notification(.warning)
                showRevokeConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.shield.fill")
                    Text("Revoke All Pairings")
                }
            }
            .confirmationDialog(
                "Revoke all pairings?",
                isPresented: $showRevokeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Revoke All", role: .destructive) {
                    Task { await appState.revokeAllPairings() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Paired Macs will lose access. They will need to scan a new QR code to reconnect.")
            }
        } header: {
            Text("Connected Macs (\(pairedDevices.count))")
        } footer: {
            if let lastExport = appState.syncConfiguration.lastExportAt {
                Text("Last sync \(lastExport, style: .relative) ago.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func expirationCountdown(for expiresAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let expired = expiresAt < context.date
            LabeledContent("Valid until") {
                if expired {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        Text("Expired — tap Refresh")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                } else {
                    Text(expiresAt, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func fingerprintRow(_ fingerprint: String) -> some View {
        DisclosureGroup(isExpanded: $showFingerprintExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(fingerprint)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = fingerprint
                    HapticFeedback.notification(.success)
                } label: {
                    Label("Copy Fingerprint", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } label: {
            LabeledContent("Fingerprint") {
                Text(fingerprint)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func qrPayloadString(for qr: PairingQRCode) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(qr)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Copies QR pairing payload to clipboard with BOTH text AND image atomically.
    /// Universal Clipboard between iOS and macOS is unreliable for one or the other;
    /// setting both representations from the same payload guarantees they match.
    private func copyPayloadToClipboard(_ payload: String, expiresAt: Date) {
        guard !payload.isEmpty else {
            HapticFeedback.notification(.error)
            return
        }
        guard let qrImage = QRCodeRenderer.render(payload: payload),
              let pngData = qrImage.pngData() else {
            PairingClipboard.setTextPayload(payload, expiration: expiresAt)
            HapticFeedback.notification(.success)
            showCopiedFeedback = true
            resetCopiedFeedback()
            return
        }
        PairingClipboard.setPayload(payload, pngData: pngData, expiration: expiresAt)
        HapticFeedback.notification(.success)
        showCopiedFeedback = true
        resetCopiedFeedback()
    }

    private func resetCopiedFeedback() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { showCopiedFeedback = false }
        }
    }
}
