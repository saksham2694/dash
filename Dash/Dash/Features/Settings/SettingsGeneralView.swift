//
//  SettingsGeneralView.swift
//  Dash — Settings feature
//
//  Intentionally minimal (M8.3 §2): no General settings exist yet, so this is
//  a plain "more to come" placeholder rather than invented options.
//

import SwiftUI

struct SettingsGeneralView: View {

    var body: some View {
        ContentUnavailableView(
            "General",
            systemImage: "gearshape",
            description: Text("General settings will appear here in a future update.")
        )
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    NavigationStack { SettingsGeneralView() }
}
#endif
