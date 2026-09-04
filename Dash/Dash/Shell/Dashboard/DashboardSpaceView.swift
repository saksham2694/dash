//
//  DashboardSpaceView.swift
//  Dash
//
//  The widget dashboard surface. Reads `DashboardLayoutStore` for the current
//  page's placements, resolves each `WidgetPlacement.featureID` through
//  `FeatureRegistry`, and asks the feature for a size-appropriate component
//  (`DashFeature.makeComponentView(size:)`).
//
//  It knows nothing about `MapViewModel` / route / navigation — only
//  `WidgetPlacement`, `DashFeature`, `FeatureRegistry`, and the grid.
//
//  M5.3.0: each widget is a button; tapping forwards its `featureID` up through
//  `onOpenFeature` (→ `ShellStore.openApp`).
//  M5.3.1: exactly ONE Dashboard space, no page controls — renders page 0.
//  M5.4.1: an Edit / Done control toggles `DashboardEditModel`; edit mode
//  disables tap-to-open.
//  M5.4.2: "Add Widget" picker (first-fit auto-placement), per-widget Remove
//  control and size Menu. Every mutation goes through `DashboardLayoutStore`.
//  M5.4.3: widgets are draggable (snap to grid) and resizable (bottom-trailing
//  handle steps through the feature's supported `ComponentSize` footprints;
//  bottom-leading size Menu unchanged) while editing. A live ghost shows where
//  the widget would land, red when invalid. Interaction state is transient view
//  state; only the final valid placement is committed — one `DashboardLayoutStore`
//  write per interaction, never per pixel.
//
//  M5.4.3 polish (device feedback): the move gesture uses `.global` coordinate
//  space so the live `.offset` can't feed back into `translation` (was causing
//  the widget to vibrate). No implicit animation tracks the drag — only the
//  ghost animates its cell-to-cell snap, and the drag-end settle is one
//  explicit `withAnimation`.
//
//  M5.5.1: colours / radii / spacing / typography come from `DashTheme`.
//
//  M5.5.2a: the dashboard is a two-column, six-row canvas (`DashboardGrid` 2×6)
//  so the CarPlay-style compositions (large + 2 medium / large + 3 compact)
//  tile the whole canvas with no half-width voids. Widgets sit on translucent
//  `.dashGlassSurface()` panels over `DashShellBackground`; this view draws no
//  ground of its own. Editing / drag / persistence behaviour is unchanged.
//

import SwiftUI

struct DashboardSpaceView: View {

    @ObservedObject var dashboards: DashboardCollectionStore
    @ObservedObject var editModel: DashboardEditModel
    let registry: FeatureRegistry
    let grid: DashboardGrid

    /// Ask the shell to open a feature full-screen (a widget was tapped). The
    /// dashboard never touches `ShellStore` directly.
    let onOpenFeature: (FeatureID) -> Void

    @State private var showingPicker = false
    @State private var showingDashboardManager = false
    @State private var editAlert: EditAlert?

    /// The in-flight drag / resize, if any. Transient — never persisted; the
    /// store is written once, on `end`.
    @State private var interaction: Interaction?

    private static let gap: CGFloat = DashMetrics.gridGap

    /// The single Dashboard page. Exposed for tests; the shell never has to know
    /// anything about pages.
    var page: DashboardPage? { dashboards.layout.pages.first }

