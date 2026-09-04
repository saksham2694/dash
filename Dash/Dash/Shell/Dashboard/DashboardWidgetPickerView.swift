//
//  DashboardWidgetPickerView.swift
//  Dash
//
//  The "Add Widget" sheet, shown only from Dashboard edit mode (M5.4.2).
//
//  A plain custom SwiftUI list — **not** a system/document picker. It lists every
//  registered feature that has at least one widget size and, per feature, only
//  the widget sizes that feature's `DashFeature` manifest supports. Picking a
//  feature + size calls `onSelect` and dismisses; the store then auto-places the
//  widget.
//
//  Feature-agnostic: it takes `[FeatureManifest]` value types, never the
//  registry, a `DashFeature`, or any Maps-specific type. No hard-coded features.
//
//  M5.5.2b: styled to the shell's glass language (translucent rows over
//  `DashShellBackground`, rounded surfaces, restrained accent) and each size row
//  carries an **accurate footprint preview** — a 2×6 grid frame with the size's
//  real 1×2 / 1×3 / 1×6 cell footprint filled in, so Large = full height,
//  Medium = half, Compact = one third is unmistakable.
//

import SwiftUI

struct DashboardWidgetPickerView: View {

    /// Every registered feature's manifest, in registry order.
    let manifests: [FeatureManifest]

    /// The user chose a feature + widget size.
    let onSelect: (FeatureID, ComponentSize) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The widget sizes to offer for `manifest`: `ComponentSize.widgetSizes`
    /// order, filtered to those the feature actually supports. Pure + tested.
    static func offeredSizes(for manifest: FeatureManifest) -> [ComponentSize] {
        ComponentSize.widgetSizes.filter { manifest.supportedSizes.contains($0) }
    }

    /// The features worth showing — those with at least one widget size. Pure +
    /// tested (a registered-but-not-implemented feature advertises none).
    static func placeableFeatures(_ manifests: [FeatureManifest]) -> [FeatureManifest] {
        manifests.filter { !offeredSizes(for: $0).isEmpty }
    }

    private var features: [FeatureManifest] { Self.placeableFeatures(manifests) }

    var body: some View {
        NavigationStack {
            ZStack {
                // A modal sheet: the shell wallpaper isn't in this view's
                // environment, so draw the default field rather than the live
                // selection — the sheet just needs the shell's dark ground.
                DashWallpaperView(wallpaper: WallpaperCatalog.default)
                    .ignoresSafeArea()

                Group {
                    if features.isEmpty {
                        ContentUnavailableView(
                            "No widgets available",
                            systemImage: "square.grid.2x2",
                            description: Text("No features offer a dashboard widget yet.")
                        )
                    } else {
                        ScrollView {
                            VStack(spacing: DashMetrics.spacingMedium) {
                                ForEach(features) { manifest in
                                    featureCard(manifest)
                                }
                            }
                            .padding(DashMetrics.spacingMedium)
                        }
                    }
                }
            }
            .navigationTitle("Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func featureCard(_ manifest: FeatureManifest) -> some View {
        VStack(alignment: .leading, spacing: DashMetrics.spacingSmall) {
            Label {
                Text(manifest.title).font(.dashControl)
            } icon: {
                Image(systemName: manifest.symbolName).foregroundStyle(Color.dashTextSecondary)
            }
            .foregroundStyle(Color.dashTextPrimary)

            ForEach(Self.offeredSizes(for: manifest), id: \.self) { size in
                Button {
                    onSelect(manifest.id, size)
                    dismiss()
                } label: {
                    sizeRow(size)
                }
                .buttonStyle(.dashPress)
            }
        }
        .padding(DashMetrics.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashGlassSurface(cornerRadius: DashMetrics.cardCornerRadius)
    }

    private func sizeRow(_ size: ComponentSize) -> some View {
        HStack(spacing: 16) {
            WidgetFootprintPreview(size: size)
            VStack(alignment: .leading, spacing: 2) {
                Text(sizeName(size))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.dashTextPrimary)
                Text(footprintText(size))
                    .font(.dashCaption)
                    .foregroundStyle(Color.dashTextSecondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.dashAccent)
        }
        .padding(.vertical, DashMetrics.spacingTight)
        .contentShape(Rectangle())
        .accessibilityLabel("Add \(sizeName(size)) widget")
    }

    private func sizeName(_ size: ComponentSize) -> String {
        size.rawValue.prefix(1).uppercased() + size.rawValue.dropFirst()
    }

    /// A plain-language description of the footprint on the 2×6 dashboard.
    private func footprintText(_ size: ComponentSize) -> String {
        switch size {
        case .compact: return "One third of a column"
        case .medium:  return "Half a column"
        case .large:   return "A full-height column"
        case .full:    return "Full dashboard"
        }
    }
}

/// An accurate footprint preview: the 2×6 dashboard grid drawn to scale with the
/// size's real 1×N cell footprint filled in the leading column.
struct WidgetFootprintPreview: View {

    let size: ComponentSize

    /// Cells the size occupies on the standard grid. Pure passthrough — exposed
    /// so a test can assert the preview matches `DashboardGrid.span(for:)`.
    static func span(for size: ComponentSize) -> GridSpan {
        DashboardGrid.standard.span(for: size)
    }

    var body: some View {
        let grid = DashboardGrid.standard
        let span = Self.span(for: size)
        let unit: CGFloat = 8
        let cellGap: CGFloat = 2
        let frameW = unit * CGFloat(grid.columns) + cellGap * CGFloat(grid.columns - 1)
        let frameH = unit * CGFloat(grid.rows) + cellGap * CGFloat(grid.rows - 1)
        let footW = unit * CGFloat(span.columns) + cellGap * CGFloat(max(0, span.columns - 1))
        let footH = unit * CGFloat(span.rows) + cellGap * CGFloat(max(0, span.rows - 1))

        ZStack(alignment: .topLeading) {
            // Empty grid cells.
            VStack(spacing: cellGap) {
                ForEach(0..<grid.rows, id: \.self) { _ in
                    HStack(spacing: cellGap) {
                        ForEach(0..<grid.columns, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: unit, height: unit)
                        }
                    }
                }
            }

            // The size's footprint.
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.dashAccent)
                .frame(width: footW, height: footH)
        }
        .frame(width: frameW, height: frameH, alignment: .topLeading)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: DashMetrics.hairline)
        )
        .accessibilityHidden(true)
    }
}
