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
//  widgets show an "editing" border and their tap-to-open action is disabled.
//
//  M5.4.2: edit mode is now usable — an "Add Widget" custom picker sheet
//  (deterministic first-fit auto-placement), a per-widget Remove control, and a
//  per-widget size Menu. Every mutation goes through `DashboardLayoutStore`
//  (never a direct `DashboardLayout` edit from the view); a change that doesn't
//  fit is reported in an alert, not applied. Still no drag / resize gestures and
//  no final styling — that is M5.4.3.
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

    @State private var showingPicker = false
    @State private var editAlert: EditAlert?

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
            editControls.padding(18)
        }
        .animation(.easeInOut(duration: 0.2), value: editModel.isEditing)
        .sheet(isPresented: $showingPicker) {
            DashboardWidgetPickerView(manifests: registry.manifests) { featureID, size in
                addWidget(featureID, size)
            }
        }
        .alert(
            editAlert?.title ?? "",
            isPresented: Binding(
                get: { editAlert != nil },
                set: { if !$0 { editAlert = nil } }
            ),
            presenting: editAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: - Edit-mode actions (all through DashboardLayoutStore)

    private func addWidget(_ featureID: FeatureID, _ size: ComponentSize) {
        switch layoutStore.addWidget(featureID: featureID, size: size) {
        case .added:
            break
        case .noSpace, .rejected:
            editAlert = .noRoomToAdd
        }
    }

    private func removeWidget(_ id: UUID) {
        layoutStore.removePlacement(id: id)
    }

    private func resizeWidget(_ id: UUID, to size: ComponentSize) {
        if !layoutStore.updatePlacementSize(id: id, to: size) {
            editAlert = .sizeDoesNotFit
        }
    }

    // MARK: - Edit / Done / Add

    @ViewBuilder
    private var editControls: some View {
        HStack(spacing: 10) {
            if editModel.isEditing {
                Button {
                    showingPicker = true
                } label: {
                    pill(text: "Add Widget", systemImage: "plus", filled: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a widget")
            }

            Button {
                editModel.toggle()
            } label: {
                pill(
                    text: editModel.isEditing ? "Done" : "Edit",
                    systemImage: editModel.isEditing ? "checkmark" : "slider.horizontal.3",
                    filled: editModel.isEditing
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(editModel.isEditing ? "Done editing the dashboard" : "Edit the dashboard")
        }
    }

    private func pill(text: String, systemImage: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(Capsule().fill(filled ? Color.accentColor : Color.white.opacity(0.14)))
        .foregroundStyle(filled ? Color.white : Color.primary)
    }

    // MARK: - Alerts

    enum EditAlert: Identifiable {
        case noRoomToAdd
        case sizeDoesNotFit

        var id: Int { hashValue }

        var title: String {
            switch self {
            case .noRoomToAdd:   return "No room on the dashboard"
            case .sizeDoesNotFit: return "That size doesn’t fit here"
            }
        }

        var message: String {
            switch self {
            case .noRoomToAdd:
                return "Remove a widget or add a smaller one to make space."
            case .sizeDoesNotFit:
                return "There isn’t room for that size at this widget’s position. Remove or shrink a nearby widget first."
            }
        }
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
                        isEditing: editModel.isEditing,
                        onRemove: { removeWidget(placement.id) },
                        onResize: { resizeWidget(placement.id, to: $0) }
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
/// dashed "editing" border.
///
/// M5.4.2: in edit mode the tile is not a Button at all — instead it carries a
/// Remove control and a size Menu (only the feature's supported widget sizes).
/// Both call back to `DashboardSpaceView`, which routes them through
/// `DashboardLayoutStore`. No drag / resize gestures yet.
struct WidgetHostView: View {

    let placement: WidgetPlacement
    let registry: FeatureRegistry
    let onOpenFeature: (FeatureID) -> Void

    /// Whether the Dashboard is in edit mode. Disables tap-to-open and reveals
    /// the Remove / resize controls.
    var isEditing: Bool = false

    /// Edit-mode: remove this widget (→ `DashboardLayoutStore.removePlacement`).
    var onRemove: (() -> Void)? = nil

    /// Edit-mode: change this widget's size (→ `DashboardLayoutStore.updatePlacementSize`).
    var onResize: ((ComponentSize) -> Void)? = nil

    /// The tap action — the tile's whole job in normal mode. A no-op while
    /// editing. Exposed for tests.
    func activate() {
        guard !isEditing else { return }
        onOpenFeature(placement.featureID)
    }

    private var featureTitle: String {
        registry.feature(placement.featureID)?.manifest.title ?? placement.featureID
    }

    /// The feature's supported widget sizes, in `compact → large` order. Empty /
    /// single → no size control. Exposed for tests.
    var supportedWidgetSizes: [ComponentSize] {
        guard let manifest = registry.feature(placement.featureID)?.manifest else { return [] }
        return ComponentSize.widgetSizes.filter { manifest.supportedSizes.contains($0) }
    }

    var body: some View {
        if isEditing {
            editingTile
        } else {
            Button(action: activate) { styledContent }
                .buttonStyle(WidgetButtonStyle())
                .accessibilityHint("Opens \(featureTitle)")
        }
    }

    private var styledContent: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Editing chrome

    private var editingTile: some View {
        styledContent
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
            )
            .opacity(0.9)
            .overlay(alignment: .topLeading) { removeControl }
            .overlay(alignment: .bottomTrailing) { sizeControl }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(featureTitle) widget, editing")
    }

    private var removeControl: some View {
        Button(role: .destructive) {
            onRemove?()
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .background(Circle().fill(.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel("Remove \(featureTitle) widget")
    }

    @ViewBuilder
    private var sizeControl: some View {
        if supportedWidgetSizes.count > 1 {
            Menu {
                ForEach(supportedWidgetSizes, id: \.self) { size in
                    Button {
                        onResize?(size)
                    } label: {
                        if size == placement.size {
                            Label(sizeName(size), systemImage: "checkmark")
                        } else {
                            Text(sizeName(size))
                        }
                    }
                }
            } label: {
                Image(systemName: "square.resize")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(9)
                    .background(Circle().fill(.black.opacity(0.55)))
            }
            .padding(8)
            .accessibilityLabel("Change \(featureTitle) widget size")
        }
    }

    private func sizeName(_ size: ComponentSize) -> String {
        size.rawValue.prefix(1).uppercased() + size.rawValue.dropFirst()
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
