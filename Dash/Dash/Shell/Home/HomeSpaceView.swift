//
//  HomeSpaceView.swift
//  Dash
//
//  One page of the App-Home launcher. Renders the icons for a single `HomePage`,
//  resolving each placement's `featureID` through `FeatureRegistry` for the icon
//  + title, and — when an icon is tapped — forwards the `featureID` up through
//  `onOpenFeature` (wired to `ShellStore.openApp` by `DashboardShell`, the same
//  boundary `DashboardSpaceView` uses).
//
//  This view is NOT a pager. Horizontal navigation between the Dashboard and the
//  Home pages is one shell-level model (`SpacePagerView`); this view is just the
//  content of a single Home space. Icons start at the TOP-LEFT of the usable
//  area and fill left-to-right, then top-to-bottom — no centring.
//
//  Feature-agnostic: it knows only `HomePage` / `HomeAppPlacement` / `FeatureID`
//  / `FeatureManifest` and the open callback. No `ShellStore`, no view models.
//

import SwiftUI

struct HomeSpaceView: View {

    /// The page to render.
    let page: HomePage

    private let registry: FeatureRegistry

    /// Ask the shell to open a feature full-screen (an icon was tapped).
    private let onOpenFeature: (FeatureID) -> Void

    /// Presentation-only "coming soon" icons — **not** registered features and
    /// **not** persisted. Supplied by `DashboardShell`; only shown on the last
    /// Home page.
    private let comingSoon: [HomeComingSoonApp]

    init(
        page: HomePage,
        registry: FeatureRegistry,
        comingSoon: [HomeComingSoonApp] = [],
        onOpenFeature: @escaping (FeatureID) -> Void
    ) {
        self.page = page
        self.registry = registry
        self.comingSoon = comingSoon
        self.onOpenFeature = onOpenFeature
    }

    // MARK: - Test-facing

    /// The `featureID`s of this page's tiles, in slot order (top-left first).
    var featureIDs: [FeatureID] { page.apps.map(\.featureID) }

    // MARK: - Body

    /// Fixed-width icon columns — `HomeGrid.columns` of them — so icons flow
    /// left-to-right and wrap to a new row. Not adaptive/centred: the collection
    /// is anchored to the top-left of the usable area.
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(
                .fixed(HomeMetrics.slotWidth),
                spacing: HomeMetrics.columnSpacing,
                alignment: .top
            ),
            count: max(1, HomeGrid.columns)
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: HomeMetrics.rowSpacing) {
                ForEach(page.apps) { placement in
                    HomeAppTileButton(
                        manifest: registry.feature(placement.featureID)?.manifest,
                        featureID: placement.featureID,
                        onOpen: onOpenFeature
                    )
                }
                ForEach(comingSoon) { app in
                    HomeAppIcon(symbol: app.symbolName, title: app.title, dimmed: true)
                }
            }
            .padding(.top, HomeMetrics.topPadding)
            .padding(.leading, HomeMetrics.leadingPadding)
            .padding(.trailing, HomeMetrics.leadingPadding)
            .padding(.bottom, HomeMetrics.bottomPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.dashBackground)
    }
}

// MARK: - Metrics

private enum HomeMetrics {
    static let iconSize: CGFloat = 84
    static let iconCorner: CGFloat = 20
    static let glyphSize: CGFloat = 38
    static let labelSpacing: CGFloat = 10
    /// One icon + its label, with breathing room — the grid's fixed cell width.
    static let slotWidth: CGFloat = 128
    static let columnSpacing: CGFloat = 28
    static let rowSpacing: CGFloat = 34
    /// Sensible automotive inset from the top / left edges of the usable area.
    static let topPadding: CGFloat = 40
    static let leadingPadding: CGFloat = 44
    static let bottomPadding: CGFloat = 40
}

// MARK: - App icon

/// A tappable Home app icon. Tapping forwards `featureID` — it knows nothing
/// about which feature that is or how it opens.
struct HomeAppTileButton: View {

    let manifest: FeatureManifest?
    let featureID: FeatureID
    let onOpen: (FeatureID) -> Void

    /// The tap action — the icon's whole job. Exposed for tests.
    func activate() { onOpen(featureID) }

    private var title: String { manifest?.title ?? featureID }
    private var symbol: String { manifest?.symbolName ?? "questionmark.app.dashed" }

    var body: some View {
        Button(action: activate) {
            HomeAppIcon(symbol: symbol, title: title)
        }
        .buttonStyle(HomeIconButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
        .accessibilityAddTraits(.isButton)
    }
}

/// The icon's visuals — a rounded-square glyph container with the title beneath.
/// Dumb and feature-agnostic; reused for real and "coming soon" icons.
struct HomeAppIcon: View {

    let symbol: String
    let title: String
    var dimmed: Bool = false

    var body: some View {
        VStack(spacing: HomeMetrics.labelSpacing) {
            RoundedRectangle(cornerRadius: HomeMetrics.iconCorner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.26), Color(white: 0.14)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HomeMetrics.iconCorner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: HomeMetrics.glyphSize, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .frame(width: HomeMetrics.iconSize, height: HomeMetrics.iconSize)
                .shadow(color: .black.opacity(0.45), radius: 9, y: 5)

            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: HomeMetrics.iconSize + 28)

            if dimmed {
                Text("Soon")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .opacity(dimmed ? 0.5 : 1)
    }
}

/// The pressed state — a deliberate spring scale-down on the whole icon + label.
private struct HomeIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Page dots

/// CarPlay-style page indicators — one small dot per **Home page** (never the
/// Dashboard), current highlighted, each a large-hit-target button that selects
/// its page. Owned here but positioned by `SpacePagerView`.
struct HomePageDots: View {

    let count: Int
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array(0..<max(0, count)), id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(index == current ? Color.dashTextPrimary : Color.dashTextTertiary)
                        .frame(width: 7, height: 7)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    index == current
                        ? "Home page \(index + 1) of \(count), current"
                        : "Home page \(index + 1) of \(count)"
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.dashSurface.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.dashSeparator, lineWidth: DashMetrics.hairline))
        .animation(.easeInOut(duration: 0.2), value: current)
    }
}

// MARK: - Coming-soon (presentation only)

/// A presentation-only icon for an app that isn't built yet.
struct HomeComingSoonApp: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let symbolName: String
}
