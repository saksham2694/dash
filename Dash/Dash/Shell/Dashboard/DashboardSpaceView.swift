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
//  route / navigation — only `DashFeature`, `FeatureRegistry`, and the grid.
//
//  M5.2.0 scope: the grid + placeholder components only. `MapFeature`'s
//  component is still a labelled placeholder (real reduced-map / maneuver
//  rendering is M5.2.1). No editing, no drag, no resize.
//

import SwiftUI

struct DashboardSpaceView: View {

    @ObservedObject var layoutStore: DashboardLayoutStore
    let registry: FeatureRegistry
    let grid: DashboardGrid

    /// Which page the shell wants shown (`ShellSurface.dashboard(page:)`).
    let requestedPage: Int

    /// Ask the shell to move to a page.
    let onSelectPage: (Int) -> Void

    private static let gap: CGFloat = 12

    /// `requestedPage` clamped to the pages that actually exist. Exposed for
    /// tests; the shell never has to know the page count.
    var resolvedPageIndex: Int {
        let count = layoutStore.layout.pageCount
        guard count > 0 else { return 0 }
        return min(max(0, requestedPage), count - 1)
    }

    private var page: DashboardPage? { layoutStore.layout.page(at: resolvedPageIndex) }
    private var pageCount: Int { layoutStore.layout.pageCount }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                gridBody(in: proxy.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if pageCount > 1 {
                pageControls
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
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
                    WidgetHostView(placement: placement, registry: registry)
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
        .animation(.easeInOut(duration: 0.2), value: resolvedPageIndex)
    }

    private var emptyPage: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.dashed").font(.system(size: 40))
            Text("Nothing on this page yet").font(.callout)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pages

    private var pageControls: some View {
        HStack(spacing: 18) {
            Button { onSelectPage(resolvedPageIndex - 1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(resolvedPageIndex == 0)
            .accessibilityLabel("Previous page")

            HStack(spacing: 8) {
                ForEach(Array(0..<pageCount), id: \.self) { index in
                    Circle()
                        .fill(index == resolvedPageIndex ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Button { onSelectPage(resolvedPageIndex + 1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(resolvedPageIndex >= pageCount - 1)
            .accessibilityLabel("Next page")
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

/// Frames one placement: the feature's component when it resolves, otherwise a
/// clearly-labelled fallback (unknown feature, unsupported size, or a `.full`
/// size that doesn't belong on the dashboard).
private struct WidgetHostView: View {

    let placement: WidgetPlacement
    let registry: FeatureRegistry

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
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
