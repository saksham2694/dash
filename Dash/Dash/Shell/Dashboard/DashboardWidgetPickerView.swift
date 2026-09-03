//
//  DashboardWidgetPickerView.swift
//  Dash
//
//  The "Add Widget" sheet, shown only from Dashboard edit mode (M5.4.2).
//
//  A plain custom SwiftUI list — **not** a system/document picker. It lists every
//  registered feature (title + SF Symbol) and, per feature, only the widget
//  sizes that feature's `DashFeature` manifest supports. Picking a feature + size
//  calls `onSelect` and dismisses; the store then auto-places the widget.
//
//  Feature-agnostic: it takes `[FeatureManifest]` value types, never the
//  registry, a `DashFeature`, or any Maps-specific type. No hard-coded features.
//
//  Intentionally functional, not polished — final CarPlay styling is a later
//  milestone.
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

    var body: some View {
        NavigationStack {
            Group {
                if manifests.isEmpty {
                    ContentUnavailableView(
                        "No widgets available",
                        systemImage: "square.grid.2x2",
                        description: Text("No features are registered yet.")
                    )
                } else {
                    List(manifests) { manifest in
                        featureSection(manifest)
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
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func featureSection(_ manifest: FeatureManifest) -> some View {
        let sizes = Self.offeredSizes(for: manifest)

        Section {
            if sizes.isEmpty {
                Text("No widget sizes for this feature")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sizes, id: \.self) { size in
                    Button {
                        onSelect(manifest.id, size)
                        dismiss()
                    } label: {
                        sizeRow(size)
                    }
                }
            }
        } header: {
            Label {
                Text(manifest.title)
            } icon: {
                Image(systemName: manifest.symbolName)
            }
            .font(.headline)
            .textCase(nil)
        }
    }

    private func sizeRow(_ size: ComponentSize) -> some View {
        HStack(spacing: 14) {
            SizeSwatch(size: size)
            Text(sizeName(size))
                .font(.body.weight(.medium))
            Spacer()
            Text(spanText(size))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.accentColor)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Add \(sizeName(size)) widget")
    }

    private func sizeName(_ size: ComponentSize) -> String {
        size.rawValue.prefix(1).uppercased() + size.rawValue.dropFirst()
    }

    /// Cell footprint on the standard grid, purely as a hint in the row.
    private func spanText(_ size: ComponentSize) -> String {
        let span = DashboardGrid.standard.span(for: size)
        return "\(span.columns)×\(span.rows)"
    }
}

/// A tiny proportional glyph so the size being added is unmistakable.
private struct SizeSwatch: View {
    let size: ComponentSize

    var body: some View {
        let span = DashboardGrid.standard.span(for: size)
        let unit: CGFloat = 6
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor.opacity(0.85))
            .frame(
                width: unit * CGFloat(span.columns),
                height: unit * CGFloat(span.rows)
            )
            .frame(width: unit * 6, height: unit * 4, alignment: .topLeading)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.secondary.opacity(0.35))
                    .frame(width: unit * 6, height: unit * 4)
            )
    }
}