    var body: some View {
        GeometryReader { proxy in
            gridBody(geometry: DashboardGridGeometry(
                grid: grid,
                canvas: proxy.size,
                gap: Self.gap,
                leftColumnFraction: DashMetrics.dashboardLeftColumnFraction
            ))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(DashMetrics.shellContentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            dashboardBar.padding(DashMetrics.spacingMedium)
        }
        .overlay(alignment: .topTrailing) {
            editControls.padding(DashMetrics.spacingMedium)
        }
        .animation(.easeInOut(duration: 0.2), value: editModel.isEditing)
        .animation(.easeInOut(duration: 0.2), value: dashboards.activeID)
        .sheet(isPresented: $showingPicker) {
            DashboardWidgetPickerView(manifests: registry.manifests) { featureID, size in
                addWidget(featureID, size)
            }
        }
        .sheet(isPresented: $showingDashboardManager) {
            DashboardManagerView(dashboards: dashboards)
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
        switch dashboards.addWidget(featureID: featureID, size: size) {
        case .added:
            break
        case .noSpace, .rejected:
            editAlert = .noRoomToAdd
        }
    }

    private func removeWidget(_ id: UUID) {
        dashboards.removePlacement(id: id)
    }

    private func resizeWidget(_ id: UUID, to size: ComponentSize) {
        if !dashboards.updatePlacementSize(id: id, to: size) {
            editAlert = .sizeDoesNotFit
        }
    }

    /// The feature's supported widget sizes, small→large. Drives the resize
    /// stepper and the size Menu; unsupported sizes are never offered.
    private func supportedWidgetSizes(_ featureID: FeatureID) -> [ComponentSize] {
        guard let manifest = registry.feature(featureID)?.manifest else { return [] }
        return ComponentSize.widgetSizes.filter { manifest.supportedSizes.contains($0) }
    }

    // MARK: - Drag to move / resize

    private func handleMove(
        _ placement: WidgetPlacement,
        translation: CGSize,
        ended: Bool,
        geometry: DashboardGridGeometry
    ) {
        let span = grid.span(for: placement.size)
        // `translation` is a pure one-shot delta from the committed origin (the
        // drag gesture uses `.global` space, so the live `.offset` never feeds
        // back into it). No mid-drag layout write moves that reference.
        let snapped = geometry.proposedOrigin(movingFrom: placement.origin, span: span, by: translation)
        let valid = dashboards.canMovePlacement(id: placement.id, to: snapped)

        var state = interaction ?? Interaction(kind: .move, placement: placement)
        guard state.kind == .move, state.placementID == placement.id else { return }
        state.translation = translation
        state.proposedOrigin = snapped
        state.valid = valid
        if valid { state.lastValidOrigin = snapped }

        if ended {
            // One transaction: the committed frame change and the transient
            // offset returning to zero animate together — they cancel out for a
            // valid drop landing under the finger, and spring back for an
            // invalid one. Nothing here is animated *during* the drag.
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                if state.lastValidOrigin != placement.origin {
                    dashboards.movePlacement(id: placement.id, to: state.lastValidOrigin)
                }
                interaction = nil
            }
        } else {
            interaction = state
        }
    }

    private func handleResize(
        _ placement: WidgetPlacement,
        translation: CGSize,
        ended: Bool,
        geometry: DashboardGridGeometry
    ) {
        let sizes = supportedWidgetSizes(placement.featureID)
        guard sizes.count > 1 else { return }

        let stepDistance = max(24, geometry.cell.width * 0.8)
        let target = DashboardResizeStepper.targetSize(
            current: placement.size,
            supported: sizes,
            translation: translation,
            stepDistance: stepDistance
        )
        let valid = dashboards.canResizePlacement(id: placement.id, to: target)

        var state = interaction ?? Interaction(kind: .resize, placement: placement)
        guard state.kind == .resize, state.placementID == placement.id else { return }
        state.translation = translation
        state.proposedSize = target
        state.valid = valid
        if valid { state.lastValidSize = target }

        if ended {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                if state.lastValidSize != placement.size {
                    if !dashboards.updatePlacementSize(id: placement.id, to: state.lastValidSize) {
                        editAlert = .sizeDoesNotFit
                    }
                }
                interaction = nil
            }
        } else {
            interaction = state
        }
    }

    /// While `placement` is being moved, the raw finger translation so the tile
    /// tracks the finger; otherwise `.zero`.
    private func liveMoveOffset(_ placement: WidgetPlacement) -> CGSize {
        guard let it = interaction, it.kind == .move, it.placementID == placement.id else { return .zero }
        return it.translation
    }

    // MARK: - Dashboards

    /// Whether to show the dashboard switcher. Hidden entirely for the common
    /// single-dashboard case in normal mode — it only appears once there is more
    /// than one dashboard, or while editing (where "Add Dashboard" lives).
    private var showsDashboardBar: Bool {
        dashboards.dashboardCount > 1 || editModel.isEditing
    }

