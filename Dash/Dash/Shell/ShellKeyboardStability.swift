//
//  ShellKeyboardStability.swift
//  Dash
//
//  Dash is a fixed full-screen automotive surface. The software keyboard (the
//  Maps destination search field) must behave as an independent system layer
//  that OVERLAYS the lower shell area — it must never resize or reposition the
//  shell, the rail, the wallpaper, or the rounded border.
//
//  Why the SwiftUI modifiers weren't enough
//  ----------------------------------------
//  SwiftUI's App lifecycle installs automatic keyboard avoidance on the window's
//  root `_UIHostingView`: it observes the keyboard notifications and shrinks the
//  hosting view (and/or insets it) so focused input stays visible. `_UIHostingView`
//  does this at the UIKit layer — it changes the hosting view's own geometry, not
//  just a SwiftUI safe-area region. `.ignoresSafeArea(.keyboard)` is a
//  SwiftUI-layout opt-out: it removes the keyboard *safe-area inset* from a
//  subtree, but it cannot undo a bounds change on the hosting view itself. On the
//  physical iPad, with `.ignoresSafeArea(.keyboard)` applied at the WindowGroup
//  root, on `DashboardShell`, and on `MapFullScreenView`, the shell still nudged
//  upward: the reduced hosting-view height was re-centred by the shell's
//  `frame(maxHeight: .infinity)`, producing a small upward shift of the whole
//  rounded surface.
//
//  The fix
//  -------
//  Install a runtime subclass of the root `_UIHostingView` that neutralises
//  keyboard avoidance two ways, covering both mechanisms SwiftUI has used:
//
//    1. Its `safeAreaInsets` getter returns the *window's* safe-area insets —
//       i.e. the physical device insets only (notch / home indicator), never the
//       keyboard-inflated ones. SwiftUI's keyboard avoidance is driven through
//       this inset, so the layout below is proposed the same height whether or
//       not the keyboard is up. With no keyboard this is identical to normal
//       behaviour (a full-screen hosting view's safe area already equals the
//       window's), so the approved shell inset is unchanged.
//    2. Its `keyboardWillShow…` / `keyboardWillChangeFrame…` handlers (if present
//       on the running OS) are no-ops, covering any bounds-level adjustment.
//
//  Everything else about the hosting view is inherited unchanged. The `TextField`
//  still becomes first responder, the keyboard still appears, typing and search
//  suggestions still work — only the automatic layout shift is gone.
//
//  This is a private-symbol technique (runtime subclass of `_UIHostingView`).
//  Acceptable here: Dash is a personal, sideloaded, non-App-Store build. It
//  degrades safely — mechanism (1) overrides the public `UIView.safeAreaInsets`
//  getter and always applies; mechanism (2) only no-ops selectors that exist. If
//  no `_UIHostingView` ancestor is found at all, nothing is changed and a note
//  is logged in DEBUG.
//
//  Diagnostics: `logsKeyboardGeometry(_:)` (DEBUG) logs a tagged view's global
//  frame across keyboard show/hide so the FIRST layer that moves — if any still
//  does — is identifiable from the device console. Silence via
//  `ShellDiagnostics.logKeyboardGeometry = false` once confirmed stationary.
//
//  Sheets present their own hosting view lower in the hierarchy; this only
//  touches the top-most one (the WindowGroup root), so a future sheet with a text
//  field still gets normal avoidance.
//

import ObjectiveC
import SwiftUI
import UIKit

extension View {

    /// Stops SwiftUI's automatic keyboard avoidance from moving/resizing the
    /// window's root hosting view. Apply once, near the app root.
    func stopsRootKeyboardAvoidance() -> some View {
        background(RootKeyboardAvoidanceNeutraliser().accessibilityHidden(true))
    }
}

/// An inert, non-interactive probe that fills its background slot. Once it is in
/// a window it walks up to the top-most `_UIHostingView` and neutralises its
/// keyboard avoidance.
private struct RootKeyboardAvoidanceNeutraliser: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView { Probe() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Probe: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // Defer one tick so the full hierarchy (and the hosting view) exists.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                RootKeyboardAvoidance.neutralise(above: self)
            }
        }
    }
}

enum RootKeyboardAvoidance {

    /// Suffix marking a class we've already subclassed — makes the swap idempotent.
    private static let markerSuffix = "_DashKeyboardStable"

    /// Private keyboard-avoidance entry points on `_UIHostingView`, newest first.
    /// No-oping any that exist stops the hosting view reacting to the keyboard.
    private static let handlerSelectors = [
        "keyboardWillShowWithNotification:",
        "keyboardWillChangeFrameWithNotification:",
    ]

