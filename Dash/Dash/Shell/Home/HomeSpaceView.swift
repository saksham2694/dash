//
//  HomeSpaceView.swift
//  Dash
//
//  The App-Home launcher surface (M5.3.0) — replaces `HomePlaceholderView`.
//  Reads `HomeLayoutStore` for the current page's app placements, resolves each
//  `featureID` through `FeatureRegistry` for the tile's icon + title, and — when
//  a tile is tapped — forwards the `featureID` up through `onOpenFeature`
//  (wired to `ShellStore.openApp` by `DashboardShell`, the same boundary
//  `DashboardSpaceView` uses).
//
//  Completely feature-agnostic: it knows only `HomeAppPlacement`, `FeatureID`,
//  `FeatureManifest`, and the callbacks. No `ShellStore`, no feature view models.
//
//  M5.3.0 scope: the paged launcher model + real tappable tiles. No swipe
//  gesture, no reorder / edit UI, no final icon design.
//

import SwiftUI

struct HomeSpaceView: View {

    @ObservedObject var layoutStore: HomeLayoutStore
    let registry: FeatureRegistry

    /// Which page the shell wants shown (`ShellSurface.home(page:)`).
    let requestedPage: Int

    /// Ask the shell to move to a page.
    let onSelectPage: (Int) -> Void

    /// Ask the shell to open a feature full-screen (a tile was tapped).
    let onOpenFeature: (FeatureID) -> Void

    /// Presentation-only "coming soon" tiles — **not** registered features and
    /// **not** persisted. Supplied by `DashboardShell` so the grid reads
    /// correctly while only one real feature exists.
    var comingSoon: [HomeComingSoonApp] = []

    private static let columns = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 20)]

    /// `requestedPage` clamped to the pages that exist. Exposed for tests; the
    /// shell never has to know the page count.
    var resolvedPageIndex: Int {
        layoutStore.layout.clampedPageIndex(requestedPage)
    }

    /// The `featureID`s of the tiles on the current page — for tests.
    var currentPageFeatureIDs: [FeatureID] {
        (layoutStore.layout.page(at: resolvedPageIndex)?.apps ?? []).map(\.featureID)
    }

    private var pageCount: Int { layoutStore.layout.pageCount }
    private var isLastPage: Bool { resolvedPageIndex >= pageCount - 1 }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 20) {
                    ForEach(layoutStore.layout.page(at: resolvedPageIndex)?.apps ?? []) { placement in
                        HomeAppTileButton(
                            manifest: registry.feature(placement.featureID)?.manifest,
                            featureID: placement.featureID,
                            onOpen: onOpenFeature
                        )
                    }

                    if isLastPage {
                        ForEach(comingSoon) { app in
                            HomeAppTile(symbol: app.symbolName, title: app.title, comingSoon: true)
                        }
                    }
                }
                .padding(28)
            }

            if pageCount > 1 {
                HomePageControls(current: resolvedPageIndex, count: pageCount, onSelect: onSelectPage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

/// A presentation-only tile for an app that isn't built yet.
struct HomeComingSoonApp: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let symbolName: String
}

// MARK: - Tiles

/// A tappable Home app tile. Tapping forwards `featureID` — it knows nothing
/// about which feature that is or how it opens.
struct HomeAppTileButton: View {

    let manifest: FeatureManifest?
    let featureID: FeatureID
    let onOpen: (FeatureID) -> Void

    /// The tap action — the tile's whole job. Exposed for tests.
    func activate() { onOpen(featureID) }

    private var title: String { manifest?.title ?? featureID }
    private var symbol: String { manifest?.symbolName ?? "questionmark.app.dashed" }

    var body: some View {
        Button(action: activate) {
            HomeAppTile(symbol: symbol, title: title)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(HomeTileButtonStyle())
        .accessibilityHint("Opens \(title)")
    }
}

/// The tile's visuals — dumb, reused for real and "coming soon" tiles.
struct HomeAppTile: View {

    let symbol: String
    let title: String
    var comingSoon: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40))
            Text(title)
                .font(.headline)
                .lineLimit(1)
            if comingSoon {
                Text("Coming soon")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(comingSoon ? 0.04 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .foregroundStyle(comingSoon ? Color.secondary : Color.primary)
        .opacity(comingSoon ? 0.6 : 1)
    }
}

/// A light press feedback so a tile reads as tappable — no elaborate animation.
private struct HomeTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Pages

private struct HomePageControls: View {

    let current: Int
    let count: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button { onSelect(current - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(current == 0)
                .accessibilityLabel("Previous page")

            HStack(spacing: 8) {
                ForEach(Array(0..<count), id: \.self) { index in
                    Circle()
                        .fill(index == current ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Button { onSelect(current + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(current >= count - 1)
                .accessibilityLabel("Next page")
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
