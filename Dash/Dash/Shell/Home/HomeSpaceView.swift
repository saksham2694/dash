//
//  HomeSpaceView.swift
//  Dash
//
//  One page of the App-Home launcher — an automotive app grid, not an iPad
//  `LazyVGrid` of cards. Large colourful `DashAppIcon`s with the app name on a
//  dark pill beneath, filling the canvas left-to-right then top-to-bottom.
//
//  It resolves each placement's `featureID` through `FeatureRegistry` for the
//  icon identity and — when an icon is tapped — forwards the `featureID` up
//  through `onOpenFeature` (wired to `ShellStore.openApp` by `DashboardShell`).
//
//  Not a pager. Horizontal navigation between the Dashboard and the Home pages
//  is one shell-level model (`SpacePagerView`); this view is just the content of
//  a single Home space and draws no ground (it sits on `DashShellBackground`).
//
//  Feature-agnostic: knows only `HomePage` / `HomeAppPlacement` / `FeatureID` /
//  `FeatureManifest` and the open callback.
//

import SwiftUI

struct HomeSpaceView: View {

    /// The page to render.
    let page: HomePage

    private let registry: FeatureRegistry

    /// Ask the shell to open a feature full-screen (an icon was tapped).
    private let onOpenFeature: (FeatureID) -> Void

    init(
        page: HomePage,
        registry: FeatureRegistry,
        onOpenFeature: @escaping (FeatureID) -> Void
    ) {
        self.page = page
        self.registry = registry
        self.onOpenFeature = onOpenFeature
    }

    // MARK: - Test-facing

    /// The `featureID`s of this page's tiles, in slot order (top-left first).
    var featureIDs: [FeatureID] { page.apps.map(\.featureID) }

    // MARK: - Body

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: HomeMetrics.columnSpacing, alignment: .top),
            count: max(1, HomeGrid.columns)
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: HomeMetrics.rowSpacing) {
                ForEach(page.apps) { placement in
                    HomeAppTile(
                        manifest: registry.feature(placement.featureID)?.manifest,
                        featureID: placement.featureID,
                        onOpen: onOpenFeature
                    )
                }
            }
            .padding(.horizontal, HomeMetrics.edgeInset)
            .padding(.top, HomeMetrics.topInset)
            .padding(.bottom, HomeMetrics.bottomInset)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Metrics

private enum HomeMetrics {
    static let iconSize: CGFloat = 108
    static let labelSpacing: CGFloat = 12
    static let columnSpacing: CGFloat = 30
    static let rowSpacing: CGFloat = 40
    static let edgeInset: CGFloat = 44
    static let topInset: CGFloat = 44
    static let bottomInset: CGFloat = 44
}

// MARK: - Tiles

/// A tappable Home app tile. Forwards `featureID` — it knows nothing about which
/// feature that is or how it opens.
struct HomeAppTile: View {

    let manifest: FeatureManifest?
    let featureID: FeatureID
    let onOpen: (FeatureID) -> Void

    /// The tap action — exposed for tests.
    func activate() { onOpen(featureID) }

    private var title: String { manifest?.title ?? featureID }

    var body: some View {
        Button(action: activate) {
            VStack(spacing: HomeMetrics.labelSpacing) {
                icon
                HomeAppLabel(text: title)
            }
        }
        .buttonStyle(.dashPress)
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var icon: some View {
        if let manifest {
            DashAppIcon(manifest: manifest, size: HomeMetrics.iconSize)
        } else {
            DashAppIcon(symbolName: "questionmark.app.dashed", tint: .graphite, size: HomeMetrics.iconSize)
        }
    }
}

/// The app name on a dark rounded pill, CarPlay-style — compact, translucent,
/// readable. Not a bordered SwiftUI button.
private struct HomeAppLabel: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.dashTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().fill(Color.black.opacity(0.22)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: DashMetrics.hairline))
            .clipShape(Capsule())
    }
}

// MARK: - Page dots

/// CarPlay-style page indicators — one small dot per **Home page** (never the
/// Dashboard), current highlighted, each a large-hit-target button. Positioned
/// by `SpacePagerView`.
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
        .background {
            Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(Color.dashPanelTint))
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: DashMetrics.hairline))
        .animation(.easeInOut(duration: 0.2), value: current)
    }
}