    static func neutralise(above view: UIView) {
        guard let host = topHostingView(from: view) else {
            #if DEBUG
            print("⚠️ RootKeyboardAvoidance: no _UIHostingView ancestor found")
            #endif
            return
        }
        swapInNeutralSubclass(of: host)
    }

    /// The highest `_UIHostingView` on the path to the window — the WindowGroup
    /// root, not a nested one from a sheet.
    private static func topHostingView(from view: UIView) -> UIView? {
        var top: UIView?
        var node: UIView? = view
        while let current = node {
            if NSStringFromClass(type(of: current)).contains("_UIHostingView") {
                top = current
            }
            node = current.superview
        }
        return top
    }

    private static func swapInNeutralSubclass(of view: UIView) {
        guard let baseClass = object_getClass(view) else { return }
        let baseName = NSStringFromClass(baseClass)
        guard !baseName.hasSuffix(markerSuffix) else { return }

        let subclassName = baseName + markerSuffix

        if let existing = NSClassFromString(subclassName) {
            object_setClass(view, existing)
            #if DEBUG
            print("✅ RootKeyboardAvoidance: reused \(subclassName)")
            #endif
            return
        }

        guard let subclass = objc_allocateClassPair(baseClass, subclassName, 0) else { return }

        // (1) safeAreaInsets → the window's physical insets only, never the
        //     keyboard-inflated ones.
        let safeAreaSelector = #selector(getter: UIView.safeAreaInsets)
        if let method = class_getInstanceMethod(UIView.self, safeAreaSelector) {
            let insets: @convention(block) (UIView) -> UIEdgeInsets = { host in
                host.window?.safeAreaInsets ?? .zero
            }
            class_addMethod(
                subclass,
                safeAreaSelector,
                imp_implementationWithBlock(insets),
                method_getTypeEncoding(method)
            )
        }

        // (2) no-op any keyboard-notification handlers the OS still has.
        let noop: @convention(block) (AnyObject, AnyObject) -> Void = { _, _ in }
        for name in handlerSelectors {
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(baseClass, selector) else { continue }
            class_addMethod(
                subclass,
                selector,
                imp_implementationWithBlock(noop),
                method_getTypeEncoding(method)
            )
        }

        objc_registerClassPair(subclass)
        object_setClass(view, subclass)

        // Force a safe-area re-read now that the getter is overridden.
        view.setNeedsLayout()

        #if DEBUG
        print("✅ RootKeyboardAvoidance: neutralised \(baseName)")
        #endif
    }
}

// MARK: - Diagnostics (DEBUG only)

#if DEBUG
enum ShellDiagnostics {
    /// Logs the tagged view's global frame across keyboard show/hide so the
    /// FIRST layer that moves is identifiable on device. Off — the physical iPad
    /// test (M5.5.3) confirmed the shell stays stationary. Flip to `true` to
    /// re-enable if the behaviour ever regresses.
    static var logKeyboardGeometry = false
}

extension View {
    /// DEBUG: log this view's global frame + safe-area insets when the keyboard
    /// shows and hides (only if `ShellDiagnostics.logKeyboardGeometry`).
    @ViewBuilder
    func logsKeyboardGeometry(_ label: String) -> some View {
        if ShellDiagnostics.logKeyboardGeometry {
            modifier(KeyboardGeometryLogger(label: label))
        } else {
            self
        }
    }
}

private struct KeyboardGeometryLogger: ViewModifier {
    let label: String
    @State private var willShowFrame: CGRect?

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                        let f = proxy.frame(in: .global)
                        willShowFrame = f
                        print("📐 [\(label)] keyboard WILL SHOW  \(fmt(f))  safeAreaBottom=\(proxy.safeAreaInsets.bottom)")
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        let f = proxy.frame(in: .global)
                        let dy = willShowFrame.map { f.minY - $0.minY } ?? 0
                        let dh = willShowFrame.map { f.height - $0.height } ?? 0
                        let verdict = (abs(dy) < 0.5 && abs(dh) < 0.5) ? "STATIONARY ✅" : "MOVED ❌"
                        print("📐 [\(label)] keyboard DID SHOW   \(fmt(f))  Δy=\(rnd(dy)) Δheight=\(rnd(dh))  → \(verdict)")
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                        print("📐 [\(label)] keyboard DID HIDE   \(fmt(proxy.frame(in: .global)))")
                    }
            }
        )
    }

    private func fmt(_ r: CGRect) -> String {
        "origin=(\(rnd(r.minX)),\(rnd(r.minY))) size=(\(rnd(r.width))×\(rnd(r.height)))"
    }
    private func rnd(_ v: CGFloat) -> String { String(format: "%.1f", v) }
}
#else
extension View {
    @inline(__always) func logsKeyboardGeometry(_ label: String) -> some View { self }
}
#endif
