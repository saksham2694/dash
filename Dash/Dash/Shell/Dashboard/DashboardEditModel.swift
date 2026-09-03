//
//  DashboardEditModel.swift
//  Dash
//
//  The Dashboard's transient "edit mode" flag — a presentation-layer concern,
//  owned by the shell and observed by `DashboardSpaceView`.
//
//  Deliberately tiny and feature-agnostic:
//    • It holds *only* whether the Dashboard is being edited. It is not a second
//      layout model — layout + persistence stay in `DashboardLayoutStore`,
//      validation in `DashboardLayoutValidator`.
//    • Entering/leaving edit mode never touches `ShellStore` or navigation: the
//      Dashboard stays the Dashboard.
//    • Nothing here is persisted; the app always launches in normal mode.
//
//  M5.4.1 is the foundation only — no drag/drop, no resize gestures, no visual
//  CarPlay polish. Those land in M5.4.2 on top of this flag + the validated
//  mutation API on `DashboardLayoutStore`.
//

import Combine
import Foundation

@MainActor
final class DashboardEditModel: ObservableObject {

    /// Whether the Dashboard is currently in edit mode. Starts `false`.
    @Published private(set) var isEditing: Bool

    init(isEditing: Bool = false) {
        self.isEditing = isEditing
    }

    /// Enter edit mode. Idempotent.
    func beginEditing() {
        isEditing = true
    }

    /// Leave edit mode (the "Done" action). Idempotent.
    func endEditing() {
        isEditing = false
    }

    /// Flip between normal and edit mode.
    func toggle() {
        isEditing.toggle()
    }
}
