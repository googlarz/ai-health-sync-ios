// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - ContentView

/// Thin shell that hosts the NavigationStack and global modifiers
/// (scenePhase observer, typed-error alert, legacy string-error alert).
/// All actual UI lives in DashboardView and its drill-downs:
///   - DashboardView (the home screen)
///   - CategoriesView (the 178-type picker)
///   - PairingView (server start/stop, QR, Connected Macs)
///   - AuditLogView (full audit trail with filtering)
///   - ManualExportView (sheet for file export)
///   - SettingsView (About / Privacy)
///
/// File-scoped utilities (ShareSheet, CopyPayloadActivity, HapticFeedback)
/// remain at the bottom of this file because they're used across multiple
/// feature views and don't have an obvious better home yet.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            DashboardView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            appState.handleScenePhaseChange(newPhase)
        }
        // Single alert chain — typed errors take precedence over the legacy
        // string error. The legacy alert only fires when there is no typed
        // error pending so they cannot dismiss each other.
        .alert(item: typedErrorBinding) { error in
            errorAlert(for: error)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { appState.lastTypedError == nil && appState.lastError != nil },
                set: { if !$0 { appState.lastError = nil } }
            )
        ) {
            Button("OK") { appState.lastError = nil }
        } message: {
            Text(appState.lastError ?? "")
        }
    }

    private var typedErrorBinding: Binding<IdentifiableAppError?> {
        Binding(
            get: { appState.lastTypedError.map(IdentifiableAppError.init) },
            set: { if $0 == nil { appState.lastTypedError = nil } }
        )
    }

    /// Builds the typed-error Alert with optional recovery action. NOT
    /// `@ViewBuilder` — `Alert` is its own value type, not a `View`, so the
    /// function must return it explicitly via `return` statements.
    private func errorAlert(for error: IdentifiableAppError) -> Alert {
        let recovery = error.appError.recovery
        if let recovery {
            return Alert(
                title: Text(error.appError.title),
                message: Text(error.appError.message),
                primaryButton: .default(Text(recovery.label)) {
                    AppErrorRecoveryRunner.run(recovery)
                    appState.lastTypedError = nil
                },
                secondaryButton: .cancel(Text("Cancel")) {
                    appState.lastTypedError = nil
                }
            )
        } else {
            return Alert(
                title: Text(error.appError.title),
                message: Text(error.appError.message),
                dismissButton: .default(Text("OK")) {
                    appState.lastTypedError = nil
                }
            )
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var activities: [UIActivity]? = nil
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: activities)
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Custom "Copy" activity that writes the payload with an expiration.
final class CopyPayloadActivity: UIActivity {
    private let payload: String
    private let image: UIImage?
    private let expiration: Date

    init(payload: String, image: UIImage?, expiration: Date) {
        self.payload = payload
        self.image = image
        self.expiration = expiration
        super.init()
    }

    override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType("org.mvneves.healthsync.copy")
    }

    override var activityTitle: String? {
        "Copy"
    }

    override var activityImage: UIImage? {
        UIImage(systemName: "doc.on.doc")
    }

    override class var activityCategory: UIActivity.Category {
        .action
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        !payload.isEmpty
    }

    override func perform() {
        if let image, let pngData = image.pngData() {
            PairingClipboard.setPayload(payload, pngData: pngData, expiration: expiration)
        } else {
            PairingClipboard.setTextPayload(payload, expiration: expiration)
        }
        activityDidFinish(true)
    }
}

// MARK: - Haptic Feedback

/// Type-safe haptic feedback helper for iOS interactions.
/// Uses MainActor for Swift 6 concurrency safety with UIKit.
@MainActor
enum HapticFeedback {
    /// Impact feedback styles
    enum ImpactStyle {
        case light, medium, heavy, soft, rigid

        var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light: return .light
            case .medium: return .medium
            case .heavy: return .heavy
            case .soft: return .soft
            case .rigid: return .rigid
            }
        }
    }

    /// Notification feedback types
    enum NotificationType {
        case success, warning, error

        var uiType: UINotificationFeedbackGenerator.FeedbackType {
            switch self {
            case .success: return .success
            case .warning: return .warning
            case .error: return .error
            }
        }
    }

    // Cached generators with prepare() called eagerly so the first tap doesn't
    // see the typical 50-100ms warmup delay. iOS expects prepare() before each
    // expected feedback for best latency.
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let impactSoft = UIImpactFeedbackGenerator(style: .soft)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notifier = UINotificationFeedbackGenerator()
    private static let selector = UISelectionFeedbackGenerator()

    /// Triggers impact haptic feedback. Cached generator + prepare() eliminates
    /// first-tap latency.
    static func impact(_ style: ImpactStyle) {
        let g: UIImpactFeedbackGenerator
        switch style {
        case .light:  g = impactLight
        case .medium: g = impactMedium
        case .heavy:  g = impactHeavy
        case .soft:   g = impactSoft
        case .rigid:  g = impactRigid
        }
        g.prepare()
        g.impactOccurred()
    }

    /// Triggers notification haptic feedback (success / warning / error).
    static func notification(_ type: NotificationType) {
        notifier.prepare()
        notifier.notificationOccurred(type.uiType)
    }

    /// Triggers selection haptic feedback (subtle tick).
    static func selection() {
        selector.prepare()
        selector.selectionChanged()
    }
}

#Preview {
    let schema = Schema([
        SyncConfiguration.self,
        PairedDevice.self,
        AuditEventRecord.self
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: configuration)
    let state = AppState(modelContainer: container)
    return ContentView()
        .environment(state)
        .modelContainer(container)
}
