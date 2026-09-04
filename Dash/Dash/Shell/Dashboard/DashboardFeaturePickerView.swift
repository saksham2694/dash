//
//  DashboardFeaturePickerView.swift
//  Dash
//
//  The "change this widget's feature" sheet (M8.2), shown from Dashboard edit
//  mode when the user taps an already-placed widget's feature-swap control.
//
//  Unlike `DashboardWidgetPickerView` (which picks a feature + size together for
//  a brand-new widget), this picker edits ONE existing placement: the size is
//  fixed to whatever the widget already is — only the feature changes. Only
//  features whose manifest supports that size are offered, so an incompatible
//  choice can't even be tapped.
//
//  Feature-agnostic like the Add Widget picker: it takes `[FeatureManifest]`
//  value types for identity/order/filtering (no hard-coded features), plus the
//  `FeatureRegistry` so each row can render the feature's REAL widget
//  presentation as its preview — `DashFeature.makeComponentView(size:)`, the
//  same generic seam `WidgetHostView` uses to render the widget itself. There is
//  no feature-specific rendering logic here (M8.2 §4 / §9): a newly registered
//  feature shows up with a working preview automatically.
//

import SwiftUI

struct DashboardFeaturePickerView: View {

    /// Every registered feature's manifest, in registry order.
    let manifests: [FeatureManifest]

    /// Resolves a manifest's id to its live `DashFeature`, purely to render each
    /// row's preview. Never consulted for filtering — `eligibleFeatures` (below)
    /// works from manifests alone.
    let registry: FeatureRegistry

    /// The widget's footprint — fixed for this edit; only the feature changes.
    let size: ComponentSize

    /// The feature currently filling this widget — shown with a selected state.
    let currentFeatureID: FeatureID

    /// The user chose a feature (possibly the one already assigned).
    let onSelect: (FeatureID) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The features eligible for this widget: those whose manifest supports
    /// `size`. Pure + tested — the whole reason an incompatible assignment can
    /// never reach the store (M8.2 §7).
    static func eligibleFeatures(_ manifests: [FeatureManifest], for size: ComponentSize) -> [FeatureManifest] {
        manifests.filter { $0.supportedSizes.contains(size) }
    }

    private var features: [FeatureManifest] { Self.eligibleFeatures(manifests, for: size) }

    var body: some View {
        NavigationStack {
            ZStack {
                // Modal sheet: the shell wallpaper isn't in this view's
                // environment, so draw the default field — matches
                // `DashboardWidgetPickerView`.
                DashWallpaperView(wallpaper: WallpaperCatalog.default)
                    .ignoresSafeArea()

                if features.isEmpty {
                    ContentUnavailableView(
                        "No compatible features",
                        systemImage: "square.grid.2x2",
                        description: Text("No registered feature supports this widget's size.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: DashMetrics.spacingMedium) {
                            ForEach(features) { manifest in
                                featureRow(manifest)
                            }
                        }
                        .padding(DashMetrics.spacingMedium)
                    }
                }
            }
            .navigationTitle("Change Widget")
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
    private func featureRow(_ manifest: FeatureManifest) -> some View {
        let selected = manifest.id == currentFeatureID
        Button {
            onSelect(manifest.id)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: DashMetrics.spacingSmall) {
                HStack(spacing: DashMetrics.spacingMedium) {
                    DashAppIcon(manifest: manifest, size: 44)
                    Text(manifest.title)
                        .font(.dashControl)
                        .foregroundStyle(Color.dashTextPrimary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.dashAccent : Color.dashTextTertiary)
                }
                FeaturePreviewThumbnail(registry: registry, featureID: manifest.id, size: size)
            }
            .padding(DashMetrics.spacingMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashGlassSurface(cornerRadius: DashMetrics.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DashMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(selected ? Color.dashAccent : .clear, lineWidth: DashMetrics.focusStroke)
            )
        }
        .buttonStyle(.dashPress)
        .accessibilityLabel("\(manifest.title)\(selected ? ", currently selected" : "")")
    }
}

/// A small live preview of a feature at a fixed widget size — the exact same
/// view a dashboard widget would show. No feature-specific rendering logic
/// lives here: `makeComponentView(size:)` is the one generic seam every
/// registered feature already implements, so Speedometer shows its real dial,
/// Google Maps its real map widget, and a placeholder its real "not set up yet"
/// panel — automatically, with nothing added when a feature is registered.
private struct FeaturePreviewThumbnail: View {

    let registry: FeatureRegistry
    let featureID: FeatureID
    let size: ComponentSize

    /// A representative thumbnail footprint per widget size — small enough for
    /// a picker row, proportioned roughly like the real dashboard column.
    static func thumbnailSize(for size: ComponentSize) -> CGSize {
        switch size {
        case .compact: return CGSize(width: 260, height: 64)
        case .medium:  return CGSize(width: 220, height: 130)
        case .large:   return CGSize(width: 220, height: 220)
        case .full:    return CGSize(width: 260, height: 150)
        }
    }

    var body: some View {
        let dimensions = Self.thumbnailSize(for: size)
        Group {
            if let feature = registry.feature(featureID) {
                feature.makeComponentView(size: size)
            } else {
                Color.dashCard
            }
        }
        .frame(width: dimensions.width, height: dimensions.height)
        .clipShape(RoundedRectangle(cornerRadius: DashMetrics.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DashMetrics.controlCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: DashMetrics.hairline)
        )
        // A preview, not a control — the live map / player beneath it must
        // never steal the row's tap.
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Change Widget — compact") {
    DashboardFeaturePickerView(
        manifests: FeatureRegistry.makeDefault().manifests,
        registry: .makeDefault(),
        size: .compact,
        currentFeatureID: "maps",
        onSelect: { _ in }
    )
    .environmentObject(LocationStore())
}

#Preview("Change Widget — medium") {
    DashboardFeaturePickerView(
        manifests: FeatureRegistry.makeDefault().manifests,
        registry: .makeDefault(),
        size: .medium,
        currentFeatureID: SpeedometerFeature.id,
        onSelect: { _ in }
    )
    .environmentObject(LocationStore())
}
#endif
