// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Settings — pushed from the Dashboard's gear toolbar item. Currently just
/// the About + Privacy Policy links extracted from the old `settingsSection`.
/// Kept as its own screen so the Dashboard's tile grid stays focused on the
/// 4 primary destinations (Categories / Pairing / Activity / Export).
struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
            }
            NavigationLink {
                AboutView()
            } label: {
                Label("About", systemImage: "info.circle.fill")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
