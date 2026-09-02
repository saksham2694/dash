//
//  StartNavigationButton.swift
//  Dash
//
//  The "Start Navigation" action shown over the route preview (M4.3). The
//  composing view only mounts it when a route is loaded and a current location
//  is known (`MapViewModel.canStartNavigation`), so the button itself is always
//  enabled — tapping it begins the turn-by-turn session.
//

import SwiftUI

struct StartNavigationButton: View {

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 17, weight: .bold))
                Text("Start Navigation")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 15)
            .background(Color(uiColor: .systemBlue), in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start navigation")
    }
}

#if DEBUG
#Preview("Start") {
    StartNavigationButton(action: {})
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.15))
}
#endif
