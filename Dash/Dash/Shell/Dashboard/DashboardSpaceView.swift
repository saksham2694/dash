//
//  DashboardSpaceView.swift
//  Dash
//
//  The widget dashboard surface. Reads `DashboardLayoutStore` for the current
//  page's placements, resolves each `WidgetPlacement.featureID` through
//  `FeatureRegistry`, and asks the feature for a size-appropriate component
//  (`DashFeature.makeComponentView(size:)`).
//
//  Replaces `DashboardPlaceholderView`. It knows nothing about `MapViewModel` /
//  route / navigation — only `WidgetPlacement`, `DashFeature`, `FeatureRegistry`,
//  and the grid.
//
//  M5.3.0: each widget is a button. Tapping it forwards the placement's
//  `featureID` up through `onOpenFeature` (wired to `ShellStore.openApp` by
//  `DashboardShell`) — no feature-specific navigation logic here. No editing,
//  no drag, no resize.
//
//  M5.3.1: there is exactly ONE Dashboard space — no Dashboard pages, no page
//  controls. This renders the first (only) page. `DashboardLayout` keeps a page
//  model internally for a possible future customisation feature.
//
//  M5.4.1: an Edit / Done control toggles `DashboardEditModel`. In edit mode the
//  widgets show an "editing" border and their tap-to-open action is disabled —
//  no drag / resize / polish yet. Toggling edit mode is a pure presentation
//  concern: it never touches `ShellStore`, so the Dashboard stays put.
//

import SwiftUI

struct DashboardSpaceView: View {

    @ObservedObject var layoutStore: DashboardLayoutStore
    @ObservedObject var editModel: DashboardEditModel
    let registry: FeatureRegistry
    let grid: DashboardGrid

    /// Ask the shell to open a feature full-screen (a widget was tapped). The
    /// dashboard never touches `ShellStore` directly.
    let onOpenFeature: (FeatureID) -> Void

    private static let gap: CGFloat = 12

    /// The single Dashboard page. Exposed for tests; the shell never has to know
    /// anything about pages.
    var page: DashboardPage? { layoutStore.layout.pages.first }

    var body: some View {
        GeometryReader { proxy in
            gridBody(in: proxy.size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .overlay(alignment: .topTrailing) {
            editControl.padding(18)
        }
        .animation(.easeInOut(duration: 0.2), value: editModel.isEditing)
    }

    // MARK: - Edit / Done

    private var editControl: some View {
        Button {
            editModel.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: editModel.isEditing ? "checkmark" : "slider.horizontal.3")
                Text(editModel.isEditing ? "Done" : "Edit")
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(editModel.isEditing ? Color.accentColor : Color.white.opacity(0.14))
            )
            .foregroundStyle(editModel.isEditing ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(editModel.isEditing ? "Done editing the dashboard" : "Edit the dashboard")
    }

    // MARK: - Grid

    @ViewBuilder
    private func gridBody(in size: CGSize) -> some View {
        let cellW = (size.width - Self.gap * CGFloat(grid.columns - 1)) / CGFloat(max(1, grid.columns))
        let cellH = (size.height - Self.gap * CGFloat(grid.rows - 1)) / CGFloat(max(1, grid.rows))

        ZStack(alignment: .topLeading) {
            if let page, !page.placements.isEmpty {
                ForEach(page.placements) { placement in
                    let span = grid.span(for: placement.size)
                    WidgetHostView(
                        placement: placement,
                        registry: registry,
                        onOpenFeature: onOpenFeature,
                        isEditing: editModel.isEditing
                    )
                        .frame(
                            width: cellW * CGFloat(span.columns) + Self.gap * CGFloat(span.columns - 1),
                            height: cellH * CGFloat(span.rows) + Self.gap * CGFloat(span.rows - 1)
                        )
                        .offset(
                            x: (cellW + Self.gap) * CGFloat(placement.origin.column),
                            y: (cellH + Self.gap) * CGFloat(placement.origin.row)
                        )
                }
            } else {
                emptyPage
            }
        }
        .animation(.easeInOut(duration: 0.2), value: page?.id)
    }

    private var emptyPage: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.dashed").font(.system(size: 40))
            Text("Nothing on the dashboard yet").font(.callout)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Frames one placement as a **button**: the feature's component when it
/// resolves, otherwise a clearly-labelled fallback. Tapping anywhere on the tile
/// forwards `placement.featureID` to `onOpenFeature` (M5.3.0) — the tile knows
/// nothing about which feature that is or how it opens.
///
/// M5.4.1: while `isEditing` the open action is disabled and the tile shows a
/// dashed "editing" border. No drag / resize yet.
struct WidgetHostView: View {

    let placement: WidgetPlacement
    let registry: FeatureRegistry
    let onOpenFeature: (FeatureID) -> Void

    /// Whether the Dashboard is in edit mode. Disables tap-to-open.
    var isEditing: Bool = false

    /// The tap action — the tile's whole job. A no-op while editing. Exposed for
    /// tests.
    func activate() {
        guard !isEditing else { return }
        onOpenFeature(placement.featureID)
    }

    private var featureTitle: String {
        registry.feature(placement.featureID)?.manifest.title ?? placement.featureID
    }

    var body: some View {
        Button(action: activate) {
            content
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                )
                .overlay {
                    if isEditing {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                Color.accentColor.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                            )
                    }
                }
                .opacity(isEditing ? 0.85 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(WidgetButtonStyle())
        .disabled(isEditing)
        .accessibilityHint(isEditing ? "Editing the dashboard" : "Opens \(featureTitle)")
    }

    @ViewBuilder
    private var content: some View {
        if placement.size.isWidget,
           let feature = registry.feature(placement.featureID),
           feature.manifest.supportedSizes.contains(placement.size) {
            feature.makeComponentView(size: placement.size)
        } else {
            UnresolvedWidgetView(placement: placement)
        }
    }
}

/// A light press feedback so a tile reads as tappable — no chrome, no elaborate
/// animation (M5.3.0).
private struct WidgetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct UnresolvedWidgetView: View {

    let placement: WidgetPlacement

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle").font(.title3)
            Text(placement.featureID).font(.subheadline.weight(.medium))
            Text("Can't show \(placement.size.rawValue) widget")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
