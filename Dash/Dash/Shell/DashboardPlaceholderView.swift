//
//  DashboardPlaceholderView.swift
//  Dash
//
//  Placeholder for the customizable widget dashboard. The layout model, the
//  grid, size-appropriate feature components, and edit mode are M5.2+ — M5.0
//  only reserves the space in the shell.
//

import SwiftUI

struct DashboardPlaceholderView: View {

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Dashboard")
                .font(.title2.weight(.semibold))
            Text("Customizable widgets arrive in a later milestone.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