    @ViewBuilder
    private var dashboardBar: some View {
        if showsDashboardBar {
            Button {
                showingDashboardManager = true
            } label: {
                HStack(spacing: DashMetrics.spacingTight) {
                    Text(dashboards.activeName)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.dashControl)
                .padding(.horizontal, DashMetrics.spacingMedium)
                .padding(.vertical, DashMetrics.spacingSmall)
                .background {
                    Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(Color.dashPanelTint))
                }
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: DashMetrics.hairline))
                .foregroundStyle(Color.dashTextPrimary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dashboard: \(dashboards.activeName)")
            .accessibilityHint("Switch, add, rename, or remove dashboards")
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
        HStack(spacing: DashMetrics.spacingTight) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.dashControl)
        .padding(.horizontal, DashMetrics.spacingMedium)
        .padding(.vertical, DashMetrics.spacingSmall)
        .background {
            if filled {
                Capsule().fill(Color.dashAccent)
            } else {
                Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(Color.dashPanelTint))
            }
        }
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: DashMetrics.hairline))
        .foregroundStyle(filled ? Color.dashOnAccent : Color.dashTextPrimary)
        .clipShape(Capsule())
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

    // MARK: - Interaction state

    struct Interaction {
        enum Kind { case move, resize }

        let kind: Kind
        let placementID: UUID
        let startOrigin: GridPoint
        let startSize: ComponentSize

        var translation: CGSize = .zero
        var proposedOrigin: GridPoint
        var proposedSize: ComponentSize
        var lastValidOrigin: GridPoint
        var lastValidSize: ComponentSize
        var valid: Bool = true

        init(kind: Kind, placement: WidgetPlacement) {
            self.kind = kind
            self.placementID = placement.id
            self.startOrigin = placement.origin
            self.startSize = placement.size
            self.proposedOrigin = placement.origin
            self.proposedSize = placement.size
            self.lastValidOrigin = placement.origin
            self.lastValidSize = placement.size
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private func gridBody(geometry: DashboardGridGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            if let page, !page.placements.isEmpty {
                ForEach(page.placements) { placement in
                    widgetTile(placement, geometry: geometry)
                }
                dragGhost(geometry: geometry)
            } else {
                emptyPage
            }
        }
        // Only the page-swap animates here. The live drag must NOT be animated
        // implicitly — an ancestor `.animation(value: proposedOrigin)` would ease
        // the tracked widget on every cell crossing, making it lag the finger.
        // Drag-end settle is animated explicitly in `handleMove` / `handleResize`;
        // the ghost animates its own snap in `dragGhost`.
        .animation(.easeInOut(duration: 0.2), value: page?.id)
    }

    @ViewBuilder
    private func widgetTile(_ placement: WidgetPlacement, geometry: DashboardGridGeometry) -> some View {
        let frame = geometry.frame(origin: placement.origin, span: grid.span(for: placement.size))
        let offset = liveMoveOffset(placement)
        let editing = editModel.isEditing

        WidgetHostView(
            placement: placement,
            registry: registry,
            onOpenFeature: onOpenFeature,
            isEditing: editing,
            isInteracting: interaction?.placementID == placement.id,
            onRemove: { removeWidget(placement.id) },
            onResize: { resizeWidget(placement.id, to: $0) },
            onMoveGesture: editing
                ? { translation, ended in handleMove(placement, translation: translation, ended: ended, geometry: geometry) }
                : nil,
            onResizeGesture: editing
                ? { translation, ended in handleResize(placement, translation: translation, ended: ended, geometry: geometry) }
                : nil
        )
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX + offset.width, y: frame.minY + offset.height)
        .zIndex(interaction?.placementID == placement.id ? 2 : 0)
    }

    @ViewBuilder
    private func dragGhost(geometry: DashboardGridGeometry) -> some View {
        if let it = interaction {
            let span = it.kind == .resize ? grid.span(for: it.proposedSize) : grid.span(for: it.startSize)
            let frame = geometry.frame(origin: it.proposedOrigin, span: span)
            let tint = it.valid ? Color.dashAccent : Color.dashDanger

            RoundedRectangle(cornerRadius: DashMetrics.cardCornerRadius, style: .continuous)
                .fill(tint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: DashMetrics.cardCornerRadius, style: .continuous)
                        .strokeBorder(tint, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                )
                .overlay {
                    // A shape cue so "invalid" reads without relying on colour.
                    if !it.valid {
                        Image(systemName: "xmark")
                            .font(.system(size: DashMetrics.statusGlyph, weight: .semibold))
                            .foregroundStyle(Color.dashDanger)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
                .zIndex(1)
                // The ghost glides between cells; the live widget does not.
                .animation(.easeOut(duration: 0.12), value: it.proposedOrigin)
                .animation(.easeOut(duration: 0.12), value: it.proposedSize)
        }
    }

    private var emptyPage: some View {
        VStack(spacing: DashMetrics.spacingSmall) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: DashMetrics.statusGlyph))
                .foregroundStyle(Color.dashTextTertiary)
            Text("Nothing on the dashboard yet")
                .font(.dashControl)
                .foregroundStyle(Color.dashTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dashGlassSurface()
    }
}

