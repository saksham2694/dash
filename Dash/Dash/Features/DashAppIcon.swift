//
//  DashAppIcon.swift
//  Dash
//
//  Dash's app-icon system — a colourful rounded-square container with a
//  centered SF Symbol glyph, plus a soft drop shadow and a hairline edge. Used
//  by the Home launcher AND the sidebar's recent-apps rail so every surface
//  renders a feature identically — and, since M8.4, by the Settings feature's
//  Apps list, so Settings shows the SAME icons rather than a second mapping.
//
//  A feature's colour comes from its `FeatureManifest.iconStyle`: `.pinned` uses
//  a chosen `FeatureTint`; `.automatic` derives a stable tint from the id, so a
//  new feature is colourful and coherent with zero config. Feature-agnostic —
//  it only reads the manifest.
//
//  Lives at `Features/` root (M8.4) — not `Shell/` — alongside `ComponentSize`
//  and `SpeedometerUnit`, for the same reason: it's cross-cutting vocabulary
//  the shell AND a feature (Settings) both legitimately need, and a feature
//  may never import `Shell/` (CLAUDE.md).
//

import SwiftUI

struct DashAppIcon: View {

    let symbolName: String
    let tint: FeatureTint
    /// Artwork edge length.
    var size: CGFloat = 88
    /// Dim + desaturate for a "coming soon" / unavailable tile.
    var dimmed: Bool = false

    // MARK: - Tint resolution (pure, testable)

    /// A run-independent hash so `.automatic` picks the same colour every launch
    /// (`String.hashValue` is per-process randomised).
    static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return abs(hash)
    }

    static func tint(for style: FeatureIconStyle, id: FeatureID) -> FeatureTint {
        switch style {
        case .pinned(let tint):
            return tint
        case .automatic:
            let palette = FeatureTint.allCases
            return palette[stableHash(id) % palette.count]
        }
    }

    /// A local recognisable-asset name to prefer over the procedural face, if the
    /// developer has dropped one into `LocalAssets/` (e.g. `app-icon-maps`).
    var localAssetName: String?

    // MARK: - Init

    init(manifest: FeatureManifest, size: CGFloat = 88, dimmed: Bool = false) {
        self.symbolName = manifest.symbolName
        self.tint = Self.tint(for: manifest.iconStyle, id: manifest.id)
        self.size = size
        self.dimmed = dimmed
        self.localAssetName = manifest.iconAssetName ?? "app-icon-\(manifest.id)"
    }

    /// For a placeholder tile that has no manifest yet.
    init(symbolName: String, tint: FeatureTint, size: CGFloat = 88, dimmed: Bool = false) {
        self.symbolName = symbolName
        self.tint = tint
        self.size = size
        self.dimmed = dimmed
        self.localAssetName = nil
    }

    // MARK: - Body

    private var corner: CGFloat { size * 0.28 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: corner, style: .continuous) }

    var body: some View {
        face
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.36), radius: size * 0.10, y: size * 0.055)
            .opacity(dimmed ? 0.45 : 1)
            .saturation(dimmed ? 0.35 : 1)
    }

    @ViewBuilder
    private var face: some View {
        if let localAssetName, let image = DashLocalAssets.image(named: localAssetName) {
            image.resizable().scaledToFill()
        } else {
            shape
                .fill(tint.iconGradient)
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), .clear],
                            startPoint: .top, endPoint: .center
                        )
                    )
                )
                .overlay(
                    Image(systemName: symbolName)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.28), radius: 1, y: 1)
                )
        }
    }
}

// MARK: - FeatureTint → colour (shell-side presentation)

extension FeatureTint {

    /// The base fill colour for this tint.
    var color: Color {
        switch self {
        case .blue:     return Color(red: 0.13, green: 0.47, blue: 0.96)
        case .teal:     return Color(red: 0.10, green: 0.62, blue: 0.66)
        case .green:    return Color(red: 0.18, green: 0.62, blue: 0.34)
        case .indigo:   return Color(red: 0.29, green: 0.31, blue: 0.79)
        case .purple:   return Color(red: 0.51, green: 0.28, blue: 0.78)
        case .pink:     return Color(red: 0.87, green: 0.29, blue: 0.51)
        case .orange:   return Color(red: 0.93, green: 0.52, blue: 0.16)
        case .red:      return Color(red: 0.87, green: 0.26, blue: 0.24)
        case .graphite: return Color(red: 0.30, green: 0.33, blue: 0.38)
        }
    }

    /// A gentle top-to-bottom gradient of the tint for an icon face.
    var iconGradient: LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.98), color.opacity(0.74)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

#Preview {
    ZStack {
        DashWallpaperView(wallpaper: WallpaperCatalog.default).ignoresSafeArea()
        HStack(spacing: 16) {
            ForEach(FeatureTint.allCases, id: \.self) { tint in
                DashAppIcon(symbolName: "map.fill", tint: tint, size: 64)
            }
        }
        .padding()
    }
}
