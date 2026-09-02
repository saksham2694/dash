//
//  HomePlaceholderView.swift
//  Dash
//
//  A deliberately simple App-Home launcher for M5.0: a tile per registered
//  feature (tap to open it full-screen) plus a couple of clearly-marked
//  "coming soon" tiles so the CarPlay-style grid reads correctly.
//
//  The real launcher — multi-page, reorderable, persisted — is M5.4. No feature
//  logic here: it takes `FeatureManifest`s and an open-by-id closure.
//

import SwiftUI

struct HomePlaceholderView: View {

    let manifests: [FeatureManifest]
    let onOpen: (FeatureID) -> Void

    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(manifests) { manifest in
                    Button {
                        onOpen(manifest.id)
                    } label: {
                        AppTile(symbol: manifest.symbolName, title: manifest.title, comingSoon: false)
                    }
                    .buttonStyle(.plain)
                }

                AppTile(symbol: "music.note", title: "Music", comingSoon: true)
                AppTile(symbol: "gauge.open.with.lines.needle.33percent", title: "Speedometer", comingSoon: true)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private struct AppTile: View {

    let symbol: String
    let title: String
    let comingSoon: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40))
            Text(title)
                .font(.headline)
            if comingSoon {
                Text("Coming soon")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(comingSoon ? 0.04 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .foregroundStyle(comingSoon ? Color.secondary : Color.primary)
        .opacity(comingSoon ? 0.6 : 1)
    }
}