/// Frames one placement as a **button** in normal mode: the feature's component
/// when it resolves, otherwise a clearly-labelled fallback. Tapping forwards
/// `placement.featureID` to `onOpenFeature` — the tile knows nothing about which
/// feature that is or how it opens.
///
/// In edit mode the tile is not a Button: it carries a Remove control, a size
/// Menu (only the feature's supported widget sizes), a drag-to-move gesture on
/// the body, and a corner resize handle. All of them call back to
/// `DashboardSpaceView`, which routes changes through `DashboardLayoutStore`.
struct WidgetHostView: View {

    let placement: WidgetPlacement
    let registry: FeatureRegistry
    let onOpenFeature: (FeatureID) -> Void

    /// Whether the Dashboard is in edit mode. Disables tap-to-open and reveals
    /// the editing controls.
    var isEditing: Bool = false

    /// Whether this specific tile is the one currently being dragged / resized.
    var isInteracting: Bool = false

    /// Edit-mode: remove this widget (→ `DashboardLayoutStore.removePlacement`).
    var onRemove: (() -> Void)? = nil

    /// Edit-mode: change this widget's size via the Menu
    /// (→ `DashboardLayoutStore.updatePlacementSize`).
    var onResize: ((ComponentSize) -> Void)? = nil

    /// Edit-mode: the body was dragged — `(translation, ended)`. The parent snaps
    /// it to the grid and commits on `ended`.
    var onMoveGesture: ((CGSize, Bool) -> Void)? = nil

    /// Edit-mode: the resize handle was dragged — `(translation, ended)`.
    var onResizeGesture: ((CGSize, Bool) -> Void)? = nil

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
    /// single → no size control / no resize handle. Exposed for tests.
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
            .dashGlassSurface()
            .contentShape(RoundedRectangle(cornerRadius: DashMetrics.cardCornerRadius, style: .continuous))
    }

    // MARK: - Editing chrome

    private var editingTile: some View {
        styledContent
            .overlay(
                RoundedRectangle(cornerRadius: DashMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.dashAccent,
                        style: StrokeStyle(lineWidth: DashMetrics.focusStroke, dash: [6, 4])
                    )
            )
            .opacity(isInteracting ? 0.75 : 0.92)
            .overlay(alignment: .topLeading) { removeControl }
            .overlay(alignment: .bottomLeading) { sizeControl }
            .overlay(alignment: .bottomTrailing) { resizeHandle }
            .gesture(
                // `.global` space: `translation` is a pure delta from a fixed
                // reference, so driving `.offset` from it can't feed back into
                // the measurement (the cause of the drag vibration).
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { onMoveGesture?($0.translation, false) }
                    .onEnded { onMoveGesture?($0.translation, true) }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(featureTitle) widget, editing")
            .accessibilityHint("Drag to move")
    }

    private var removeControl: some View {
        Button(role: .destructive) {
            onRemove?()
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.dashOnAccent, Color.dashDanger)
                .background(Circle().fill(Color.dashControlScrim))
        }
        .buttonStyle(.plain)
        .padding(DashMetrics.overlayControlInset)
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
                    .foregroundStyle(Color.dashTextPrimary)
                    .padding(DashMetrics.spacingSmall)
                    .background(Circle().fill(Color.dashControlScrim))
            }
            .padding(DashMetrics.overlayControlInset)
            .accessibilityLabel("Change \(featureTitle) widget size")
        }
    }

    @ViewBuilder
    private var resizeHandle: some View {
        if onResizeGesture != nil, supportedWidgetSizes.count > 1 {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.dashTextPrimary)
                .padding(DashMetrics.overlayControlInset)
                .background(Circle().fill(Color.dashControlScrim))
                .padding(DashMetrics.overlayControlInset)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { onResizeGesture?($0.translation, false) }
                        .onEnded { onResizeGesture?($0.translation, true) }
                )
                .accessibilityLabel("Drag to resize \(featureTitle) widget")
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
        VStack(spacing: DashMetrics.spacingTight) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(Color.dashTextSecondary)
            Text(placement.featureID)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.dashTextPrimary)
            Text("Can't show \(placement.size.rawValue) widget")
                .font(.dashCaption)
                .foregroundStyle(Color.dashTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dashCard)
    }
}
